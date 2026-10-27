import Foundation

/// A problem in one of a project's files: the file, the path to the field, and what's wrong, as
/// docs/cli.md, "Reading the project's files", gives it:
/// `edits/video1.json: clips[3].from.fraction: 1.4 is outside -1 to 1`.
public struct FileProblem: Error, Equatable, Sendable, CustomStringConvertible {
    public var file: String
    public var path: JSONPath
    public var message: String
    /// The exact value the problem is about, when it's named at the object holding it, as an
    /// unknown key is: its object is `path`, and the key's own place is this.
    public var about: JSONPath?

    public init(file: String, path: JSONPath, message: String, about: JSONPath? = nil) {
        self.file = file
        self.path = path
        self.message = message
        self.about = about
    }

    public var description: String {
        path.isRoot ? "\(file): \(message)" : "\(file): \(path): \(message)"
    }
}

/// Reads one file's values strictly, collecting every problem rather than stopping at the first,
/// since `validate` prints them all and every command refuses a file with any. A value that has a
/// problem reads as nil, and what holds it carries on without it.
public final class JSONReader {
    /// The file as messages name it, relative to the project: `edits/video1.json`.
    public let file: String
    public private(set) var problems: [FileProblem] = []
    public private(set) var warnings: [FileProblem] = []

    public init(file: String) {
        self.file = file
    }

    public func problem(_ message: String, at path: JSONPath, about: JSONPath? = nil) {
        problems.append(FileProblem(file: file, path: path, message: message, about: about))
    }

    public func warning(_ message: String, at path: JSONPath) {
        warnings.append(FileProblem(file: file, path: path, message: message))
    }

    /// The file parsed, or nil with a problem saying where it isn't JSON.
    public func parse(_ text: String) -> JSONValue? {
        do {
            return try JSONParser.parse(text)
        } catch {
            problem("isn't valid JSON: \(error)", at: .root)
            return nil
        }
    }

    // MARK: - Values

    /// Nil, with a problem saying what was expected instead.
    func mismatch<Value>(_ expected: String, _ value: JSONValue, at path: JSONPath) -> Value? {
        problem("expected \(expected), found \(value.kind)", at: path)
        return nil
    }

    public func string(_ value: JSONValue, at path: JSONPath) -> String? {
        guard case .string(let string) = value else { return mismatch("a string", value, at: path) }
        return string
    }

    /// A string that isn't empty, for a name or a label.
    public func nonEmptyString(_ value: JSONValue, at path: JSONPath) -> String? {
        guard let string = string(value, at: path) else { return nil }
        guard !string.isEmpty else {
            problem("can't be empty", at: path)
            return nil
        }
        return string
    }

    public func bool(_ value: JSONValue, at path: JSONPath) -> Bool? {
        guard case .bool(let bool) = value else { return mismatch("true or false", value, at: path) }
        return bool
    }

    /// The limits a number may be held to, each with how an error says it was broken.
    public enum NumberLimit: Sendable {
        /// From one value to another, both included: `fraction`'s -1 to 1.
        case within(ClosedRange<Double>)
        /// More than a value: a speed more than 0.
        case above(Double)
        /// A value or more: a duration of 0 or more.
        case atLeast(Double)
    }

    public func number(_ value: JSONValue, at path: JSONPath, _ limit: NumberLimit? = nil) -> Double? {
        guard case .number(let number) = value else { return mismatch("a number", value, at: path) }
        switch limit {
        case .within(let range) where !range.contains(number):
            problem("\(Self.format(number)) is outside \(Self.format(range.lowerBound)) to \(Self.format(range.upperBound))", at: path)
            return nil
        case .above(let bound) where number <= bound:
            problem("\(Self.format(number)) must be more than \(Self.format(bound))", at: path)
            return nil
        case .atLeast(let bound) where number < bound:
            problem("\(Self.format(number)) must be at least \(Self.format(bound))", at: path)
            return nil
        default:
            return number
        }
    }

    public func integer(_ value: JSONValue, at path: JSONPath, atLeast minimum: Int? = nil) -> Int? {
        guard case .number(let number) = value else { return mismatch("a whole number", value, at: path) }
        guard number.rounded() == number, abs(number) < 1e15 else {
            problem("\(Self.format(number)) isn't a whole number", at: path)
            return nil
        }
        let integer = Int(number)
        if let minimum, integer < minimum {
            problem("\(integer) must be at least \(minimum)", at: path)
            return nil
        }
        return integer
    }

    /// One of a fixed set of strings, such as a set's `state`.
    public func choice<Choice: RawRepresentable & CaseIterable>(
        _ value: JSONValue,
        at path: JSONPath,
        as _: Choice.Type = Choice.self,
    ) -> Choice? where Choice.RawValue == String {
        guard let string = string(value, at: path) else { return nil }
        guard let choice = Choice(rawValue: string) else {
            let choices = Choice.allCases.map(\.rawValue)
            problem("\"\(string)\" isn't one of \(Self.list(choices))", at: path)
            return nil
        }
        return choice
    }

    /// A list, each element read by `element`; elements with problems are left out.
    public func array<Element>(
        _ value: JSONValue,
        at path: JSONPath,
        element: (JSONValue, JSONPath) -> Element?,
    ) -> [Element]? {
        guard case .array(let values) = value else { return mismatch("a list", value, at: path) }
        return values.enumerated().compactMap { index, value in element(value, path.appending(index)) }
    }

    /// An object whose keys are names of the file's choosing, such as environment variables, each
    /// value read by `element`, in the file's order; entries with problems are left out.
    public func dictionary<Element>(
        _ value: JSONValue,
        at path: JSONPath,
        element: (JSONValue, JSONPath) -> Element?,
    ) -> [(key: String, value: Element)]? {
        guard case .object(let object) = value else { return mismatch("an object", value, at: path) }
        reportDuplicates(in: object, at: path)
        var seen = Set<String>()
        return object.entries.compactMap { entry in
            guard seen.insert(entry.key).inserted else { return nil }
            return element(entry.value, path.appending(entry.key)).map { (entry.key, $0) }
        }
    }

    /// An object with fixed keys, read through what's returned, which says which keys it doesn't know.
    public func object(_ value: JSONValue, at path: JSONPath) -> ObjectReader? {
        guard case .object(let object) = value else { return mismatch("an object", value, at: path) }
        reportDuplicates(in: object, at: path)
        return ObjectReader(reader: self, object: object, path: path)
    }

    func reportDuplicates(in object: JSONObject, at path: JSONPath) {
        var seen = Set<String>()
        var reported = Set<String>()
        for key in object.keys where !seen.insert(key).inserted && reported.insert(key).inserted {
            problem("\"\(key)\" is given more than once", at: path)
        }
    }

    // MARK: - Formatting

    /// A number as a person writes it: `1.4`, `3`, `-0.25`.
    public static func format(_ number: Double) -> String {
        if number.rounded() == number, abs(number) < 1e15 { return String(Int(number)) }
        return String(number)
    }

    /// `a, b or c`.
    public static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " or " + items.last!
    }
}

/// An object with fixed keys. Each key a type reads is marked, and `finish()` reports every key it
/// didn't read as unknown, naming a known key when it's a likely misspelling of one.
public struct ObjectReader {
    public let reader: JSONReader
    public let object: JSONObject
    public let path: JSONPath
    private var known: [String] = []

    init(reader: JSONReader, object: JSONObject, path: JSONPath) {
        self.reader = reader
        self.object = object
        self.path = path
    }

    public func path(_ key: String) -> JSONPath { path.appending(key) }

    /// Whether the object has the key, which also makes it known.
    public mutating func has(_ key: String) -> Bool {
        know(key)
        return object[key] != nil
    }

    /// The key's value, if any, which also makes it known.
    public mutating func value(_ key: String) -> JSONValue? {
        know(key)
        return object[key]
    }

    /// A key the object must have, read by `read`; nil, with a problem, when it's missing.
    public mutating func required<Value>(_ key: String, _ read: (JSONValue, JSONPath) -> Value?) -> Value? {
        guard let value = value(key) else {
            reader.problem("is missing \"\(key)\"", at: path)
            return nil
        }
        return read(value, path(key))
    }

    /// A key the object may have, read by `read`.
    public mutating func optional<Value>(_ key: String, _ read: (JSONValue, JSONPath) -> Value?) -> Value? {
        guard let value = value(key) else { return nil }
        return read(value, path(key))
    }

    /// Makes keys known without reading them, for keys another reader handles.
    public mutating func know(_ keys: String...) {
        for key in keys where !known.contains(key) { known.append(key) }
    }

    /// Reports each key the object has that wasn't read or made known.
    public func finish() {
        for key in object.keys where !known.contains(key) {
            if let suggestion = Self.closest(to: key, in: known) {
                reader.problem("unknown key \"\(key)\"; did you mean \"\(suggestion)\"?", at: path, about: path.appending(key))
            } else {
                reader.problem("unknown key \"\(key)\"", at: path, about: path.appending(key))
            }
        }
    }

    /// The known key a misspelling most likely meant: within two edits, or differing only in case.
    static func closest(to key: String, in known: [String]) -> String? {
        let candidates = known.map { (key: $0, distance: editDistance(key.lowercased(), $0.lowercased())) }
            .filter { $0.distance <= min(2, max(1, $0.key.count / 3)) }
        return candidates.min { $0.distance < $1.distance }?.key
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}

// MARK: - The top of a file

/// The schema a file's `"$schema"` names, by its URL, as docs/cli.md, "Schemas", gives it:
/// `https://justinseanmartin.github.io/Retake/schemas/<version>/<kind>.schema.json`.
public struct SchemaReference: Equatable, Sendable {
    public static let base = "https://justinseanmartin.github.io/Retake/schemas/"

    public var version: String
    public var kind: String

    public init(version: String, kind: String) {
        self.version = version
        self.kind = kind
    }

    public init?(url: String) {
        guard url.hasPrefix(Self.base) else { return nil }
        let parts = url.dropFirst(Self.base.count).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].hasSuffix(".schema.json") else { return nil }
        version = String(parts[0])
        kind = String(parts[1].dropLast(".schema.json".count))
        guard !kind.isEmpty else { return nil }
    }

    public var url: String { "\(Self.base)\(version)/\(kind).schema.json" }

    /// This Retake's schema for a kind of file.
    public static func current(_ kind: String) -> SchemaReference {
        SchemaReference(version: RetakeVersion.current.schemaVersion, kind: kind)
    }
}

extension JSONReader {
    /// The object at the top of a file of `kind` (`retake`, `set`, `scene`, `edit`), with its
    /// optional `"$schema"` read: it's read against this Retake's schema whatever it names, with a
    /// warning when it names another version's, or another kind of file's.
    public func root(_ value: JSONValue, kind: String) -> ObjectReader? {
        guard var object = object(value, at: .root) else { return nil }
        if let schema = object.optional("$schema", string) {
            if let reference = SchemaReference(url: schema) {
                let current = SchemaReference.current(kind)
                if reference.kind != kind {
                    warning("\"$schema\" names the \(reference.kind) schema, but this is read as a \(kind) file", at: .root)
                } else if reference.version != current.version {
                    warning(
                        "\"$schema\" names Retake \(reference.version)'s schema; reading it as this Retake's (\(current.version))",
                        at: .root,
                    )
                }
            }
        }
        return object
    }
}
