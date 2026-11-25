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

    // MARK: 3.1.3 行長は文字サイズの整数倍

    func testABlocksLinesAreAWholeNumberOfItsCharactersLongWhereAskedFor() {
        // Room for 10.5 characters: set to it, every line is stretched by half a character;
        // as long as ten characters, the lines are set solid and what is over is at their end.
        let text = String(repeating: "あいうえおかきくけこさしすせそ", count: 3)
        let loose = page([.text(text, style)], em: 10.5)
        XCTAssertEqual(loose.lines[0].line.advances.reduce(0, +), size * 10.5, accuracy: 0.01)
        var settings = STReaderSettings()
        settings.wholeCharacterLines = true
        let solid = page([.text(text, style)], em: 10.5, settings: settings)
        XCTAssertEqual(solid.lines.count, 5)
        for placed in solid.lines.dropLast() {
            XCTAssertEqual(placed.line.advances.count, 10)
            XCTAssertTrue(placed.line.advances.allSatisfy { abs($0 - size) < 0.01 })
            XCTAssertEqual(placed.line.positions[0], loose.lines[0].line.positions[0], accuracy: 0.01, "from the same start")
        }
        // Down the page too.
        let down = page([.text(text, style)], em: 10.5, settings: settings, writingMode: .vertical)
        XCTAssertTrue(down.lines[0].line.advances.allSatisfy { abs($0 - size) < 0.01 })
        // Room that is a whole number already stays as it is.
        XCTAssertEqual(page([.text(text, style)], em: 10, settings: settings).lines[0].line.advances.count, 10)
        // Western text, and lines centred or set at the end, are as long as their room.
        let latin = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 3)
        XCTAssertEqual(page([.text(latin, style)], em: 10.5, settings: settings).lines[0].line.advances.reduce(0, +),
                       page([.text(latin, style)], em: 10.5).lines[0].line.advances.reduce(0, +), accuracy: 0.01)
        var centred = STBlockStyle()
        centred.align = .center
        centred.alignGiven = true
        XCTAssertEqual(page([.text(text, style)], em: 10.5, settings: settings, blockStyle: centred).lines[0].line.positions[0],
                       page([.text(text, style)], em: 10.5, blockStyle: centred).lines[0].line.positions[0], accuracy: 0.01)
    }

    // MARK: 3.8.2 端数は約物で（字間はベタのまま）

    func testWhatIsOverAtALinesEndIsTakenUpByItsPunctuationWhereAskedFor() {
        var settings = STReaderSettings()
        settings.keepsLinesSolid = true
        // 」「 in half their width leave the line half an em short of ten characters: the next
        // character is taken in and the line's punctuation gives the half, the characters solid. (Without,
        // it is left out and the line lengthened between them all.)
        let text = "あいう」「えお、かきくけこさしすせそ"
        let loose = page([.text(text, style)], em: 10).lines[0].line
        XCTAssertEqual(loose.advances.count, 10)
        XCTAssertTrue(loose.advances.contains { $0 > size + 0.01 }, "lengthened between its characters")
        let solid = page([.text(text, style)], em: 10, settings: settings).lines[0].line
        XCTAssertEqual(solid.advances.count, 11)
        XCTAssertEqual(solid.advances.reduce(0, +), size * 10, accuracy: 0.01)
        // The closing bracket and the comma share the half em given (JLREQ 3.8.3: marks alike).
        XCTAssertEqual(solid.advances[3] + solid.advances[7], size * 1.5, accuracy: 0.01)
        for index in [0, 1, 2, 5, 6, 8, 9, 10] { XCTAssertEqual(solid.advances[index], size, accuracy: 0.01) }
        // A line that fills its length is left as it is: nothing is taken in for its commas' sake.
        let full = "あいうえ、おかき、くけこさしすせそ"
        XCTAssertEqual(page([.text(full, style)], em: 10, settings: settings).lines[0].line.advances.count, 10)
        // An opening mark at a line's start keeps to the line's edge (its half given), though
        // the line is half an em short: the lines' starts stand level.
        let opening = "あいうえおかきくけこ「さしすせそたちつてとなにぬねの"
        let second = page([.text(opening, style)], em: 10, settings: settings).lines[1].line
        XCTAssertEqual(second.positions[0] + size / 2, page([.text(opening, style)], em: 10, settings: settings).lines[0].line.positions[0],
                       accuracy: 0.01, "its glyph's empty half before the line's start")
    }

    func testAMarkKeptFullWidthAtALinesEndGivesNothingWhereTheLineIsSqueezed() {
        // space-end: 」 ending the second line full width; the em the line is over comes from
        // the marks within it (」「、、 a quarter each), not from the one at its end.
        var block = STBlockStyle()
        block.spacingEnd = .space
        let text = "「あああ、いい、うううう。」「あああ、いい、うううう。」あああ「あああ、いい、うううう。」あああ「あああ、いい、うううう。」"
        let second = page([.text(text, style)], em: 21, blockStyle: block).lines[1].line
        XCTAssertEqual(second.advances.count, 23)
        XCTAssertEqual(second.advances[22], size, accuracy: 0.01, "full width at the line's end")
        XCTAssertEqual(second.advances.reduce(0, +), size * 21, accuracy: 0.01)
        for index in [5, 9, 13, 16] { XCTAssertEqual(second.advances[index], size * 0.75, accuracy: 0.01) }
    }

    func testLinesThatBreakAnywhereHangNothing() {
        // line-break: anywhere: no 禁則, so 、 after a full line starts the next; not hung
        // though 、。 hang elsewhere.
        var block = STBlockStyle()
        block.hangsEnd = true
        block.lineBreak = .anywhere
        let text = "ファッション・ショー、ファッション・ショー。"
        XCTAssertEqual(lines(text, em: 10, blockStyle: block), ["ファッション・ショー", "、ファッション・ショ", "ー。"])
        block.lineBreak = .strict
        XCTAssertEqual(lines(text, em: 10, blockStyle: block).first, "ファッション・ショー、")
    }

    func testAMarkThatMayHangLeavesTheLinesCharactersWhereTheNeighbouringLinesHaveThem() {
        var hanging = STBlockStyle()
        hanging.hangsEnd = true
        var held = STBlockStyle()
        held.hangsEnd = false
        var settings = STReaderSettings()
        settings.keepsLinesSolid = true
        // Ten characters fill the line and 、 follows: hung past its end, the comma within the
        // line keeps its full width and every character stands under the one in the line before.
        let text = "あいうえ、おかきくけ、さしすせそ"
        let hung = page([.text(text, style)], em: 10, settings: settings, blockStyle: hanging).lines[0].line
        XCTAssertEqual(hung.advances.count, 11)
        for index in 0..<10 { XCTAssertEqual(hung.advances[index], size, accuracy: 0.01) }
        XCTAssertEqual(hung.positions[10], hung.positions[0] + size * 10, accuracy: 0.01, "past the line's end")
        // Where it may not hang it is taken in, the commas giving their halves.
        let taken = page([.text(text, style)], em: 10, settings: settings, blockStyle: held).lines[0].line
        XCTAssertEqual(taken.advances.count, 11)
        XCTAssertEqual(taken.advances.reduce(0, +), size * 10, accuracy: 0.01)
        // 」、 over a full line: 」 may not start the next, and is taken in for the comma's
        // half; the 、 after it hangs and takes no room, so no more is squeezed for it.
        let pair = "あいうえ、おかきくけ」、さしすせそ"
        let both = page([.text(pair, style)], em: 10, settings: settings, blockStyle: hanging).lines[0].line
        XCTAssertEqual(both.advances.count, 12)
        XCTAssertEqual(both.advances[..<11].reduce(0, +), size * 10, accuracy: 0.01)
        XCTAssertEqual(both.advances[4], size / 2, accuracy: 0.01)
        for index in [0, 1, 2, 3, 5, 6, 7, 8, 9] { XCTAssertEqual(both.advances[index], size, accuracy: 0.01) }
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

    // MARK: 3.1.5, 3.2.5, 3.3.9, UAX #50

    func testAnOpeningMarkAfterAForcedBreakKeepsItsHalfAsAtTheParagraphsStart() {
        let set = page([.text("あい", style), .lineBreak(style), .text("「う」", style)], em: 10).lines
        XCTAssertEqual(set.count, 2)
        XCTAssertEqual(set[1].line.advances[0], size, accuracy: 0.01, "「 full, as at a paragraph's start (space-first)")
        let wrapped = page([.text("あいうえおかきくけこ「さ」", style)], em: 10).lines
        XCTAssertEqual(wrapped[1].line.advances[0], size / 2, accuracy: 0.01, "trimmed where the line only wrapped")
    }

    func testASCIIQuotesAreOpeningOrClosingByWhatIsBesideThem() {
        // A closing " does not start a line; an opening one does not end one.
        let closing = lines("あいうえ\"お\"かき", em: 5)
        XCTAssertFalse(closing.dropFirst().contains { $0.hasPrefix("\"かき") || $0 == "\"" }, "\(closing)")
        let opening = lines("あいう \"えお\"か", em: 5)
        XCTAssertFalse(opening.contains { $0.hasSuffix("\"") && !$0.hasSuffix("お\"") }, "\(opening)")
    }

    func testTateChuYokoTakesTheFontsNarrowFiguresAndEmphasis() {
        let set = page([.text("あ", style), .combined("123", style), .text("い", style)], em: 10, writingMode: .vertical).lines[0].line
        guard case .combined(let shape) = set.block.items[1].kind else { return XCTFail("not combined") }
        XCTAssertLessThanOrEqual(shape.advance, size * 1.05, "three figures in a third of an em each (twid)")
    }

    func testJapaneseQuotesStandUprightInVerticalLines() {
        let set = page([.text("あ“い”う said “hi”", style)], em: 20, writingMode: .vertical).lines[0].line
        let items = set.block.items
        XCTAssertFalse(items[1].sideways, "“ before い upright")
        XCTAssertFalse(items[3].sideways, "” after い upright")
        XCTAssertTrue(items.last { $0.scalar == 0x201D }?.sideways == true, "” after Latin turned")
    }

    func testARubyAtALinesEndOrStartOverhangsNothingBeyondTheLine() {
        let whole: (String) -> NSString = { $0 as NSString }
        // 字漢《かんじ》い with 漢 fifth: its ruby would overhang い, on the next line, and may not
        // overhang 字: 漢 goes to the next line.
        let end: [STInline] = [.text("あいう字", style), .ruby(base: [.text("漢", style)], ruby: "かんじ", style: style), .text("いう", style)]
        let endText = whole("あいう字漢いう")
        XCTAssertEqual(page(end, em: 5).lines.map { endText.substring(with: NSRange($0.line.range)) }.first, "あいう字")
        // え漢《かんじ》い: half on each side, and え takes it all at the line's end: 漢 stays.
        let kana: [STInline] = [.text("あいうえ", style), .ruby(base: [.text("漢", style)], ruby: "かんじ", style: style), .text("いう", style)]
        let kanaText = whole("あいうえ漢いう")
        XCTAssertEqual(page(kana, em: 5).lines.map { kanaText.substring(with: NSRange($0.line.range)) }.first, "あいうえ漢")
        // お｜漢《かんじ》字 with 漢 starting a line: お is on the line before, so the base takes the room.
        let start: [STInline] = [.text("あいうえお", style), .ruby(base: [.text("漢", style)], ruby: "かんじ", style: style), .text("字です", style)]
        let second = page(start, em: 5).lines[1].line
        XCTAssertEqual(second.advances[0], size * 1.5, accuracy: 0.01, "half an em before 漢")
        XCTAssertEqual(second.positions[0], size / 2, accuracy: 0.01, "漢 after it")
    }

    // MARK: 3.3.7 熟語ルビ

    func testAWordsRubiesStandOverItsBasesTogether() {
        var word = style
        word.rubyJukugo = 1
        func inlines(_ style: STTextStyle) -> [STInline] {
            [.text("字", self.style), .ruby(base: [.text("百", style)], ruby: "ひゃく", style: style),
             .ruby(base: [.text("日", style)], ruby: "じつ", style: style), .ruby(base: [.text("紅", style)], ruby: "こう", style: style),
             .text("が咲く", self.style)]
        }
        // Mono ruby: 百 spaced for its ruby, as 字 before it may not be overhung.
        let mono = page(inlines(style), em: 10).lines[0].line
        XCTAssertEqual(mono.advances[1], size * 1.5, accuracy: 0.01)
        // 熟語ルビ: the bases set solid; ひゃく over 百 and part of 日, じつ and こう moved on,
        // こう overhanging が by half an em.
        let jukugo = page(inlines(word), em: 10).lines[0].line
        for i in 1...3 { XCTAssertEqual(jukugo.advances[i], size, accuracy: 0.01, "base \(i) solid") }
        XCTAssertEqual(jukugo.block.rubies.map(\.shift), [5, 10, 10])
        // Rubies no longer than their bases: as mono ruby.
        let short: [STInline] = [.ruby(base: [.text("日", word)], ruby: "ひ", style: word), .ruby(base: [.text("本", word)], ruby: "ほん", style: word)]
        XCTAssertEqual(page(short, em: 10).lines[0].line.block.rubies.map(\.shift), [0, 0])
    }

    func testANoteReferenceIsNotPartedFromWhatItMarks() {
        var mark = style
        mark.keepsWithPrevious = true
        // 「…残っている図７。」 with 図７ falling at the next line's start: the line before gives it its last character.
        let inlines: [STInline] = [.text("あいうえお", style), .text("図７", mark), .text("。かきくけこ", style)]
        let whole = "あいうえお図７。かきくけこ" as NSString
        let set = page(inlines, em: 5).lines.map { whole.substring(with: NSRange($0.line.range)) }
        XCTAssertFalse(set.contains { $0.hasPrefix("図") || $0.hasPrefix("７") }, "\(set)")
        XCTAssertTrue(set.contains { $0.contains("お図７") }, "\(set)")
    }

    // MARK: 欧文の均等配置

    func testAJustifiedBlocksLatinWordsAreHyphenatedUnlessTheBookSaysNot() {
        let text = "Translations include Toshihiko Izutsu’s Language and Magic, supervised by the translator, published by the university press."
        func hyphens(_ style: STBlockStyle, settings: STReaderSettings = STReaderSettings()) -> Int {
            let block = STBlock(inlines: [.text(text, self.style)], style: style)
            let section = STSection(blocks: [block], writingMode: .horizontal)
            let pages = STTypesetter(settings: { var s = settings; s.hangsPunctuation = false; return s }())
                .paginate(section, geometry: STPageGeometry(size: CGSize(width: size * 9 + 40, height: 800), top: 20, left: 20, bottom: 20, right: 20))
            return pages[0].lines.first?.line.block.hyphens.count ?? 0
        }
        var japanese = STBlockStyle()
        japanese.language = "ja"
        japanese.alignGiven = true
        japanese.align = .justify
        XCTAssertGreaterThan(hyphens(japanese), 0, "justified by the book, and in English though the book is Japanese")
        var reader = STBlockStyle()
        reader.language = "ja"
        XCTAssertEqual(hyphens(reader), 0, "justified by the reader's 行末を揃える only: not hyphenated")
        var keepAll = japanese
        keepAll.wordBreak = .keepAll
        XCTAssertEqual(hyphens(keepAll), 0, "the book says how its words break")
        var none = japanese
        none.hyphensGiven = true
        none.hyphenates = false
        XCTAssertEqual(hyphens(none), 0, "hyphens: none")
        var start = STReaderSettings()
        start.justifies = false
        XCTAssertEqual(hyphens(reader, settings: start), 0, "set at the start: not hyphenated")
    }

    func testCapitalsAreNotHyphenatedUnlessTheBookAsks() {
        let text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        func lines(_ style: STBlockStyle) -> STSetBlock? {
            let block = STBlock(inlines: [.text(text, self.style)], style: style)
            let section = STSection(blocks: [block], writingMode: .horizontal)
            let pages = STTypesetter(settings: { var s = STReaderSettings(); s.hangsPunctuation = false; return s }())
                .paginate(section, geometry: STPageGeometry(size: CGSize(width: size * 10 + 40, height: 800), top: 20, left: 20, bottom: 20, right: 20))
            return pages[0].lines.first?.line.block
        }
        var justified = STBlockStyle()
        justified.alignGiven = true
        justified.align = .justify
        XCTAssertEqual(lines(justified)?.hyphens.count ?? 0, 0, "a run of capitals, hyphens not asked for")
    }

    func testAMarkAtALinesEndThatDoesNotHangIsKeptInTheLine() {
        // 、 taken in (追い込み) where 、。 do not hang: the line squeezed to its length, not the
        // mark set outside it. The reader's hanging on, the book's off.
        var settings = STReaderSettings()
        settings.hangsPunctuation = true
        var block = STBlockStyle()
        block.hangsEnd = false
        let text = "ファッション・ショー、ファッション・ショー。"
        let section = STSection(blocks: [STBlock(inlines: [.text(text, style)], style: block)], writingMode: .horizontal)
        let page = STTypesetter(settings: settings)
            .paginate(section, geometry: STPageGeometry(size: CGSize(width: size * 10 + 40, height: 600), top: 20, left: 20, bottom: 20, right: 20))[0]
        let first = page.lines[0].line
        XCTAssertEqual((text as NSString).substring(with: NSRange(first.range)), "ファッション・ショー、")
        let last = first.positions.count - 1
        XCTAssertLessThanOrEqual(first.positions[last] + first.advances[last], size * 10 + 0.05, "inside the line")
    }

    func testALineBreakSetOnAPartOfTheTextPushesOutAsCSSDoes() {
        // line-break set on the part (takesIn off): nothing taken in; loose lets ー start a line,
        // strict does not.
        var loose = STBlockStyle()
        loose.lineBreak = .loose
        loose.takesIn = false
        XCTAssertEqual(lines("ファッション・ショー、ファッション・ショー。", em: 10, blockStyle: loose).first, "ファッション・ショ")
        var strict = loose
        strict.lineBreak = .strict
        XCTAssertEqual(lines("ファッション・ショー、ファッション・ショー。", em: 10, blockStyle: strict).first, "ファッション・")
        // Set on the whole book: taken in, as JLREQ has it.
        var book = STBlockStyle()
        book.lineBreak = .strict
        XCTAssertEqual(lines("ファッション・ショー、ファッション・ショー。", em: 10, blockStyle: book).first, "ファッション・ショー、")
    }

    func testARaisedCharactersMarkStandsWhereItIsDrawn() {
        // 「本文※本」 down a vertical line, ※ smaller and raised (vertical-align: super): its
        // rect is its own em box, toward the right, not the line's.
        var small = style
        small.size = size * 0.6
        small.baselineShift = size * 0.3
        let section = STSection(blocks: [STBlock(inlines: [.text("本文", style), .text("※", small), .text("本", style)], style: STBlockStyle())],
                                writingMode: .vertical)
        let geometry = STPageGeometry(size: CGSize(width: 300, height: 300), top: 20, left: 20, bottom: 20, right: 20)
        let page = STTypesetter(settings: STReaderSettings()).paginate(section, geometry: geometry)[0]
        let characters = page.characters(geometry: geometry, writingMode: .vertical)
        let body = characters[0].rect, mark = characters[2].rect
        XCTAssertEqual(body.width, size, accuracy: 0.01)
        XCTAssertEqual(mark.width, size * 0.6, accuracy: 0.01)
        XCTAssertEqual(mark.midX - body.midX, size * 0.3, accuracy: 0.01, "raised: toward the right")
    }

    func testACharacterSaysWhichWayItsLineRunsAndWhichWayItIsRead() {
        // Hebrew within a line set left to right is read from its right; the rest from the left.
        let geometry = STPageGeometry(size: CGSize(width: 400, height: 300), top: 20, left: 20, bottom: 20, right: 20)
        let across = STSection(blocks: [STBlock(inlines: [.text("あい\u{5D0}\u{5D1}\u{5D2}う", style)], style: STBlockStyle())], writingMode: .horizontal)
        let page = STTypesetter(settings: STReaderSettings()).paginate(across, geometry: geometry)[0]
        let characters = page.characters(geometry: geometry, writingMode: .horizontal)
        XCTAssertEqual(characters.map(\.isReversed), [false, false, true, true, true, false])
        XCTAssertTrue(characters.allSatisfy { !$0.isVertical })
        XCTAssertGreaterThan(characters[2].rect.minX, characters[4].rect.minX, "the first of them at the right")
        let down = STSection(blocks: [STBlock(inlines: [.text("あい", style)], style: STBlockStyle())], writingMode: .vertical)
        let vertical = STTypesetter(settings: STReaderSettings()).paginate(down, geometry: geometry)[0]
        XCTAssertTrue(vertical.characters(geometry: geometry, writingMode: .vertical).allSatisfy { $0.isVertical && !$0.isReversed })
    }
}
