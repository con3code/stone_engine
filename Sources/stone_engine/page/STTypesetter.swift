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
    /// The ruby it is under (`STSetBlock.rubies`), and a second ruby about the first (両側ルビ).
    var ruby: Int?
    var outerRuby: Int?
    /// Its first scalar (0 for an image or a line break).
    var scalar: UInt32 = 0
    /// How far an image stands across the line.
    var across: CGFloat = 0
    /// Space added before and after a ruby's base where its ruby is longer, the glyphs
    /// drawn after `leadPad`.
    var leadPad: CGFloat = 0
    var trailPad: CGFloat = 0
    /// Room for inline boxes' padding and borders before and after its glyphs.
    var boxLead: CGFloat = 0
    var boxTrail: CGFloat = 0

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
    /// The items a line ends before with a hyphen.
    var hyphens = Set<Int>()
    /// Set down a vertical line.
    var vertical = false

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
    /// How it is put on what is under it, and how it fills its place.
    public var blendMode: CGBlendMode = .normal
    public var fit: STObjectFit = .fill
    public var fitPosition = CGPoint(x: 0.5, y: 0.5)
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

/// A box's part on a page: where it stands, and whether it starts or ends here (a box split
/// between pages is cut at the break).
public struct STPlacedBox: Sendable {
    /// The box among the section's.
    public let box: Int
    public internal(set) var inline: CGFloat, block: CGFloat, inlineSize: CGFloat, blockSize: CGFloat
    public internal(set) var startsHere: Bool
    public internal(set) var endsHere: Bool
    /// The placed box it is in, among the page's.
    public let parent: Int?
    /// The page's lines and images inside it.
    public internal(set) var lines: Range<Int>
    public internal(set) var images: Range<Int>
}

/// One page of a section.
public struct STPage: @unchecked Sendable {
    public internal(set) var lines: [STPlacedLine] = []
    public internal(set) var images: [STPlacedImage] = []
    public internal(set) var rules: [STPlacedBackground] = []
    public internal(set) var backgrounds: [STPlacedBackground] = []
    /// The boxes on the page, outer ones before those inside them.
    public internal(set) var boxes: [STPlacedBox] = []
    /// The text the page holds, in its section's UTF-16 units.
    public internal(set) var range: Range<Int> = 0..<0
    /// The anchors (elements' ids) of the blocks that start on the page.
    public internal(set) var anchors: [String] = []
    /// Blocks of the other writing mode, each set as a page of its own in its place.
    public internal(set) var flows: [STPlacedFlow] = []

    var isEmpty: Bool { lines.isEmpty && images.isEmpty && rules.isEmpty && flows.isEmpty }
    private var hasRange = false

    mutating func extend(_ text: Range<Int>) {
        range = hasRange ? min(range.lowerBound, text.lowerBound)..<max(range.upperBound, text.upperBound) : text
        hasRange = true
    }
}

/// Blocks of the other writing mode on a page: what they make, set as a page of its own,
/// and its place among the page's (logical, in the page's writing mode).
public struct STPlacedFlow: Sendable {
    public let page: STPage
    public let vertical: Bool
    public let inline: CGFloat, block: CGFloat, inlineSize: CGFloat, blockSize: CGFloat
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
    /// The block whose lines are being broken (for its rubies).
    private var currentSet: STSetBlock?

    public init(settings: STReaderSettings) {
        self.settings = settings
        fonts = STFontBook(settings: settings)
    }

    // MARK: Items

    func setBlock(_ block: STBlock, index: Int, vertical: Bool) -> STSetBlock {
        let set = STSetBlock(block: block, index: index)
        set.vertical = vertical
        var position = 0
        for inline in block.inlines {
            let length = inline.text.utf16.count
            switch inline {
            case .text(let text, let style):
                appendCharacters(text, style: style, at: position, vertical: vertical, to: set)
            case .ruby(let base, let ruby, let style):
                appendRuby(base: base, ruby: ruby, style: style, at: position, vertical: vertical, to: set)
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
        if settings.squeezesPunctuation, block.style.trimsAdjacent { squeeze(set) }
        autospace(set)
        spreadRubies(set)
        makeRoomForInlineBoxes(set)
        return set
    }

    /// The padding and border of inline boxes, before their first character and after their last.
    private func makeRoomForInlineBoxes(_ set: STSetBlock) {
        let items = set.items
        for index in items.indices where !items[index].style.inlineBoxes.isEmpty {
            for box in items[index].style.inlineBoxes {
                let first = index == 0 || !items[index - 1].style.inlineBoxes.contains { $0.id == box.id }
                let last = index + 1 >= items.count || !items[index + 1].style.inlineBoxes.contains { $0.id == box.id }
                if first, box.startSpace > 0 {
                    set.items[index].boxLead += box.startSpace
                    set.items[index].advance += box.startSpace
                }
                if last, box.endSpace > 0 {
                    set.items[index].boxTrail += box.endSpace
                    set.items[index].advance += box.endSpace
                }
            }
        }
    }

    /// Ruby over its base; a ruby in the base (両側ルビ) its own, this one about it.
    private func appendRuby(base: [STInline], ruby: String, style: STTextStyle, at position: Int, vertical: Bool, to set: STSetBlock) {
        let first = set.items.count
        var basePosition = position
        for part in base {
            switch part {
            case .image(let id, let size, let imageStyle):
                appendImage(id, size: size, style: imageStyle, at: basePosition, vertical: vertical, to: set)
            case .ruby(let innerBase, let innerRuby, let innerStyle):
                appendRuby(base: innerBase, ruby: innerRuby, style: innerStyle, at: basePosition, vertical: vertical, to: set)
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
        rubyStyle.inlineBoxes = []
        let shapes = ruby.map { fonts.shape(String($0), rubyStyle, vertical: vertical && STCharacterClass.of($0).upright) }
        let rubyLength = zip(ruby, shapes).reduce(CGFloat(0)) { sum, pair in
            sum + (vertical && STCharacterClass.of(pair.0).upright ? pair.1.verticalAdvance : pair.1.advance)
        }
        let index = set.rubies.count
        set.rubies.append(STRuby(text: ruby, style: rubyStyle, items: first..<set.items.count, shapes: shapes, length: rubyLength))
        for item in first..<set.items.count {
            if set.items[item].ruby == nil { set.items[item].ruby = index } else { set.items[item].outerRuby = index }
        }
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
            if ruby.style.rubyAlign == .spaceBetween, range.count > 1 {
                // The base spread to the ruby's length, evenly between its characters.
                let each = extra / CGFloat(range.count - 1)
                for index in range.dropLast() { set.items[index].advance += each }
                continue
            }
            let pad = max(0, extra - overhang(range.lowerBound - 1) - overhang(range.upperBound))
            if ruby.style.rubyAlign == .spaceAround, range.count > 1 {
                // Group ruby longer than its base: the base's characters spread under it, a
                // full share between them and half one at each end (1:2:1, ruby-align: space-around).
                let unit = pad / CGFloat(range.count)
                set.items[range.lowerBound].leadPad += unit / 2
                set.items[range.lowerBound].advance += unit / 2
                for index in range.dropLast() {
                    set.items[index].trailPad += unit
                    set.items[index].advance += unit
                }
                set.items[range.upperBound - 1].trailPad += unit / 2
                set.items[range.upperBound - 1].advance += unit / 2
                continue
            }
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
        let characters = Array(text)
        func upright(_ characterClass: STCharacterClass) -> Bool {
            switch style.orientation {
            case .mixed: characterClass.upright
            case .upright: true
            case .sideways: false
            }
        }
        /// Latin text (letters, digits and the punctuation among them), set across or turned
        /// in a vertical line: shaped a word at a time, for its kerning and ligatures.
        func isLatin(_ character: Character) -> Bool {
            guard let scalar = character.unicodeScalars.first?.value, scalar < 0x2000 else { return false }
            let characterClass = STCharacterClass.of(character)
            return !characterClass.space && !characterClass.ideographic && !(vertical && upright(characterClass))
        }
        var index = 0
        while index < characters.count {
            if isLatin(characters[index]), style.letterSpacing == 0 {
                var end = index + 1
                while end < characters.count, isLatin(characters[end]) { end += 1 }
                let word = String(characters[index..<end])
                if end - index >= 2, let clusters = fonts.shapeWord(word, style) {
                    for (range, shape) in clusters {
                        let cluster = (word as NSString).substring(with: NSRange(location: range.lowerBound, length: range.count))
                        let first = cluster.first ?? " "
                        set.items.append(STItem(
                            kind: .glyphs, shape: shape, style: style, range: (position + range.lowerBound)..<(position + range.upperBound),
                            characterClass: STCharacterClass.of(first), sideways: vertical, advance: shape.advance,
                            scalar: first.unicodeScalars.first?.value ?? 0))
                    }
                    position += word.utf16.count
                    index = end
                    continue
                }
            }
            let character = characters[index]
            index += 1
            let length = String(character).utf16.count
            let characterClass = STCharacterClass.of(character)
            let upright: Bool
            switch style.orientation {
            case .mixed: upright = characterClass.upright
            case .upright: upright = true
            case .sideways: upright = false
            }
            // Set upright by text-orientation alone (Latin and the like): the letter as it
            // stands across. The font's vertical forms (vrt2) of these are the turned ones.
            let shape = fonts.shape(String(character), style, vertical: vertical && upright && characterClass.upright)
            let advance = (vertical && upright ? shape.verticalAdvance : shape.advance) + style.letterSpacing
            set.items.append(STItem(
                kind: .glyphs, shape: shape, style: style, range: position..<(position + length),
                characterClass: characterClass, sideways: vertical && !upright, advance: advance,
                scalar: character.unicodeScalars.first?.value ?? 0))
            position += length
        }
    }

    /// 和欧間: a quarter em between Japanese and Latin letters (or digits), where the block asks
    /// for it (text-spacing: ideograph-alpha, ideograph-numeric).
    private func autospace(_ set: STSetBlock) {
        let style = set.block.style
        guard style.autospaceAlpha || style.autospaceNumeric else { return }
        func kind(_ item: STItem) -> Int {
            guard case .glyphs = item.kind, !item.isSpace else { return 0 }
            if item.characterClass.ideographic, item.characterClass.punctuation == .whole,
               !(0xFF00...0xFFEF).contains(item.scalar), !(0x3000...0x303F).contains(item.scalar) { return 1 }
            guard let scalar = Unicode.Scalar(item.scalar), !item.characterClass.ideographic else { return 0 }
            if (0x30...0x39).contains(item.scalar) { return 3 }
            return scalar.properties.isAlphabetic ? 2 : 0
        }
        for index in set.items.indices.dropLast() {
            let a = kind(set.items[index]), b = kind(set.items[index + 1])
            let pair = Set([a, b])
            guard pair.contains(1), (style.autospaceAlpha && pair.contains(2)) || (style.autospaceNumeric && pair.contains(3)) else { continue }
            let quarter = min(set.items[index].style.size, set.items[index + 1].style.size) / 4
            set.items[index].advance += quarter
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

    /// Small kana and the like: lines may start with them where 禁則 is not strict.
    private static let smallKana: Set<UInt32> = Set("ァィゥェォッャュョヮヵヶぁぃぅぇぉっゃゅょゎゕゖㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿ".unicodeScalars.map(\.value))
    /// The prolonged sound mark, iteration marks: lines may start with them where it is loose.
    private static let looseStarters: Set<UInt32> = Set("ーヽヾゝゞ々〻".unicodeScalars.map(\.value))

    /// Whether a line may break between `items[index - 1]` and `items[index]`, as the block's
    /// word-break and line-break say.
    private func canBreak(before index: Int, in items: [STItem], style: STBlockStyle = STBlockStyle()) -> Bool {
        let before = items[index - 1], after = items[index]
        if before.isLineBreak { return true }
        if let ruby = before.ruby, ruby == after.ruby {
            // Inside a group ruby: only one of more than two characters, which may run on to the next line.
            guard let set = currentSet, set.rubies.indices.contains(ruby), set.rubies[ruby].items.count > 2 else { return false }
        }
        if let outer = before.outerRuby, outer == after.outerRuby { return false }
        if after.isSpace { return false }
        if before.isSpace { return true }
        if style.lineBreak == .anywhere { return true }
        if settings.kinsoku {
            var notStarting = after.characterClass.notStarting
            switch style.lineBreak {
            case .normal?: if Self.smallKana.contains(after.scalar) { notStarting = false }
            case .loose?: if Self.smallKana.contains(after.scalar) || Self.looseStarters.contains(after.scalar) { notStarting = false }
            case .strict?: if after.scalar == 0x30FC { notStarting = true }
            default: break
            }
            if notStarting || before.characterClass.notEnding { return false }
        }
        // 分離禁止: the halves of ……, ――, ‥‥ stay together.
        if before.scalar == after.scalar, Self.inseparable.contains(before.scalar) { return false }
        switch style.wordBreak {
        case .breakAll:
            if before.shape != nil && after.shape != nil { return true }
        case .keepAll:
            // Only at spaces and after punctuation: not inside words, Japanese ones too.
            let letter: (STItem) -> Bool = { $0.characterClass.wordLetter || ($0.characterClass.ideographic && $0.characterClass.punctuation == .whole) }
            if letter(before) && letter(after) { return false }
        case .normal:
            break
        }
        if before.characterClass.wordLetter && after.characterClass.wordLetter { return false }
        if before.characterClass.ideographic || after.characterClass.ideographic { return true }
        if case .image = before.kind { return true }
        if case .image = after.kind { return true }
        // A hyphen or a dash ends a line after it.
        return before.shape != nil && !before.characterClass.wordLetter
    }

    /// Opening punctuation (Ps, Pi), which hanging-punctuation: first hangs.
    static func opens(_ scalar: UInt32) -> Bool {
        guard let value = Unicode.Scalar(scalar) else { return false }
        switch value.properties.generalCategory {
        case .openPunctuation, .initialPunctuation: return true
        default: return value == "\"" || value == "'"
        }
    }

    /// Where a Latin word overflowing the line may be hyphenated: the item the line ends
    /// before, the hyphen fitting with what comes before it; nil where it cannot be.
    private func hyphenation(_ set: STSetBlock, from start: Int, overflowing index: Int, width: CGFloat, available: CGFloat) -> Int? {
        let items = set.items
        guard items[index].characterClass.wordLetter else { return nil }
        var first = index, last = index
        while first > start, items[first - 1].characterClass.wordLetter { first -= 1 }
        while last + 1 < items.count, items[last + 1].characterClass.wordLetter { last += 1 }
        guard first > start || first == start else { return nil }
        let word = set.block.text as NSString
        let lower = items[first].range.lowerBound, upper = items[last].range.upperBound
        guard upper <= word.length else { return nil }
        let text = word.substring(with: NSRange(location: lower, length: upper - lower)) as CFString
        let locale = CFLocaleCreate(nil, CFLocaleIdentifier(rawValue: (set.block.style.language ?? "en") as CFString))
        guard CFStringIsHyphenationAvailableForLocale(locale) else { return nil }
        let hyphenWidth = items[index].style.size * 0.35
        // The width before the word on the line.
        var before = width
        for item in items[first..<index] { before -= item.squeezedAdvance }
        var location = CFIndex(index > first ? items[index].range.lowerBound - lower : 0) + 1
        while location > 1 {
            let found = CFStringGetHyphenationLocationBeforeIndex(text, location, CFRange(location: 0, length: upper - lower), 0, locale, nil)
            guard found != kCFNotFound, found > 0 else { return nil }
            // The item the word breaks before there.
            guard let breakItem = (first...last).first(where: { items[$0].range.lowerBound - lower >= found }), breakItem > first else { return nil }
            let length = items[first..<breakItem].reduce(before) { $0 + $1.squeezedAdvance }
            if length + hyphenWidth <= available + 0.01 { return breakItem }
            location = found
        }
        return nil
    }

    /// Marks set in twos that a line does not break between: … ‥ — ― ─ ⋯.
    private static let inseparable: Set<UInt32> = [0x2026, 0x2025, 0x2014, 0x2015, 0x2500, 0x22EF]

    /// Breaks a block's items into lines `measure` long, the first line `firstMeasure`.
    func breakLines(_ set: STSetBlock, firstMeasure: CGFloat, measure: CGFloat) -> [Range<Int>] {
        currentSet = set
        defer { currentSet = nil }
        let items = set.items
        let spacing = set.block.style
        var lines: [Range<Int>] = []
        var start = 0
        while start < items.count {
            var available = lines.isEmpty ? firstMeasure : measure
            // An opening mark at the paragraph's start hangs outside the line (hanging-punctuation: first).
            if spacing.hangsFirst, lines.isEmpty, start == 0, !items.isEmpty, Self.opens(items[0].scalar) { available += items[0].squeezedAdvance }
            // A list item's marker set outside the lines takes none of the first.
            if spacing.outsideMarker > 0, lines.isEmpty, start == 0 {
                available += items.prefix { $0.range.upperBound <= spacing.outsideMarker }.reduce(0) { $0 + $1.squeezedAdvance }
            }
            // An opening mark at this line's start gives up its empty half.
            let trimsStart = spacing.spacingStart == .trim || (spacing.spacingStart == .first && (start > 0 || !lines.isEmpty))
            var width: CGFloat = 0
            var index = start
            var end: Int?
            while index < items.count {
                if items[index].isLineBreak {
                    end = index + 1
                    break
                }
                var advance = items[index].squeezedAdvance
                if index == start, trimsStart, settings.squeezesPunctuation, items[index].characterClass.punctuation == .secondHalf,
                   !items[index].sideways, items[index].startTrim == 0 {
                    advance -= items[index].style.size / 2
                }
                // A closing mark that holds the line only trimmed: kept on it, trimmed (allow-end, trim-end).
                if width + advance > available + 0.01, index > start, spacing.spacingEnd != .space, settings.squeezesPunctuation,
                   items[index].characterClass.punctuation == .firstHalf, !items[index].sideways, items[index].endTrim == 0,
                   width + advance - items[index].style.size / 2 <= available + 0.01,
                   index + 1 >= items.count || canBreak(before: index + 1, in: items, style: spacing) {
                    end = index + 1
                    break
                }
                if width + advance > available + 0.01, index > start {
                    // 、。 may hang past the end; spaces never push a line.
                    if items[index].isSpace || ((spacing.hangsEnd ?? settings.hangsPunctuation) && items[index].characterClass.hangs
                        && (index + 1 >= items.count || canBreak(before: index + 1, in: items, style: spacing))) {
                        end = index + 1
                        break
                    }
                    var breakAt = index
                    while breakAt > start + 1, !canBreak(before: breakAt, in: items, style: spacing) { breakAt -= 1 }
                    // Hyphenated where the word allows it (hyphens: auto).
                    if spacing.hyphenates, let hyphen = hyphenation(set, from: start, overflowing: index, width: width, available: available),
                       hyphen > breakAt || !canBreak(before: breakAt, in: items, style: spacing) {
                        set.hyphens.insert(hyphen)
                        end = hyphen
                        break
                    }
                    if !canBreak(before: breakAt, in: items, style: spacing) {
                        if spacing.breaksLongWords ?? (spacing.wordBreak != .keepAll) {
                            breakAt = index
                        } else {
                            // overflow-wrap: normal: the word runs past the line's end.
                            breakAt = index + 1
                            while breakAt < items.count, !canBreak(before: breakAt, in: items, style: spacing) { breakAt += 1 }
                        }
                    }
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
            let trimsStart = style.spacingStart == .trim || (style.spacingStart == .first && !(isFirst && range.lowerBound == 0))
            if trimsStart, items[0].characterClass.punctuation == .secondHalf, !items[0].sideways, items[0].startTrim == 0 {
                starts[0] = items[0].style.size / 2
                advances[0] -= starts[0]
            }
            // A closing mark at the line's end gives its empty half: always (trim-end), or
            // where the line would not hold it otherwise (allow-end).
            if let last = items.lastIndex(where: { !$0.isSpace && !$0.isLineBreak }),
               items[last].characterClass.punctuation == .firstHalf, !items[last].sideways, items[last].endTrim == 0 {
                let full = advances.reduce(0, +) - (items.last?.isLineBreak == true ? 0 : 0)
                let indent = isFirst ? style.textIndent : 0
                switch style.spacingEnd {
                case .trim: advances[last] -= items[last].style.size / 2
                case .allow: if full > measure - indent + 0.01 { advances[last] -= items[last].style.size / 2 }
                case .space: break
                }
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
        var content = used - hanging
        var indent = isFirst ? style.textIndent : 0
        // The line's length, which a mark hanging outside its start does not lengthen.
        let available = measure - indent
        // An opening mark hanging outside the paragraph's first line.
        if style.hangsFirst, isFirst, range.lowerBound == 0, Self.opens(items[0].scalar) {
            content -= advances[0]
            indent -= advances[0]
        }
        // A list item's marker outside the lines (list-style-position: outside): before
        // their start, ending at the edge it is given.
        var markerCount = 0, markerWidth: CGFloat = 0
        if style.outsideMarker > 0, isFirst, range.lowerBound == 0 {
            markerCount = items.prefix { $0.range.upperBound <= style.outsideMarker }.count
            markerWidth = advances[..<markerCount].reduce(0, +)
            content -= markerWidth
        }
        // A hyphen after a word broken at the line's end takes room on it.
        if set.hyphens.contains(range.upperBound) { content += items[items.count - 1].style.size * 0.35 }
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
                // A line with Japanese in it is spread between its characters and at its
                // spaces alike (inside words and ruby bases not); a line of words only at its
                // spaces; a line with neither is left as it is.
                let hasIdeographs = items[..<trailing].contains { $0.characterClass.ideographic }
                let chosen = hasIdeographs
                    ? (markerCount..<max(markerCount, trailing - 1)).filter { i in
                        let a = items[i], b = items[i + 1]
                        if let ruby = a.ruby, ruby == b.ruby { return false }
                        return !(a.characterClass.wordLetter && b.characterClass.wordLetter)
                    }
                    : (markerCount..<max(markerCount, trailing - 1)).filter { items[$0].isSpace }
                if !chosen.isEmpty {
                    let each = slack / CGFloat(chosen.count)
                    for i in chosen { extra[i] = each }
                }
            }
        }
        var positions: [CGFloat] = []
        var position = offset
        var markerPosition = style.markerEdge - markerWidth
        for i in items.indices {
            if i < markerCount {
                positions.append(markerPosition - starts[i] - items[i].startTrim)
                markerPosition += advances[i]
                continue
            }
            positions.append(position - starts[i] - items[i].startTrim)
            position += advances[i] + extra[i]
            advances[i] += extra[i]
        }
        return (positions, advances)
    }

    /// The lines of a block where each may be shortened (beside a float): `room(line)` gives
    /// a line's start along and its length, the lines' extents taken as the block's usual one.
    func lines(of set: STSetBlock, room: (CGFloat) -> (start: CGFloat, measure: CGFloat)) -> [STLine] {
        let style = set.block.style
        let usual = set.block.baseStyle.size * max(style.lineHeight, settings.minimumLineHeight)
        var ranges: [Range<Int>] = []
        var placed: [(start: CGFloat, measure: CGFloat)] = []
        var start = 0
        var across: CGFloat = 0
        while start < set.items.count {
            let here = room(across)
            let measure = max(set.block.baseStyle.size, here.measure)
            let first = ranges.isEmpty ? measure - style.textIndent : measure
            let next = breakLines(set, from: start, measure: max(1, first))
            ranges.append(next)
            placed.append((here.start, measure))
            start = next.upperBound
            across += usual
        }
        if ranges.isEmpty {
            ranges = [0..<0]
            placed = [room(0)]
        }
        return ranges.enumerated().map { index, range in
            let laid = setLine(set, items: range, isFirst: index == 0, isLast: index == ranges.count - 1,
                               inlineStart: placed[index].start, measure: placed[index].measure)
            return line(set, range: range, positions: laid.positions, advances: laid.advances)
        }
    }

    /// One line's items from `start`, `measure` long.
    private func breakLines(_ set: STSetBlock, from start: Int, measure: CGFloat) -> Range<Int> {
        let tail = STSetBlock(block: set.block, index: set.index)
        tail.vertical = set.vertical
        tail.items = Array(set.items[start...])
        tail.rubies = set.rubies
        guard let first = breakLines(tail, firstMeasure: measure, measure: measure).first else { return start..<set.items.count }
        return (start + first.lowerBound)..<(start + max(first.upperBound, first.lowerBound + 1))
    }

    /// A block's items with its first line in its ::first-line style: the block broken in
    /// that style to find where the first line ends, those items taken from it.
    func setBlockWithFirstLine(_ block: STBlock, index: Int, vertical: Bool, measure: CGFloat) -> STSetBlock {
        let set = setBlock(block, index: index, vertical: vertical)
        guard let firstLine = block.firstLine else { return set }
        var styled = block
        styled.inlines = block.inlines.map(firstLine.apply)
        styled.firstLine = nil
        let other = setBlock(styled, index: index, vertical: vertical)
        guard other.items.count == set.items.count,
              let first = breakLines(other, firstMeasure: max(1, measure - block.style.textIndent), measure: measure).first else { return set }
        for item in first { set.items[item] = other.items[item] }
        return set
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
        // Ruby and emphasis marks on either side, the one beyond the other where both are.
        var overMarks: CGFloat = 0, underMarks: CGFloat = 0
        for item in items {
            var itemOver: CGFloat = 0, itemUnder: CGFloat = 0
            for index in [item.ruby, item.outerRuby].compactMap({ $0 }) {
                let ruby = set.rubies[index]
                if ruby.style.rubyUnder { itemUnder += ruby.style.size } else { itemOver += ruby.style.size }
            }
            if item.style.emphasis != nil {
                if item.style.emphasisUnder { itemUnder += item.style.size / 2 } else { itemOver += item.style.size / 2 }
            }
            overMarks = max(overMarks, itemOver)
            underMarks = max(underMarks, itemUnder)
        }
        over = max(over, overMarks)
        under = max(under, underMarks)
        // Images larger than the em box: across, one stands on the em box's foot and pushes the
        // line out on the over side; down, one is centred on the line and pushes it out on both.
        for item in items where item.across > emSize {
            if set.vertical {
                over = max(over, (extent - emSize) / 2 + (item.across - emSize) / 2)
                under = max(under, (extent - emSize) / 2 + (item.across - emSize) / 2)
            } else {
                over = max(over, (extent - emSize) / 2 + item.across - emSize)
            }
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

    /// Sets a section into pages of `geometry`. Margins across the lines collapse as CSS's
    /// do (the larger of two positive ones) and are let go at a page's start; boxes are cut
    /// where a page breaks them.
    public func paginate(_ section: STSection, geometry: STPageGeometry) -> [STPage] {
        let section = section.boxes.contains { $0.intrinsicInline != nil } ? resolvingIntrinsicSizes(section, geometry: geometry) : section
        return layout(section, blocks: 0..<section.blocks.count, geometry: geometry, inColumns: false)
    }

    /// The section with its boxes sized by what they hold (min-content, max-content,
    /// fit-content) made as long as that along the lines, the blocks in them narrowed to
    /// match: their lines set as long as they can be, or as short, and the longest taken.
    public func resolvingIntrinsicSizes(_ section: STSection, geometry: STPageGeometry) -> STSection {
        var section = section
        let vertical = section.writingMode == .vertical
        let content = geometry.content
        let inlineExtent = vertical ? content.height : content.width
        for boxIndex in section.boxes.indices {
            guard let sizing = section.boxes[boxIndex].intrinsicInline else { continue }
            section.boxes[boxIndex].intrinsicInline = nil
            guard let start = section.blocks.firstIndex(where: { if case .boxStart(boxIndex) = $0.kind { true } else { false } }),
                  let end = section.blocks[start...].firstIndex(where: { if case .boxEnd(boxIndex) = $0.kind { true } else { false } }),
                  end > start + 1 else { continue }
            let inner = (start + 1)..<end
            let box = section.boxes[boxIndex]
            let starts = section.blocks[inner].map(\.style.marginStart)
            let ends = section.blocks[inner].map(\.style.marginEnd)
            guard let contentStart = starts.min(), let contentEnd = ends.min() else { continue }
            /// The longest line of the box's blocks set `room` long along the lines (past what
            /// the box has, not counting their margins).
            func longest(_ room: CGFloat) -> CGFloat {
                let along = contentStart + contentEnd + room
                let size = vertical ? CGSize(width: 100_000, height: along) : CGSize(width: along, height: 100_000)
                let pages = layout(section, blocks: inner, geometry: STPageGeometry(size: size, top: 0, left: 0, bottom: 0, right: 0),
                                   inColumns: false, vertical: vertical)
                var result: CGFloat = 0
                for page in pages {
                    for placed in page.lines {
                        let line = placed.line
                        let items = line.block.items[line.items]
                        guard let last = items.lastIndex(where: { !$0.isSpace && !$0.isLineBreak }) else { continue }
                        let offset = last - line.items.lowerBound
                        result = max(result, line.positions[offset] + line.advances[offset] - contentStart)
                    }
                    for image in page.images { result = max(result, image.inline + image.inlineSize - contentStart) }
                    for inner in page.boxes { result = max(result, inner.inline + inner.inlineSize - contentStart) }
                }
                return result
            }
            let room = inlineExtent - contentStart - contentEnd
            let wanted: CGFloat
            /// The longest stretch of the box's text between the places its lines may break
            /// (no word broken where it need not be), with the block's start margin.
            func longestUnbreakable() -> CGFloat {
                var result: CGFloat = 0
                for index in inner {
                    let block = section.blocks[index]
                    switch block.kind {
                    case .paragraph, .heading: break
                    default: continue
                    }
                    let set = setBlock(block, index: index, vertical: vertical)
                    currentSet = set
                    defer { currentSet = nil }
                    let lead = block.style.marginStart - contentStart
                    var width: CGFloat = 0
                    for (i, item) in set.items.enumerated() {
                        if i > 0, canBreak(before: i, in: set.items, style: block.style) { width = 0 }
                        if item.isLineBreak { width = 0; continue }
                        if item.isSpace { continue }
                        width += item.squeezedAdvance
                        result = max(result, lead + width + (i == 0 ? max(0, block.style.textIndent) : 0))
                    }
                }
                // Pictures and boxes of their own length in it.
                return max(result, longest(1) > result && !section.blocks[inner].contains { block in
                    if case .paragraph = block.kind { return true }
                    if case .heading = block.kind { return true }
                    return false
                } ? longest(1) : 0)
            }
            switch sizing {
            case .minContent: wanted = longestUnbreakable()
            case .maxContent: wanted = longest(100_000)
            case .fitContent: wanted = min(room, longest(100_000))
            }
            let padding = box.inlineSize - room
            let length = max(box.minInlineSize, (wanted + padding).rounded(.up))
            let delta = box.inlineSize - length
            guard delta != 0 else { continue }
            section.boxes[boxIndex].inlineSize = length
            let edge = box.inlineStart + length
            for index in inner {
                section.blocks[index].style.marginEnd += delta
                if case .boxStart(let nested) = section.blocks[index].kind {
                    let nestedBox = section.boxes[nested]
                    section.boxes[nested].inlineSize = max(0, min(nestedBox.inlineSize, edge - nestedBox.inlineStart))
                }
            }
        }
        return section
    }

    /// Sets some of a section's blocks into pages (or, in columns, columns) of `geometry`,
    /// in the section's writing mode or the one given.
    func layout(_ section: STSection, blocks range: Range<Int>, geometry: STPageGeometry, inColumns: Bool, vertical givenVertical: Bool? = nil) -> [STPage] {
        let vertical = givenVertical ?? (section.writingMode == .vertical)
        let content = geometry.content
        let inlineExtent = vertical ? content.height : content.width
        let blockExtent = vertical ? content.width : content.height
        var pages: [STPage] = []
        var page = STPage()
        var position: CGFloat = 0
        /// The margin waiting to be put in before the next thing placed: the positive and negative parts.
        var carryPositive: CGFloat = 0, carryNegative: CGFloat = 0
        /// The boxes open now, outermost first: the box, and its part on this page (nil until
        /// something of it is placed).
        var open: [(box: Int, placed: Int?)] = []

        func carry(_ margin: CGFloat) {
            if margin >= 0 { carryPositive = max(carryPositive, margin) } else { carryNegative = min(carryNegative, margin) }
        }
        func takeCarry() {
            position += carryPositive + carryNegative
            carryPositive = 0
            carryNegative = 0
        }
        /// The open boxes' parts begin on this page where they have not yet.
        func placeOpenBoxes() {
            for index in open.indices where open[index].placed == nil {
                let box = section.boxes[open[index].box]
                let parent = open[..<index].last?.placed
                page.boxes.append(STPlacedBox(
                    box: open[index].box, inline: box.inlineStart, block: position, inlineSize: box.inlineSize, blockSize: 0,
                    startsHere: !continued.contains(open[index].box), endsHere: false, parent: parent,
                    lines: page.lines.count..<page.lines.count, images: page.images.count..<page.images.count))
                open[index].placed = page.boxes.count - 1
            }
        }
        var continued = Set<Int>()
        /// Before something is placed: the margins put in, the boxes begun.
        func beginContent() {
            if open.contains(where: { $0.placed == nil }) {
                takeCarry()
                placeOpenBoxes()
            } else {
                takeCarry()
            }
        }
        func closeBox(_ placed: Int, at end: CGFloat, ends: Bool) {
            page.boxes[placed].blockSize = max(0, end - page.boxes[placed].block)
            page.boxes[placed].endsHere = ends
            page.boxes[placed].lines = page.boxes[placed].lines.lowerBound..<page.lines.count
            page.boxes[placed].images = page.boxes[placed].images.lowerBound..<page.images.count
        }
        func newPage() {
            // The open boxes are cut here and go on on the next page.
            for (box, placed) in open {
                if let placed { closeBox(placed, at: position, ends: false) }
                continued.insert(box)
            }
            if !page.isEmpty || !page.anchors.isEmpty || !page.boxes.isEmpty { pages.append(page) }
            page = STPage()
            position = 0
            carryPositive = 0
            carryNegative = 0
            floats = []
            for index in open.indices {
                open[index].placed = nil
            }
            // A box split before goes on from the page's start, its padding not again.
            if !open.isEmpty { placeOpenBoxes() }
        }

        /// Blocks a table set already (its cells'), passed over.
        var skipUntil = 0
        /// Floats beside which lines are shortened: at the lines' end or not, how much of
        /// the line they take, and where across they end.
        var floats: [(atEnd: Bool, length: CGFloat, end: CGFloat)] = []

        /// A table: its columns' lengths from what they are given and what their cells hold,
        /// its rows one after another (a page breaks between them), each cell's blocks set in
        /// its column, the cells' boxes drawn about them.
        func setTable(_ table: STTable, block: STBlock) {
            let style = block.style
            let available = max(1, inlineExtent - style.marginStart - style.marginEnd)
            let columns = table.rows.map { $0.reduce(0) { $0 + max(1, $1.span) } }.max() ?? 0
            guard columns > 0 else { return }
            let spacing = table.collapses ? 0 : table.spacing
            let tableBox = table.box.map { section.boxes[$0] }
            let tablePadding = (tableBox?.paddingStart ?? 0) + (tableBox?.paddingEnd ?? 0)
            var tableLength: CGFloat?
            switch table.length {
            case .points(let points): tableLength = points
            case .percent(let percent): tableLength = available * percent / 100
            case .auto: break
            }
            // What each cell needs at least (its longest word) and at most (all on one line).
            func contentLengths(_ cell: STTable.Cell) -> (CGFloat, CGFloat) {
                let box = section.boxes[cell.box]
                var least: CGFloat = 0, most: CGFloat = 0
                for blockIndex in cell.blocks {
                    let inner = section.blocks[blockIndex]
                    guard case .paragraph = inner.kind else {
                        if case .heading = inner.kind {} else { continue }
                        continue
                    }
                    let set = setBlock(inner, index: blockIndex, vertical: vertical)
                    let margins = inner.style.marginStart + inner.style.marginEnd
                    for range in breakLines(set, firstMeasure: .greatestFiniteMagnitude, measure: .greatestFiniteMagnitude) {
                        most = max(most, set.items[range].reduce(0) { $0 + $1.squeezedAdvance } + margins + max(0, inner.style.textIndent))
                    }
                    for range in breakLines(set, firstMeasure: 0.5, measure: 0.5) {
                        least = max(least, set.items[range].filter { !$0.isSpace }.reduce(0) { $0 + $1.squeezedAdvance } + margins)
                    }
                }
                return (least + box.paddingStart + box.paddingEnd, most + box.paddingStart + box.paddingEnd)
            }
            var given = [CGFloat?](repeating: nil, count: columns)
            var least = [CGFloat](repeating: 0, count: columns)
            var most = [CGFloat](repeating: 0, count: columns)
            for row in table.rows {
                var column = 0
                for cell in row {
                    guard column < columns else { break }
                    let (low, high) = contentLengths(cell)
                    if cell.span <= 1 {
                        least[column] = max(least[column], low)
                        most[column] = max(most[column], high)
                        switch cell.length {
                        case .points(let points): given[column] = max(given[column] ?? 0, points)
                        case .percent(let percent):
                            let whole = (tableLength ?? available) - tablePadding - spacing * CGFloat(columns + 1)
                            given[column] = max(given[column] ?? 0, whole * percent / 100)
                        case .auto: break
                        }
                    }
                    column += max(1, cell.span)
                }
            }
            let gaps = spacing * CGFloat(columns + 1) + tablePadding
            let wanted = (0..<columns).reduce(CGFloat(0)) { $0 + max(given[$1] ?? most[$1], least[$1]) }
            let whole = max(1, (tableLength ?? min(available, wanted + gaps)) - gaps)
            var lengths = (0..<columns).map { max(given[$0] ?? most[$0], least[$0]) }
            let total = lengths.reduce(0, +)
            if total < whole {
                // The room left to the columns given no length (all, if each has one), by what they hold.
                let free = (0..<columns).filter { given[$0] == nil }
                let receivers = free.isEmpty ? Array(0..<columns) : free
                let weight = receivers.reduce(CGFloat(0)) { $0 + max(lengths[$1], 1) }
                for column in receivers { lengths[column] += (whole - total) * max(lengths[column], 1) / weight }
            } else if total > whole {
                // Narrowed towards their least, the columns given no length first.
                var excess = total - whole
                for pass in 0..<2 {
                    let candidates = (0..<columns).filter { pass == 1 || given[$0] == nil }
                    let room = candidates.reduce(CGFloat(0)) { $0 + max(0, lengths[$1] - least[$1]) }
                    guard room > 0, excess > 0 else { continue }
                    let take = min(excess, room)
                    for column in candidates { lengths[column] -= take * max(0, lengths[column] - least[column]) / room }
                    excess -= take
                }
                if excess > 0.5 {
                    let sum = lengths.reduce(0, +)
                    lengths = lengths.map { $0 * whole / max(sum, 1) }
                }
            }
            let tableInline = lengths.reduce(0, +) + gaps
            let tableStart = style.marginStart + (style.align == .center ? max(0, (available - tableInline) / 2) : 0)
            carry(style.marginBefore)
            beginContent()
            // The table's own box, about its rows.
            var tablePlaced: Int?
            func openTableBox() {
                guard let boxIndex = table.box else { return }
                page.boxes.append(STPlacedBox(
                    box: boxIndex, inline: tableStart, block: position, inlineSize: tableInline, blockSize: 0,
                    startsHere: true, endsHere: false, parent: open.last?.placed,
                    lines: page.lines.count..<page.lines.count, images: page.images.count..<page.images.count))
                tablePlaced = page.boxes.count - 1
            }
            func closeTableBox(ends: Bool) {
                guard let placed = tablePlaced else { return }
                closeBox(placed, at: position, ends: ends)
            }
            openTableBox()
            position += (tableBox?.paddingBefore ?? 0) + spacing
            var rowsPlaced = 0
            for row in table.rows {
                // Each cell's lines at its column's length.
                var cells: [(cell: STTable.Cell, inline: CGFloat, length: CGFloat, lines: [(STLine, CGFloat)], height: CGFloat)] = []
                var column = 0
                var inline = tableStart + (tableBox?.paddingStart ?? 0) + spacing
                for cell in row {
                    guard column < columns else { break }
                    let span = min(max(1, cell.span), columns - column)
                    let length = lengths[column..<(column + span)].reduce(0, +) + spacing * CGFloat(span - 1)
                    let box = section.boxes[cell.box]
                    let contentStart = inline + box.paddingStart
                    let measure = max(1, length - box.paddingStart - box.paddingEnd)
                    var placed: [(STLine, CGFloat)] = []
                    var height: CGFloat = 0
                    var previousAfter: CGFloat = 0
                    for blockIndex in cell.blocks {
                        let inner = section.blocks[blockIndex]
                        switch inner.kind {
                        case .paragraph, .heading:
                            height += placed.isEmpty ? 0 : max(previousAfter, inner.style.marginBefore)
                            let set = setBlock(inner, index: blockIndex, vertical: vertical)
                            let innerMeasure = max(inner.baseStyle.size, measure - inner.style.marginStart - inner.style.marginEnd)
                            for line in lines(of: set, measure: innerMeasure, inlineStart: contentStart + inner.style.marginStart) {
                                placed.append((line, height))
                                height += line.extent
                            }
                            previousAfter = inner.style.marginAfter
                        default:
                            continue
                        }
                    }
                    cells.append((cell, inline, length, placed, height))
                    inline += length + spacing
                    column += span
                }
                let rowHeight = cells.map { $0.height + section.boxes[$0.cell.box].paddingBefore + section.boxes[$0.cell.box].paddingAfter }.max() ?? 0
                if position + rowHeight > blockExtent + 0.01, !page.isEmpty {
                    if rowsPlaced == 0 {
                        // Nothing of it on this page yet: the whole table on the next.
                        if let placed = tablePlaced, placed == page.boxes.count - 1 { page.boxes.removeLast() }
                        tablePlaced = nil
                        newPage()
                        openTableBox()
                        position += (tableBox?.paddingBefore ?? 0) + spacing
                    } else {
                        closeTableBox(ends: false)
                        newPage()
                        openTableBox()
                        if let placed = tablePlaced { page.boxes[placed].startsHere = false }
                    }
                }
                rowsPlaced += 1
                let rowStart = position
                for cell in cells {
                    let box = section.boxes[cell.cell.box]
                    let contentRoom = rowHeight - box.paddingBefore - box.paddingAfter
                    let shift = max(0, contentRoom - cell.height) * cell.cell.align
                    let firstLine = page.lines.count
                    page.boxes.append(STPlacedBox(
                        box: cell.cell.box, inline: cell.inline, block: rowStart, inlineSize: cell.length, blockSize: rowHeight,
                        startsHere: true, endsHere: true, parent: tablePlaced ?? open.last?.placed,
                        lines: firstLine..<firstLine, images: page.images.count..<page.images.count))
                    let placedBox = page.boxes.count - 1
                    for (line, offset) in cell.lines {
                        page.lines.append(STPlacedLine(line: line, blockPosition: rowStart + box.paddingBefore + shift + offset))
                        page.extend(line.range)
                    }
                    page.boxes[placedBox].lines = firstLine..<page.lines.count
                }
                position = rowStart + rowHeight + spacing
            }
            position += tableBox?.paddingAfter ?? 0
            closeTableBox(ends: true)
            carry(style.marginAfter)
        }

        /// The lines of a heading that ends the page, nothing after it, taken off the page (to
        /// go with what follows it onto the next): where they start and end, its anchor and its
        /// end margin.
        func takeTrailingHeading() -> (lines: [STPlacedLine], start: CGFloat, end: CGFloat, anchors: [String], marginAfter: CGFloat)? {
            guard open.isEmpty, let last = page.lines.last, case .heading = last.line.block.block.kind else { return nil }
            let blockIndex = last.line.block.index
            guard let first = page.lines.lastIndex(where: { $0.line.block.index != blockIndex }).map({ $0 + 1 }) ?? Optional(0),
                  first > 0 else { return nil }
            let lines = Array(page.lines[first...])
            let start = lines[0].blockPosition
            // Nothing else placed after it, nor beside it.
            guard !page.images.contains(where: { $0.block + $0.blockSize > start + 0.01 }),
                  !page.boxes.contains(where: { $0.block + $0.blockSize > start + 0.01 }),
                  !page.flows.contains(where: { $0.block + $0.blockSize > start + 0.01 }) else { return nil }
            let block = section.blocks[blockIndex]
            page.lines.removeLast(lines.count)
            let textStart = lines.map(\.line.range.lowerBound).min() ?? page.range.upperBound
            page.range = page.range.lowerBound..<max(page.range.lowerBound, min(page.range.upperBound, textStart))
            var anchors: [String] = []
            if let anchor = block.anchor, page.anchors.last == anchor { anchors = [page.anchors.removeLast()] }
            let end = (lines.last.map { $0.blockPosition + $0.line.extent }) ?? start
            return (lines, start, end, anchors, block.style.marginAfter)
        }

        /// A new page, a heading that ended the last going on to it (its lines at the page's
        /// start): whether one did.
        func newPageWithHeading(marginBefore: CGFloat) -> Bool {
            let heading = takeTrailingHeading()
            newPage()
            guard let heading else { return false }
            for line in heading.lines {
                page.lines.append(STPlacedLine(line: line.line, blockPosition: line.blockPosition - heading.start))
                page.extend(line.line.range)
            }
            page.anchors += heading.anchors
            position = heading.end - heading.start
            carry(heading.marginAfter)
            carry(marginBefore)
            return true
        }

        /// Columns: as long as they need to be to hold their blocks in their number (balanced),
        /// or the box's length; on as many pages as they take.
        func setColumns(_ columns: STColumns, block: STBlock, index: Int) {
            let style = block.style
            let available = max(1, inlineExtent - style.marginStart - style.marginEnd)
            var count = max(1, columns.count)
            if let width = columns.width, width > 0 {
                let fitting = Int(((available + columns.gap) / (width + columns.gap)).rounded(.down))
                count = max(1, columns.count > 1 ? min(columns.count, fitting) : fitting)
            }
            let length = max(1, (available - columns.gap * CGFloat(count - 1)) / CGFloat(count))
            carry(style.marginBefore)
            if blockExtent - position - carryPositive - carryNegative < blockExtent / 6, !page.isEmpty {
                _ = newPageWithHeading(marginBefore: style.marginBefore)
            }
            beginContent()
            func run(_ height: CGFloat) -> [STPage] {
                // The blocks in columns are given as from a column's start, their end margins
                // making them as long as one: the page's length along the lines.
                let size = vertical ? CGSize(width: height, height: inlineExtent) : CGSize(width: inlineExtent, height: height)
                return layout(section, blocks: (index + 1)..<columns.end, geometry: STPageGeometry(size: size, top: 0, left: 0, bottom: 0, right: 0),
                              inColumns: true, vertical: vertical)
            }
            /// Whether columns this long hold it all, no box kept whole (break-inside: avoid) split.
            func holds(_ pages: [STPage]) -> Bool {
                pages.count <= count && !pages.contains { page in
                    page.boxes.contains { !$0.startsHere && section.boxes.indices.contains($0.box) && section.boxes[$0.box].keepTogether }
                }
            }
            var height = max(1, columns.blockSize ?? (blockExtent - position))
            var pages = run(height)
            // Columns that run on past this page but would be whole on the next begin there.
            if !holds(pages), !page.isEmpty, columns.blockSize == nil, position > 0 {
                let whole = run(blockExtent)
                if holds(whole) {
                    let moved = newPageWithHeading(marginBefore: style.marginBefore)
                    beginContent()
                    height = blockExtent - position
                    pages = moved ? run(height) : whole
                }
            }
            if columns.balances, pages.count <= count {
                // The shortest columns that hold it all.
                var low: CGFloat = 1, high = height
                for _ in 0..<18 {
                    let middle = (low + high) / 2
                    if holds(run(middle)) { high = middle } else { low = middle }
                }
                height = columns.blockSize ?? high
                pages = run(high)
            }
            var used: CGFloat = 0
            for (number, column) in pages.enumerated() {
                let place = number % count
                if number > 0, place == 0 {
                    // On to the next page, as many again.
                    position += used
                    used = 0
                    newPage()
                }
                let dx = style.marginStart + CGFloat(place) * (length + columns.gap)
                let dy = position
                let lineBase = page.lines.count, imageBase = page.images.count, boxBase = page.boxes.count
                for placed in column.lines {
                    let line = placed.line
                    let moved = STLine(block: line.block, items: line.items, positions: line.positions.map { $0 + dx }, advances: line.advances,
                                       extent: line.extent, emStart: line.emStart, emSize: line.emSize, baseline: line.baseline)
                    page.lines.append(STPlacedLine(line: moved, blockPosition: placed.blockPosition + dy))
                    page.extend(line.range)
                }
                for var image in column.images {
                    image = STPlacedImage(id: image.id, blendMode: image.blendMode, fit: image.fit, fitPosition: image.fitPosition,
                                          textOffset: image.textOffset, blockIndex: image.blockIndex, inline: image.inline + dx,
                                          block: image.block + dy, inlineSize: image.inlineSize, blockSize: image.blockSize)
                    page.images.append(image)
                    page.extend(image.textOffset..<(image.textOffset + 1))
                }
                for box in column.boxes {
                    page.boxes.append(STPlacedBox(
                        box: box.box, inline: box.inline + dx, block: box.block + dy, inlineSize: box.inlineSize, blockSize: box.blockSize,
                        startsHere: box.startsHere, endsHere: box.endsHere, parent: box.parent.map { $0 + boxBase } ?? open.last?.placed,
                        lines: (box.lines.lowerBound + lineBase)..<(box.lines.upperBound + lineBase),
                        images: (box.images.lowerBound + imageBase)..<(box.images.upperBound + imageBase)))
                }
                for rule in column.rules {
                    page.rules.append(STPlacedBackground(color: rule.color, inline: rule.inline + dx, block: rule.block + dy, inlineSize: rule.inlineSize, blockSize: rule.blockSize))
                }
                page.anchors += column.anchors
                if place > 0, columns.ruleStyle != .none, columns.ruleWidth > 0 {
                    page.rules.append(STPlacedBackground(
                        color: columns.ruleColor ?? settings.textColor, inline: dx - columns.gap / 2 - columns.ruleWidth / 2, block: dy,
                        inlineSize: columns.ruleWidth, blockSize: height))
                }
                used = height
            }
            position += pages.isEmpty ? 0 : used
            carry(style.marginAfter)
        }

        for index in range {
            let block = section.blocks[index]
            if index < skipUntil { continue }
            let style = block.style
            switch block.kind {
            case .columns(let columns):
                setColumns(columns, block: block, index: index)
                skipUntil = columns.end
                continue
            case .flow(let flow):
                skipUntil = flow.end
                // Its lines run across the page's: as long as the page (or as it is given)
                // while it is set, then as long as its longest line.
                let available = max(1, inlineExtent - style.marginStart - style.marginEnd)
                let lineRoom = min(flow.lineLength ?? blockExtent, blockExtent)
                func setFlow(_ lineLength: CGFloat) -> STPage? {
                    let size = flow.vertical ? CGSize(width: available, height: lineLength) : CGSize(width: lineLength, height: available)
                    return layout(section, blocks: (index + 1)..<flow.end, geometry: STPageGeometry(size: size, top: 0, left: 0, bottom: 0, right: 0),
                                  inColumns: false, vertical: flow.vertical).first
                }
                guard let made = setFlow(lineRoom) else { continue }
                var lineLength = lineRoom
                if flow.lineLength == nil {
                    let longest = made.lines.map { line in
                        zip(line.line.positions, line.line.advances).map { $0 + $1 }.max() ?? 0
                    }.max() ?? 0
                    if longest > 0 { lineLength = min(lineRoom, longest + 1) }
                }
                let used = max(
                    made.lines.map { $0.blockPosition + $0.line.extent }.max() ?? 0,
                    made.images.map { $0.block + $0.blockSize }.max() ?? 0,
                    made.boxes.map { $0.block + $0.blockSize }.max() ?? 0)
                carry(style.marginBefore)
                if position + carryPositive + carryNegative + lineLength > blockExtent + 0.01, !page.isEmpty { newPage() }
                beginContent()
                let offset = flow.centered ? max(0, (available - used) / 2) : 0
                page.flows.append(STPlacedFlow(
                    page: made, vertical: flow.vertical, inline: style.marginStart + offset, block: position,
                    inlineSize: used, blockSize: lineLength))
                if made.range != 0..<0 || !made.lines.isEmpty { page.extend(made.range) }
                page.anchors += made.anchors
                position += lineLength
                carry(style.marginAfter)
                continue
            case .table(let table):
                if let anchor = block.anchor { page.anchors.append(anchor) }
                setTable(table, block: block)
                skipUntil = table.end
                continue
            case .boxStart(let boxIndex):
                let box = section.boxes[boxIndex]
                if box.pageBreakBefore || (inColumns && box.columnBreakBefore), !page.isEmpty { newPage() }
                carry(box.marginBefore)
                // Kept whole where it fits (break-inside: avoid).
                if box.keepTogether, !page.isEmpty, let end = section.blocks[index...].firstIndex(where: {
                    if case .boxEnd(let other) = $0.kind { return other == boxIndex }
                    return false
                }) {
                    let measured = layout(section, blocks: index..<(end + 1), geometry: geometry, inColumns: inColumns, vertical: vertical)
                    if measured.count == 1, let only = measured.first {
                        let size = (only.lines.map { $0.blockPosition + $0.line.extent } + only.boxes.map { $0.block + $0.blockSize }).max() ?? 0
                        if position + carryPositive + carryNegative + size > blockExtent + 0.01 { newPage() }
                    } else if measured.count > 1 {
                        newPage()
                    }
                }
                // Not begun where its border and padding and its first line do not fit: no
                // part of a box with nothing in it at a page's or column's end.
                if !page.isEmpty, !box.fixedBlockSize {
                    var room = box.paddingBefore
                    scan: for block in section.blocks[(index + 1)...] {
                        switch block.kind {
                        case .boxStart(let inner):
                            room += max(0, section.boxes[inner].marginBefore) + section.boxes[inner].paddingBefore
                        case .paragraph, .heading:
                            room += max(0, block.style.marginBefore)
                                + block.baseStyle.size * max(block.style.lineHeight, settings.minimumLineHeight)
                            break scan
                        default:
                            break scan
                        }
                    }
                    if position + carryPositive + carryNegative + room > blockExtent + 0.01 { newPage() }
                }
                // A box of its own size that fits on a page is not split.
                if box.fixedBlockSize, box.minBlockSize <= blockExtent, !page.isEmpty,
                   position + carryPositive + carryNegative + box.minBlockSize > blockExtent + 0.01 {
                    newPage()
                }
                open.append((boxIndex, nil))
                if box.paddingBefore > 0 || box.isDrawn {
                    // Its border and padding stop the margins collapsing through it.
                    beginContent()
                    position += box.paddingBefore
                }
                continue
            case .boxEnd(let boxIndex):
                guard let at = open.lastIndex(where: { $0.box == boxIndex }) else { continue }
                let box = section.boxes[boxIndex]
                if open[at].placed == nil { beginContent() }
                if box.paddingAfter > 0 || box.isDrawn || box.minBlockSize > 0 { takeCarry() }
                position += box.paddingAfter
                if let placed = open[at].placed {
                    let start = page.boxes[placed].block
                    let size = position - start
                    if box.minBlockSize > size, page.boxes[placed].startsHere {
                        let slack = box.minBlockSize - size
                        if box.centersContent {
                            // What is inside goes down to the middle.
                            let shift = slack / 2
                            let lines = page.boxes[placed].lines.lowerBound..<page.lines.count
                            for line in lines {
                                page.lines[line] = STPlacedLine(line: page.lines[line].line, blockPosition: page.lines[line].blockPosition + shift)
                            }
                            for image in page.boxes[placed].images.lowerBound..<page.images.count {
                                let placedImage = page.images[image]
                                page.images[image] = STPlacedImage(
                                    id: placedImage.id, blendMode: placedImage.blendMode, fit: placedImage.fit, fitPosition: placedImage.fitPosition,
                                    textOffset: placedImage.textOffset, blockIndex: placedImage.blockIndex,
                                    inline: placedImage.inline, block: placedImage.block + shift,
                                    inlineSize: placedImage.inlineSize, blockSize: placedImage.blockSize)
                            }
                            for inner in (placed + 1)..<page.boxes.count { page.boxes[inner].block += shift }
                        }
                        position = start + box.minBlockSize
                    } else if box.fixedBlockSize, page.boxes[placed].startsHere {
                        // Its own size: what it holds runs out of it.
                        position = start + box.minBlockSize
                    }
                    closeBox(placed, at: position, ends: true)
                }
                open.remove(at: at)
                continued.remove(boxIndex)
                carry(box.marginAfter)
                if box.pageBreakAfter || (inColumns && box.columnBreakAfter) { newPage() }
                continue
            default:
                break
            }
            if style.pageBreakBefore || (inColumns && style.columnBreakBefore), !page.isEmpty { newPage() }
            if let anchor = block.anchor { page.anchors.append(anchor) }
            carry(style.marginBefore)
            let inlineStart = style.marginStart
            let measure = max(block.baseStyle.size, inlineExtent - style.marginStart - style.marginEnd)
            var backgroundStart: CGFloat?
            switch block.kind {
            case .image(let id, let natural, let fit):
                var inlineSize = vertical ? natural.height : natural.width
                var blockSize = vertical ? natural.width : natural.height
                let remaining = blockExtent - position - carryPositive - carryNegative
                if blockSize > remaining, !page.isEmpty, blockSize <= blockExtent || fit {
                    newPage()
                }
                beginContent()
                backgroundStart = position
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
                let imageStyle = block.inlines.first?.style
                page.images.append(STPlacedImage(
                    id: id, blendMode: imageStyle?.blendMode ?? .normal, fit: imageStyle?.objectFit ?? .fill,
                    fitPosition: imageStyle?.objectPosition ?? CGPoint(x: 0.5, y: 0.5), textOffset: block.offset, blockIndex: index,
                    inline: inlineStart + alignOffset, block: position, inlineSize: inlineSize, blockSize: blockSize))
                page.extend(block.offset..<(block.offset + 1))
                position += blockSize
            case .rule:
                if position + carryPositive + carryNegative + 1 > blockExtent { newPage() }
                beginContent()
                backgroundStart = position
                page.rules.append(STPlacedBackground(color: block.baseStyle.color ?? settings.textColor, inline: inlineStart, block: position, inlineSize: measure, blockSize: 1))
                position += 1
            case .float(let id, let size, let atEnd, let gap, let after):
                let inlineSize = min(vertical ? size.height : size.width, measure)
                let blockSize = vertical ? size.width : size.height
                if position + carryPositive + carryNegative + blockSize > blockExtent + 0.01, !page.isEmpty { newPage() }
                beginContent()
                // Beside the floats there already.
                let startTaken = floats.filter { !$0.atEnd && $0.end > position }.map(\.length).reduce(0, +)
                let endTaken = floats.filter { $0.atEnd && $0.end > position }.map(\.length).reduce(0, +)
                let inline = atEnd ? inlineStart + measure - endTaken - inlineSize : inlineStart + startTaken
                let imageStyle = block.inlines.first?.style
                page.images.append(STPlacedImage(
                    id: id, blendMode: imageStyle?.blendMode ?? .normal, textOffset: block.offset, blockIndex: index,
                    inline: inline, block: position, inlineSize: inlineSize, blockSize: blockSize))
                page.extend(block.offset..<(block.offset + 1))
                floats.append((atEnd, inlineSize + gap, position + blockSize + after))
                // What follows starts beside it, not after it.
                carry(style.marginAfter)
                continue
            case .boxStart, .boxEnd, .table:
                break
            default:
                let set = setBlockWithFirstLine(block, index: index, vertical: vertical, measure: measure)
                let lines: [STLine]
                if floats.contains(where: { $0.end > position + carryPositive + carryNegative }) {
                    // Shortened beside the floats, as far across as they go.
                    let top = position + carryPositive + carryNegative
                    lines = self.lines(of: set) { across in
                        let at = top + across
                        let startTaken = floats.filter { !$0.atEnd && $0.end > at }.map(\.length).reduce(0, +)
                        let endTaken = floats.filter { $0.atEnd && $0.end > at }.map(\.length).reduce(0, +)
                        return (inlineStart + startTaken, measure - startTaken - endTaken)
                    }
                } else {
                    lines = self.lines(of: set, measure: measure, inlineStart: inlineStart)
                }
                // Kept whole where it fits on a page (break-inside: avoid).
                if style.keepTogether, !page.isEmpty {
                    let total = lines.reduce(CGFloat(0)) { $0 + $1.extent }
                    if position + carryPositive + total > blockExtent + 0.01, total <= blockExtent { newPage() }
                }
                // Where the page breaks the block: no fewer lines than `orphans` before it, nor
                // than `widows` after it, where the page can be ended sooner.
                var breakBefore: Int?
                func fitting(from first: Int) -> Int {
                    var room = blockExtent - position - carryPositive - carryNegative
                    var count = 0
                    for line in lines[first...] {
                        if line.extent > room + 0.01 { break }
                        room -= line.extent
                        count += 1
                    }
                    return count
                }
                func plannedBreak(from first: Int) -> Int? {
                    let left = lines.count - first
                    var fit = fitting(from: first)
                    guard fit < left else { return nil }
                    if left - fit < style.widows { fit = left - style.widows }
                    if fit < style.orphans { fit = 0 }
                    return first + max(0, fit)
                }
                if !page.isEmpty || position > 0 { breakBefore = plannedBreak(from: 0) }
                for (number, line) in lines.enumerated() {
                    let overflows = position + carryPositive + carryNegative + line.extent > blockExtent + 0.01
                    if (number == breakBefore || overflows), !page.isEmpty {
                        if let color = style.background, let start = backgroundStart, position > start {
                            page.backgrounds.append(STPlacedBackground(color: color, inline: 0, block: start, inlineSize: inlineExtent, blockSize: position - start))
                        }
                        newPage()
                        backgroundStart = nil
                        breakBefore = plannedBreak(from: number)
                    }
                    beginContent()
                    if backgroundStart == nil { backgroundStart = position }
                    page.lines.append(STPlacedLine(line: line, blockPosition: position))
                    page.extend(line.range)
                    position += line.extent
                }
            }
            if let color = style.background, let start = backgroundStart {
                page.backgrounds.append(STPlacedBackground(color: color, inline: 0, block: max(0, start), inlineSize: inlineExtent, blockSize: max(0, position - start)))
            }
            carry(style.marginAfter)
            if style.pageBreakAfter || (inColumns && style.columnBreakAfter) { newPage() }
        }
        for (_, placed) in open {
            if let placed { closeBox(placed, at: position, ends: true) }
        }
        if !page.isEmpty || !page.boxes.isEmpty || pages.isEmpty { pages.append(page) }
        return pages
    }
}

private extension CGFloat {
    var nonZero: CGFloat? { self > 0 ? self : nil }
}
