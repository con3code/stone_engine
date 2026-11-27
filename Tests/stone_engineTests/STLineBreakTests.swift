/*
STLineBreakTests.swift

Part of the page layer added to stone_engine for SMSReader (see PAGE_LAYOUT.md). MIT License.
*/

import XCTest
@testable import stone_engine

/// 禁則 and 分離禁止 in the page layer's lines: what a line may start with, as the block's
/// line-break says, and the pairs not parted at a line's end.
final class STLineBreakTests: XCTestCase {
    /// The lines a paragraph is set in, five full-width characters to a line.
    private func lines(_ text: String, lineBreak: STLineBreak? = nil, writingMode: STWritingMode = .horizontal) -> [String] {
        var style = STTextStyle()
        style.size = 20
        var blockStyle = STBlockStyle()
        blockStyle.lineBreak = lineBreak
        let block = STBlock(inlines: [.text(text, style)], style: blockStyle)
        let section = STSection(blocks: [block], writingMode: writingMode)
        var settings = STReaderSettings()
        settings.hangsPunctuation = false
        let geometry = writingMode == .horizontal
            ? STPageGeometry(size: CGSize(width: 140, height: 400), top: 20, left: 20, bottom: 20, right: 20)
            : STPageGeometry(size: CGSize(width: 400, height: 140), top: 20, left: 20, bottom: 20, right: 20)
        let pages = STTypesetter(settings: settings).paginate(section, geometry: geometry)
        let whole = text as NSString
        return pages.flatMap(\.lines).map { whole.substring(with: NSRange($0.line.range)) }
    }

    func testTheStrictRuleKeepsJLREQsCharactersOffALinesStart() {
        // Each of them sixth: the line before ends one sooner rather than leave it at the start.
        for mark in ["！", "，", "．", "：", "；", "・", "･", "ゝ", "ゞ", "ー", "‐", "–", "〜", "゠", "⦆", "｣", "？", "、", "。", "」", "ッ"] {
            let set = lines("あいうえお\(mark)かきくけ")
            XCTAssertGreaterThan(set.count, 1)
            for line in set.dropFirst() {
                XCTAssertFalse(line.hasPrefix(mark), "「\(mark)」 at a line's start: \(set)")
            }
            let strict = lines("あいうえお\(mark)かきくけ", lineBreak: .strict)
            XCTAssertFalse(strict.dropFirst().contains { $0.hasPrefix(mark) }, "strict, 「\(mark)」: \(strict)")
        }
        XCTAssertFalse(lines("いろはにほ！へと", writingMode: .vertical).dropFirst().contains { $0.hasPrefix("！") }, "in vertical lines too")
    }

    func testNormalAndLooseLetALineStartWithWhatCSSLets() {
        // normal: small kana, the prolonged sound mark and the hyphens.
        for mark in ["ッ", "ー", "〜", "゠"] {
            XCTAssertEqual(lines("あいうえお\(mark)かき", lineBreak: .normal).dropFirst().first?.first.map(String.init), mark, "normal, 「\(mark)」")
        }
        for mark in ["・", "ゝ", "！", "。"] {
            XCTAssertFalse(lines("あいうえお\(mark)かき", lineBreak: .normal).dropFirst().contains { $0.hasPrefix(mark) }, "normal, 「\(mark)」")
        }
        // loose: the iteration marks and the middle dots as well.
        for mark in ["・", "ゝ", "々", "：", "ー"] {
            XCTAssertEqual(lines("あいうえお\(mark)かき", lineBreak: .loose).dropFirst().first?.first.map(String.init), mark, "loose, 「\(mark)」")
        }
        for mark in ["！", "。", "」"] {
            XCTAssertFalse(lines("あいうえお\(mark)かき", lineBreak: .loose).dropFirst().contains { $0.hasPrefix(mark) }, "loose, 「\(mark)」")
        }
    }

    func testTheHalvesOfTheKunojitenAreNotParted() {
        for mark in ["〳〵", "〴〵", "……", "――"] {
            let set = lines("あいうえ\(mark)かき")
            XCTAssertTrue(set.contains { $0.contains(mark) }, "「\(mark)」 parted: \(set)")
        }
    }

    /// Where the lines of a paragraph of text and character-sized images (￼ in `text`) start.
    private func lineStarts(_ text: String, extent: CGFloat, writingMode: STWritingMode) -> [Int] {
        var style = STTextStyle()
        style.size = 20
        let inlines: [STInline] = text.split(separator: "\u{FFFC}", omittingEmptySubsequences: false).enumerated().flatMap { index, part -> [STInline] in
            (index > 0 ? [.image(id: "mark", size: CGSize(width: 20, height: 20), style: style)] : []) + (part.isEmpty ? [] : [.text(String(part), style)])
        }
        let section = STSection(blocks: [STBlock(inlines: inlines, style: STBlockStyle())], writingMode: writingMode)
        let geometry = writingMode == .horizontal
            ? STPageGeometry(size: CGSize(width: extent + 40, height: 4000), top: 20, left: 20, bottom: 20, right: 20)
            : STPageGeometry(size: CGSize(width: 4000, height: extent + 40), top: 20, left: 20, bottom: 20, right: 20)
        return STTypesetter(settings: STReaderSettings()).paginate(section, geometry: geometry).flatMap(\.lines).map { $0.line.range.lowerBound }
    }

    func testAMarkDrawnAsAnImageIsNotPartedFromTheLatinTextItStandsAgainst() {
        // Quotation marks as 外字 images around English among Japanese, as some books have them.
        let text = "これほど高いものではなかった……\u{FFFC}What do you get when you cross an optic with a mental object? An eye-dea\u{FFFC}（計量ジガーとメンタルなものを交配させたら何ができる？）。"
        let whole = text as NSString
        let opening = whole.range(of: "\u{FFFC}").location
        let closing = whole.range(of: "\u{FFFC}", options: .backwards).location
        for writingMode in [STWritingMode.vertical, .horizontal] {
            for extent in stride(from: CGFloat(200), through: 900, by: 7) {
                let starts = lineStarts(text, extent: extent, writingMode: writingMode)
                XCTAssertGreaterThan(starts.count, 1)
                XCTAssertFalse(starts.contains(closing), "the closing mark starts a line, \(extent) long")
                XCTAssertFalse(starts.contains(opening + 1), "the opening mark ends a line, \(extent) long")
            }
        }
        // Among Japanese it is a character like another: a line may start with it.
        XCTAssertTrue(lineStarts("あいうえお\u{FFFC}かきく", extent: 100, writingMode: .horizontal).contains(5))
    }

    func testAFaceDrawnForVerticalLinesGivesPlaceToItsFellowOnHorizontalOnes() {
        var settings = STReaderSettings()
        settings.horizontalFaces = ["HiraMinProN-W3": "HiraginoSans-W3", "HiraMinProN-W6": "NoSuchFace-W6"]
        let fonts = STFontBook(settings: settings)
        var style = STTextStyle()
        style.family = .mincho
        func face(_ text: String, _ style: STTextStyle, vertical: Bool) -> String {
            fonts.shape(text, style, vertical: vertical).glyphs.first.map { CTFontCopyPostScriptName($0.font) as String } ?? ""
        }
        XCTAssertEqual(face("あ", style, vertical: true), "HiraMinProN-W3")
        XCTAssertEqual(face("あ", style, vertical: false), "HiraginoSans-W3")
        // Latin text is the same in both, and a fellow the system has not is passed over.
        XCTAssertEqual(face("a", style, vertical: false), "HiraMinProN-W3")
        style.bold = true
        XCTAssertEqual(face("あ", style, vertical: false), "HiraMinProN-W6")
        // Nothing is changed where none is named.
        style.bold = false
        let plain = STFontBook(settings: STReaderSettings()).shape("あ", style, vertical: false).glyphs.first.map { CTFontCopyPostScriptName($0.font) as String }
        XCTAssertEqual(plain, "HiraMinProN-W3")
    }
}
