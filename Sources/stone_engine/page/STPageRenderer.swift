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
        in context: CGContext, boxes: [STBox] = [], image: (String) -> CGImage?
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        // Drawn with y going down, as the layout is worked out.
        context.translateBy(x: 0, y: geometry.size.height)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(settings.background.cgColor)
        context.fill(CGRect(origin: .zero, size: geometry.size))
        let mapper = Mapper(content: geometry.content, vertical: writingMode == .vertical)
        drawBody(page, mapper: mapper, writingMode: writingMode, settings: settings, in: context, boxes: boxes, image: image)
    }

    /// What a page holds, its content area `mapper`'s: boxes, images, lines, and the blocks
    /// of the other writing mode in their places.
    private static func drawBody(
        _ page: STPage, mapper: Mapper, writingMode: STWritingMode, settings: STReaderSettings,
        in context: CGContext, boxes: [STBox], image: (String) -> CGImage?
    ) {

        for background in page.backgrounds {
            context.setFillColor(background.color.cgColor)
            context.fill(mapper.rect(inline: background.inline, block: background.block, inlineSize: background.inlineSize, blockSize: background.blockSize))
        }
        for rule in page.rules {
            context.setFillColor(rule.color.cgColor)
            context.fill(mapper.rect(inline: rule.inline, block: rule.block, inlineSize: rule.inlineSize, blockSize: rule.blockSize))
        }
        // Boxes, outer ones first, each turned with those it is in.
        let placedBoxes = page.boxes.filter { boxes.indices.contains($0.box) }
        func transform(of placed: Int?) -> CGAffineTransform {
            guard let placed, page.boxes.indices.contains(placed), boxes.indices.contains(page.boxes[placed].box) else { return .identity }
            let fragment = page.boxes[placed]
            let box = boxes[fragment.box]
            var own = CGAffineTransform.identity
            if box.rotation != 0 || box.scale != CGSize(width: 1, height: 1) || box.translation != .zero {
                let rect = mapper.rect(inline: fragment.inline, block: fragment.block, inlineSize: fragment.inlineSize, blockSize: fragment.blockSize)
                let pivot = CGPoint(x: rect.minX + rect.width * box.origin.x, y: rect.minY + rect.height * box.origin.y)
                own = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
                    .concatenating(CGAffineTransform(scaleX: box.scale.width, y: box.scale.height))
                    .concatenating(CGAffineTransform(rotationAngle: box.rotation))
                    .concatenating(CGAffineTransform(translationX: pivot.x + box.translation.width, y: pivot.y + box.translation.height))
            }
            return own.concatenating(transform(of: fragment.parent))
        }
        /// The innermost placed box a line or an image is in.
        func container(line: Int? = nil, image: Int? = nil) -> Int? {
            page.boxes.indices.last { index in
                if let line { return page.boxes[index].lines.contains(line) }
                if let image { return page.boxes[index].images.contains(image) }
                return false
            }
        }
        /// The boxes that cut what is in them, a line's or an image's, clipped to.
        func clip(_ placed: Int?) {
            var current = placed
            while let index = current, page.boxes.indices.contains(index) {
                let fragment = page.boxes[index]
                if boxes.indices.contains(fragment.box), boxes[fragment.box].clips {
                    context.clip(to: mapper.rect(inline: fragment.inline, block: fragment.block, inlineSize: fragment.inlineSize, blockSize: fragment.blockSize))
                }
                current = fragment.parent
            }
        }
        func blend(of placed: Int?) -> (CGBlendMode, CGFloat) {
            var mode = CGBlendMode.normal
            var current = placed
            while let index = current, page.boxes.indices.contains(index) {
                if boxes.indices.contains(page.boxes[index].box), mode == .normal { mode = boxes[page.boxes[index].box].blendMode }
                current = page.boxes[index].parent
            }
            return (mode, 1)
        }
        if !placedBoxes.isEmpty {
            for (index, fragment) in page.boxes.enumerated() where boxes.indices.contains(fragment.box) {
                context.saveGState()
                context.concatenate(transform(of: index))
                context.setBlendMode(blend(of: index).0)
                drawBox(boxes[fragment.box], fragment, mapper: mapper, vertical: writingMode == .vertical, settings: settings, context: context, image: image)
                context.restoreGState()
            }
        }
        for (index, placed) in page.images.enumerated() {
            guard let picture = image(placed.id) else { continue }
            let inside = container(image: index)
            context.saveGState()
            context.concatenate(transform(of: inside))
            context.setBlendMode(placed.blendMode != .normal ? placed.blendMode : blend(of: inside).0)
            clip(inside)
            let place = mapper.rect(inline: placed.inline, block: placed.block, inlineSize: placed.inlineSize, blockSize: placed.blockSize)
            if placed.fit == .fill {
                drawImage(picture, in: place, context: context)
            } else {
                // Fitted in its place, kept in shape, at its position; what is outside cut.
                let natural = CGSize(width: picture.width, height: picture.height)
                let containScale = min(place.width / max(natural.width, 1), place.height / max(natural.height, 1))
                let coverScale = max(place.width / max(natural.width, 1), place.height / max(natural.height, 1))
                let scale: CGFloat = switch placed.fit {
                case .contain: containScale
                case .cover: coverScale
                case .scaleDown: min(1, containScale)
                default: containScale
                }
                let size = CGSize(width: natural.width * scale, height: natural.height * scale)
                let drawn = CGRect(x: place.minX + (place.width - size.width) * placed.fitPosition.x,
                                   y: place.minY + (place.height - size.height) * placed.fitPosition.y, width: size.width, height: size.height)
                context.clip(to: place)
                drawImage(picture, in: drawn, context: context)
            }
            context.restoreGState()
        }
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        // The emphasis marks' font, made once for the page.
        let fonts = STFontBook(settings: settings)
        for (index, placed) in page.lines.enumerated() {
            let inside = page.boxes.isEmpty ? nil : container(line: index)
            if inside != nil {
                context.saveGState()
                context.concatenate(transform(of: inside))
                context.setBlendMode(blend(of: inside).0)
                clip(inside)
            }
            // A list item's marker outside the lines stays where it is: not moved with a box it is not in.
            let markerLength = placed.line.items.lowerBound == 0 ? placed.line.block.block.style.outsideMarker : 0
            let isMarker: (Int) -> Bool = { placed.line.block.items[$0].range.upperBound <= markerLength }
            drawLine(placed.line, at: placed.blockPosition, mapper: mapper, settings: settings, fonts: fonts, context: context, image: image,
                     skip: inside != nil && markerLength > 0 ? isMarker : nil)
            if inside != nil { context.restoreGState() }
            if inside != nil, markerLength > 0 {
                drawLine(placed.line, at: placed.blockPosition, mapper: mapper, settings: settings, fonts: fonts, context: context, image: image,
                         skip: { !isMarker($0) })
            }
        }
        for flow in page.flows {
            let rect = mapper.rect(inline: flow.inline, block: flow.block, inlineSize: flow.inlineSize, blockSize: flow.blockSize)
            drawBody(flow.page, mapper: Mapper(content: rect, vertical: flow.vertical), writingMode: flow.vertical ? .vertical : .horizontal,
                     settings: settings, in: context, boxes: boxes, image: image)
        }
    }

    // MARK: Boxes

    /// Inline elements' backgrounds and borders about their text on the line, outer ones
    /// first: along the line from their first character's start to their last's end; across,
    /// the characters' em box and the padding before and after it.
    private static func drawInlineBoxes(_ line: STLine, emStart: CGFloat, mapper: Mapper, settings: STReaderSettings, context: CGContext) {
        let set = line.block
        var order: [Int] = []
        var spans: [Int: (box: STInlineBox, first: Int, last: Int, size: CGFloat)] = [:]
        for (offset, index) in line.items.enumerated() {
            let item = set.items[index]
            for box in item.style.inlineBoxes {
                if var span = spans[box.id] {
                    span.last = offset
                    span.size = max(span.size, item.style.size)
                    spans[box.id] = span
                } else {
                    spans[box.id] = (box, offset, offset, item.style.size)
                    order.append(box.id)
                }
            }
        }
        guard !order.isEmpty else { return }
        let emCentre = emStart + line.emSize / 2
        for id in order {
            guard let span = spans[id] else { continue }
            let box = span.box
            let firstIndex = line.items.lowerBound + span.first, lastIndex = line.items.lowerBound + span.last
            let firstItem = set.items[firstIndex], lastItem = set.items[lastIndex]
            var start = line.positions[span.first] + firstItem.startTrim
            var end = line.positions[span.last] + lastItem.startTrim + line.advances[span.last]
            // Right-to-left text (STBidi) puts the box's characters otherwise along the line:
            // it takes in the room they take, whichever end they are at.
            if set.baseLevel > 0 || set.items[firstIndex...lastIndex].contains(where: { $0.level > 0 }) {
                let rooms = (span.first...span.last).map { offset in
                    (line.positions[offset] + set.items[line.items.lowerBound + offset].startTrim, line.advances[offset])
                }
                start = rooms.map(\.0).min() ?? start
                end = rooms.map { $0.0 + $0.1 }.max() ?? end
            }
            // The room of the boxes about this one that start or end at the same character is
            // theirs: this one begins after it and ends before it (a white span at the end of a
            // padded violet one leaves the violet's padding violet).
            for outer in firstItem.style.inlineBoxes.prefix(while: { $0.id != id })
            where firstIndex == 0 || !set.items[firstIndex - 1].style.inlineBoxes.contains(where: { $0.id == outer.id }) {
                start += outer.startSpace
            }
            for outer in lastItem.style.inlineBoxes.prefix(while: { $0.id != id })
            where lastIndex + 1 >= set.items.count || !set.items[lastIndex + 1].style.inlineBoxes.contains(where: { $0.id == outer.id }) {
                end -= outer.endSpace
            }
            let before: CGFloat, after: CGFloat
            if mapper.vertical {
                before = emCentre - span.size / 2
                after = emCentre + span.size / 2
            } else {
                before = emStart + line.baseline - span.size * 0.88
                after = before + span.size
            }
            let widths = zip(box.borderWidths, box.borderStyles).map { $1 == .none ? 0 : $0 }
            let outerBefore = before - box.padding[0] - widths[0], outerAfter = after + box.padding[1] + widths[1]
            let rect = mapper.rect(inline: start, block: outerBefore, inlineSize: max(0, end - start), blockSize: outerAfter - outerBefore)
            if let background = box.background {
                context.setFillColor(background.faded(firstItem.style.opacity).cgColor)
                context.fill(rect)
            }
            // The sides: before, after, start (only where the element starts on the line), end.
            let isStart = firstItem.boxLead > 0 || span.first == 0 && line.items.lowerBound == 0
            let isEnd = lastItem.boxTrail > 0
            for side in 0..<4 where widths[side] > 0 {
                if side == 2, !isStart { continue }
                if side == 3, !isEnd { continue }
                let color = (box.borderColors[side] ?? firstItem.style.color ?? settings.textColor).cgColor
                context.setFillColor(color)
                let width = widths[side]
                let sideRect: CGRect
                switch side {
                case 0: sideRect = mapper.rect(inline: start, block: outerBefore, inlineSize: end - start, blockSize: width)
                case 1: sideRect = mapper.rect(inline: start, block: outerAfter - width, inlineSize: end - start, blockSize: width)
                case 2: sideRect = mapper.rect(inline: start, block: outerBefore, inlineSize: width, blockSize: outerAfter - outerBefore)
                default: sideRect = mapper.rect(inline: end - width, block: outerBefore, inlineSize: width, blockSize: outerAfter - outerBefore)
                }
                if box.borderStyles[side] == .dashed || box.borderStyles[side] == .dotted {
                    context.saveGState()
                    context.setStrokeColor(color)
                    context.setLineWidth(width)
                    setDash(box.borderStyles[side], width: width, context: context)
                    let vertical = sideRect.height > sideRect.width
                    context.move(to: vertical ? CGPoint(x: sideRect.midX, y: sideRect.minY) : CGPoint(x: sideRect.minX, y: sideRect.midY))
                    context.addLine(to: vertical ? CGPoint(x: sideRect.midX, y: sideRect.maxY) : CGPoint(x: sideRect.maxX, y: sideRect.midY))
                    context.strokePath()
                    context.restoreGState()
                } else {
                    context.fill(sideRect)
                }
            }
        }
    }

    /// A box's part on the page: its shadows, background, border and outline. A side where
    /// the box is cut by the page is left open (box-decoration-break: slice), unless it is drawn whole on each.
    private static func drawBox(
        _ box: STBox, _ fragment: STPlacedBox, mapper: Mapper, vertical: Bool, settings: STReaderSettings,
        context: CGContext, image: (String) -> CGImage?
    ) {
        var rect = mapper.rect(inline: fragment.inline, block: fragment.block, inlineSize: fragment.inlineSize, blockSize: fragment.blockSize)
        // Physical sides: top, right, bottom, left. The block's before side is the top across, the right down.
        let beforeSide = vertical ? 1 : 0, afterSide = vertical ? 3 : 2
        var widths = box.borderWidths
        var styles = box.borderStyles
        var radii = box.radii
        let cutBefore = !fragment.startsHere && !box.cloneDecoration
        let cutAfter = !fragment.endsHere && !box.cloneDecoration
        func openSide(_ side: Int) {
            widths[side] = 0
            styles[side] = .none
            // The corners on that side square.
            switch side {
            case 0: radii[0] = 0; radii[1] = 0
            case 1: radii[1] = 0; radii[2] = 0
            case 2: radii[2] = 0; radii[3] = 0
            default: radii[3] = 0; radii[0] = 0
            }
        }
        if cutBefore {
            openSide(beforeSide)
            // Drawn past the page's edge, so that nothing of the cut side shows.
            switch beforeSide {
            case 0: rect.origin.y -= 2; rect.size.height += 2
            default: rect.size.width += 2
            }
        }
        if cutAfter {
            openSide(afterSide)
            switch afterSide {
            case 2: rect.size.height += 2
            default: rect.origin.x -= 2; rect.size.width += 2
            }
        }
        let outer = roundedPath(rect, radii: radii)
        // Shadows outside the box: drawn under a shape the box itself then hides.
        for shadow in box.shadows.reversed() where !shadow.inset {
            context.saveGState()
            let spread = rect.insetBy(dx: -shadow.spread, dy: -shadow.spread)
            let path = roundedPath(spread, radii: radii.map { $0 > 0 ? $0 + shadow.spread : 0 })
            let clip = CGMutablePath()
            clip.addRect(rect.insetBy(dx: -10_000, dy: -10_000))
            clip.addPath(outer)
            context.addPath(clip)
            context.clip(using: .evenOdd)
            context.setShadow(offset: CGSize(width: shadow.x, height: shadow.y), blur: shadow.blur, color: shadow.color.faded(box.opacity).cgColor)
            context.setFillColor(shadow.color.faded(box.opacity).cgColor)
            context.addPath(path.copy(using: nil) ?? path)
            context.translateBy(x: 0, y: 0)
            context.fillPath()
            context.restoreGState()
        }
        // The background: to the border's edge, or inside it.
        let inner = rect.inset(top: widths[0], right: widths[1], bottom: widths[2], left: widths[3])
        let backgroundRect = box.backgroundToBorder ? rect : inner
        let backgroundPath = box.backgroundToBorder ? outer : roundedPath(inner, radii: radii.map { max(0, $0 - widths.max()!) })
        if let color = box.background {
            context.setFillColor(color.faded(box.opacity).cgColor)
            context.addPath(backgroundPath)
            context.fillPath()
        }
        if !box.backgroundLayers.isEmpty {
            context.saveGState()
            context.addPath(backgroundPath)
            context.clip()
            context.setAlpha(box.opacity)
            if box.backgroundBlendMode != .normal { context.setBlendMode(box.backgroundBlendMode) }
            for layer in box.backgroundLayers.reversed() {
                drawBackgroundLayer(layer, in: backgroundRect, context: context, image: image)
            }
            context.restoreGState()
        }
        // Inset shadows, inside the border.
        for shadow in box.shadows where shadow.inset {
            context.saveGState()
            context.addPath(roundedPath(inner, radii: radii))
            context.clip()
            let hole = CGMutablePath()
            hole.addRect(inner.insetBy(dx: -10_000, dy: -10_000))
            hole.addPath(roundedPath(inner.insetBy(dx: shadow.spread, dy: shadow.spread), radii: radii))
            context.setShadow(offset: CGSize(width: shadow.x, height: shadow.y), blur: shadow.blur, color: shadow.color.cgColor)
            context.setFillColor(shadow.color.cgColor)
            context.addPath(hole)
            context.fillPath(using: .evenOdd)
            context.restoreGState()
        }
        if let borderImage = box.borderImage, let picture = image(borderImage.id) {
            drawBorderImage(borderImage, picture: picture, rect: rect, widths: box.borderWidths, context: context)
        } else {
            drawBorder(rect: rect, widths: widths, colors: box.borderColors.map { ($0 ?? settings.textColor).faded(box.opacity) },
                       styles: styles, radii: radii, context: context)
        }
        if box.outlineStyle != .none, box.outlineWidth > 0 {
            let outset = box.outlineOffset + box.outlineWidth / 2
            let color = (box.outlineColor ?? settings.textColor).faded(box.opacity)
            context.saveGState()
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(box.outlineWidth)
            setDash(box.outlineStyle, width: box.outlineWidth, context: context)
            context.stroke(rect.insetBy(dx: -outset, dy: -outset))
            context.restoreGState()
        }
    }

    /// A border from a picture: its corners at the corners, its sides along the sides
    /// (stretched, or repeated), its middle filling the box where asked.
    private static func drawBorderImage(_ border: STBorderImage, picture: CGImage, rect: CGRect, widths: [CGFloat], context: CGContext) {
        let width = CGFloat(picture.width), height = CGFloat(picture.height)
        let s = border.slices.count == 4 ? border.slices : [0, 0, 0, 0]
        let top = border.slicesArePercent ? s[0] * height : s[0], right = border.slicesArePercent ? s[1] * width : s[1]
        let bottom = border.slicesArePercent ? s[2] * height : s[2], left = border.slicesArePercent ? s[3] * width : s[3]
        // The picture's parts (pixels, y down) and where they go.
        let xs = [0, left, width - right, width], ys = [0, top, height - bottom, height]
        let rx = [rect.minX, rect.minX + widths[3], rect.maxX - widths[1], rect.maxX]
        let ry = [rect.minY, rect.minY + widths[0], rect.maxY - widths[2], rect.maxY]
        for row in 0..<3 {
            for column in 0..<3 {
                if row == 1, column == 1, !border.fill { continue }
                let source = CGRect(x: xs[column], y: ys[row], width: xs[column + 1] - xs[column], height: ys[row + 1] - ys[row])
                let target = CGRect(x: rx[column], y: ry[row], width: rx[column + 1] - rx[column], height: ry[row + 1] - ry[row])
                guard source.width >= 1, source.height >= 1, target.width > 0, target.height > 0,
                      let part = picture.cropping(to: source.integral) else { continue }
                if border.repeats, row == 1 || column == 1 {
                    // Repeated along the side at the size the border's width gives it.
                    let scale = row == 1 && column != 1 ? target.width / source.width : target.height / source.height
                    let tile = CGSize(width: column == 1 ? source.width * scale : target.width, height: row == 1 ? source.height * scale : target.height)
                    context.saveGState()
                    context.clip(to: target)
                    var y = target.minY
                    while y < target.maxY {
                        var x = target.minX
                        while x < target.maxX {
                            drawImage(part, in: CGRect(origin: CGPoint(x: x, y: y), size: tile), context: context)
                            x += max(tile.width, 1)
                        }
                        y += max(tile.height, 1)
                    }
                    context.restoreGState()
                } else {
                    drawImage(part, in: target, context: context)
                }
            }
        }
    }

    private static func roundedPath(_ rect: CGRect, radii: [CGFloat]) -> CGPath {
        guard radii.contains(where: { $0 > 0 }) else { return CGPath(rect: rect, transform: nil) }
        let limit = min(rect.width, rect.height) / 2
        let r = radii.map { min(max(0, $0), limit) }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + r[0], y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r[1], y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r[1]), radius: r[1])
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r[2]))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r[2], y: rect.maxY), radius: r[2])
        path.addLine(to: CGPoint(x: rect.minX + r[3], y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r[3]), radius: r[3])
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r[0]))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + r[0], y: rect.minY), radius: r[0])
        path.closeSubpath()
        return path
    }

    private static func setDash(_ style: STBorderStyle, width: CGFloat, context: CGContext) {
        switch style {
        case .dashed: context.setLineDash(phase: 0, lengths: [width * 3, width * 2])
        case .dotted:
            context.setLineCap(.round)
            context.setLineDash(phase: 0, lengths: [0, width * 2])
        default: context.setLineDash(phase: 0, lengths: [])
        }
    }

    /// The four sides of a border: one stroke round a rounded box where they are alike,
    /// else each side by itself.
    private static func drawBorder(rect: CGRect, widths: [CGFloat], colors: [STColor], styles: [STBorderStyle], radii: [CGFloat], context: CGContext) {
        let sides = (0..<4).filter { widths[$0] > 0 && styles[$0] != .none }
        guard !sides.isEmpty else { return }
        context.saveGState()
        defer { context.restoreGState() }
        func shade(_ color: STColor, _ factor: CGFloat) -> CGColor {
            STColor(red: color.red * factor, green: color.green * factor, blue: color.blue * factor, alpha: color.alpha).cgColor
        }
        let alike = sides.count == 4 && Set(widths).count == 1 && Set(colors).count == 1 && Set(styles).count == 1
        if alike, ![.groove, .ridge, .inset, .outset].contains(styles[0]) {
            let width = widths[0]
            context.setStrokeColor(colors[0].cgColor)
            if styles[0] == .double {
                let third = width / 3
                context.setLineWidth(third)
                context.addPath(roundedPath(rect.insetBy(dx: third / 2, dy: third / 2), radii: radii))
                context.addPath(roundedPath(rect.insetBy(dx: width - third / 2, dy: width - third / 2), radii: radii.map { max(0, $0 - width) }))
                context.strokePath()
                return
            }
            context.setLineWidth(width)
            setDash(styles[0], width: width, context: context)
            context.addPath(roundedPath(rect.insetBy(dx: width / 2, dy: width / 2), radii: radii.map { max(0, $0 - width / 2) }))
            context.strokePath()
            return
        }
        for side in sides {
            let width = widths[side]
            var color = colors[side].cgColor
            switch styles[side] {
            case .inset, .groove: color = (side == 0 || side == 3) ? shade(colors[side], 0.6) : colors[side].cgColor
            case .outset, .ridge: color = (side == 1 || side == 2) ? shade(colors[side], 0.6) : colors[side].cgColor
            default: break
            }
            let start: CGPoint, end: CGPoint
            switch side {
            case 0: start = CGPoint(x: rect.minX, y: rect.minY + width / 2); end = CGPoint(x: rect.maxX, y: rect.minY + width / 2)
            case 1: start = CGPoint(x: rect.maxX - width / 2, y: rect.minY); end = CGPoint(x: rect.maxX - width / 2, y: rect.maxY)
            case 2: start = CGPoint(x: rect.minX, y: rect.maxY - width / 2); end = CGPoint(x: rect.maxX, y: rect.maxY - width / 2)
            default: start = CGPoint(x: rect.minX + width / 2, y: rect.minY); end = CGPoint(x: rect.minX + width / 2, y: rect.maxY)
            }
            context.setStrokeColor(color)
            if styles[side] == .double {
                let third = width / 3
                context.setLineWidth(third)
                let normal = side % 2 == 0 ? CGPoint(x: 0, y: width / 3) : CGPoint(x: width / 3, y: 0)
                for offset in [-1.0, 1.0] {
                    context.move(to: CGPoint(x: start.x + normal.x * offset, y: start.y + normal.y * offset))
                    context.addLine(to: CGPoint(x: end.x + normal.x * offset, y: end.y + normal.y * offset))
                }
                context.strokePath()
                continue
            }
            context.setLineWidth(width)
            setDash(styles[side], width: width, context: context)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }
    }

    /// A background picture (tiled, or once, at its place) or a gradient, in the box.
    private static func drawBackgroundLayer(_ layer: STBackgroundLayer, in rect: CGRect, context: CGContext, image: (String) -> CGImage?) {
        switch layer {
        case .image(let id, let given, let cover, let contain, let repeatX, let repeatY, let position):
            guard let picture = image(id) else { return }
            var size = given ?? CGSize(width: picture.width, height: picture.height)
            if cover || contain {
                let scale = cover ? max(rect.width / max(size.width, 1), rect.height / max(size.height, 1))
                    : min(rect.width / max(size.width, 1), rect.height / max(size.height, 1))
                size = CGSize(width: size.width * scale, height: size.height * scale)
            }
            guard size.width > 0.5, size.height > 0.5 else { return }
            let originX = rect.minX + (rect.width - size.width) * position.x
            let originY = rect.minY + (rect.height - size.height) * position.y
            var xs = [originX], ys = [originY]
            if repeatX {
                var x = originX
                while x > rect.minX { x -= size.width }
                xs = Array(stride(from: x, to: rect.maxX, by: size.width))
            }
            if repeatY {
                var y = originY
                while y > rect.minY { y -= size.height }
                ys = Array(stride(from: y, to: rect.maxY, by: size.height))
            }
            for y in ys.prefix(400) {
                for x in xs.prefix(400) { drawImage(picture, in: CGRect(origin: CGPoint(x: x, y: y), size: size), context: context) }
            }
        case .linear(let angle, let stops, let repeating):
            // CSS: 0deg points up, 90deg right; the gradient line is as long as the box's
            // corners need for the angle.
            let radians = angle * .pi / 180
            let direction = CGPoint(x: sin(radians), y: -cos(radians))
            let length = abs(rect.width * sin(radians)) + abs(rect.height * cos(radians))
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let start = CGPoint(x: centre.x - direction.x * length / 2, y: centre.y - direction.y * length / 2)
            let end = CGPoint(x: centre.x + direction.x * length / 2, y: centre.y + direction.y * length / 2)
            guard let gradient = makeGradient(stops, length: length, repeating: repeating) else { return }
            context.drawLinearGradient(gradient.gradient, start: start, end: gradient.repeatLength.map {
                CGPoint(x: start.x + direction.x * $0, y: start.y + direction.y * $0)
            } ?? end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            if let repeatLength = gradient.repeatLength, repeatLength > 1 {
                var offset = repeatLength
                while offset < length {
                    let from = CGPoint(x: start.x + direction.x * offset, y: start.y + direction.y * offset)
                    let to = CGPoint(x: from.x + direction.x * repeatLength, y: from.y + direction.y * repeatLength)
                    context.saveGState()
                    // Each repeat over the part from its start on.
                    let band = CGMutablePath()
                    let normal = CGPoint(x: -direction.y, y: direction.x)
                    let far: CGFloat = length * 2
                    band.move(to: CGPoint(x: from.x + normal.x * far, y: from.y + normal.y * far))
                    band.addLine(to: CGPoint(x: from.x - normal.x * far, y: from.y - normal.y * far))
                    band.addLine(to: CGPoint(x: from.x - normal.x * far + direction.x * far, y: from.y - normal.y * far + direction.y * far))
                    band.addLine(to: CGPoint(x: from.x + normal.x * far + direction.x * far, y: from.y + normal.y * far + direction.y * far))
                    band.closeSubpath()
                    context.addPath(band)
                    context.clip()
                    context.drawLinearGradient(gradient.gradient, start: from, end: to, options: [.drawsAfterEndLocation])
                    context.restoreGState()
                    offset += repeatLength
                }
            }
        case .radial(let circle, let stops, let repeating):
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            // farthest-corner, as CSS's default.
            let radius = hypot(rect.width / 2, rect.height / 2)
            context.saveGState()
            if !circle, rect.height > 0 {
                // An ellipse: a circle scaled to the box's shape.
                context.translateBy(x: centre.x, y: centre.y)
                context.scaleBy(x: 1, y: rect.height / max(rect.width, 1))
                context.translateBy(x: -centre.x, y: -centre.y)
            }
            let r = circle ? radius : hypot(rect.width / 2, rect.width / 2)
            if let gradient = makeGradient(stops, length: r, repeating: repeating) {
                if let repeatLength = gradient.repeatLength, repeatLength > 1 {
                    var outer = r + repeatLength
                    outer -= outer.truncatingRemainder(dividingBy: repeatLength)
                    var radiusNow = outer
                    while radiusNow > 0 {
                        context.drawRadialGradient(gradient.gradient, startCenter: centre, startRadius: max(0, radiusNow - repeatLength),
                                                   endCenter: centre, endRadius: radiusNow, options: [])
                        radiusNow -= repeatLength
                    }
                } else {
                    context.drawRadialGradient(gradient.gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: r,
                                               options: [.drawsAfterEndLocation])
                }
            }
            context.restoreGState()
        }
    }

    /// A CGGradient for stops along `length` points; for a repeating one, the length of one repeat.
    private static func makeGradient(_ stops: [STGradientStop], length: CGFloat, repeating: Bool) -> (gradient: CGGradient, repeatLength: CGFloat?)? {
        guard stops.count >= 1 else { return nil }
        // Places in points: given, or spread evenly between the given ones.
        var places: [CGFloat?] = stops.map { stop in stop.points ?? stop.position.map { $0 * length } }
        if places[0] == nil { places[0] = 0 }
        if places[places.count - 1] == nil { places[places.count - 1] = repeating ? (places.compactMap { $0 }.max() ?? length) : length }
        var index = 0
        while index < places.count {
            if places[index] == nil {
                let before = index - 1
                var after = index
                while places[after] == nil { after += 1 }
                let from = places[before]!, to = places[after]!
                for missing in index..<after {
                    places[missing] = from + (to - from) * CGFloat(missing - before) / CGFloat(after - before)
                }
                index = after
            }
            index += 1
        }
        var resolved = places.map { $0! }
        for i in 1..<resolved.count where resolved[i] < resolved[i - 1] { resolved[i] = resolved[i - 1] }
        let span = repeating ? max(resolved.last! - resolved.first!, 0.5) : max(length, 0.5)
        let base = repeating ? resolved.first! : 0
        let locations = resolved.map { min(max(($0 - base) / span, 0), 1) }
        let colors = stops.map { $0.color.cgColor } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else { return nil }
        return (gradient, repeating ? span : nil)
    }

    /// A page drawn into a new image `scale` pixels to the point.
    public static func image(
        _ page: STPage, geometry: STPageGeometry, writingMode: STWritingMode, settings: STReaderSettings,
        scale: CGFloat, boxes: [STBox] = [], image: (String) -> CGImage?
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
        draw(page, geometry: geometry, writingMode: writingMode, settings: settings, in: context, boxes: boxes, image: image)
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
        context: CGContext, image: (String) -> CGImage?, skip: ((Int) -> Bool)? = nil
    ) {
        let set = line.block
        let emStart = blockPosition + line.emStart
        let emCentre = emStart + line.emSize / 2
        if skip == nil { drawInlineBoxes(line, emStart: emStart, mapper: mapper, settings: settings, context: context) }
        // Inline backgrounds first, under every character of the line: characters next to each
        // other in one colour are painted as one, so no seam shows between them.
        var run: (color: STColor, start: CGFloat, end: CGFloat)?
        func paintRun() {
            guard let painted = run else { return }
            context.setFillColor(painted.color.cgColor)
            context.fill(mapper.rect(inline: painted.start, block: emStart, inlineSize: painted.end - painted.start, blockSize: line.emSize))
            run = nil
        }
        for (offset, index) in line.items.enumerated() {
            if let skip, skip(index) { paintRun(); continue }
            guard let background = set.items[index].style.background else { paintRun(); continue }
            let color = background.faded(set.items[index].style.opacity)
            // Not over the padding and border of the inline boxes it starts or ends: theirs.
            let item = set.items[index]
            let start = line.positions[offset] + item.startTrim + item.boxLead
            let end = line.positions[offset] + item.startTrim + line.advances[offset] - item.boxTrail
            if let current = run, current.color == color, abs(current.end - start) < 0.5 {
                run?.end = end
            } else {
                paintRun()
                run = (color, start, end)
            }
        }
        paintRun()
        for (offset, index) in line.items.enumerated() {
            if let skip, skip(index) { continue }
            let item = set.items[index]
            let position = line.positions[offset]
            let advance = line.advances[offset]
            // Where the glyphs go: after the space a long ruby set before them, and an inline box's.
            let at = position + item.leadPad + item.boxLead
            let style = item.style
            let color = (style.color ?? settings.textColor).faded(style.opacity).cgColor
            context.setFillColor(color)
            switch item.kind {
            case .lineBreak:
                continue
            case .image(let id, let size):
                guard let picture = image(id) else { continue }
                context.saveGState()
                defer { context.restoreGState() }
                context.setAlpha(style.opacity)
                if style.blendMode != .normal { context.setBlendMode(style.blendMode) }
                let rect: CGRect
                if mapper.vertical {
                    let centre = mapper.point(inline: at, block: emCentre)
                    rect = CGRect(x: centre.x - size.width / 2, y: centre.y, width: size.width, height: size.height)
                } else {
                    // On the em box's foot (text-bottom), as the guide sets 外字; raised by its shift.
                    let foot = mapper.point(inline: at, block: emStart + line.emSize - style.baselineShift)
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
                item, from: position + item.startTrim, length: advance, emStart: emStart, line: line,
                mapper: mapper, settings: settings, fonts: fonts, context: context)
        }
        // The hyphen of a word broken at the line's end (hyphens: auto).
        // The line's end (its hyphen, its ruby) drawn with the part of it that holds its last character.
        let drawsEnd = line.items.last.map { last in !(skip?(last) ?? false) } ?? true
        if drawsEnd, set.hyphens.contains(line.items.upperBound), let last = line.items.last, let offset = line.positions.indices.last {
            let item = set.items[last]
            let hyphen = fonts.shape("-", item.style, vertical: false)
            let end = line.positions[offset] + item.startTrim + line.advances[offset]
            context.setFillColor((item.style.color ?? settings.textColor).faded(item.style.opacity).cgColor)
            if mapper.vertical {
                let start = mapper.point(inline: end, block: emCentre)
                context.saveGState()
                context.translateBy(x: start.x, y: start.y)
                context.rotate(by: .pi / 2)
                drawGlyphs(hyphen, at: CGPoint(x: 0, y: (hyphen.ascent - hyphen.descent) / 2), context: context)
                context.restoreGState()
            } else {
                let baseline = mapper.point(inline: end, block: emStart + line.baseline)
                drawGlyphs(hyphen, at: baseline, context: context)
            }
        }
        if drawsEnd { drawRubies(line, emStart: emStart, mapper: mapper, settings: settings, context: context) }
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

    /// 圏点 and the lines over, under and through an item. Lines stand by the item's own em
    /// box, beyond its ruby and emphasis marks on their side, never through them.
    private static func drawDecorations(
        _ item: STItem, from start: CGFloat, length: CGFloat, emStart: CGFloat, line: STLine,
        mapper: Mapper, settings: STReaderSettings, fonts: STFontBook, context: CGContext
    ) {
        let style = item.style
        let set = line.block
        let size = style.size
        let thickness = max(0.5, size / 18)
        let textColor = (style.color ?? settings.textColor).faded(style.opacity)
        let rubyUnder = item.ruby.map { set.rubies[$0].style.rubyUnder }
        let rubySize = item.ruby.map { set.rubies[$0].style.size } ?? 0
        let emphasizes = style.emphasis != nil && Self.takesEmphasis(item)
        let overMarks = (rubyUnder == false ? rubySize : 0) + (emphasizes && !style.emphasisUnder ? size / 2 : 0)
        let underMarks = (rubyUnder == true ? rubySize : 0) + (emphasizes && style.emphasisUnder ? size / 2 : 0)
        // The item's em box across the line.
        let emCentre = emStart + line.emSize / 2
        let overEdge: CGFloat, underEdge: CGFloat, baseline: CGFloat
        if mapper.vertical {
            overEdge = emCentre - size / 2
            underEdge = emCentre + size / 2
            baseline = emCentre
        } else {
            baseline = emStart + line.baseline - style.baselineShift
            overEdge = baseline - size * 0.88
            underEdge = baseline + size * 0.12
        }
        let decorationColor = (style.decorationColor ?? style.color ?? settings.textColor).faded(style.opacity).cgColor
        func stroke(atBlock block: CGFloat) {
            context.setFillColor(decorationColor)
            context.setStrokeColor(decorationColor)
            switch style.decorationStyle {
            case .solid:
                context.fill(mapper.rect(inline: start, block: block - thickness / 2, inlineSize: length, blockSize: thickness))
            case .double:
                for offset in [-thickness, thickness] {
                    context.fill(mapper.rect(inline: start, block: block + offset - thickness / 3, inlineSize: length, blockSize: thickness * 2 / 3))
                }
            case .dotted, .dashed:
                let dash = style.decorationStyle == .dotted ? thickness : thickness * 3
                var along = start
                while along < start + length {
                    context.fill(mapper.rect(inline: along, block: block - thickness / 2, inlineSize: min(dash, start + length - along), blockSize: thickness))
                    along += dash * 2
                }
            case .wavy:
                let path = CGMutablePath()
                let amplitude = thickness * 1.5
                let wavelength = thickness * 6
                var along: CGFloat = 0
                path.move(to: mapper.point(inline: start, block: block))
                while along < length {
                    let step = min(wavelength / 2, length - along)
                    let sign: CGFloat = Int((along / (wavelength / 2)).rounded()) % 2 == 0 ? -1 : 1
                    path.addQuadCurve(
                        to: mapper.point(inline: start + along + step, block: block),
                        control: mapper.point(inline: start + along + step / 2, block: block + sign * amplitude * 2))
                    along += step
                }
                context.setLineWidth(thickness)
                context.addPath(path)
                context.strokePath()
            }
        }
        // In a vertical line the over side is the right, the under side the left.
        if style.overline { stroke(atBlock: overEdge - overMarks - thickness) }
        if style.underline {
            if mapper.vertical, !style.underlineLeft {
                // 傍線, on the right of a vertical line, beyond its ruby and marks there.
                stroke(atBlock: overEdge - overMarks - thickness)
            } else {
                stroke(atBlock: underEdge + underMarks + (mapper.vertical ? thickness : 0))
            }
        }
        if style.lineThrough { stroke(atBlock: mapper.vertical ? emCentre : baseline - size * 0.3) }
        // Emphasis marks beside each character (not spaces or punctuation), beyond the ruby on its side.
        if let mark = style.emphasis, emphasizes {
            var markStyle = style
            markStyle.size = size / 2
            let character = Character(mark.character)
            let shape = fonts.shape(mark.character, markStyle, vertical: mapper.vertical && STCharacterClass.of(character).upright)
            let ascentRatio = shape.ascent / max(shape.ascent + shape.descent, 1)
            context.setFillColor((style.emphasisColor?.faded(style.opacity) ?? textColor).cgColor)
            let centreAlong = start + item.leadPad + item.boxLead
                + (item.squeezedAdvance - item.leadPad - item.trailPad - item.boxLead - item.boxTrail) / 2
            let centreAcross = style.emphasisUnder
                ? emStart + line.emSize + (rubyUnder == true ? rubySize : 0) + markStyle.size / 2
                : emStart - (rubyUnder == false ? rubySize : 0) - markStyle.size / 2
            let centre = mapper.point(inline: centreAlong, block: centreAcross)
            drawGlyphs(shape, at: CGPoint(x: centre.x - shape.advance / 2, y: centre.y - markStyle.size / 2 + markStyle.size * ascentRatio), context: context)
        }
    }

    /// Whether emphasis marks go beside an item: characters, not spaces, line breaks or
    /// punctuation (CSS Text Decoration: Zs, Cc, Cf and P* take none).
    private static func takesEmphasis(_ item: STItem) -> Bool {
        guard case .glyphs = item.kind, !item.isSpace, let scalar = Unicode.Scalar(item.scalar) else { return false }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
             .finalPunctuation, .otherPunctuation, .spaceSeparator, .control, .format:
            return false
        default:
            return true
        }
    }

    /// The ruby over the line's characters: over the middle of its base, or spread across
    /// it (an equal space between and half of it at either end) where the base is longer.
    private static func drawRubies(_ line: STLine, emStart: CGFloat, mapper: Mapper, settings: STReaderSettings, context: CGContext) {
        let set = line.block
        var seen = Set<Int>()
        for (offset, index) in line.items.enumerated() {
          for rubyIndex in [set.items[index].ruby, set.items[index].outerRuby].compactMap({ $0 }) {
            guard seen.insert(rubyIndex).inserted else { continue }
            let whole = set.rubies[rubyIndex]
            let first = offset
            let last = min(line.items.count - 1, offset + (whole.items.upperBound - index) - 1)
            // A group ruby broken between lines: its part over the base on this one, by the base's share.
            var ruby = whole
            let shownBase = index..<(line.items.lowerBound + last + 1)
            if shownBase != whole.items, whole.items.count > 0 {
                let characters = Array(whole.text)
                let from = Int((CGFloat(characters.count) * CGFloat(shownBase.lowerBound - whole.items.lowerBound) / CGFloat(whole.items.count)).rounded())
                let to = Int((CGFloat(characters.count) * CGFloat(shownBase.upperBound - whole.items.lowerBound) / CGFloat(whole.items.count)).rounded())
                let part = max(0, min(from, characters.count))..<max(0, min(to, characters.count))
                ruby.text = String(characters[part])
                ruby.shapes = Array(whole.shapes[part])
            }
            // Over the base's glyphs, without the space a long ruby made beside them.
            let firstItem = set.items[index], lastItem = set.items[line.items.lowerBound + last]
            let start = line.positions[first] + firstItem.startTrim + firstItem.leadPad + firstItem.boxLead
            let end = line.positions[last] + lastItem.startTrim + lastItem.squeezedAdvance - lastItem.trailPad - lastItem.boxTrail
            let lengths = zip(ruby.text, ruby.shapes).map { character, shape in
                mapper.vertical && STCharacterClass.of(character).upright ? shape.verticalAdvance : shape.advance
            }
            let total = lengths.reduce(0, +)
            let span = end - start
            var gap: CGFloat = 0
            var along = start + (span - total) / 2
            if total < span, !lengths.isEmpty {
                switch ruby.style.rubyAlign {
                case .start: along = start
                case .center: break
                case .spaceBetween:
                    gap = lengths.count > 1 ? (span - total) / CGFloat(lengths.count - 1) : 0
                    along = lengths.count > 1 ? start : start + (span - total) / 2
                case .spaceAround:
                    gap = (span - total) / CGFloat(lengths.count)
                    along = start + gap / 2
                }
            }
            let size = ruby.style.size
            // Under the line (left of a vertical one) for ruby-position: under.
            // A second ruby on the same side as the first stands beyond it.
            let innerOnSameSide = set.items[index].outerRuby == rubyIndex && set.items[index].ruby.map { set.rubies[$0].style.rubyUnder == ruby.style.rubyUnder } == true
            let beyond = innerOnSameSide ? (set.items[index].ruby.map { set.rubies[$0].style.size } ?? 0) : 0
            let rubyBlock = ruby.style.rubyUnder ? emStart + line.emSize + size + beyond : emStart - beyond
            context.setFillColor((ruby.style.color ?? settings.textColor).faded(ruby.style.opacity).cgColor)
            for ((character, shape), length) in zip(zip(ruby.text, ruby.shapes), lengths) {
                let upright = STCharacterClass.of(character).upright
                if mapper.vertical {
                    let centre = mapper.point(inline: along, block: rubyBlock - size / 2)
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
                    let foot = mapper.point(inline: along, block: rubyBlock - size + size * ascentRatio)
                    drawGlyphs(shape, at: foot, context: context)
                }
                along += length + gap
            }
          }
        }
    }
}

private extension CGRect {
    func inset(top: CGFloat, right: CGFloat, bottom: CGFloat, left: CGFloat) -> CGRect {
        CGRect(x: minX + left, y: minY + top, width: max(0, width - left - right), height: max(0, height - top - bottom))
    }
}
