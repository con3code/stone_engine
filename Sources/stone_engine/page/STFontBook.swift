/*
STFontBook.swift

Part of the page layer added to stone_engine for SMSReader (see PAGE_LAYOUT.md). MIT License.
*/

import CoreGraphics
import CoreText
import Foundation

/// A glyph of a shaped character: the font it is in, and where it stands from the
/// character's start along the line (for a run of glyphs a character came to).
struct STGlyph: @unchecked Sendable {
    var font: CTFont
    var glyph: CGGlyph
    var offset: CGFloat
}

/// One character (a grapheme cluster) shaped in a style: its glyphs, how far it advances
/// across and down, and the font's ascent and descent.
struct STShape: @unchecked Sendable {
    var glyphs: [STGlyph]
    /// The advance across (horizontal) — also the length of a character turned sideways in a
    /// vertical line.
    var advance: CGFloat
    /// The advance down an upright character in a vertical line.
    var verticalAdvance: CGFloat
    var ascent: CGFloat
    var descent: CGFloat
}

/// The fonts and shaped characters of one typesetting: made as they are first asked for and
/// kept. Not shared between threads: each typesetter has its own.
final class STFontBook {
    /// A font as made for a run: its face's name, its size, whether it is slanted (a face
    /// with no italic of its own) and made bold, and the OpenType features asked of it.
    private struct FontKey: Hashable {
        var name: String
        var size: CGFloat
        var slanted: Bool
        var emboldened: Bool
        var features: [String: Int]
    }

    private struct ShapeKey: Hashable {
        var text: String
        var font: FontKey
        var vertical: Bool
    }

    let settings: STReaderSettings
    private var fonts: [FontKey: CTFont] = [:]
    private var shapes: [ShapeKey: STShape] = [:]
    private var fallbacks: [String: CTFont] = [:]
    private var knownNames: [String: Bool] = [:]

    init(settings: STReaderSettings) {
        self.settings = settings
    }

    /// Whether the system has a font by this PostScript name.
    private func exists(_ name: String) -> Bool {
        if let known = knownNames[name] { return known }
        let found = (CTFontCopyPostScriptName(CTFontCreateWithName(name as CFString, 12, nil)) as String) == name
        knownNames[name] = found
        return found
    }

    /// The face a style sets a character in (by its first scalar): the reader's faces (a true
    /// italic for Latin), or the book's own by their ranges, weight and style.
    private func key(_ style: STTextStyle, scalar: UInt32) -> FontKey {
        var family = settings.forcedFamily ?? style.family
        if !settings.usesBookFonts {
            switch family {
            case .named, .faces: family = .mincho
            default: break
            }
        }
        let wide = scalar >= 0x2E80 && !(0xFF61...0xFF9F).contains(scalar)
        func reader(_ faces: [String], italics: [String]) -> FontKey {
            let index = style.bold && faces.count > 1 ? 1 : 0
            if style.italic, !wide, italics.indices.contains(index), exists(italics[index]) {
                return FontKey(name: italics[index], size: style.size, slanted: false, emboldened: false, features: style.fontFeatures)
            }
            return FontKey(name: faces[index], size: style.size, slanted: style.italic, emboldened: false, features: style.fontFeatures)
        }
        func resolve(_ family: STFontFamily) -> FontKey {
            switch family {
            case .mincho:
                if wide, let faces = languageFaces(serif: true, language: style.language, scalar: scalar) { return reader(faces, italics: []) }
                return reader(settings.minchoFonts, italics: settings.minchoItalicFonts)
            case .gothic:
                if wide, let faces = languageFaces(serif: false, language: style.language, scalar: scalar) { return reader(faces, italics: []) }
                return reader(settings.gothicFonts, italics: settings.gothicItalicFonts)
            case .monospace: return reader(settings.monospaceFonts, italics: settings.monospaceItalicFonts)
            case .named(let name):
                guard exists(name) else { return resolve(.mincho) }
                return FontKey(name: name, size: style.size, slanted: style.italic, emboldened: style.bold, features: style.fontFeatures)
            case .faces(let faces, let fallback):
                // The face declared last first, as CSS tries them.
                let covering = faces.reversed().filter { $0.covers(scalar) && exists($0.name) }
                guard !covering.isEmpty else { return resolve(fallback) }
                let face = covering.first { $0.bold == style.bold && $0.italic == style.italic }
                    ?? covering.first { $0.italic == style.italic }
                    ?? covering[0]
                return FontKey(name: face.name, size: style.size, slanted: style.italic && !face.italic,
                               emboldened: style.bold && !face.bold, features: style.fontFeatures)
            }
        }
        return resolve(family)
    }

    /// The faces (regular, bold) for Han and Hangul in Chinese and Korean text, whose
    /// characters take shapes of their own there (骨, 直 are drawn otherwise than in Japanese):
    /// simplified Chinese, traditional (Taiwan; Hong Kong and Macao), Korean. The serif ones
    /// where the system has them, else the sans-serif ones; nil for any other language.
    private func languageFaces(serif: Bool, language: String?, scalar: UInt32) -> [String]? {
        guard let language = language?.lowercased(), language.hasPrefix("zh") || language.hasPrefix("ko") else { return nil }
        let parts = language.split(separator: "-").map(String.init)
        let candidates: [[String]]
        if parts.first == "ko" {
            // Hangul and Han only: Korean faces' brackets and points are not set full width.
            let hangul = (0x3130...0x318F).contains(scalar) || (0xA960...0xA97F).contains(scalar) || (0xAC00...0xD7FF).contains(scalar)
            let han = (0x3400...0x9FFF).contains(scalar) || (0xF900...0xFAFF).contains(scalar) || scalar >= 0x20000
            guard hangul || han else { return nil }
            candidates = (serif ? [["AppleMyungjo", "AppleMyungjo"]] : []) + [["AppleSDGothicNeo-Regular", "AppleSDGothicNeo-Bold"]]
        } else if parts.first == "zh" {
            let hongKong = parts.contains("hk") || parts.contains("mo")
            let traditional = hongKong || parts.contains("hant") || parts.contains("tw")
            let sans = hongKong ? ["PingFangHK-Regular", "PingFangHK-Semibold"]
                : traditional ? ["PingFangTC-Regular", "PingFangTC-Semibold"] : ["PingFangSC-Regular", "PingFangSC-Semibold"]
            let song = traditional ? ["STSongti-TC-Regular", "STSongti-TC-Bold"] : ["STSongti-SC-Regular", "STSongti-SC-Bold"]
            candidates = (serif ? [song] : []) + [sans]
        } else {
            return nil
        }
        return candidates.first { exists($0[0]) }
    }

    /// The font a style sets text in.
    func font(_ style: STTextStyle) -> CTFont { font(for: key(style, scalar: 0x41)) }

    private func font(for key: FontKey) -> CTFont {
        if let font = fonts[key] { return font }
        var font = CTFontCreateWithName(key.name as CFString, key.size, nil)
        if key.emboldened, let bold = CTFontCreateCopyWithSymbolicTraits(font, key.size, nil, .traitBold, .traitBold) {
            font = bold
        }
        if key.slanted, let italic = CTFontCreateCopyWithSymbolicTraits(font, key.size, nil, .traitItalic, .traitItalic),
           (CTFontCopyPostScriptName(italic) as String) != (CTFontCopyPostScriptName(font) as String) {
            font = italic
        } else if key.slanted {
            // Slanted: the face has no italic of its own.
            var slant = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)
            font = CTFontCreateCopyWithAttributes(font, key.size, &slant, nil)
        }
        if !key.features.isEmpty {
            let settings = key.features.sorted { $0.key < $1.key }.map { tag, value in
                [kCTFontOpenTypeFeatureTag: tag, kCTFontOpenTypeFeatureValue: value] as [CFString: Any]
            }
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFeatureSettingsAttribute: settings] as CFDictionary)
            font = CTFontCreateCopyWithAttributes(font, key.size, nil, descriptor)
        }
        fonts[key] = font
        return font
    }

    /// One character shaped in `style`; `vertical` for an upright character of a vertical
    /// line, which takes the font's vertical forms (GSUB vert) where it has them.
    func shape(_ text: String, _ style: STTextStyle, vertical: Bool) -> STShape {
        let fontKey = key(style, scalar: text.unicodeScalars.first?.value ?? 0x41)
        let shapeKey = ShapeKey(text: text, font: fontKey, vertical: vertical)
        if let shape = shapes[shapeKey] { return shape }
        let base = font(for: fontKey)
        var glyphs = glyphsOf(text, in: base, shaped: !fontKey.features.isEmpty)
        if vertical {
            for index in glyphs.indices {
                glyphs[index].glyph = STVerticalForms.glyph(glyphs[index].glyph, in: glyphs[index].font)
            }
        }
        var advance: CGFloat = 0
        var verticalAdvance: CGFloat = 0
        for index in glyphs.indices {
            var glyph = glyphs[index].glyph
            var size = CGSize.zero
            CTFontGetAdvancesForGlyphs(glyphs[index].font, .horizontal, &glyph, &size, 1)
            glyphs[index].offset = advance
            advance += size.width
            var down = CGSize.zero
            CTFontGetAdvancesForGlyphs(glyphs[index].font, .vertical, &glyph, &down, 1)
            verticalAdvance = max(verticalAdvance, abs(down.height))
        }
        // Combining marks and the like ride on the first glyph, where CoreText placed them.
        if glyphs.count > 1, text.unicodeScalars.count > 1, text.count == 1 {
            let placed = glyphsOf(text, in: base, shaped: true)
            if placed.count == glyphs.count {
                for index in glyphs.indices { glyphs[index].offset = placed[index].offset }
            }
            var first = glyphs[0].glyph
            var size = CGSize.zero
            CTFontGetAdvancesForGlyphs(glyphs[0].font, .horizontal, &first, &size, 1)
            advance = size.width
        }
        if verticalAdvance <= 0 { verticalAdvance = style.size }
        let font = glyphs.first?.font ?? base
        let shape = STShape(
            glyphs: glyphs, advance: advance, verticalAdvance: verticalAdvance,
            ascent: CTFontGetAscent(font), descent: CTFontGetDescent(font))
        shapes[shapeKey] = shape
        return shape
    }

    /// A run of Latin text (a word) shaped as one by CoreText, its kerning and ligatures
    /// with it: each cluster (one character, or several a ligature joins) as a shape, by its
    /// range in the run's UTF-16 units.
    func shapeWord(_ text: String, _ style: STTextStyle) -> [(range: Range<Int>, shape: STShape)]? {
        let first = text.unicodeScalars.first?.value ?? 0x41
        let fontKey = key(style, scalar: first)
        // Where the book's ranges put characters in other faces: each run of one face by itself.
        if let split = text.firstIndex(where: { key(style, scalar: $0.unicodeScalars.first?.value ?? 0x41).name != fontKey.name }) {
            let head = String(text[..<split]), tail = String(text[split...])
            guard !head.isEmpty else {
                // The first character alone, then the rest.
                let one = String(text.first!), rest = String(text.dropFirst())
                let shaped = shape(one, style, vertical: false)
                let offset = (one as NSString).length
                let others = rest.isEmpty ? [] : (shapeWord(rest, style) ?? [])
                return [(0..<offset, shaped)] + others.map { ($0.range.lowerBound + offset)..<($0.range.upperBound + offset) }.enumerated().map { ($1, others[$0].shape) }
            }
            guard let before = shapeWord(head, style) else { return nil }
            let offset = (head as NSString).length
            let after = shapeWord(tail, style) ?? []
            return before + after.map { ((($0.range.lowerBound + offset)..<($0.range.upperBound + offset)), $0.shape) }
        }
        let font = font(for: fontKey)
        var attributes: [NSAttributedString.Key: Any] = [kCTFontAttributeName as NSAttributedString.Key: font]
        // CoreText kerns whatever the font's feature says; a kern of 0 stops it (font-kerning: none).
        if style.fontFeatures["kern"] == 0 { attributes[kCTKernAttributeName as NSAttributedString.Key] = 0 }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var glyphs: [(index: Int, glyph: STGlyph, x: CGFloat)] = []
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var ids = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &ids)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            for i in 0..<count where ids[i] != 0 {
                glyphs.append((indices[i], STGlyph(font: runFont, glyph: ids[i], offset: 0), positions[i].x))
            }
        }
        guard !glyphs.isEmpty else { return nil }
        let length = (text as NSString).length
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        // Clusters: the glyphs from one character (grapheme) a glyph stands for to the next,
        // a ligature's characters with it, a mark with its letter. Each is as wide as the space
        // from where it starts to where the next one along the line starts, wherever that
        // one stands in the text: a right-to-left word's (Arabic, Hebrew) come from the right.
        let nsText = text as NSString
        func graphemeStart(_ index: Int) -> Int { nsText.rangeOfComposedCharacterSequence(at: min(max(index, 0), length - 1)).location }
        let clustered = glyphs.map { (start: graphemeStart($0.index), glyph: $0.glyph, x: $0.x) }
        let starts = Array(Set(clustered.map(\.start))).sorted()
        let lefts = Dictionary(uniqueKeysWithValues: starts.map { start in (start, clustered.filter { $0.start == start }.map(\.x).min() ?? 0) })
        let edges = lefts.values.sorted()
        var result: [(Range<Int>, STShape)] = []
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        for (number, start) in starts.enumerated() {
            let end = number + 1 < starts.count ? starts[number + 1] : length
            let x = lefts[start] ?? 0
            let right = edges.first { $0 > x + 0.001 } ?? width
            let shapeGlyphs = clustered.filter { $0.start == start }.map { STGlyph(font: $0.glyph.font, glyph: $0.glyph.glyph, offset: $0.x - x) }
            result.append((start..<end, STShape(glyphs: shapeGlyphs, advance: max(0, right - x), verticalAdvance: style.size, ascent: ascent, descent: descent)))
        }
        return result
    }

    /// The glyphs of a character in `font`, or in the font the system takes for it where
    /// `font` has none. A character of one scalar is looked up directly; a cluster (a
    /// character with a variation selector or combining marks) is shaped by CoreText.
    private func glyphsOf(_ text: String, in font: CTFont, shaped: Bool = false) -> [STGlyph] {
        let units = Array(text.utf16)
        if text.unicodeScalars.count == 1, !shaped {
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            if CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count), glyphs[0] != 0 {
                return [STGlyph(font: font, glyph: glyphs[0], offset: 0)]
            }
            let substitute = fallback(for: text, from: font)
            if CTFontGetGlyphsForCharacters(substitute, units, &glyphs, units.count), glyphs[0] != 0 {
                return [STGlyph(font: substitute, glyph: glyphs[0], offset: 0)]
            }
            return []
        }
        // Shaped as a line: CoreText picks the variant a variation selector asks for, and the
        // fonts the characters need.
        let attributed = NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        let line = CTLineCreateWithAttributedString(attributed)
        var result: [STGlyph] = []
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName] as! CTFont
            for i in 0..<count where glyphs[i] != 0 {
                result.append(STGlyph(font: runFont, glyph: glyphs[i], offset: positions[i].x))
            }
        }
        return result
    }

    private func fallback(for text: String, from font: CTFont) -> CTFont {
        let key = "\(CTFontCopyPostScriptName(font))|\(CTFontGetSize(font))|\(text)"
        if let found = fallbacks[key] { return found }
        let found = CTFontCreateForString(font, text as CFString, CFRange(location: 0, length: (text as NSString).length))
        fallbacks[key] = found
        return found
    }
}

/// The vertical forms of glyphs (GSUB vrt2 / vert), by stone_engine's reading of the font's
/// tables, which keeps one state for the whole process: asked one at a time.
enum STVerticalForms {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: [CGGlyph: CGGlyph]] = [:]

    static func glyph(_ glyph: CGGlyph, in font: CTFont) -> CGGlyph {
        let name = CTFontCopyPostScriptName(font) as String
        return lock.withLock {
            if let found = cache[name]?[glyph] { return found }
            let substituted = STTextVerticalSubstitutionGlyphWithGlyph(fontName: name, glyph: glyph)
            let result = substituted == 0 || substituted == 65535 ? glyph : substituted
            cache[name, default: [:]][glyph] = result
            return result
        }
    }
}
