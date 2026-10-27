/*
STPageQueries.swift

Part of the page layer added to stone_engine for SMSReader (see PAGE_LAYOUT.md). MIT License.

Where the text of a page set by STTypesetter stands on it: for selecting, searching,
outlining paragraphs, following links and reading ruby.
*/

import CoreGraphics
import Foundation

/// A character (or an image) on a page: where it is in its section's text and on the page.
public struct STPlacedCharacter: Sendable, Hashable {
    /// In the section's text, in UTF-16 units.
    public let range: Range<Int>
    /// Its em box on the page, in points with y going down.
    public let rect: CGRect
    /// The line among the page's lines, and the block among the section's blocks.
    public let line: Int
    public let block: Int
    /// The link the character is part of.
    public let link: String?
    /// A forced line break, or a space: there in the text, nothing drawn.
    public let isBlank: Bool
}

/// Ruby on a page: the base's text range and its reading.
public struct STPlacedRuby: Sendable, Hashable {
    public let range: Range<Int>
    public let reading: String
}

extension STPage {
    /// The page's characters, line by line in reading order; images on their own are included.
    public func characters(geometry: STPageGeometry, writingMode: STWritingMode) -> [STPlacedCharacter] {
        characters(mapper: STPageRenderer.Mapper(content: geometry.content, vertical: writingMode == .vertical))
    }

    func characters(mapper: STPageRenderer.Mapper) -> [STPlacedCharacter] {
        var result: [STPlacedCharacter] = []
        for (lineIndex, placed) in lines.enumerated() {
            let line = placed.line
            let set = line.block
            let emStart = placed.blockPosition + line.emStart
            for (offset, index) in line.items.enumerated() {
                let item = set.items[index]
                let rect = mapper.rect(
                    inline: line.positions[offset] + item.startTrim, block: emStart,
                    inlineSize: max(line.advances[offset], 0.5), blockSize: line.emSize)
                let start = set.block.offset + item.range.lowerBound
                result.append(STPlacedCharacter(
                    range: start..<(set.block.offset + item.range.upperBound), rect: rect, line: lineIndex,
                    block: set.index, link: item.style.link, isBlank: item.isLineBreak || item.isSpace))
            }
        }
        for image in images {
            let rect = mapper.rect(inline: image.inline, block: image.block, inlineSize: image.inlineSize, blockSize: image.blockSize)
            result.append(STPlacedCharacter(
                range: image.textOffset..<(image.textOffset + 1), rect: rect, line: -1, block: image.blockIndex, link: nil, isBlank: false))
        }
        // The blocks of the other writing mode, in their places.
        for flow in flows {
            let rect = mapper.rect(inline: flow.inline, block: flow.block, inlineSize: flow.inlineSize, blockSize: flow.blockSize)
            let inner = flow.page.characters(mapper: STPageRenderer.Mapper(content: rect, vertical: flow.vertical))
            let base = lines.count
            result += inner.map { character in
                STPlacedCharacter(range: character.range, rect: character.rect, line: character.line >= 0 ? character.line + base : -1,
                                  block: character.block, link: character.link, isBlank: character.isBlank)
            }
        }
        return result
    }

    /// The page's pictures and where they stand on it (in points, y going down).
    public func pictures(geometry: STPageGeometry, writingMode: STWritingMode) -> [(id: String, rect: CGRect)] {
        let mapper = STPageRenderer.Mapper(content: geometry.content, vertical: writingMode == .vertical)
        return images.map { ($0.id, mapper.rect(inline: $0.inline, block: $0.block, inlineSize: $0.inlineSize, blockSize: $0.blockSize)) }
    }

    /// Every picture on the page and where it is drawn (in points, y going down): those
    /// standing on their own and floated, and those set in its lines (外字, a picture among
    /// words), placed as the renderer draws them; those of the blocks of the other writing
    /// mode too. For showing a picture by itself, as a finger rests on it.
    public func allPictures(geometry: STPageGeometry, writingMode: STWritingMode) -> [(id: String, rect: CGRect)] {
        allPictures(mapper: STPageRenderer.Mapper(content: geometry.content, vertical: writingMode == .vertical))
    }

    func allPictures(mapper: STPageRenderer.Mapper) -> [(id: String, rect: CGRect)] {
        var result = images.map { ($0.id, mapper.rect(inline: $0.inline, block: $0.block, inlineSize: $0.inlineSize, blockSize: $0.blockSize)) }
        for placed in lines {
            let line = placed.line
            let set = line.block
            let emStart = placed.blockPosition + line.emStart
            let emCentre = emStart + line.emSize / 2
            for (offset, index) in line.items.enumerated() {
                let item = set.items[index]
                guard case .image(let id, let size) = item.kind else { continue }
                // As STPageRenderer.drawLine places it.
                let at = line.positions[offset] + item.leadPad + item.boxLead
                if mapper.vertical {
                    let centre = mapper.point(inline: at, block: emCentre)
                    result.append((id, CGRect(x: centre.x - size.width / 2, y: centre.y, width: size.width, height: size.height)))
                } else {
                    let foot = mapper.point(inline: at, block: emStart + line.emSize - item.style.baselineShift)
                    result.append((id, CGRect(x: foot.x, y: foot.y - size.height, width: size.width, height: size.height)))
                }
            }
        }
        for flow in flows {
            let rect = mapper.rect(inline: flow.inline, block: flow.block, inlineSize: flow.inlineSize, blockSize: flow.blockSize)
            result += flow.page.allPictures(mapper: STPageRenderer.Mapper(content: rect, vertical: flow.vertical))
        }
        return result
    }

    /// The ruby of the page's lines.
    public var rubies: [STPlacedRuby] {
        var result: [STPlacedRuby] = flows.flatMap(\.page.rubies)
        for placed in lines {
            let set = placed.line.block
            var seen = Set<Int>()
            for index in placed.line.items {
                guard let rubyIndex = set.items[index].ruby, seen.insert(rubyIndex).inserted else { continue }
                let ruby = set.rubies[rubyIndex]
                let first = set.items[ruby.items.lowerBound], last = set.items[ruby.items.upperBound - 1]
                result.append(STPlacedRuby(
                    range: (set.block.offset + first.range.lowerBound)..<(set.block.offset + last.range.upperBound),
                    reading: ruby.text))
            }
        }
        return result
    }

    /// The blocks the page shows part of, by their index in the section, in order.
    public var blockIndices: [Int] {
        var seen: [Int] = []
        for placed in lines where seen.last != placed.line.block.index { seen.append(placed.line.block.index) }
        for flow in flows {
            for index in flow.page.blockIndices where !seen.contains(index) { seen.append(index) }
        }
        return seen
    }
}
