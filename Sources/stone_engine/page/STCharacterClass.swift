/*
STCharacterClass.swift

Part of the page layer added to stone_engine for SMSReader (see PAGE_LAYOUT.md). MIT License.
*/

import Foundation

/// What the typesetting needs to know of a character: how it stands in a vertical line,
/// whether it is punctuation that can be squeezed, whether a line may start or end with it,
/// whether it is part of a word lines are not broken in.
struct STCharacterClass: @unchecked Sendable {
    /// Upright in a vertical line (UAX #50: U, Tu, Tr; Tu and Tr take the font's vertical
    /// forms); turned a quarter clockwise where false (R).
    var upright: Bool
    var punctuation: STPunctuation
    /// A line may not start with it (closing brackets, 、。, small kana, 々…).
    var notStarting: Bool
    /// A line may not end with it (opening brackets).
    var notEnding: Bool
    /// 、。, which may stand past the line's end.
    var hangs: Bool
    /// A letter or digit of a word set in spaces (Latin, Greek, Cyrillic, digits): lines
    /// break between words, not inside them.
    var wordLetter: Bool
    /// A space lines break at.
    var space: Bool
    /// Ideographs, kana, fullwidth forms: lines may break between any two of them.
    var ideographic: Bool

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [UInt32: STCharacterClass] = [:]

    /// The class of a character, by its first scalar.
    static func of(_ character: Character) -> STCharacterClass {
        guard let scalar = character.unicodeScalars.first else { return of(scalar: " ") }
        return of(scalar: scalar)
    }

    static func of(scalar: Unicode.Scalar) -> STCharacterClass {
        let value = scalar.value
        if let found = lock.withLock({ cache[value] }) { return found }
        let character = Character(scalar)
        let properties = scalar.properties
        let ideographic = properties.isIdeographic || isKanaOrFullwidth(value)
        let space = properties.isWhitespace && value != 0x3000
        // Letters and digits, and the apostrophe inside a word ("don't").
        // Characters set upright in vertical lines (Ⅰ, ℃) are not: lines break around them.
        let wordLetter = !ideographic && !space && !isUpright(value)
            && (properties.isAlphabetic || properties.numericType != nil || value == 0x27 || value == 0x2019)
        let found = STCharacterClass(
            upright: isUpright(value),
            punctuation: STPunctuation.valueOf(charatcter: character),
            notStarting: STKinsoku.notStartingCharSet.contains(scalar),
            notEnding: STKinsoku.notEndingCharSet.contains(scalar),
            hangs: STKinsoku.hangingCharSet.contains(scalar) || value == 0xFF0C || value == 0xFF0E,
            wordLetter: wordLetter,
            space: space,
            ideographic: ideographic)
        lock.withLock { cache[value] = found }
        return found
    }

    private static func isKanaOrFullwidth(_ v: UInt32) -> Bool {
        (0x3000...0x30FF).contains(v) || (0x31F0...0x31FF).contains(v) || (0xFF01...0xFF60).contains(v)
            || (0xFFE0...0xFFE6).contains(v) || (0x3200...0x33FF).contains(v)
    }

    /// Unicode's vertical orientation (UAX #50), U/Tu/Tr against R: the ranges set upright
    /// in a vertical line, as the standard lists them (the main of them; anything else is
    /// turned, as Latin is).
    private static func isUpright(_ v: UInt32) -> Bool {
        if v < 0x00A7 { return false }
        switch v {
        case 0x00A7, 0x00A9, 0x00AE, 0x00B1, 0x00BC...0x00BE, 0x00D7, 0x00F7: return true
        case 0x02EA...0x02EB: return true
        case 0x1100...0x11FF: return true  // Hangul Jamo
        case 0x1401...0x167F: return true  // Canadian syllabics
        case 0x18B0...0x18FF: return true
        case 0x2016, 0x2020...0x2021, 0x2030...0x2031, 0x203B...0x203C, 0x2042, 0x2047...0x2049, 0x2051, 0x2065: return true
        case 0x20DD...0x20E0, 0x20E2...0x20E4: return true
        case 0x2100...0x2101, 0x2103...0x2109, 0x210F, 0x2113...0x2114, 0x2116...0x2117, 0x211E...0x2123,
             0x2125, 0x2127, 0x2129, 0x212E, 0x2135...0x213F, 0x2145...0x214A, 0x214C...0x214D, 0x214F...0x2189,
             0x218C...0x218F: return true
        case 0x221E, 0x2234...0x2235: return true
        case 0x2300...0x2307, 0x230C...0x231F, 0x2322...0x232B, 0x237D...0x239A, 0x23BE...0x23CD, 0x23CF,
             0x23D1...0x23DB, 0x23E2...0x2422, 0x2424...0x24FF: return true
        case 0x25A0...0x2619, 0x2620...0x2767, 0x2776...0x2793: return true
        case 0x2B12...0x2B2F, 0x2B50...0x2B59, 0x2BB8...0x2BFF: return true
        case 0x2E80...0xA4CF: return true  // CJK radicals, kana, ideographs, Yi
        case 0xA960...0xA97F, 0xAC00...0xD7FF: return true  // Hangul
        case 0xE000...0xFAFF: return true  // private use (外字), compatibility ideographs
        case 0xFE10...0xFE1F, 0xFE30...0xFE48, 0xFE50...0xFE6F: return true
        case 0xFF01...0xFF60, 0xFFE0...0xFFE7: return true  // fullwidth forms
        case 0x1F000...0x1FAFF: return true  // symbols, emoji
        case 0x20000...0x3FFFD: return true  // ideographs beyond the BMP
        default: return false
        }
    }
}
