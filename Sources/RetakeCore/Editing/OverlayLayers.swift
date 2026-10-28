import AppKit
import AVFoundation
import QuartzCore

/// What's drawn over a video's picture, as Core Animation layers timed on the video's clock, for
/// `AVVideoCompositionCoreAnimationTool`, which renders them only in an export. Blurs aren't layers:
/// the export draws them on each frame.
public struct OverlayLayers: @unchecked Sendable {
    /// The whole canvas, holding `video` and what's drawn over it.
    public let parent: CALayer
    /// Where the composition's picture is drawn.
    public let video: CALayer

    /// The layers for `overlays` on a canvas of `spec`'s size, `stills` being each still's frame,
    /// in the order of `overlays.stills`.
    public init(_ overlays: Overlays, spec: PreviewSpec, stills: [CGImage] = []) {
        let canvas = spec.size
        parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: canvas)
        // Top-down, as the canvas's positions are.
        parent.isGeometryFlipped = true
        video = CALayer()
        video.frame = parent.frame
        parent.addSublayer(video)

        for (still, image) in zip(overlays.stills, stills) {
            parent.addSublayer(Self.still(still, image: image.cropping(to: still.crop.integral) ?? image, canvas: canvas))
        }
        for touch in overlays.touches { parent.addSublayer(Self.touch(touch)) }
        for spotlight in overlays.spotlights {
            for layer in Self.spotlight(spotlight, canvas: canvas) { parent.addSublayer(layer) }
        }
        for caption in overlays.captions { parent.addSublayer(Self.caption(caption, canvas: canvas)) }
    }

    // MARK: Touches

    /// A dot where the touch landed, pressed and let go, or for a drag, moving with it.
    static func touch(_ touch: Overlays.Touch) -> CALayer {
        let diameter = 92.0
        let dot = CALayer()
        dot.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        dot.position = touch.from
        dot.cornerRadius = diameter / 2
        dot.backgroundColor = NSColor.white.withAlphaComponent(0.45).cgColor
        dot.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        dot.borderWidth = 5
        dot.shadowOpacity = 0.25
        dot.shadowRadius = 8
        dot.shadowOffset = .zero
        dot.opacity = 0

        // Held for the drag's length on screen; a tap is a press and a release.
        let dragging = touch.to == nil ? 0 : max(0.2, touch.duration - 0.15)
        let pressed = 0.12 + dragging
        dot.add(animation("opacity", values: [0, 1, 1, 0], keyTimes: [0, 0.08, pressed, pressed + 0.3], at: touch.start), forKey: "opacity")
        dot.add(animation("transform.scale", values: [0.6, 1, 1, 1.25], keyTimes: [0, 0.12, pressed, pressed + 0.3], at: touch.start), forKey: "scale")
        if let to = touch.to {
            let move = animation(
                "position", values: [NSValue(point: touch.from), NSValue(point: touch.from), NSValue(point: to), NSValue(point: to)],
                keyTimes: [0, 0.1, 0.1 + dragging, pressed + 0.3], at: touch.start,
            )
            move.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .linear)]
            dot.add(move, forKey: "position")
        }
        return dot
    }

    // MARK: Spotlights

    /// The rest of the canvas dimmed, and a ring pulsing around what's spotlit.
    static func spotlight(_ spotlight: Overlays.Spotlight, canvas: CGSize) -> [CALayer] {
        let frame = spotlight.rect
        let cornerRadius = min(frame.height / 2, 40)
        let dim = CAShapeLayer()
        let dimPath = CGMutablePath()
        dimPath.addRect(CGRect(origin: .zero, size: canvas))
        dimPath.addPath(CGPath(roundedRect: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        dim.path = dimPath
        dim.fillRule = .evenOdd
        dim.fillColor = NSColor.black.withAlphaComponent(0.45).cgColor
        dim.opacity = 0

        let color = cgColor(spotlight.color)
        let ring = CAShapeLayer()
        ring.frame = frame
        ring.path = CGPath(roundedRect: CGRect(origin: .zero, size: frame.size), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ring.fillColor = nil
        ring.strokeColor = color
        ring.lineWidth = 8
        ring.shadowColor = color
        ring.shadowOpacity = 0.8
        ring.shadowRadius = 16
        ring.shadowOffset = .zero
        ring.opacity = 0

        let length = spotlight.end - spotlight.start
        let fade = animation("opacity", values: [0, 1, 1, 0], keyTimes: [0, min(0.2, length / 3), max(length - 0.2, length * 2 / 3), length], at: spotlight.start)
        dim.add(fade, forKey: "opacity")
        ring.add(fade, forKey: "opacity")
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1
        pulse.toValue = 1.08
        pulse.duration = 0.45
        pulse.autoreverses = true
        pulse.repeatCount = .greatestFiniteMagnitude
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.beginTime = AVCoreAnimationBeginTimeAtZero + spotlight.start
        pulse.isRemovedOnCompletion = false
        ring.add(pulse, forKey: "pulse")
        return [dim, ring]
    }

    // MARK: Stills

    /// One of a grid of rounded frames, popping in on a spring.
    static func still(_ still: Overlays.Still, image: CGImage, canvas: CGSize) -> CALayer {
        let columns = still.count > 4 ? 3 : 2
        let rows = (still.count + columns - 1) / columns
        let gap = 30.0
        let width = (canvas.width - 70 * 2 - gap * Double(columns - 1)) / Double(columns)
        let height = width * Double(image.height) / Double(image.width)
        let gridHeight = height * Double(rows) + gap * Double(rows - 1)
        let top = (canvas.height - gridHeight) / 2 + 110
        let column = still.index % columns
        let row = still.index / columns
        // A short last row is centred.
        let inRow = row == rows - 1 ? still.count - row * columns : columns
        let rowWidth = width * Double(inRow) + gap * Double(inRow - 1)
        let left = (canvas.width - rowWidth) / 2

        let screen = CALayer()
        screen.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        screen.position = CGPoint(x: left + Double(column) * (width + gap) + width / 2, y: top + Double(row) * (height + gap) + height / 2)
        screen.contents = image
        screen.contentsGravity = .resizeAspectFill
        screen.cornerRadius = 30
        screen.masksToBounds = true
        screen.borderColor = NSColor.white.cgColor
        screen.borderWidth = 6

        // The shadow is drawn by a holder, since the frame masks to its rounded corners.
        let holder = CALayer()
        holder.frame = CGRect(origin: .zero, size: canvas)
        holder.shadowOpacity = 0.3
        holder.shadowRadius = 18
        holder.shadowOffset = CGSize(width: 0, height: 8)
        holder.addSublayer(screen)

        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0
        pop.toValue = 1
        pop.mass = 1
        pop.stiffness = 220
        pop.damping = 14
        pop.duration = pop.settlingDuration
        pop.beginTime = AVCoreAnimationBeginTimeAtZero + still.start
        pop.fillMode = .both
        pop.isRemovedOnCompletion = false
        screen.add(pop, forKey: "pop")
        screen.opacity = 0
        let length = still.end - still.start
        screen.add(animation("opacity", values: [0, 1, 1, 0], keyTimes: [0, 0.05, max(0.05, length - 0.15), length], at: still.start), forKey: "opacity")
        return holder
    }

    // MARK: Captions

    /// The caption's text on a pill of its colour, across the canvas's centre at its `y`, with its
    /// symbol before the text, turning as its animation says.
    static func caption(_ caption: Overlays.Caption, canvas: CGSize) -> CALayer {
        let font = NSFont.systemFont(ofSize: 54, weight: .heavy).rounded
        let text = NSAttributedString(string: caption.text, attributes: [.font: font, .foregroundColor: NSColor.white])
        let textSize = text.size()
        let padding = CGSize(width: 40, height: 22)
        let symbol = caption.symbol.flatMap { symbolImage($0.name, font: font) }
        let symbolWidth = symbol.map { ceil($0.size.width) + 20 } ?? 0

        let pill = CALayer()
        pill.bounds = CGRect(x: 0, y: 0, width: symbolWidth + ceil(textSize.width) + padding.width * 2, height: ceil(textSize.height) + padding.height * 2)
        pill.position = CGPoint(x: canvas.width / 2, y: caption.y * canvas.height)
        pill.cornerRadius = pill.bounds.height / 2
        pill.backgroundColor = cgColor(caption.color, alpha: 0.88)
        pill.shadowOpacity = 0.25
        pill.shadowRadius = 14
        pill.shadowOffset = CGSize(width: 0, height: 6)

        // Drawn into an image, since a CATextLayer renders nothing in an export.
        let label = CALayer()
        label.frame = CGRect(x: padding.width + symbolWidth, y: padding.height, width: ceil(textSize.width), height: ceil(textSize.height))
        label.contents = image(of: text, size: label.frame.size)
        pill.addSublayer(label)
        if let symbol {
            let glyph = CALayer()
            glyph.bounds = CGRect(origin: .zero, size: symbol.size)
            glyph.position = CGPoint(x: padding.width + symbol.size.width / 2, y: pill.bounds.midY)
            glyph.contents = symbol.image
            pill.addSublayer(glyph)
            if let rotation = caption.symbol?.rotation {
                // Clockwise when positive, as the canvas runs top-down.
                let turn = CABasicAnimation(keyPath: "transform.rotation.z")
                turn.fromValue = 0
                turn.toValue = rotation.degrees * .pi / 180
                turn.duration = rotation.duration
                turn.beginTime = AVCoreAnimationBeginTimeAtZero + caption.start
                turn.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                turn.fillMode = .both
                turn.isRemovedOnCompletion = false
                glyph.add(turn, forKey: "turn")
            }
        }
        pill.opacity = 0
        let length = caption.end - caption.start
        let rise = min(0.2, length / 3)
        pill.add(animation("opacity", values: [0, 1, 1, 0], keyTimes: [0, rise, length - rise, length], at: caption.start), forKey: "opacity")
        pill.add(animation("transform.scale", values: [0.85, 1.04, 1, 1], keyTimes: [0, rise, min(rise * 1.6, length - rise), length], at: caption.start), forKey: "scale")
        return pill
    }

    /// An SF Symbol in white, sized to sit beside text in `font`.
    static func symbolImage(_ name: String, font: NSFont) -> (image: CGImage, size: CGSize)? {
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .heavy)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return nil }
        let size = symbol.size
        guard let image = draw(size: size, { symbol.draw(in: CGRect(origin: .zero, size: size)) }) else { return nil }
        return (image, size)
    }

    static func image(of text: NSAttributedString, size: CGSize) -> CGImage? {
        draw(size: size) { text.draw(at: .zero) }
    }

    /// Draws at twice the size, for a sharp image when scaled.
    static func draw(size: CGSize, _ body: () -> Void) -> CGImage? {
        let scale = 2.0
        guard size.width > 0, size.height > 0, let context = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        body()
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    // MARK: Timing

    /// A keyframe animation on the video's clock; `keyTimes` are seconds after `time`.
    static func animation(_ keyPath: String, values: [Any], keyTimes: [Double], at time: Double) -> CAKeyframeAnimation {
        let duration = max(keyTimes.last ?? 0, 0.001)
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes.map { NSNumber(value: $0 / duration) }
        animation.duration = duration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + time
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        return animation
    }

    static func cgColor(_ color: Color, alpha: Double? = nil) -> CGColor {
        CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: alpha ?? color.alpha)
    }
}

private extension NSFont {
    var rounded: NSFont {
        fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: pointSize) } ?? self
    }
}
