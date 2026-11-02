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
}
