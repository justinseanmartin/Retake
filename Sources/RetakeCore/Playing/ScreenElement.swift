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

extension ElementTarget {
    /// The shortest name for `elements[index]` that no other of `elements` matches, as `compose`
    /// suggests one: its label, else its label with, or instead, its identifier, value, hint or
    /// traits, trying fewer of them before more and in that order, and the fewest traits that do;
    /// traits alone only for an element with nothing else.
    /// Where nothing it has tells it apart from another, the shortest name that matches as few as
    /// any can, with the `occurrence` that picks it among those. Nil for an element with nothing to
    /// name it by.
    public static func naming(_ index: Int, in elements: [ScreenElement]) -> ElementTarget? {
        let element = elements[index]
        let nonEmpty = { (text: String?) in text.flatMap { $0.isEmpty ? nil : $0 } }
        let traits = element.traits.filter(knownTraits.contains)
        // Each field it has, in the order a name tries them.
        let fields: [(inout ElementTarget) -> Void] = [
            nonEmpty(element.label).map { label in { $0.label = label } },
            nonEmpty(element.identifier).map { identifier in { $0.identifier = identifier } },
            nonEmpty(element.value).map { value in { $0.value = value } },
            nonEmpty(element.hint).map { hint in { $0.hint = hint } },
            traits.isEmpty ? nil : { $0.traits = traits },
        ].compactMap(\.self)
        guard !fields.isEmpty else { return nil }
        let matching = { (target: ElementTarget) in elements.indices.filter { target.matches(elements[$0]) } }
        let target = { (chosen: [Int]) in chosen.reduce(into: ElementTarget()) { target, field in fields[field](&target) } }
        // Every field together matches as few as any name can; the first, shortest, name that does
        // too matches the same elements, since a field left out can only match more.
        let fewest = matching(target(Array(fields.indices))).count
        // Traits say what kind of thing it is rather than which, so they name it alone only when it
        // has nothing else.
        let traitsOnly = traits.isEmpty ? nil : [fields.count - 1]
        for chosen in subsets(of: fields.count) where chosen != traitsOnly || fields.count == 1 {
            var name = target(chosen)
            guard matching(name).count == fewest else { continue }
            if name.traits != nil {
                name.traits = subsets(of: traits.count).lazy.map { $0.map { traits[$0] } }.first { fewer in
                    var trimmed = name
                    trimmed.traits = fewer
                    return matching(trimmed).count == fewest
                }
            }
            let matches = matching(name)
            if matches.count > 1 { name.occurrence = matches.firstIndex(of: index)! + 1 }
            return name
        }
        return nil
    }

    /// Every non-empty subset of `0..<count`, as sorted indices, fewer before more and, among as
    /// many, in order: [0], [1], [0, 1].
    static func subsets(of count: Int) -> [[Int]] {
        func choose(_ size: Int, from start: Int) -> [[Int]] {
            guard size > 0 else { return [[]] }
            return (start..<max(start, count - size + 1)).flatMap { first in choose(size - 1, from: first + 1).map { [first] + $0 } }
        }
        return (0...count).dropFirst().flatMap { choose($0, from: 0) }
    }
}
