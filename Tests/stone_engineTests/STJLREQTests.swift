/*
STJLREQTests.swift

Part of the page layer added to stone_engine for SMSReader (see PAGE_LAYOUT.md). MIT License.
*/

import XCTest
@testable import stone_engine

/// The page layer's lines against JLREQ (Requirements for Japanese Text Layout): the spacing
/// of punctuation, the line pitch with ruby, 追い込み before 追い出し, the order a line is
/// lengthened in, 和欧間, 分割禁止, and the reader's choice of justification and 和欧間.
final class STJLREQTests: XCTestCase {
    private let size: CGFloat = 20

    private func page(_ inlines: [STInline], em: CGFloat = 5, settings: STReaderSettings = STReaderSettings(),
                      blockStyle: STBlockStyle = STBlockStyle(), writingMode: STWritingMode = .horizontal) -> STPage {
        let block = STBlock(inlines: inlines, style: blockStyle)
        let section = STSection(blocks: [block], writingMode: writingMode)
        var settings = settings
        settings.hangsPunctuation = false
        let measure = em * size
        let geometry = writingMode == .horizontal
            ? STPageGeometry(size: CGSize(width: measure + 40, height: 600), top: 20, left: 20, bottom: 20, right: 20)
            : STPageGeometry(size: CGSize(width: 600, height: measure + 40), top: 20, left: 20, bottom: 20, right: 20)
        return STTypesetter(settings: settings).paginate(section, geometry: geometry)[0]
    }

    private var style: STTextStyle {
        var style = STTextStyle()
        style.size = size
        return style
    }

    private func lines(_ text: String, em: CGFloat = 5, settings: STReaderSettings = STReaderSettings(),
                       blockStyle: STBlockStyle = STBlockStyle()) -> [String] {
        let whole = text as NSString
        return page([.text(text, style)], em: em, settings: settings, blockStyle: blockStyle).lines
            .map { whole.substring(with: NSRange($0.line.range)) }
    }

    private func line(_ text: String, em: CGFloat = 20, settings: STReaderSettings = STReaderSettings(),
                      blockStyle: STBlockStyle = STBlockStyle()) -> STLine {
        page([.text(text, style)], em: em, settings: settings, blockStyle: blockStyle).lines[0].line
    }

    // MARK: 3.1.4 連続する約物

    func testAClosingMarkBeforeAnOpeningOneKeepsTheHalfEmBetweenThem() {
        // 」「 、「 。「 ）（: 1.5em, as JLREQ and CSS's trim-adjacent have them.
        for pair in ["」「", "、「", "。「", "）（"] {
            let set = line("あ\(pair)い")
            XCTAssertEqual(set.advances[1] + set.advances[2], size * 1.5, accuracy: 0.01, pair)
        }
        // 」」 。」 「「 」、: 1.5em as before.
        for pair in ["」」", "。」", "「「", "」、"] {
            let set = line("あ\(pair)い")
            XCTAssertEqual(set.advances[1] + set.advances[2], size * 1.5, accuracy: 0.01, pair)
        }
        // A full-width comma and stop are punctuation with an empty half too.
        let comma = line("あ，「い")
        XCTAssertEqual(comma.advances[1] + comma.advances[2], size * 1.5, accuracy: 0.01)
    }

    // MARK: 4.5.1 行送り

    func testRubyDoesNotWidenTheLinePitchWhereTheLeadingHoldsIt() {
        let text: [STInline] = [.text("あいうえおかきくけこ", style), .ruby(base: [.text("漢字", style)], ruby: "かんじ", style: style),
                                .text("さしすせそたちつてと", style)]
        let lines = page(text, em: 5).lines
        XCTAssertGreaterThanOrEqual(lines.count, 4)
        let pitches = zip(lines, lines.dropFirst()).map { $1.blockPosition - $0.blockPosition }
        for pitch in pitches { XCTAssertEqual(pitch, size * 1.75, accuracy: 0.01, "the pitch kept: \(pitches)") }
        // Set close, where the leading cannot hold it, the line is made room for.
        var close = STBlockStyle()
        close.lineHeight = 1.0
        close.lineHeightGiven = true
        var settings = STReaderSettings()
        settings.minimumLineHeight = 1.0
        let tight = page(text, em: 5, settings: settings, blockStyle: close).lines
        let tightPitches = zip(tight, tight.dropFirst()).map { $1.blockPosition - $0.blockPosition }
        XCTAssertTrue(tightPitches.contains { $0 > size + 0.01 }, "\(tightPitches)")
    }

    // MARK: 3.8 追い込み・追い出し

    func testALineIsTakenInBeforeItsLastCharacterIsPushedOut() {
        // 6em: 「あ、い、うえ」 and ッ, which may not start a line: the two commas' halves make room for it.
        XCTAssertEqual(lines("あ、い、うえッかきく", em: 6).first, "あ、い、うえッ")
        // A bracket's half and a closing one's at the end: 「あいう「え」」 in 5em.
        XCTAssertEqual(lines("あいう「え」かき", em: 5).first, "あいう「え」")
        // No room to be had: pushed out, and the rest spread.
        let out = lines("あいうえおッかき", em: 5)
        XCTAssertEqual(out.first, "あいうえ")
        XCTAssertFalse(out.dropFirst().contains { $0.hasPrefix("ッ") })
        // The line taken in fits its length.
        let taken = page([.text("あ、い、うえッかきく", style)], em: 6).lines[0].line
        let end = taken.positions[6] + taken.advances[6]
        XCTAssertLessThanOrEqual(end, size * 6 + 0.01)
    }

    func testAJustifiedLineIsSpreadWhereJLREQLetsIt() {
        // 5em, pushed out to 4em: 「あ……い」 takes the em between あ and … and … and い, not between the dots.
        let set = page([.text("あ……い「う」え", style)], em: 5).lines[0].line
        XCTAssertEqual(set.advances[1], size, accuracy: 0.01, "nothing between the halves of ……")
        XCTAssertEqual(set.advances[0], size * 1.5, accuracy: 0.01)
        XCTAssertEqual(set.positions.last! + set.advances.last!, size * 5, accuracy: 0.05)
        // Not after an opening mark nor before a closing one.
        let brackets = page([.text("あ「い」うえおかき", style)], em: 7.4).lines[0].line
        XCTAssertEqual(brackets.advances[1], size, accuracy: 0.01, "「 as it is, its empty half before it")
        XCTAssertEqual(brackets.advances[2], size, accuracy: 0.01, "い not spread before 」")
    }

    // MARK: 3.2.6 和欧間

    func testJapaneseAndLatinAreSpacedAQuarterEmButAtALinesEnd() {
        // The reader's standard: spaced.
        let spaced = line("あAい")
        XCTAssertEqual(spaced.advances[0], size * 1.25, accuracy: 0.01)
        // Not at the line's end: お stays on the first line.
        XCTAssertEqual(lines("あいうえおabc").first, "あいうえお")
        // The reader may have them solid; the book's own choice holds over the reader's.
        var solid = STReaderSettings()
        solid.autospaces = false
        XCTAssertEqual(line("あAい", settings: solid).advances[0], size, accuracy: 0.01)
        var given = STBlockStyle()
        given.autospaceGiven = true
        given.autospaceAlpha = false
        XCTAssertEqual(line("あAい", blockStyle: given).advances[0], size, accuracy: 0.01)
    }

    // MARK: 3.8.1 両端揃え

    func testLinesAreJustifiedUnlessTheReaderOrTheBookSaysOtherwise() {
        func end(_ settings: STReaderSettings = STReaderSettings(), _ style: STBlockStyle = STBlockStyle()) -> CGFloat {
            let set = page([.text("あいうえおッかきくけこ", self.style)], em: 5, settings: settings, blockStyle: style).lines[0].line
            return set.positions.last! + set.advances.last!
        }
        XCTAssertEqual(end(), size * 5, accuracy: 0.05, "justified")
        var start = STReaderSettings()
        start.justifies = false
        XCTAssertEqual(end(start), size * 4, accuracy: 0.05, "at the start, as the reader has it")
        var given = STBlockStyle()
        given.align = .start
        given.alignGiven = true
        XCTAssertEqual(end(STReaderSettings(), given), size * 4, accuracy: 0.05, "the book's text-align: start")
    }

    func testTheLastLineOfAJustifiedParagraphIsSetAtTheStart() {
        // 均等配置（最終行は行頭揃え）: the last line, a one-line paragraph and a line before <br/> at the start.
        func ends(_ inlines: [STInline]) -> [CGFloat] {
            page(inlines, em: 5).lines.map { placed in
                let line = placed.line
                let last = line.positions.indices.last { !line.block.items[line.items.lowerBound + $0].isLineBreak } ?? 0
                return line.positions[last] + line.advances[last]
            }
        }
        let paragraph = ends([.text("あいうえおッかきくけこさ", style)])
        XCTAssertEqual(paragraph.first ?? 0, size * 5, accuracy: 0.05, "justified")
        XCTAssertEqual(paragraph.last ?? 0, size * 3, accuracy: 0.05, "the last line at the start: \(paragraph)")
        XCTAssertEqual(ends([.text("あいう", style)]).first ?? 0, size * 3, accuracy: 0.05, "a short paragraph at the start")
        let broken = ends([.text("あいうえおッかき", style), .lineBreak(style), .text("くけ", style)])
        XCTAssertEqual(broken[1], size * 4, accuracy: 0.05, "the line before <br/> (おッかき) at the start: \(broken)")
        XCTAssertEqual(broken[2], size * 2, accuracy: 0.05)
        // text-align-last: justify, where the book asks for it: the last line spread too.
        var all = STBlockStyle()
        all.alignLast = .justify
        let block = STBlock(inlines: [.text("あいうえおかきくけこさしす", style)], style: all)
        let spread = STTypesetter(settings: STReaderSettings()).paginate(
            STSection(blocks: [block], writingMode: .horizontal),
            geometry: STPageGeometry(size: CGSize(width: size * 5 + 40, height: 600), top: 20, left: 20, bottom: 20, right: 20))[0].lines.last!.line
        XCTAssertEqual(spread.positions.last! + spread.advances.last!, size * 5, accuracy: 0.05)
    }

    // MARK: 3.1.10 分割禁止

    func testNumbersAndAbbreviationsAreNotParted() {
        for text in ["あいうえ3.14かき", "あいうえ1,000かき", "あいうえ12:30かき", "あいうえ¥1000かき", "あいうえ$250かき", "あいうU.S.A.かき"] {
            let set = lines(text, em: 5)
            XCTAssertFalse(set.contains { $0.hasSuffix(".") || $0.hasSuffix(",") || $0.hasSuffix(":") || $0.hasSuffix("¥") || $0.hasSuffix("$") }, "\(text): \(set)")
        }
        let wide = lines("あいうえ２０２６年", em: 5)
        XCTAssertTrue(wide.contains { $0.contains("２０２６") }, "\(wide)")
        let percent = lines("あいうえお５０％です", em: 6)
        XCTAssertTrue(percent.contains { $0.contains("５０％") }, "\(percent)")
        let nbsp = lines("Mr.\u{00A0}Smith is here", em: 7)
        XCTAssertTrue(nbsp.contains { $0.contains("Mr.\u{00A0}Smith") }, "\(nbsp)")
    }

    func testAGroupRubyIsNotPartedBetweenLines() {
        let text: [STInline] = [.text("あいう", style), .ruby(base: [.text("紫陽花", style)], ruby: "あじさい", style: style), .text("かきく", style)]
        let whole = "あいう紫陽花かきく" as NSString
        let set = page(text, em: 5).lines.map { whole.substring(with: NSRange($0.line.range)) }
        XCTAssertTrue(set.contains { $0.contains("紫陽花") }, "\(set)")
    }

    // MARK: 3.3.8 ルビの掛け

    func testRubyOverhangsOnlyTheKanaBesideIt() {
        // あ漢《かんじ》字: 10pt longer than its base; あ takes it all, 字 none.
        let text: [STInline] = [.text("あ", style), .ruby(base: [.text("漢", style)], ruby: "かんじ", style: style), .text("字です", style)]
        let set = page(text, em: 10).lines[0].line
        XCTAssertEqual(set.block.rubies[0].shift, -5, accuracy: 0.01, "the ruby stands toward あ")
        XCTAssertEqual(set.advances[1], size, accuracy: 0.01, "漢 not spread: the overhang makes the room")
        // Kana on both sides: half on each.
        let both: [STInline] = [.text("あ", style), .ruby(base: [.text("漢", style)], ruby: "かんじ", style: style), .text("いです", style)]
        XCTAssertEqual(page(both, em: 10).lines[0].line.block.rubies[0].shift, 0, accuracy: 0.01)
        // Kanji on both sides: none; the base made room for it.
        let none: [STInline] = [.text("字", style), .ruby(base: [.text("漢", style)], ruby: "かんじ", style: style), .text("字です", style)]
        let spaced = page(none, em: 10).lines[0].line
        XCTAssertEqual(spaced.block.rubies[0].shift, 0, accuracy: 0.01)
        XCTAssertEqual(spaced.advances[1], size * 1.5, accuracy: 0.01)
    }
}
