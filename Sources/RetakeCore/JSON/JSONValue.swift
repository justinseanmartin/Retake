/// A JSON value, as Retake reads its files: objects keep their keys in the order the file gives
/// them, so an edit Retake rewrites before `cut` keeps its shape.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    /// What kind of value it is, as an error message says it: "a string", "a list".
    public var kind: String {
        switch self {
        case .null: "null"
        case .bool: "true or false"
        case .number: "a number"
        case .string: "a string"
        case .array: "a list"
        case .object: "an object"
        }
    }
}

/// A JSON object's keys and values, in the file's order, including any key given twice, so that
/// reading it can say so.
public struct JSONObject: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var key: String
        public var value: JSONValue

        public init(key: String, value: JSONValue) {
            self.key = key
            self.value = value
        }
    }

    public var entries: [Entry]

    public init(_ entries: [Entry] = []) {
        self.entries = entries
    }

    /// The value of the first entry with the key.
    public subscript(key: String) -> JSONValue? {
        entries.first { $0.key == key }?.value
    }

    public var keys: [String] { entries.map(\.key) }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByArrayLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}
