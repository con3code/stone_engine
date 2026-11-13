import CoreGraphics
import XCTest
@testable import stone_engine

/// GSUB single substitution subtables, read from bytes written here.
final class STSubstitutionGlyphTests: XCTestCase {
    private func substitute(_ glyph: CGGlyph, in subtable: [UInt16], lookupType: Int = 1) -> CGGlyph {
        let bytes = subtable.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        return bytes.withUnsafeBufferPointer {
            STTextSubstitutionGlyph.substituteGlyphIdWithLookupSubtable(
                lookupType: lookupType, subTablePtr: $0.baseAddress!, glyph: glyph)
        }
    }

    /// Format 1: the substitute is the glyph ID plus a delta, for the glyphs the coverage lists.
    func testFormat1AddsTheDeltaToCoveredGlyphs() {
        // substFormat 1, coverage at 6, delta 5; coverage format 1 with glyphs 10 and 20.
        let table: [UInt16] = [1, 6, 5, 1, 2, 10, 20]
        XCTAssertEqual(substitute(10, in: table), 15)
        XCTAssertEqual(substitute(20, in: table), 25)
        XCTAssertEqual(substitute(30, in: table), 0, "not covered")
    }

    /// The delta is signed: the addition is modulo 65536.
    func testFormat1DeltaMayBeNegative() {
        // delta -1 (0xFFFF); coverage format 2 with the range 100...102.
        let table: [UInt16] = [1, 6, 0xFFFF, 2, 1, 100, 102, 0]
        XCTAssertEqual(substitute(100, in: table), 99)
        XCTAssertEqual(substitute(102, in: table), 101)
        XCTAssertEqual(substitute(103, in: table), 0, "outside the range")
    }

    /// Format 2, as before: the substitute listed at the coverage index.
    func testFormat2TakesTheListedSubstitute() {
        // substFormat 2, coverage at 10, two substitutes 500 and 600; coverage format 1 with glyphs 7 and 9.
        let table: [UInt16] = [2, 10, 2, 500, 600, 1, 2, 7, 9]
        XCTAssertEqual(substitute(7, in: table), 500)
        XCTAssertEqual(substitute(9, in: table), 600)
        XCTAssertEqual(substitute(8, in: table), 0)
    }
}
