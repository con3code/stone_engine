/*
STBidi.swift

Part of the page layer added to stone_engine for SMSReader (see PAGE_LAYOUT.md). MIT License.
*/

import CoreFoundation
import Foundation

/// Right-to-left text (Arabic, Hebrew) among left-to-right text, as the Unicode
/// Bidirectional Algorithm (UAX #9) has it for a paragraph whose direction is left to
/// right: each item given an embedding level (0 left to right, 1 right to left, 2 numbers
/// inside right-to-left text), and a line's items placed in the order those levels give
/// (rule L2). What the algorithm does with explicit embeddings, isolates and right-to-left
/// paragraphs is not done here.
enum STBidi {
    /// The bidirectional classes the resolution tells apart.
    enum Kind: Equatable {
        /// Strong left to right: Latin, kana, ideographs, most letters.
        case left
        /// Strong right to left: Hebrew, Arabic, Syriac, Thaana, N'Ko…
        case right
        /// European digits (0–9 and their fullwidth forms).
        case european
        /// Arabic-Indic digits.
        case arabic
        /// Spaces, punctuation, symbols, pictures: they take the direction about them.
        case neutral
    }

    /// The scripts written from right to left.
    static func isRightToLeft(_ v: UInt32) -> Bool {
        (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v)
            || (0x10800...0x10FFF).contains(v) || (0x1E800...0x1EFFF).contains(v)
    }

    static func kind(of v: UInt32) -> Kind {
        if (0x30...0x39).contains(v) || (0xFF10...0xFF19).contains(v) { return .european }
        if (0x0660...0x0669).contains(v) || (0x066B...0x066C).contains(v) || (0x06F0...0x06F9).contains(v) { return .arabic }
        if isRightToLeft(v) { return .right }
        guard let scalar = Unicode.Scalar(v) else { return .neutral }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .spacingMark, .letterNumber, .otherNumber:
            return .left
        default:
            return .neutral
        }
    }

    /// Separators that join the digits about them into one number ("3.14", "1,000", "10:30").
    private static let separators: Set<UInt32> = [0x2C, 0x2E, 0x3A, 0x2F, 0x2B, 0x2D, 0xA0]
    /// Signs that go with the number beside them ("50%", "$3").
    private static let terminators: Set<UInt32> = [0x25, 0x24, 0x23, 0xB0, 0x2030, 0x20AC, 0xA3, 0xA5]

    /// The embedding levels of a paragraph's items, by their kinds and first scalars; all 0
    /// (and nothing to do) where there is no right-to-left text.
    static func levels(kinds: [Kind], scalars: [UInt32]) -> [UInt8] {
        let count = kinds.count
        guard kinds.contains(where: { $0 == .right || $0 == .arabic }) else { return [UInt8](repeating: 0, count: count) }
        var types = kinds
        // W4: one separator between two numbers of a kind is part of them.
        if count >= 3 {
            for i in 1..<(count - 1) where types[i] == .neutral && separators.contains(scalars[i]) {
                if types[i - 1] == types[i + 1], types[i - 1] == .european || types[i - 1] == .arabic { types[i] = types[i - 1] }
            }
        }
        // W5: signs beside European digits go with them.
        for i in types.indices where types[i] == .neutral && terminators.contains(scalars[i]) {
            if (i > 0 && types[i - 1] == .european) || (i + 1 < count && types[i + 1] == .european) { types[i] = .european }
        }
        // W7: European digits after left-to-right text (or at the start) are left to right.
        var lastStrong = Kind.left
        for i in types.indices {
            switch types[i] {
            case .left, .right: lastStrong = types[i]
            case .european: if lastStrong == .left { types[i] = .left }
            default: break
            }
        }
        func direction(_ kind: Kind) -> Kind? {
            switch kind {
            case .left: .left
            case .right, .european, .arabic: .right
            case .neutral: nil
            }
        }
        // N0: a pair of brackets takes the direction of what is inside it where that is the
        // paragraph's (left to right); where only right-to-left text is inside, that of the
        // text before it. "(3.14)" after Hebrew stays one pair, seen the right way round.
        var stack: [(index: Int, closing: UInt32)] = []
        var pairs: [(open: Int, close: Int)] = []
        for i in types.indices where types[i] == .neutral {
            if let closing = brackets[scalars[i]] {
                guard stack.count < 63 else { break }
                stack.append((i, closing))
            } else if let found = stack.lastIndex(where: { $0.closing == scalars[i] || mirrorsCJK(closing: $0.closing, scalars[i]) }) {
                pairs.append((stack[found].index, i))
                stack.removeSubrange(found...)
            }
        }
        for pair in pairs.sorted(by: { $0.open < $1.open }) {
            let inside = types[(pair.open + 1)..<pair.close].compactMap(direction)
            let resolved: Kind?
            if inside.contains(.left) {
                resolved = .left
            } else if inside.contains(.right) {
                let before = types[..<pair.open].reversed().lazy.compactMap(direction).first ?? .left
                resolved = before == .right ? .right : .left
            } else {
                resolved = nil
            }
            if let resolved {
                types[pair.open] = resolved
                types[pair.close] = resolved
            }
        }
        // N1, N2: neutrals between text of one direction take it (numbers count as right
        // to left); else the paragraph's (left to right). The paragraph's ends are left to right.
        var i = 0
        while i < count {
            guard types[i] == .neutral else {
                i += 1
                continue
            }
            var end = i
            while end < count, types[end] == .neutral { end += 1 }
            let before = i > 0 ? direction(types[i - 1]) ?? .left : .left
            let after = end < count ? direction(types[end]) ?? .left : .left
            let resolved: Kind = before == after ? before : .left
            for j in i..<end { types[j] = resolved }
            i = end
        }
        // I1: right to left at 1, numbers at 2 (inside right-to-left text, read left to right).
        return types.map { kind in
            switch kind {
            case .left, .neutral: 0
            case .right: 1
            case .european, .arabic: 2
            }
        }
    }

    /// The order a line's items are seen in, left to right along the line, by their levels
    /// (L2: each run at or above a level reversed, from the highest down to 1).
    static func visualOrder(_ levels: [UInt8]) -> [Int] {
        var order = Array(levels.indices)
        guard let highest = levels.max(), highest > 0 else { return order }
        for level in stride(from: highest, through: 1, by: -1) {
            var i = 0
            while i < order.count {
                guard levels[order[i]] >= level else {
                    i += 1
                    continue
                }
                var end = i
                while end < order.count, levels[order[end]] >= level { end += 1 }
                order[i..<end].reverse()
                i = end
            }
        }
        return order
    }

    /// Opening brackets, by their closing ones (BD16).
    private static let brackets: [UInt32: UInt32] = [
        0x28: 0x29, 0x5B: 0x5D, 0x7B: 0x7D, 0x2045: 0x2046, 0x207D: 0x207E, 0x208D: 0x208E,
        0x3008: 0x3009, 0x300A: 0x300B, 0x300C: 0x300D, 0x300E: 0x300F, 0x3010: 0x3011,
        0xFF08: 0xFF09, 0xFF3B: 0xFF3D, 0xFF5B: 0xFF5D,
    ]

    /// Fullwidth and ASCII parentheses close each other's pairs.
    private static func mirrorsCJK(closing: UInt32, _ scalar: UInt32) -> Bool {
        (closing == 0x29 && scalar == 0xFF09) || (closing == 0xFF09 && scalar == 0x29)
    }

    /// The mirror image of a bracket or the like, drawn in right-to-left text (L4).
    static func mirror(_ v: UInt32) -> UInt32? {
        mirrors[v]
    }

    private static let mirrors: [UInt32: UInt32] = {
        let pairs: [(UInt32, UInt32)] = [
            (0x28, 0x29), (0x3C, 0x3E), (0x5B, 0x5D), (0x7B, 0x7D), (0xAB, 0xBB), (0x2039, 0x203A),
            (0x2045, 0x2046), (0x207D, 0x207E), (0x208D, 0x208E), (0x2264, 0x2265), (0x3008, 0x3009),
            (0x300A, 0x300B), (0x300C, 0x300D), (0x300E, 0x300F), (0x3010, 0x3011), (0xFF08, 0xFF09),
            (0xFF3B, 0xFF3D), (0xFF5B, 0xFF5D),
        ]
        var map: [UInt32: UInt32] = [:]
        for (a, b) in pairs {
            map[a] = b
            map[b] = a
        }
        return map
    }()

    /// Scripts written without spaces between words, broken into lines between words found
    /// by the system's dictionaries: Thai, Lao, Khmer, Myanmar. The locale to find them in.
    static func unspacedScript(_ v: UInt32) -> String? {
        switch v {
        case 0x0E00...0x0E7F: "th"
        case 0x0E80...0x0EFF: "lo"
        case 0x1780...0x17FF, 0x19E0...0x19FF: "km"
        case 0x1000...0x109F, 0xAA60...0xAA7F: "my"
        default: nil
        }
    }

    /// Where words start in a run of such a script (UTF-16 offsets, the first left out).
    static func wordStarts(_ text: String, locale: String) -> [Int] {
        let string = text as CFString
        let length = CFStringGetLength(string)
        guard length > 0,
              let tokenizer = CFStringTokenizerCreate(nil, string, CFRange(location: 0, length: length),
                                                      kCFStringTokenizerUnitWordBoundary, CFLocaleCreate(nil, CFLocaleIdentifier(rawValue: locale as CFString)))
        else { return [] }
        var starts: [Int] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            if range.location > 0 { starts.append(range.location) }
        }
        return starts
    }
}
