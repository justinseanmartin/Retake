/// Writes JSON as Retake's files are written: two-space indents, keys in the order given, and a
/// list of plain values on one line when it fits.
public enum JSONWriter {
    public static func write(_ value: JSONValue) -> String {
        var text = ""
        write(value, indent: 0, into: &text)
        return text + "\n"
    }

    /// How long a list may be, written on one line, before each value gets a line of its own.
    static let lineLimit = 80

    private static func write(_ value: JSONValue, indent: Int, into text: inout String) {
        switch value {
        case .null: text += "null"
        case .bool(let bool): text += bool ? "true" : "false"
        case .number(let number): text += JSONReader.format(number)
        case .string(let string): text += quote(string)
        case .array(let values):
            if values.isEmpty {
                text += "[]"
            } else if values.allSatisfy(isPlain), let line = Optional(values.map(inline).joined(separator: ", ")),
                      line.count + indent <= lineLimit {
                text += "[\(line)]"
            } else {
                text += "[\n"
                for (index, element) in values.enumerated() {
                    text += String(repeating: " ", count: indent + 2)
                    write(element, indent: indent + 2, into: &text)
                    text += index == values.count - 1 ? "\n" : ",\n"
                }
                text += String(repeating: " ", count: indent) + "]"
            }
        case .object(let object):
            if object.entries.isEmpty {
                text += "{}"
                return
            }
            text += "{\n"
            for (index, entry) in object.entries.enumerated() {
                text += String(repeating: " ", count: indent + 2) + quote(entry.key) + ": "
                write(entry.value, indent: indent + 2, into: &text)
                text += index == object.entries.count - 1 ? "\n" : ",\n"
            }
            text += String(repeating: " ", count: indent) + "}"
        }
    }

    /// Writes JSON as a person would lay out an edit: each object or list on one line when it fits
    /// within `width` columns where it starts, laid out a member to a line when it doesn't, the file
    /// itself always laid out. Rewriting a file laid out this way changes only what changed.
    public static func fitting(_ value: JSONValue, width: Int = 100) -> String {
        var text = ""
        fit(value, indent: 0, prefix: 0, width: width, into: &text)
        return text + "\n"
    }

    /// `prefix` is how much of the line is already taken where the value starts: its indent and key.
    private static func fit(_ value: JSONValue, indent: Int, prefix: Int, width: Int, into text: inout String) {
        switch value {
        case .array(let values) where !values.isEmpty:
            if indent > 0 || prefix > 0, prefix + compact(value).count + 1 <= width {
                text += compact(value)
                return
            }
            text += "[\n"
            for (index, element) in values.enumerated() {
                text += String(repeating: " ", count: indent + 2)
                fit(element, indent: indent + 2, prefix: indent + 2, width: width, into: &text)
                text += index == values.count - 1 ? "\n" : ",\n"
            }
            text += String(repeating: " ", count: indent) + "]"
        case .object(let object) where !object.entries.isEmpty:
            if indent > 0 || prefix > 0, prefix + compact(value).count + 1 <= width {
                text += compact(value)
                return
            }
            text += "{\n"
            for (index, entry) in object.entries.enumerated() {
                let key = String(repeating: " ", count: indent + 2) + quote(entry.key) + ": "
                text += key
                fit(entry.value, indent: indent + 2, prefix: key.count, width: width, into: &text)
                text += index == object.entries.count - 1 ? "\n" : ",\n"
            }
            text += String(repeating: " ", count: indent) + "}"
        default:
            text += compact(value)
        }
    }

    /// A value on one line, spaced as Retake's files write a short object:
    /// `{ "id": "new-note", "tap": { "label": "New Note" } }`.
    public static func compact(_ value: JSONValue) -> String {
        switch value {
        case .array(let values):
            values.isEmpty ? "[]" : "[" + values.map(compact).joined(separator: ", ") + "]"
        case .object(let object):
            object.entries.isEmpty ? "{}" : "{ " + object.entries.map { "\(quote($0.key)): \(compact($0.value))" }.joined(separator: ", ") + " }"
        default:
            inline(value)
        }
    }

    private static func inline(_ value: JSONValue) -> String {
        var text = ""
        write(value, indent: 0, into: &text)
        return text
    }

    private static func isPlain(_ value: JSONValue) -> Bool {
        switch value {
        case .array, .object: false
        default: true
        }
    }

    static func quote(_ string: String) -> String {
        var text = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            case "\n": text += "\\n"
            case "\r": text += "\\r"
            case "\t": text += "\\t"
            case "\u{08}": text += "\\b"
            case "\u{0C}": text += "\\f"
            case _ where scalar.value < 0x20:
                text += "\\u" + String(repeating: "0", count: 4 - String(scalar.value, radix: 16).count)
                    + String(scalar.value, radix: 16)
            default: text.unicodeScalars.append(scalar)
            }
        }
        return text + "\""
    }
}
