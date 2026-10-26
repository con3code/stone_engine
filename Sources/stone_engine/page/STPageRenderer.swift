/*
STPageRenderer.swift

Part of the page layer added to stone_engine for SMSReader (see PAGE_LAYOUT.md). MIT License.
*/

import CoreGraphics
import CoreText
import Foundation

/// Draws pages set by `STTypesetter` into a CGContext: off the main thread, as the reader
/// makes its page images.
public enum STPageRenderer {
    /// Draws `page` into `context`, whose user space is the page in points with y going up
    /// (CoreGraphics' own; a bitmap context scaled to the page). `image` gives the pictures
    /// by their ids.
    public static func draw(
        _ page: STPage, geometry: STPageGeometry, writingMode: STWritingMode, settings: STReaderSettings,
        in context: CGContext, image: (String) -> CGImage?
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        // Drawn with y going down, as the layout is worked out.
        context.translateBy(x: 0, y: geometry.size.height)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(settings.background.cgColor)
        context.fill(CGRect(origin: .zero, size: geometry.size))
        let mapper = Mapper(content: geometry.content, vertical: writingMode == .vertical)

        for background in page.backgrounds {
            context.setFillColor(background.color.cgColor)
            context.fill(mapper.rect(inline: background.inline, block: background.block, inlineSize: background.inlineSize, blockSize: background.blockSize))
        }
        for rule in page.rules {
            context.setFillColor(rule.color.cgColor)
            context.fill(mapper.rect(inline: rule.inline, block: rule.block, inlineSize: rule.inlineSize, blockSize: rule.blockSize))
        }
        for placed in page.images {
            guard let picture = image(placed.id) else { continue }
            drawImage(picture, in: mapper.rect(inline: placed.inline, block: placed.block, inlineSize: placed.inlineSize, blockSize: placed.blockSize), context: context)
        }
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        // The emphasis marks' font, made once for the page.
        let fonts = STFontBook(settings: settings)
        for placed in page.lines {
            drawLine(placed.line, at: placed.blockPosition, mapper: mapper, settings: settings, fonts: fonts, context: context, image: image)
        }
    }

    /// A page drawn into a new image `scale` pixels to the point.
    public static func image(
        _ page: STPage, geometry: STPageGeometry, writingMode: STWritingMode, settings: STReaderSettings,
        scale: CGFloat, image: (String) -> CGImage?
    ) -> CGImage? {
        let width = Int((geometry.size.width * scale).rounded()), height = Int((geometry.size.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .high
        draw(page, geometry: geometry, writingMode: writingMode, settings: settings, in: context, image: image)
        return context.makeImage()
    }

    /// Logical coordinates to the page's (y down).
    struct Mapper {
        let content: CGRect
        let vertical: Bool

        func rect(inline: CGFloat, block: CGFloat, inlineSize: CGFloat, blockSize: CGFloat) -> CGRect {
            vertical
                ? CGRect(x: content.maxX - block - blockSize, y: content.minY + inline, width: blockSize, height: inlineSize)
                : CGRect(x: content.minX + inline, y: content.minY + block, width: inlineSize, height: blockSize)
        }

        /// A point along the line (inline) at a distance across (block).
        func point(inline: CGFloat, block: CGFloat) -> CGPoint {
            vertical ? CGPoint(x: content.maxX - block, y: content.minY + inline) : CGPoint(x: content.minX + inline, y: content.minY + block)
        }
    }

    private static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    private static func drawLine(
        _ line: STLine, at blockPosition: CGFloat, mapper: Mapper, settings: STReaderSettings, fonts: STFontBook,
        context: CGContext, image: (String) -> CGImage?
    ) {
        let set = line.block
        let emStart = blockPosition + line.emStart
        let emCentre = emStart + line.emSize / 2
        // The room ruby and emphasis marks take on the over side: lines over the text go beyond it.
        let markRoom = set.items[line.items].filter { $0.ruby != nil || $0.style.emphasis != nil }.map { $0.style.size / 2 }.max() ?? 0
        // Inline backgrounds first, under every character of the line.
        for (offset, index) in line.items.enumerated() {
            guard let background = set.items[index].style.background else { continue }
            context.setFillColor(background.cgColor)
            context.fill(mapper.rect(
                inline: line.positions[offset] + set.items[index].startTrim, block: emStart,
                inlineSize: line.advances[offset], blockSize: line.emSize))
        }
        for (offset, index) in line.items.enumerated() {
            let item = set.items[index]
            let position = line.positions[offset]
            let advance = line.advances[offset]
            // Where the glyphs go: after the space a long ruby set before them.
            let at = position + item.leadPad
            let style = item.style
            let color = (style.color ?? settings.textColor).cgColor
            context.setFillColor(color)
            switch item.kind {
            case .lineBreak:
                continue
            case .image(let id, let size):
                guard let picture = image(id) else { continue }
                let rect: CGRect
                if mapper.vertical {
                    let centre = mapper.point(inline: at, block: emCentre)
                    rect = CGRect(x: centre.x - size.width / 2, y: centre.y, width: size.width, height: size.height)
                } else {
                    // On the em box's foot (text-bottom), as the guide sets 外字.
                    let foot = mapper.point(inline: at, block: emStart + line.emSize)
                    rect = CGRect(x: foot.x, y: foot.y - size.height, width: size.width, height: size.height)
                }
                drawImage(picture, in: rect, context: context)
            case .combined(let shape):
                // Side by side in one character's space, narrowed to fit it.
                let centre = mapper.point(inline: at, block: emCentre)
                let squeeze = min(1, style.size * 1.05 / max(shape.advance, 1))
                let ascentRatio = shape.ascent / max(shape.ascent + shape.descent, 1)
                context.saveGState()
                context.translateBy(x: centre.x - shape.advance * squeeze / 2, y: centre.y + style.size * ascentRatio)
                context.scaleBy(x: squeeze, y: 1)
                drawGlyphs(shape, at: .zero, context: context)
                context.restoreGState()
            case .glyphs:
                guard let shape = item.shape else { continue }
                if item.characterClass.space { break }
                if isJoinedDash(at: index, in: set.items) {
                    drawJoinedDash(shape, item: item, from: position + item.startTrim, length: advance, emStart: emStart, line: line, mapper: mapper, context: context)
                } else if mapper.vertical && item.sideways {
                    // Turned a quarter clockwise about the line's centre.
                    let start = mapper.point(inline: at + item.startTrim, block: emCentre)
                    context.saveGState()
                    context.translateBy(x: start.x, y: start.y)
                    context.rotate(by: .pi / 2)
                    drawGlyphs(shape, at: CGPoint(x: 0, y: (shape.ascent - shape.descent) / 2 - style.baselineShift), context: context)
                    context.restoreGState()
                } else if mapper.vertical {
                    let centre = mapper.point(inline: at, block: emCentre)
                    let ascentRatio = shape.ascent / max(shape.ascent + shape.descent, 1)
                    let origin = CGPoint(x: centre.x - shape.advance / 2 + style.baselineShift, y: centre.y + style.size * ascentRatio)
                    drawGlyphs(shape, at: origin, context: context)
                } else {
                    let baseline = mapper.point(inline: at, block: emStart + line.baseline)
                    drawGlyphs(shape, at: CGPoint(x: baseline.x, y: baseline.y - style.baselineShift), context: context)
                }
            }
            drawDecorations(
                item, from: position + item.startTrim, length: advance, emStart: emStart, markRoom: markRoom, line: line,
                mapper: mapper, settings: settings, fonts: fonts, context: context)
        }
        drawRubies(line, emStart: emStart, mapper: mapper, settings: settings, context: context)
    }

    /// Dashes set in twos (2倍ダーシ: ――, ——, ──), which fonts draw with a gap between, as the
    /// 電書連 guide asks a reader to join.
    private static let dashes: Set<UInt32> = [0x2014, 0x2015, 0x2500]

    private static func isJoinedDash(at index: Int, in items: [STItem]) -> Bool {
        let scalar = items[index].scalar
        guard dashes.contains(scalar) else { return false }
        return (index > 0 && items[index - 1].scalar == scalar) || (index + 1 < items.count && items[index + 1].scalar == scalar)
    }

    /// A dash stretched along the line over its whole advance, so that two meet.
    private static func drawJoinedDash(
        _ shape: STShape, item: STItem, from start: CGFloat, length: CGFloat, emStart: CGFloat, line: STLine,
        mapper: Mapper, context: CGContext
    ) {
        guard let glyph = shape.glyphs.first else { return }
        var id = glyph.glyph
        var ink = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(glyph.font, .horizontal, &id, &ink, 1)
        let thickness = max(0.6, ink.height > 0 && ink.height < ink.width ? ink.height : item.style.size / 16)
        let centreAcross: CGFloat = mapper.vertical
            ? emStart + line.emSize / 2
            : emStart + line.baseline - (ink.midY.isFinite ? ink.midY : item.style.size * 0.35)
        context.fill(mapper.rect(inline: start, block: centreAcross - thickness / 2, inlineSize: length, blockSize: thickness))
    }

    /// Draws a character's glyphs with their baseline's start at `origin` (user space, y
    /// down). The position goes in the text matrix: the positions CoreText takes are in text
    /// space, which the matrix (flipped, for y going down) would turn about.
    private static func drawGlyphs(_ shape: STShape, at origin: CGPoint, context: CGContext) {
        for glyph in shape.glyphs {
            var id = glyph.glyph
            var point = CGPoint.zero
            context.textMatrix = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: origin.x + glyph.offset, ty: origin.y)
            CTFontDrawGlyphs(glyph.font, &id, &point, 1, context)
        }
    }

    /// 圏点 and the lines over, under and through an item.
    private static func drawDecorations(
        _ item: STItem, from start: CGFloat, length: CGFloat, emStart: CGFloat, markRoom: CGFloat, line: STLine,
        mapper: Mapper, settings: STReaderSettings, fonts: STFontBook, context: CGContext
    ) {
        let style = item.style
        let thickness = max(0.5, style.size / 18)
        let color = (style.color ?? settings.textColor).cgColor
        func stroke(atBlock block: CGFloat) {
            context.setFillColor(color)
            context.fill(mapper.rect(inline: start, block: block - thickness / 2, inlineSize: length, blockSize: thickness))
        }
        // In a vertical line the over side is the right, the under side the left. A line over
        // the text stands beyond its ruby and emphasis marks, never through them.
        if style.overline { stroke(atBlock: emStart - markRoom - thickness) }
        if style.underline { stroke(atBlock: mapper.vertical ? emStart + line.emSize + thickness : emStart + line.baseline + style.size * 0.1) }
        if style.lineThrough { stroke(atBlock: emStart + line.emSize / 2) }
        // Emphasis marks beside each character, as ruby is set; ruby takes the place where both are.
        if let mark = style.emphasis, item.ruby == nil, !item.isSpace, case .glyphs = item.kind {
            var markStyle = style
            markStyle.size = style.size / 2
            let character = Character(mark.character)
            let shape = fonts.shape(mark.character, markStyle, vertical: mapper.vertical && STCharacterClass.of(character).upright)
            let ascentRatio = shape.ascent / max(shape.ascent + shape.descent, 1)
            context.setFillColor((style.emphasisColor ?? style.color ?? settings.textColor).cgColor)
            let centreAlong = start + item.leadPad + (item.squeezedAdvance - item.leadPad - item.trailPad) / 2
            let centreAcross = emStart - markStyle.size / 2
            let centre = mapper.point(inline: centreAlong, block: centreAcross)
            drawGlyphs(shape, at: CGPoint(x: centre.x - shape.advance / 2, y: centre.y - markStyle.size / 2 + markStyle.size * ascentRatio), context: context)
        }
    }

    /// The ruby over the line's characters: over the middle of its base, or spread across
    /// it (an equal space between and half of it at either end) where the base is longer.
    private static func drawRubies(_ line: STLine, emStart: CGFloat, mapper: Mapper, settings: STReaderSettings, context: CGContext) {
        let set = line.block
        var seen = Set<Int>()
        for (offset, index) in line.items.enumerated() {
            guard let rubyIndex = set.items[index].ruby, seen.insert(rubyIndex).inserted else { continue }
            let ruby = set.rubies[rubyIndex]
            let first = offset
            let last = min(line.items.count - 1, offset + (ruby.items.upperBound - index) - 1)
            // Over the base's glyphs, without the space a long ruby made beside them.
            let firstItem = set.items[index], lastItem = set.items[line.items.lowerBound + last]
            let start = line.positions[first] + firstItem.startTrim + firstItem.leadPad
            let end = line.positions[last] + lastItem.startTrim + lastItem.squeezedAdvance - lastItem.trailPad
            let lengths = zip(ruby.text, ruby.shapes).map { character, shape in
                mapper.vertical && STCharacterClass.of(character).upright ? shape.verticalAdvance : shape.advance
            }
            let total = lengths.reduce(0, +)
            let span = end - start
            let gap = total < span && !lengths.isEmpty ? (span - total) / CGFloat(lengths.count) : 0
            var along = total < span ? start + gap / 2 : start + (span - total) / 2
            let size = ruby.style.size
            context.setFillColor((ruby.style.color ?? settings.textColor).cgColor)
            for ((character, shape), length) in zip(zip(ruby.text, ruby.shapes), lengths) {
                let upright = STCharacterClass.of(character).upright
                if mapper.vertical {
                    let centre = mapper.point(inline: along, block: emStart - size / 2)
                    if upright {
                        let ascentRatio = shape.ascent / max(shape.ascent + shape.descent, 1)
                        drawGlyphs(shape, at: CGPoint(x: centre.x - shape.advance / 2, y: centre.y + size * ascentRatio), context: context)
                    } else {
                        context.saveGState()
                        context.translateBy(x: centre.x, y: centre.y)
                        context.rotate(by: .pi / 2)
                        drawGlyphs(shape, at: CGPoint(x: 0, y: (shape.ascent - shape.descent) / 2), context: context)
                        context.restoreGState()
                    }
                } else {
                    let ascentRatio = shape.ascent / max(shape.ascent + shape.descent, 1)
                    let foot = mapper.point(inline: along, block: emStart - size + size * ascentRatio)
                    drawGlyphs(shape, at: foot, context: context)
                }
                along += length + gap
            }
        }
    }
}
