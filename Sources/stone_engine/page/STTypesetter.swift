/*
STTypesetter.swift

Part of the page layer added to stone_engine for SMSReader (see PAGE_LAYOUT.md). MIT License.

Sets sections of styled text into pages, in logical coordinates: "inline" along a line
(right in horizontal lines, down in vertical ones) and "block" across the lines (down in
horizontal text, leftwards in vertical text), both from the page's content area's start.
*/

import CoreGraphics
import Foundation

/// One character of a block, or an image, a 縦中横, a line break, as it is set.
struct STItem: @unchecked Sendable {
    enum Kind {
        case glyphs
        /// Characters set side by side in the space of one, upright in a vertical line.
        case combined(STShape)
        case image(id: String, size: CGSize)
        case lineBreak
    }

    var kind: Kind
    var shape: STShape?
    var style: STTextStyle
    /// Where it stands in the block's text, in UTF-16 units.
    var range: Range<Int>
    var characterClass: STCharacterClass
    /// Turned a quarter clockwise in a vertical line.
    var sideways: Bool
    /// The advance along the line, before squeezing.
    var advance: CGFloat
    /// Squeezed off at its start (an opening bracket's empty half) and at its end.
    var startTrim: CGFloat = 0
    var endTrim: CGFloat = 0
    /// The ruby it is under (`STSetBlock.rubies`).
    var ruby: Int?
    /// Its first scalar (0 for an image or a line break).
    var scalar: UInt32 = 0
    /// How far an image stands across the line.
    var across: CGFloat = 0
    /// Space added before and after a ruby's base where its ruby is longer, the glyphs
    /// drawn after `leadPad`.
    var leadPad: CGFloat = 0
    var trailPad: CGFloat = 0

    var squeezedAdvance: CGFloat { advance - startTrim - endTrim }

    var isSpace: Bool {
        if case .glyphs = kind { return characterClass.space }
        return false
    }

    var isLineBreak: Bool {
        if case .lineBreak = kind { return true }
        return false
    }
}

/// Ruby over items of a block.
struct STRuby: @unchecked Sendable {
    var text: String
    var style: STTextStyle
    var items: Range<Int>
    var shapes: [STShape]
    /// How long the ruby is along the line.
    var length: CGFloat
}

/// A block's items, shaped once and shared by the lines and pages made of them.
final class STSetBlock: @unchecked Sendable {
    let block: STBlock
    let index: Int
    var items: [STItem] = []
    var rubies: [STRuby] = []

    init(block: STBlock, index: Int) {
        self.block = block
        self.index = index
    }
}

/// A line: the items it holds and where each stands along it.
public struct STLine: @unchecked Sendable {
    let block: STSetBlock
    /// The items of the block in the line.
    let items: Range<Int>
    /// Where each item starts along the line (its squeezed-off start taken out), from the
    /// content area's start: the block's margin, the indent and the alignment are in them.
    let positions: [CGFloat]
    /// The space each item takes along the line, after squeezing and justifying.
    let advances: [CGFloat]
    /// How far the line takes across, and where its characters' em box starts and how large
    /// it is (ruby and emphasis marks stand before it, on the over side).
    let extent: CGFloat
    let emStart: CGFloat
    let emSize: CGFloat
    /// For horizontal lines: the baseline, from the em box's start.
    let baseline: CGFloat

    /// The text's range in its section, in UTF-16 units.
    public var range: Range<Int> {
        let items = block.items[self.items]
        guard let first = items.first, let last = items.last else { return block.block.offset..<block.block.offset }
        return (block.block.offset + first.range.lowerBound)..<(block.block.offset + last.range.upperBound)
    }
}

/// A line, an image or a rule placed on a page, at a distance across from the content area's start.
public struct STPlacedLine: @unchecked Sendable {
    public let line: STLine
    public let blockPosition: CGFloat
}

public struct STPlacedImage: Sendable {
    public let id: String
    /// Where it stands in the section's text, and its block.
    public let textOffset: Int
    public let blockIndex: Int
    /// In logical coordinates: inline start, block start, inline size, block size.
    public let inline: CGFloat, block: CGFloat, inlineSize: CGFloat, blockSize: CGFloat
}

public struct STPlacedBackground: Sendable {
    public let color: STColor
    public let inline: CGFloat, block: CGFloat, inlineSize: CGFloat, blockSize: CGFloat
}

/// One page of a section.
public struct STPage: @unchecked Sendable {
    public internal(set) var lines: [STPlacedLine] = []
    public internal(set) var images: [STPlacedImage] = []
    public internal(set) var rules: [STPlacedBackground] = []
    public internal(set) var backgrounds: [STPlacedBackground] = []
    /// The text the page holds, in its section's UTF-16 units.
    public internal(set) var range: Range<Int> = 0..<0
    /// The anchors (elements' ids) of the blocks that start on the page.
    public internal(set) var anchors: [String] = []

    var isEmpty: Bool { lines.isEmpty && images.isEmpty && rules.isEmpty }
    private var hasRange = false

    mutating func extend(_ text: Range<Int>) {
        range = hasRange ? min(range.lowerBound, text.lowerBound)..<max(range.upperBound, text.upperBound) : text
        hasRange = true
    }
}

/// The size of a page and the margins around its text, in points.
public struct STPageGeometry: Sendable, Hashable {
    public var size: CGSize
    public var top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat

    public init(size: CGSize, top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.size = size
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public var content: CGRect {
        CGRect(x: left, y: top, width: max(1, size.width - left - right), height: max(1, size.height - top - bottom))
    }
}

/// Sets sections into pages. One for each thread: it keeps the fonts and shapes it made.
public final class STTypesetter {
    public let settings: STReaderSettings
    let fonts: STFontBook

    public init(settings: STReaderSettings) {
        self.settings = settings
        fonts = STFontBook(settings: settings)
    }

    // MARK: Items

    func setBlock(_ block: STBlock, index: Int, vertical: Bool) -> STSetBlock {
        let set = STSetBlock(block: block, index: index)
        var position = 0
        for inline in block.inlines {
            let length = inline.text.utf16.count
            switch inline {
            case .text(let text, let style):
                appendCharacters(text, style: style, at: position, vertical: vertical, to: set)
            case .ruby(let base, let ruby, let style):
                let first = set.items.count
                var basePosition = position
                for part in base {
                    switch part {
                    case .image(let id, let size, let imageStyle):
                        appendImage(id, size: size, style: imageStyle, at: basePosition, vertical: vertical, to: set)
                    default:
                        appendCharacters(part.text, style: part.style, at: basePosition, vertical: vertical, to: set)
                    }
                    basePosition += part.text.utf16.count
                }
                var rubyStyle = style
                rubyStyle.size = style.size / 2
                rubyStyle.emphasis = nil
                rubyStyle.overline = false
                rubyStyle.underline = false
                rubyStyle.lineThrough = false
                rubyStyle.letterSpacing = 0
                rubyStyle.background = nil
                let shapes = ruby.map { fonts.shape(String($0), rubyStyle, vertical: vertical && STCharacterClass.of($0).upright) }
                let rubyLength = zip(ruby, shapes).reduce(CGFloat(0)) { sum, pair in
                    sum + (vertical && STCharacterClass.of(pair.0).upright ? pair.1.verticalAdvance : pair.1.advance)
                }
                let index = set.rubies.count
                set.rubies.append(STRuby(text: ruby, style: rubyStyle, items: first..<set.items.count, shapes: shapes, length: rubyLength))
                for item in first..<set.items.count { set.items[item].ruby = index }
            case .combined(let text, let style):
                let shape = fonts.shape(text, style, vertical: false)
                let scalar = text.unicodeScalars.first ?? " "
                set.items.append(STItem(
                    kind: vertical ? .combined(shape) : .glyphs, shape: shape, style: style, range: position..<(position + length),
                    characterClass: STCharacterClass.of(scalar: scalar), sideways: false,
                    advance: vertical ? style.size : shape.advance + style.letterSpacing, scalar: scalar.value))
            case .image(let id, let size, let style):
                appendImage(id, size: size, style: style, at: position, vertical: vertical, to: set)
            case .lineBreak(let style):
                set.items.append(STItem(
                    kind: .lineBreak, shape: nil, style: style, range: position..<(position + 1),
                    characterClass: STCharacterClass.of(scalar: "\n"), sideways: false, advance: 0))
            }
            position += length
        }
        if settings.squeezesPunctuation { squeeze(set) }
        spreadRubies(set)
        return set
    }

    private func appendImage(_ id: String, size: CGSize, style: STTextStyle, at position: Int, vertical: Bool, to set: STSetBlock) {
        set.items.append(STItem(
            kind: .image(id: id, size: size), shape: nil, style: style, range: position..<(position + 1),
            characterClass: STCharacterClass.of(scalar: "\u{3007}"), sideways: false,
            advance: vertical ? size.height : size.width, across: vertical ? size.width : size.height))
    }

    /// Ruby longer than its base: the ruby overhangs the kana beside it without ruby of its own
    /// by up to one ruby character on each side; what is left over the base takes, half before
    /// it and half after, its glyphs in the middle.
    private func spreadRubies(_ set: STSetBlock) {
        for ruby in set.rubies {
            let range = ruby.items
            guard !range.isEmpty else { continue }
            let baseLength = set.items[range].reduce(CGFloat(0)) { $0 + $1.squeezedAdvance }
            let extra = ruby.length - baseLength
            guard extra > 0.01 else { continue }
            func overhang(_ index: Int) -> CGFloat {
                guard set.items.indices.contains(index), set.items[index].ruby == nil, Self.isKana(set.items[index].scalar) else { return 0 }
                return min(ruby.style.size, extra / 2)
            }
            let pad = max(0, extra - overhang(range.lowerBound - 1) - overhang(range.upperBound))
            set.items[range.lowerBound].leadPad += pad / 2
            set.items[range.lowerBound].advance += pad / 2
            set.items[range.upperBound - 1].trailPad += pad / 2
            set.items[range.upperBound - 1].advance += pad / 2
        }
    }

    private static func isKana(_ scalar: UInt32) -> Bool {
        (0x3041...0x309F).contains(scalar) || (0x30A0...0x30FF).contains(scalar)
    }

    private func appendCharacters(_ text: String, style: STTextStyle, at start: Int, vertical: Bool, to set: STSetBlock) {
        var position = start
        for character in text {
            let length = String(character).utf16.count
            let characterClass = STCharacterClass.of(character)
            let upright: Bool
            switch style.orientation {
            case .mixed: upright = characterClass.upright
            case .upright: upright = true
            case .sideways: upright = false
            }
            let shape = fonts.shape(String(character), style, vertical: vertical && upright)
            let advance = (vertical && upright ? shape.verticalAdvance : shape.advance) + style.letterSpacing
            set.items.append(STItem(
                kind: .glyphs, shape: shape, style: style, range: position..<(position + length),
                characterClass: characterClass, sideways: vertical && !upright, advance: advance,
                scalar: character.unicodeScalars.first?.value ?? 0))
            position += length
        }
    }

    /// 約物の詰め (stone mode): a closing mark followed by punctuation, and an opening mark
    /// after punctuation, take half their width. Only fullwidth marks, which have the empty
    /// half to give.
    private func squeeze(_ set: STSetBlock) {
        let items = set.items
        for index in items.indices {
            let punctuation = items[index].characterClass.punctuation
            guard punctuation != .whole, case .glyphs = items[index].kind, !items[index].sideways else { continue }
            let half = items[index].style.size / 2
            if punctuation == .firstHalf, index + 1 < items.count, items[index + 1].characterClass.punctuation != .whole {
                set.items[index].endTrim = half
            }
            if punctuation == .secondHalf, index > 0, items[index - 1].characterClass.punctuation != .whole {
                set.items[index].startTrim = half
            }
        }
    }

    // MARK: Lines

    /// Whether a line may break between `items[index - 1]` and `items[index]`.
    private func canBreak(before index: Int, in items: [STItem]) -> Bool {
        let before = items[index - 1], after = items[index]
        if before.isLineBreak { return true }
        if let ruby = before.ruby, ruby == after.ruby { return false }
        if after.isSpace { return false }
        if before.isSpace { return true }
        if settings.kinsoku {
            if after.characterClass.notStarting || before.characterClass.notEnding { return false }
        }
        // 分離禁止: the halves of ……, ――, ‥‥ stay together.
        if before.scalar == after.scalar, Self.inseparable.contains(before.scalar) { return false }
        if before.characterClass.wordLetter && after.characterClass.wordLetter { return false }
        if before.characterClass.ideographic || after.characterClass.ideographic { return true }
        if case .image = before.kind { return true }
        if case .image = after.kind { return true }
        // A hyphen or a dash ends a line after it.
        return before.shape != nil && !before.characterClass.wordLetter
    }

    /// Marks set in twos that a line does not break between: … ‥ — ― ─ ⋯.
    private static let inseparable: Set<UInt32> = [0x2026, 0x2025, 0x2014, 0x2015, 0x2500, 0x22EF]

    /// Breaks a block's items into lines `measure` long, the first line `firstMeasure`.
    func breakLines(_ set: STSetBlock, firstMeasure: CGFloat, measure: CGFloat) -> [Range<Int>] {
        let items = set.items
        var lines: [Range<Int>] = []
        var start = 0
        while start < items.count {
            let available = lines.isEmpty ? firstMeasure : measure
            var width: CGFloat = 0
            var index = start
            var end: Int?
            while index < items.count {
                if items[index].isLineBreak {
                    end = index + 1
                    break
                }
                var advance = items[index].squeezedAdvance
                // An opening mark at a line's start gives up its empty half.
                if index == start, settings.squeezesPunctuation, items[index].characterClass.punctuation == .secondHalf,
                   !items[index].sideways, items[index].startTrim == 0 {
                    advance -= items[index].style.size / 2
                }
                if width + advance > available + 0.01, index > start {
                    // 、。 may hang past the end; spaces never push a line.
                    if items[index].isSpace || (settings.hangsPunctuation && items[index].characterClass.hangs
                        && (index + 1 >= items.count || canBreak(before: index + 1, in: items))) {
                        end = index + 1
                        break
                    }
                    var breakAt = index
                    while breakAt > start + 1, !canBreak(before: breakAt, in: items) { breakAt -= 1 }
                    if !canBreak(before: breakAt, in: items) { breakAt = index }
                    end = breakAt
                    break
                }
                width += advance
                index += 1
            }
            let lineEnd = end ?? items.count
            lines.append(start..<lineEnd)
            start = lineEnd
        }
        return lines
    }

    /// Places a line's items along it: the indent, the alignment, the squeezing at its ends,
    /// justified where the block is (spaces stretched first, then the gaps between ideographs).
    func setLine(_ set: STSetBlock, items range: Range<Int>, isFirst: Bool, isLast: Bool, inlineStart: CGFloat, measure: CGFloat) -> (positions: [CGFloat], advances: [CGFloat]) {
        let style = set.block.style
        var advances = set.items[range].map(\.squeezedAdvance)
        var starts = [CGFloat](repeating: 0, count: advances.count)
        let items = Array(set.items[range])
        guard !items.isEmpty else { return ([], []) }
        if settings.squeezesPunctuation {
            if items[0].characterClass.punctuation == .secondHalf, !items[0].sideways, items[0].startTrim == 0 {
                starts[0] = items[0].style.size / 2
                advances[0] -= starts[0]
            }
            // A closing mark at the line's end gives its empty half (the justification fills
            // the line out again).
            if let last = items.lastIndex(where: { !$0.isSpace && !$0.isLineBreak }),
               items[last].characterClass.punctuation == .firstHalf, !items[last].sideways, items[last].endTrim == 0, !isLast {
                advances[last] -= items[last].style.size / 2
            }
        }
        // Spaces at the end of a line and a line break take no room; a hanging mark stands outside.
        var used = advances.reduce(0, +)
        var trailing = items.count
        while trailing > 0, items[trailing - 1].isSpace || items[trailing - 1].isLineBreak {
            trailing -= 1
            used -= advances[trailing]
        }
        var hanging: CGFloat = 0
        if trailing > 0, items[trailing - 1].characterClass.hangs, used > measure + 0.01 {
            hanging = advances[trailing - 1]
        }
        let content = used - hanging
        let indent = isFirst ? style.textIndent : 0
        let available = measure - indent
        let endsParagraph = isLast || items.last?.isLineBreak == true
        let align = endsParagraph ? (style.align == .justify ? style.alignLast : style.align) : style.align
        var offset = inlineStart + indent
        var extra: [CGFloat] = .init(repeating: 0, count: items.count)
        let slack = available - content
        switch align {
        case .start: break
        case .center: offset += max(0, slack / 2)
        case .end: offset += max(0, slack)
        case .justify:
            if slack > 0.01, trailing > 1 {
                let gaps = (0..<(trailing - 1)).filter { items[$0].isSpace }
                let chosen = gaps.isEmpty
                    ? (0..<(trailing - 1)).filter { i in
                        let a = items[i], b = items[i + 1]
                        if let ruby = a.ruby, ruby == b.ruby { return false }
                        return !(a.characterClass.wordLetter && b.characterClass.wordLetter)
                    }
                    : gaps
                if !chosen.isEmpty {
                    let each = slack / CGFloat(chosen.count)
                    for i in chosen { extra[i] = each }
                }
            }
        }
        var positions: [CGFloat] = []
        var position = offset
        for i in items.indices {
            positions.append(position - starts[i] - items[i].startTrim)
            position += advances[i] + extra[i]
            advances[i] += extra[i]
        }
        return (positions, advances)
    }

    /// The lines of a block, `measure` long, set and with their extents across.
    func lines(of set: STSetBlock, measure: CGFloat, inlineStart: CGFloat) -> [STLine] {
        let style = set.block.style
        let firstMeasure = measure - style.textIndent
        var ranges = breakLines(set, firstMeasure: max(1, firstMeasure), measure: measure)
        if ranges.isEmpty { ranges = [0..<0] }
        return ranges.enumerated().map { index, range in
            let placed = setLine(set, items: range, isFirst: index == 0, isLast: index == ranges.count - 1, inlineStart: inlineStart, measure: measure)
            return line(set, range: range, positions: placed.positions, advances: placed.advances)
        }
    }

    /// The line's extent across: as high as its tallest character's size times the line
    /// height, with room on the over side for ruby and emphasis marks where the leading
    /// does not give it, and for images taller than the text.
    private func line(_ set: STSetBlock, range: Range<Int>, positions: [CGFloat], advances: [CGFloat]) -> STLine {
        let items = set.items[range]
        let base = set.block.baseStyle
        let emSize = items.reduce(CGFloat(0)) { max($0, $1.style.size) }.nonZero ?? base.size
        let lineHeight = max(set.block.style.lineHeight, settings.minimumLineHeight)
        var extent = emSize * lineHeight
        var over = (extent - emSize) / 2
        var under = over
        let marks = items.contains { $0.ruby != nil || $0.style.emphasis != nil }
        if marks {
            let markSize = items.compactMap { $0.ruby != nil || $0.style.emphasis != nil ? $0.style.size / 2 : nil }.max() ?? 0
            if markSize > over { over = markSize }
        }
        // Images stand on the em box; one larger than it pushes the line out on the over side.
        for item in items where item.across > emSize {
            over = max(over, (extent - emSize) / 2 + item.across - emSize)
        }
        under = max(under, 0)
        extent = over + emSize + under
        let shape = items.first(where: { $0.shape != nil })?.shape
        let ascentRatio = shape.map { $0.ascent / max($0.ascent + $0.descent, 1) } ?? 0.88
        return STLine(
            block: set, items: range, positions: positions, advances: advances,
            extent: extent, emStart: over, emSize: emSize, baseline: emSize * ascentRatio)
    }

    // MARK: Pages

    /// Sets a section into pages of `geometry`.
    public func paginate(_ section: STSection, geometry: STPageGeometry) -> [STPage] {
        let vertical = section.writingMode == .vertical
        let content = geometry.content
        let inlineExtent = vertical ? content.height : content.width
        let blockExtent = vertical ? content.width : content.height
        var pages: [STPage] = []
        var page = STPage()
        var position: CGFloat = 0

        func newPage() {
            if !page.isEmpty || !page.anchors.isEmpty { pages.append(page) }
            page = STPage()
            position = 0
        }

        for (index, block) in section.blocks.enumerated() {
            let style = block.style
            if style.pageBreakBefore, !page.isEmpty { newPage() }
            if let anchor = block.anchor { page.anchors.append(anchor) }
            position += style.marginBefore
            let inlineStart = style.marginStart
            let measure = max(block.baseStyle.size, inlineExtent - style.marginStart - style.marginEnd)
            let backgroundStart = position
            switch block.kind {
            case .image(let id, let natural, let fit):
                var inlineSize = vertical ? natural.height : natural.width
                var blockSize = vertical ? natural.width : natural.height
                let remaining = blockExtent - position
                if blockSize > remaining, !page.isEmpty, blockSize <= blockExtent || fit {
                    newPage()
                }
                // Scaled down to the line's length and to the page, keeping its shape.
                let room = blockExtent - position
                let scale = min(1, measure / max(inlineSize, 1), (fit || blockSize > room) ? room / max(blockSize, 1) : 1)
                inlineSize *= scale
                blockSize *= scale
                let alignOffset: CGFloat
                switch style.align {
                case .center: alignOffset = (measure - inlineSize) / 2
                case .end: alignOffset = measure - inlineSize
                default: alignOffset = 0
                }
                page.images.append(STPlacedImage(
                    id: id, textOffset: block.offset, blockIndex: index, inline: inlineStart + alignOffset, block: position,
                    inlineSize: inlineSize, blockSize: blockSize))
                page.extend(block.offset..<(block.offset + 1))
                position += blockSize
            case .rule:
                if position + 1 > blockExtent { newPage() }
                page.rules.append(STPlacedBackground(color: block.baseStyle.color ?? settings.textColor, inline: inlineStart, block: position, inlineSize: measure, blockSize: 1))
                position += 1
            default:
                let set = setBlock(block, index: index, vertical: vertical)
                for line in lines(of: set, measure: measure, inlineStart: inlineStart) {
                    if position + line.extent > blockExtent + 0.01, !page.isEmpty {
                        if let color = style.background, position > backgroundStart {
                            page.backgrounds.append(STPlacedBackground(color: color, inline: 0, block: backgroundStart, inlineSize: inlineExtent, blockSize: position - backgroundStart))
                        }
                        newPage()
                    }
                    page.lines.append(STPlacedLine(line: line, blockPosition: position))
                    page.extend(line.range)
                    position += line.extent
                }
            }
            position += style.marginAfter
            if let color = style.background {
                page.backgrounds.append(STPlacedBackground(color: color, inline: 0, block: max(0, min(backgroundStart, position)), inlineSize: inlineExtent, blockSize: max(0, position - max(0, backgroundStart))))
            }
            if style.pageBreakAfter { newPage() }
        }
        if !page.isEmpty || pages.isEmpty { pages.append(page) }
        return pages
    }
}

private extension CGFloat {
    var nonZero: CGFloat? { self > 0 ? self : nil }
}
