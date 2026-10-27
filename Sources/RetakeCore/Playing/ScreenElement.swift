import Foundation

/// An element on screen, as `compose` prints it and an `orientation` step watches it: what
/// VoiceOver knows it by, and where it is, in screen points.
public struct ScreenElement: Equatable, Sendable {
    public var label: String?
    public var value: String?
    public var identifier: String?
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

    public init(label: String? = nil, value: String? = nil, identifier: String? = nil, traits: [String] = [], frame: Rect? = nil, activationPoint: Point? = nil) {
        self.label = label
        self.value = value
        self.identifier = identifier
        self.traits = traits
        self.frame = frame
        self.activationPoint = activationPoint
    }

    /// One line: `"New Note"  button  frame (20, 96, 160×44)  at (100, 118)`, with a value and an
    /// identifier when it has them, since a step can name it by either.
    public var line: String {
        var parts: [String] = []
        parts.append(label.map(JSONWriter.quote) ?? "(no label)")
        if let value { parts.append("value \(JSONWriter.quote(value))") }
        if let identifier { parts.append("identifier \(JSONWriter.quote(identifier))") }
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
