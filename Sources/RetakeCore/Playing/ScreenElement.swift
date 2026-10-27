import Foundation

/// An element on screen, as `compose` prints it and an `orientation` step watches it: what
/// VoiceOver knows it by, and where it is, in screen points.
public struct ScreenElement: Equatable, Sendable {
    public var label: String?
    public var value: String?
    public var identifier: String?
    public var hint: String?
    public var traits: [String]
    /// Nil for an element off screen.
    public var frame: Rect?
    public var activationPoint: Point?

    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public init(
        label: String? = nil, value: String? = nil, identifier: String? = nil, hint: String? = nil, traits: [String] = [],
        frame: Rect? = nil, activationPoint: Point? = nil,
    ) {
        self.hint = hint
        self.label = label
        self.value = value
        self.identifier = identifier
        self.traits = traits
        self.frame = frame
        self.activationPoint = activationPoint
    }

    /// One line: `"New Note"  button  frame (20, 96, 160×44)  at (100, 118)`, with a value, an
    /// identifier and a hint when it has them, since a step can name it by any of them.
    public var line: String {
        var parts: [String] = []
        parts.append(label.map(JSONWriter.quote) ?? "(no label)")
        if let value { parts.append("value \(JSONWriter.quote(value))") }
        if let identifier { parts.append("identifier \(JSONWriter.quote(identifier))") }
        if let hint { parts.append("hint \(JSONWriter.quote(hint))") }
        if !traits.isEmpty { parts.append(traits.joined(separator: ", ")) }
        if let frame {
            parts.append("frame (\(Point.number(frame.x)), \(Point.number(frame.y)), \(Point.number(frame.width))×\(Point.number(frame.height)))")
        } else {
            parts.append("off screen")
        }
        if let activationPoint { parts.append("at \(activationPoint)") }
        return parts.joined(separator: "  ")
    }
}

extension ElementTarget {
    /// Whether `element` is one this names: every field given equal to the element's, as The Button
    /// Heist matches them, leaving `occurrence` aside, which picks among those that match.
    public func matches(_ element: ScreenElement) -> Bool {
        (label == nil || label == element.label)
            && (value == nil || value == element.value)
            && (identifier == nil || identifier == element.identifier)
            && (hint == nil || hint == element.hint)
            && (traits ?? []).allSatisfy(element.traits.contains)
    }
}
