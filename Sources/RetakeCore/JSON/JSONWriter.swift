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
