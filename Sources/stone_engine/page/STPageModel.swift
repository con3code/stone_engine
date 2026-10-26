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
public indirect enum STFontFamily: Sendable, Hashable {
    case mincho
    case gothic
    /// The reader's fixed-width face (CSS monospace).
    case monospace
    case named(String)
    /// A family of the book's own faces (its `@font-face` rules): each character in the
    /// face for it (its unicode-range, its weight and style), else in `fallback`.
    case faces([STFontFace], fallback: STFontFamily)
}

/// One of a book's own faces: its font's PostScript name, its weight and style, the
/// characters it is for (all, where none are given).
public struct STFontFace: Sendable, Hashable {
    public var name: String
    public var bold: Bool
    public var italic: Bool
    public var ranges: [ClosedRange<UInt32>]

    public init(name: String, bold: Bool, italic: Bool, ranges: [ClosedRange<UInt32>]) {
        self.name = name
        self.bold = bold
        self.italic = italic
        self.ranges = ranges
    }

    func covers(_ scalar: UInt32) -> Bool {
        ranges.isEmpty || ranges.contains { $0.contains(scalar) }
    }
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
    /// The language the text is in (BCP 47, as lang has it): its Han and Hangul set in that
    /// language's faces where it is Chinese or Korean; nil when unknown.
    public var language: String? = nil
    /// The bidirectional isolates and embeddings the text is in (dir on an inline element,
    /// bdi, bdo, unicode-bidi), outermost first.
    public var bidi: [STBidiSpan] = []
    /// How opaque the run is (CSS opacity, as it comes down from the elements it is in).
    public var opacity: CGFloat = 1
    /// Emphasis marks on the under side (left in vertical lines) rather than the over side.
    public var emphasisUnder = false
    /// The lines' colour (the text's when nil) and their kind.
    public var decorationColor: STColor? = nil
    public var decorationStyle: STDecorationStyle = .solid
    /// In a vertical line, the underline on the left (text-underline-position: left) rather
    /// than the right, where Japanese draws its 傍線.
    public var underlineLeft = false
    /// For ruby: set on the under side (left in vertical lines), not the over side, and
    /// how it is spread over a longer base.
    public var rubyUnder = false
    public var rubyAlign: STRubyAlign = .spaceAround
    /// How an image is put on what is under it (mix-blend-mode on an img).
    public var blendMode: CGBlendMode = .normal
    /// OpenType features, by tag ("kern", "liga", "jp90"), as font-feature-settings and the
    /// font-variant properties ask: 0 off, 1 (or another value) on.
    public var fontFeatures: [String: Int] = [:]
    /// The inline elements the run is in that have padding, a border or a background drawn
    /// about their text, outermost first.
    public var inlineBoxes: [STInlineBox] = []
    /// How an image fills its box (object-fit), and where it stands in it (object-position,
    /// parts 0–1 of the room left).
    public var objectFit: STObjectFit = .fill
    public var objectPosition = CGPoint(x: 0.5, y: 0.5)

    public init() {}
}

/// How an image fills its box (CSS object-fit).
public enum STObjectFit: Int, Sendable, Hashable {
    case fill, contain, cover, none, scaleDown
}

/// An inline element's box about its text on each line: padding, border and background.
/// Sides are the line's: before (over), after (under), start, end. The start's padding and
/// border go before its first character, the end's after its last.
public struct STInlineBox: Sendable, Hashable {
    /// Tells the element's runs from those of another.
    public var id: Int
    public var background: STColor?
    public var padding: [CGFloat] = [0, 0, 0, 0]
    public var borderWidths: [CGFloat] = [0, 0, 0, 0]
    public var borderColors: [STColor?] = [nil, nil, nil, nil]
    public var borderStyles: [STBorderStyle] = [.none, .none, .none, .none]

    public init(id: Int) {
        self.id = id
    }

    /// The room it takes before its first character and after its last.
    var startSpace: CGFloat { padding[2] + (borderStyles[2] == .none ? 0 : borderWidths[2]) }
    var endSpace: CGFloat { padding[3] + (borderStyles[3] == .none ? 0 : borderWidths[3]) }
}

/// How ruby shorter than its base stands over it (ruby-align).
public enum STRubyAlign: Int, Sendable, Hashable {
    case start, center, spaceBetween, spaceAround
}

/// The kind of line a text decoration draws (text-decoration-style).
public enum STDecorationStyle: Int, Sendable, Hashable {
    case solid, double, dotted, dashed, wavy
}

extension STColor {
    /// The colour with its alpha multiplied.
    public func faded(_ opacity: CGFloat) -> STColor {
        opacity >= 1 ? self : STColor(red: red, green: green, blue: blue, alpha: alpha * opacity)
    }
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
    /// A list item's marker at the block's start (its UTF-16 length) set outside the lines,
    /// ending at `markerEdge` along them (list-style-position: outside); 0 for none.
    public var outsideMarker: Int = 0
    public var markerEdge: CGFloat = 0
    /// The distance from one line's baseline to the next, as a multiple of the font size.
    public var lineHeight: CGFloat = 1.75
    public var background: STColor? = nil
    public var pageBreakBefore = false
    public var pageBreakAfter = false
    /// The block is not split between pages where it fits on one.
    public var keepTogether = false
    /// A column break before or after it (in columns; a page break where it is not in any).
    public var columnBreakBefore = false
    public var columnBreakAfter = false
    /// The least lines it leaves at a page's (or column's) end before a break, and at the next one's start.
    public var orphans = 2
    public var widows = 2
    /// How fullwidth punctuation is spaced (CSS text-spacing): an opening mark at a line's
    /// start, a closing mark at its end, marks next to each other; the space between
    /// Japanese and Latin letters or digits.
    public var spacingStart: STSpacingStart = .first
    public var spacingEnd: STSpacingEnd = .allow
    public var trimsAdjacent = true
    public var autospaceAlpha = false
    public var autospaceNumeric = false
    /// Where lines may break: word-break, line-break (nil: the reader's 禁則), whether a
    /// word longer than a line is broken (overflow-wrap; nil: broken, so nothing runs off
    /// the page), hyphenated (hyphens: auto, in `language`).
    public var wordBreak: STWordBreak = .normal
    public var lineBreak: STLineBreak? = nil
    public var breaksLongWords: Bool? = nil
    public var hyphenates = false
    /// The paragraph's direction (CSS direction, dir): its lines start on the right where
    /// it is right to left; auto takes it from its first strong letter (dir="auto").
    public var direction: STTextDirection = .ltr
    public var language: String? = nil
    /// hanging-punctuation: an opening mark at the paragraph's start outside the line; 、。
    /// past its end (nil: as the reader chose).
    public var hangsFirst = false
    public var hangsEnd: Bool? = nil

    public init() {}
}

/// An opening mark at a line's start: kept fullwidth, trimmed to half, or kept only at a
/// paragraph's first line (text-spacing: space-start, trim-start, space-first).
public enum STSpacingStart: Int, Sendable, Hashable { case space, trim, first }

/// A closing mark at a line's end: kept fullwidth, trimmed to half, or trimmed only where
/// the line would not hold it otherwise (space-end, trim-end, allow-end).
public enum STSpacingEnd: Int, Sendable, Hashable { case space, trim, allow }

/// word-break.
public enum STWordBreak: Int, Sendable, Hashable { case normal, keepAll, breakAll }

/// line-break: how strict 禁則 is.
public enum STLineBreak: Int, Sendable, Hashable { case loose, normal, strict, anywhere }

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
        /// Where a box (`STSection.boxes`) starts and ends among the blocks: an element with
        /// a border, a background, padding or a size of its own, around the blocks between.
        case boxStart(Int)
        case boxEnd(Int)
        /// A table: its cells' blocks follow it in the section (up to `STTable.end`), set in
        /// their columns and rows when the table is.
        case table(STTable)
        /// An image floated to the lines' start or end (CSS float), the lines after it
        /// shortened beside it: `size` in points (physical), `gap` the space kept between it
        /// and the text along the lines, `after` across them.
        case float(id: String, size: CGSize, atEnd: Bool, gap: CGFloat, after: CGFloat)
        /// Columns (CSS multi-column): the blocks after it, up to `STColumns.end`, set in them.
        case columns(STColumns)
        /// Blocks of the other writing mode (a vertical block in horizontal text, or the
        /// other way): the blocks after it, up to `end`, set in a place of their own.
        case flow(STFlow)
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
    /// The first line's look (::first-line): its text in this style's size (as a multiple of
    /// each run's), colour and weight.
    public var firstLine: STFirstLine?

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
        case .image, .float: 1
        case .rule, .boxStart, .boxEnd, .table, .columns, .flow: 0
        default: text.utf16.count
        }
    }
}

/// How a block's first line differs from the rest (CSS ::first-line).
public struct STFirstLine: Sendable, Hashable {
    public var scale: CGFloat = 1
    public var color: STColor?
    public var bold: Bool?

    public init(scale: CGFloat = 1, color: STColor? = nil, bold: Bool? = nil) {
        self.scale = scale
        self.color = color
        self.bold = bold
    }

    func apply(_ style: STTextStyle) -> STTextStyle {
        var style = style
        style.size *= scale
        if let color { style.color = color }
        if let bold { style.bold = bold }
        return style
    }

    func apply(_ inline: STInline) -> STInline {
        switch inline {
        case .text(let text, let style): .text(text, apply(style))
        case .ruby(let base, let ruby, let style): .ruby(base: base.map(apply), ruby: ruby, style: apply(style))
        case .combined(let text, let style): .combined(text, apply(style))
        case .image(let id, let size, let style): .image(id: id, size: size, style: apply(style))
        case .lineBreak(let style): .lineBreak(apply(style))
        }
    }
}

/// A run of blocks set together: one content document (an EPUB's chapter).
public struct STSection: Sendable, Hashable {
    public var blocks: [STBlock]
    public var writingMode: STWritingMode
    public var background: STColor?
    /// The boxes the blocks' `boxStart` and `boxEnd` stand for.
    public var boxes: [STBox] = []

    public init(blocks: [STBlock], writingMode: STWritingMode, background: STColor? = nil, boxes: [STBox] = []) {
        self.blocks = blocks
        self.writingMode = writingMode
        self.background = background
        self.boxes = boxes
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
    public var monospaceFonts = ["Menlo-Regular", "Menlo-Bold"]
    /// Faces with a true italic for Latin text set in the reader's Mincho, Gothic and fixed-width
    /// faces (Japanese faces have none): regular and bold.
    public var minchoItalicFonts = ["TimesNewRomanPS-ItalicMT", "TimesNewRomanPS-BoldItalicMT"]
    public var gothicItalicFonts = ["HelveticaNeue-Italic", "HelveticaNeue-BoldItalic"]
    public var monospaceItalicFonts = ["Menlo-Italic", "Menlo-BoldItalic"]
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
    /// 縦中横 the reader asks for where the book gives none: in a vertical line of mixed
    /// orientation, a run of up to this many ASCII digits standing apart (not part of a word,
    /// a decimal or a time), and one or two of ! and ?, set upright side by side in one
    /// character's space. 0: only what the book says (text-combine-upright).
    public var combinesDigits = 0
    /// The text's colour where the book sets none, and the page's.
    public var textColor: STColor = .black
    public var background: STColor = .white

    public init() {}
}

/// How a side of a border is drawn (border-style); `none` draws nothing.
public enum STBorderStyle: Int, Sendable, Hashable {
    case none, solid, dashed, dotted, double, groove, ridge, inset, outset
}

/// A shadow behind a box (box-shadow, outer ones).
public struct STShadow: Sendable, Hashable {
    public var x: CGFloat, y: CGFloat, blur: CGFloat, spread: CGFloat
    public var color: STColor
    public var inset = false

    public init(x: CGFloat, y: CGFloat, blur: CGFloat, spread: CGFloat, color: STColor, inset: Bool = false) {
        self.x = x
        self.y = y
        self.blur = blur
        self.spread = spread
        self.color = color
        self.inset = inset
    }
}

/// A layer of a box's background: a picture by the caller's id, or a gradient.
public enum STBackgroundLayer: Sendable, Hashable {
    /// `size` in points (nil: its natural size, from the picture); `repeats` along x and y;
    /// `position` the picture's place as a part (0–1) of the room left, x and y.
    case image(id: String, size: CGSize?, cover: Bool, contain: Bool, repeatX: Bool, repeatY: Bool, position: CGPoint)
    /// `angle` in degrees (CSS: 0 is up, 90 right); stops as colour and place (0–1).
    case linear(angle: CGFloat, stops: [STGradientStop], repeating: Bool)
    case radial(circle: Bool, stops: [STGradientStop], repeating: Bool)
}

public struct STGradientStop: Sendable, Hashable {
    public var color: STColor
    /// Where along the gradient (0–1), or in points for a repeating one; nil to be spread evenly.
    public var position: CGFloat?
    public var points: CGFloat?

    public init(color: STColor, position: CGFloat?, points: CGFloat? = nil) {
        self.color = color
        self.position = position
        self.points = points
    }
}

/// A border drawn from a picture: cut into nine (its corners, sides and middle) at
/// `slices` (top, right, bottom, left, in the picture's pixels, or parts 0–1 of it), the
/// sides stretched or repeated along the box.
public struct STBorderImage: Sendable, Hashable {
    public var id: String
    public var slices: [CGFloat]
    public var slicesArePercent = false
    public var fill = false
    public var repeats = false

    public init(id: String, slices: [CGFloat]) {
        self.id = id
        self.slices = slices
    }
}

/// A box drawn about blocks: its border, background, shadow and outline, its place along
/// the lines and its padding. Sides are physical: top, right, bottom, left.
public struct STBox: Sendable, Hashable {
    public var borderWidths: [CGFloat] = [0, 0, 0, 0]
    /// nil: the text's colour.
    public var borderColors: [STColor?] = [nil, nil, nil, nil]
    public var borderStyles: [STBorderStyle] = [.none, .none, .none, .none]
    /// The corners' radii: top-left, top-right, bottom-right, bottom-left.
    public var radii: [CGFloat] = [0, 0, 0, 0]
    public var background: STColor? = nil
    /// Topmost first, as CSS lists them.
    public var backgroundLayers: [STBackgroundLayer] = []
    /// The background painted to the border's outer edge (border-box) or inside it.
    public var backgroundToBorder = true
    public var shadows: [STShadow] = []
    /// A picture drawn as the border (border-image), in place of its lines.
    public var borderImage: STBorderImage? = nil
    public var outlineWidth: CGFloat = 0
    public var outlineColor: STColor? = nil
    public var outlineStyle: STBorderStyle = .none
    public var outlineOffset: CGFloat = 0
    /// Turned about its middle (CSS transform: rotate), in radians; scaled.
    public var rotation: CGFloat = 0
    public var scale: CGSize = CGSize(width: 1, height: 1)
    public var translation: CGSize = .zero
    /// How what is drawn in the box is put on what is under it (mix-blend-mode), and how
    /// its background pictures are put on its background colour (background-blend-mode).
    public var blendMode: CGBlendMode = .normal
    public var backgroundBlendMode: CGBlendMode = .normal
    public var opacity: CGFloat = 1
    /// Where the border box starts along the lines, from the content area's start, and how long it is.
    public var inlineStart: CGFloat = 0
    public var inlineSize: CGFloat = 0
    /// The margins outside it across the lines (they collapse with those next to them, as
    /// CSS's do), and the border and padding inside it before its first block and after its last.
    public var marginBefore: CGFloat = 0
    public var marginAfter: CGFloat = 0
    public var paddingBefore: CGFloat = 0
    public var paddingAfter: CGFloat = 0
    /// Its least size across the lines, border box (height, min-height); with
    /// `fixedBlockSize`, its size whatever it holds (what is more runs out of it).
    public var minBlockSize: CGFloat = 0
    public var fixedBlockSize = false
    /// What is in it cut at its edges (overflow: hidden, contain: paint).
    public var clips = false
    /// The point it is turned about, as parts (0–1) of it, x and y.
    public var origin = CGPoint(x: 0.5, y: 0.5)
    /// Its content set in the middle across where the box is larger than it (flex and grid centring).
    public var centersContent = false
    /// A box split between pages drawn whole on each (box-decoration-break: clone), not cut.
    public var cloneDecoration = false
    public var pageBreakBefore = false
    public var pageBreakAfter = false
    public var keepTogether = false
    public var columnBreakBefore = false
    public var columnBreakAfter = false
    /// Its length along the lines from what it holds (width: min-content, max-content,
    /// fit-content), `inlineSize` the room it has; never less than `minInlineSize`.
    public var intrinsicInline: STIntrinsicSize? = nil
    public var minInlineSize: CGFloat = 0

    public init() {}

    /// The border and padding at its start and end along the lines (a table cell's).
    public var paddingStart: CGFloat = 0
    public var paddingEnd: CGFloat = 0

    /// Whether anything of it is drawn.
    public var isDrawn: Bool {
        background != nil || !backgroundLayers.isEmpty || !shadows.isEmpty || outlineStyle != .none
            || zip(borderWidths, borderStyles).contains { $0 > 0 && $1 != .none }
    }
}

/// A length from what a box holds (CSS's intrinsic sizes).
public enum STIntrinsicSize: Sendable, Hashable {
    /// Its longest word or character: the lines broken wherever they may be.
    case minContent
    /// Its longest line unbroken.
    case maxContent
    /// The longest line unbroken, but no more than the room it has.
    case fitContent
}

/// A length a table or a cell is given along the lines.
public enum STTableLength: Sendable, Hashable {
    case auto
    case points(CGFloat)
    /// Of the table's length (a cell's), or of the room for the table (the table's).
    case percent(CGFloat)
}

/// A table: rows of cells, each cell's blocks among those after the table in the section.
public struct STTable: Sendable, Hashable {
    public struct Cell: Sendable, Hashable {
        /// Its blocks, by their indices in the section.
        public var blocks: Range<Int>
        /// Its border, background and padding (a box of the section's).
        public var box: Int
        public var length: STTableLength = .auto
        /// How many columns it takes.
        public var span: Int = 1
        /// Where its content stands across the row: 0 at the start, 0.5 in the middle, 1 at the end.
        public var align: CGFloat = 0.5

        public init(blocks: Range<Int>, box: Int) {
            self.blocks = blocks
            self.box = box
        }
    }

    public var rows: [[Cell]] = []
    public var length: STTableLength = .auto
    /// The space between cells (border-spacing), none where borders collapse into one.
    public var spacing: CGFloat = 2
    public var collapses = false
    /// The table's own box about it (border, background), if it has one.
    public var box: Int?
    /// The index after the last block of its cells.
    public var end: Int = 0
    /// Its columns from the right (direction: rtl).
    public var rightToLeft = false

    public init() {}
}

/// Columns: how many, the space between them and its rule, how full each is.
public struct STColumns: Sendable, Hashable {
    /// The number of columns; with `width`, as many as fit at least that long.
    public var count: Int = 1
    public var width: CGFloat?
    public var gap: CGFloat = 16
    public var ruleWidth: CGFloat = 0
    public var ruleColor: STColor?
    public var ruleStyle: STBorderStyle = .none
    /// The columns as long as one another (balance), or each filled before the next (auto).
    public var balances = true
    /// Their length across the lines, where the box they are in fixes it.
    public var blockSize: CGFloat?
    /// The index after the last block set in them.
    public var end: Int = 0

    public init() {}
}

/// Blocks set in the other writing mode, in a place of their own in the page.
public struct STFlow: Sendable, Hashable {
    /// Its lines down (vertical-rl) rather than across.
    public var vertical = true
    /// How long its lines are (its height in vertical text in a horizontal page), where it
    /// is given; else as long as what it holds needs, no longer than the page allows.
    public var lineLength: CGFloat?
    /// Set in the middle along the lines around it (margins auto).
    public var centered = false
    /// The index after its last block.
    public var end: Int = 0

    public init() {}
}

/// The direction text runs in: left to right, right to left, or as its first strong letter says.
public enum STTextDirection: Sendable, Hashable {
    case ltr, rtl, auto
}

/// Text set apart in its own direction inside a paragraph (an isolate: dir on an inline
/// element, bdi, unicode-bidi: isolate; or an embedding), every letter of it taken as that
/// direction's where it overrides (bdo, unicode-bidi: bidi-override).
public struct STBidiSpan: Sendable, Hashable {
    /// Tells one span from the next of the same kind.
    public var id: Int
    public var direction: STTextDirection
    public var overrides: Bool

    public init(id: Int, direction: STTextDirection, overrides: Bool = false) {
        self.id = id
        self.direction = direction
        self.overrides = overrides
    }
}
