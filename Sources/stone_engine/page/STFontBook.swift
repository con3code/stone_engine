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
    private struct FontKey: Hashable {
        var family: STFontFamily
        var bold: Bool
        var italic: Bool
        var size: CGFloat
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

    init(settings: STReaderSettings) {
        self.settings = settings
    }

    private func key(_ style: STTextStyle) -> FontKey {
        var family = settings.forcedFamily ?? style.family
        if case .named = family, !settings.usesBookFonts { family = .mincho }
        return FontKey(family: family, bold: style.bold, italic: style.italic, size: style.size)
    }

    /// The font a style sets text in.
    func font(_ style: STTextStyle) -> CTFont { font(for: key(style)) }

    private func font(for key: FontKey) -> CTFont {
        if let font = fonts[key] { return font }
        var name: String
        switch key.family {
        case .mincho: name = settings.minchoFonts[key.bold && settings.minchoFonts.count > 1 ? 1 : 0]
        case .gothic: name = settings.gothicFonts[key.bold && settings.gothicFonts.count > 1 ? 1 : 0]
        case .named(let named): name = named
        }
        var font = CTFontCreateWithName(name as CFString, key.size, nil)
        // A name the system does not know comes back as another font: the reader's Mincho then.
        if case .named = key.family, (CTFontCopyPostScriptName(font) as String) != name {
            font = CTFontCreateWithName(settings.minchoFonts[key.bold && settings.minchoFonts.count > 1 ? 1 : 0] as CFString, key.size, nil)
        }
        if key.bold, case .named = key.family, let bold = CTFontCreateCopyWithSymbolicTraits(font, key.size, nil, .traitBold, .traitBold) {
            font = bold
        }
        if key.italic {
            // Slanted: Japanese faces have no italic of their own.
            var slant = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)
            font = CTFontCreateCopyWithAttributes(font, key.size, &slant, nil)
        }
        fonts[key] = font
        return font
    }

    /// One character shaped in `style`; `vertical` for an upright character of a vertical
    /// line, which takes the font's vertical forms (GSUB vert) where it has them.
    func shape(_ text: String, _ style: STTextStyle, vertical: Bool) -> STShape {
        let fontKey = key(style)
        let shapeKey = ShapeKey(text: text, font: fontKey, vertical: vertical)
        if let shape = shapes[shapeKey] { return shape }
        let base = font(for: fontKey)
        var glyphs = glyphsOf(text, in: base)
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
        // Combining marks and the like ride on the first glyph.
        if glyphs.count > 1, text.unicodeScalars.count > 1, text.count == 1 {
            advance = glyphs.reduce(0) { max($0, $1.offset) } + {
                var glyph = glyphs.last!.glyph
                var size = CGSize.zero
                CTFontGetAdvancesForGlyphs(glyphs.last!.font, .horizontal, &glyph, &size, 1)
                return size.width
            }()
        }
        if verticalAdvance <= 0 { verticalAdvance = style.size }
        let font = glyphs.first?.font ?? base
        let shape = STShape(
            glyphs: glyphs, advance: advance, verticalAdvance: verticalAdvance,
            ascent: CTFontGetAscent(font), descent: CTFontGetDescent(font))
        shapes[shapeKey] = shape
        return shape
    }

    /// The glyphs of a character in `font`, or in the font the system takes for it where
    /// `font` has none. A character of one scalar is looked up directly; a cluster (a
    /// character with a variation selector or combining marks) is shaped by CoreText.
    private func glyphsOf(_ text: String, in font: CTFont) -> [STGlyph] {
        let units = Array(text.utf16)
        if text.unicodeScalars.count == 1 {
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
