/*
STPageModel.swift

Part of the page layer added to stone_engine for SMSReader (see PAGE_LAYOUT.md): styled text set into
pages, for EPUB books. MIT License, as stone_engine.
*/

import CoreGraphics
import Foundation

/// How lines run: across, top to bottom (horizontal-tb), or down, right to left (vertical-rl).
public enum STWritingMode: Int, Sendable, Hashable {
    case horizontal
    case vertical
}

/// A colour, kept as plain numbers so that styles can be compared and sent between threads.
public struct STColor: Sendable, Hashable {
    public var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = STColor(red: 0, green: 0, blue: 0)
    public static let white = STColor(red: 1, green: 1, blue: 1)

    public var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: alpha) }

    /// How light the colour looks, 0 (black) to 1 (white).
    public var luminance: CGFloat { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
}

/// The face a run of text is set in: the reader's Mincho or Gothic (`serif` and
/// `sans-serif` in CSS), or a font of the book's own by its PostScript name.
public enum STFontFamily: Sendable, Hashable {
    case mincho
    case gothic
    case named(String)
}

/// 圏点・傍点 (CSS text-emphasis), set beside each character on the line's over side.
public enum STEmphasisMark: Int, Sendable, Hashable {
    case sesame, sesameOpen, dot, dotOpen, circle, circleOpen, doubleCircle, doubleCircleOpen, triangle, triangleOpen

    /// The character drawn for the mark.
    public var character: String {
        switch self {
        case .sesame: "﹅"
        case .sesameOpen: "﹆"
        case .dot: "•"
        case .dotOpen: "◦"
        case .circle: "●"
        case .circleOpen: "○"
        case .doubleCircle: "◉"
        case .doubleCircleOpen: "◎"
        case .triangle: "▲"
        case .triangleOpen: "△"
        }
    }
}

/// How a character stands in a vertical line (CSS text-orientation).
public enum STOrientation: Int, Sendable, Hashable {
    /// As Unicode's vertical orientation (UAX #50) says: CJK upright, Latin turned.
    case mixed
    /// Every character upright.
    case upright
    /// Every character turned a quarter clockwise.
    case sideways
}

/// The style of a run of text. Lengths are in points.
public struct STTextStyle: Sendable, Hashable {
    public var family: STFontFamily = .mincho
    public var size: CGFloat = 16
    public var bold = false
    public var italic = false
    public var color: STColor? = nil
    /// Added after each character, in points.
    public var letterSpacing: CGFloat = 0
    /// Painted behind the characters (an inline element's background colour).
    public var background: STColor? = nil
    public var emphasis: STEmphasisMark? = nil
    public var emphasisColor: STColor? = nil
    /// A line on the over side (right in vertical lines), the under side, through the middle.
    public var overline = false
    public var underline = false
    public var lineThrough = false
    public var orientation: STOrientation = .mixed
    /// Raised (positive) or lowered, in points: super- and subscripts.
    public var baselineShift: CGFloat = 0
    /// A link the run is part of, by what the caller makes of it.
    public var link: String? = nil

    public init() {}
}

/// How a block (a paragraph, a heading) is set. Lengths are in points; "before" and "after"
/// run in the block direction (top and bottom across, right and left down), "start" and
/// "end" in the inline direction.
public struct STBlockStyle: Sendable, Hashable {
    public enum Align: Int, Sendable, Hashable { case start, center, end, justify }

    public var align: Align = .justify
    /// The last line's alignment (text-align-last); `start` for a justified block.
    public var alignLast: Align = .start
    /// The first line's indent; negative for a hanging indent (with a start margin to match).
    public var textIndent: CGFloat = 0
    public var marginBefore: CGFloat = 0
    public var marginAfter: CGFloat = 0
    public var marginStart: CGFloat = 0
    public var marginEnd: CGFloat = 0
    /// The distance from one line's baseline to the next, as a multiple of the font size.
    public var lineHeight: CGFloat = 1.75
    public var background: STColor? = nil
    public var pageBreakBefore = false
    public var pageBreakAfter = false
    /// The block is not split between pages where it fits on one.
    public var keepTogether = false

    public init() {}
}

/// Something in a line of text.
public enum STInline: Sendable, Hashable {
    case text(String, STTextStyle)
    /// Ruby (ルビ) over its base: text, and images where a 外字 is part of it. Mono ruby is
    /// one of these for each character, group ruby one over the whole word.
    case ruby(base: [STInline], ruby: String, style: STTextStyle)
    /// Upright in a vertical line, the characters side by side in the space of one
    /// (縦中横, CSS text-combine-upright).
    case combined(String, STTextStyle)
    /// An image in the line, by the caller's id, `size` in points (a 外字 is 1em square).
    case image(id: String, size: CGSize, style: STTextStyle)
    /// A forced line break (`<br/>`).
    case lineBreak(STTextStyle)

    var style: STTextStyle {
        switch self {
        case .text(_, let style), .ruby(_, _, let style), .combined(_, let style), .image(_, _, let style), .lineBreak(let style): style
        }
    }

    /// The text this stands for in the block's text (`STBlock.text`): an image is U+FFFC.
    var text: String {
        switch self {
        case .text(let text, _), .combined(let text, _): text
        case .ruby(let base, _, _): base.map(\.text).joined()
        case .image: "\u{FFFC}"
        case .lineBreak: "\n"
        }
    }
}

/// A block of the text: a paragraph, a heading, an image standing alone, a rule, an empty line.
public struct STBlock: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case paragraph
        /// h1–h6.
        case heading(Int)
        /// An image on its own, `size` its natural size in points; `fit` scales it down to
        /// the page where it is larger (the 電書連 guide's `.fit`).
        case image(id: String, size: CGSize, fit: Bool)
        /// A thematic break (hr).
        case rule
    }

    public var kind: Kind
    public var inlines: [STInline]
    public var style: STBlockStyle
    /// The style empty lines and markers take where there is no text.
    public var baseStyle: STTextStyle
    /// Where the block's text starts in its section's text, in UTF-16 units.
    public var offset: Int
    /// A name for the block the caller gives (an element's id), for links into it.
    public var anchor: String?

    public init(kind: Kind = .paragraph, inlines: [STInline], style: STBlockStyle = STBlockStyle(),
                baseStyle: STTextStyle = STTextStyle(), offset: Int = 0, anchor: String? = nil) {
        self.kind = kind
        self.inlines = inlines
        self.style = style
        self.baseStyle = baseStyle
        self.offset = offset
        self.anchor = anchor
    }

    /// The block's text: ruby left out (its base kept), an image as U+FFFC.
    public var text: String { inlines.map(\.text).joined() }

    /// How long the block's text is, in UTF-16 units.
    public var length: Int {
        switch kind {
        case .image: 1
        case .rule: 0
        default: text.utf16.count
        }
    }
}

/// A run of blocks set together: one content document (an EPUB's chapter).
public struct STSection: Sendable, Hashable {
    public var blocks: [STBlock]
    public var writingMode: STWritingMode
    public var background: STColor?

    public init(blocks: [STBlock], writingMode: STWritingMode, background: STColor? = nil) {
        self.blocks = blocks
        self.writingMode = writingMode
        self.background = background
    }

    /// Gives each block its offset in the section's text, one after another.
    public mutating func numberBlocks() {
        var offset = 0
        for index in blocks.indices {
            blocks[index].offset = offset
            offset += blocks[index].length
        }
    }
}

/// What the reader chose of how text is set, over what the book says.
public struct STReaderSettings: Sendable, Hashable {
    /// The size `1em` of the book's body text comes to, in points.
    public var fontSize: CGFloat = 16
    /// The faces the reader's Mincho and Gothic stand for (PostScript names), regular and bold.
    public var minchoFonts = ["HiraMinProN-W3", "HiraMinProN-W6"]
    public var gothicFonts = ["HiraginoSans-W3", "HiraginoSans-W6"]
    /// The book's own fonts are used where it names them; otherwise its faces are the reader's.
    public var usesBookFonts = true
    /// Every run set in this face whatever the book says (the reader's choice of 明朝 or
    /// ゴシック for the whole text); nil to follow the book.
    public var forcedFamily: STFontFamily? = nil
    /// The line height every block is set to at least, as a multiple of its font size.
    public var minimumLineHeight: CGFloat = 1.5
    /// The punctuation squeezed as in Japanese typesetting (約物の詰め) ("stone" mode).
    public var squeezesPunctuation = true
    /// 禁則: no line starting with closing punctuation or small kana, nor ending with opening.
    public var kinsoku = true
    /// 、。 may stand past the line's end (ぶら下げ) rather than be pushed to the next line.
    public var hangsPunctuation = true
    /// The text's colour where the book sets none, and the page's.
    public var textColor: STColor = .black
    public var background: STColor = .white

    public init() {}
}
