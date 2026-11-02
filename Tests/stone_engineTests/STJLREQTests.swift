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
        XCTAssertGreaterThan(hyphens(japanese), 0, "justified, and in English though the book is Japanese")
        var none = japanese
        none.hyphensGiven = true
        none.hyphenates = false
        XCTAssertEqual(hyphens(none), 0, "hyphens: none")
        var start = STReaderSettings()
        start.justifies = false
        XCTAssertEqual(hyphens(japanese, settings: start), 0, "set at the start: not hyphenated")
    }
}
