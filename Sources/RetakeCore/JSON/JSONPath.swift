/// Where a value is in a file, as errors name it: `clips[3].from.fraction`. Lists are counted from 0,
/// as in JSON tools and editors.
public struct JSONPath: Hashable, Sendable, CustomStringConvertible {
    public enum Component: Hashable, Sendable {
        case key(String)
        case index(Int)
    }

    public var components: [Component]

    public init(_ components: [Component] = []) {
        self.components = components
    }

    public static let root = JSONPath()

    public var isRoot: Bool { components.isEmpty }

    public func appending(_ key: String) -> JSONPath {
        JSONPath(components + [.key(key)])
    }

    public func appending(_ index: Int) -> JSONPath {
        JSONPath(components + [.index(index)])
    }

    public var description: String {
        var text = ""
        for component in components {
            switch component {
            case .index(let index):
                text += "[\(index)]"
            case .key(let key) where Self.isPlain(key):
                text += text.isEmpty ? key : ".\(key)"
            case .key(let key):
                // A key that isn't a plain name, such as a set's file path, is quoted.
                let escaped = key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                text += "[\"\(escaped)\"]"
            }
        }
        return text
    }

    /// Letters, digits, `_`, `-` and `$`, not starting with a digit or `-`: `create-note`, `$schema`.
    private static func isPlain(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first, !CharacterSetLite.digits.contains(first), first != "-" else {
            return false
        }
        return key.unicodeScalars.allSatisfy { CharacterSetLite.plain.contains($0) }
    }
}

/// The ASCII sets a plain key is made of, without Foundation's `CharacterSet`.
private enum CharacterSetLite {
    static let digits = Set("0123456789".unicodeScalars)
    static let plain = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-$".unicodeScalars)
}
