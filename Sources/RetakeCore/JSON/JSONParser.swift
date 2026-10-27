/// Parses JSON (RFC 8259) strictly, keeping objects' keys in order: no comments, no trailing commas,
/// and nothing after the value but whitespace.
public enum JSONParser {
    /// Where parsing stopped, by line and column from 1, and why.
    public struct Failure: Error, Equatable, Sendable, CustomStringConvertible {
        public var line: Int
        public var column: Int
        public var message: String

        public var description: String { "line \(line), column \(column): \(message)" }
    }

    public static func parse(_ text: String) throws(Failure) -> JSONValue {
        var parser = Parser(bytes: Array(text.utf8))
        parser.skipByteOrderMark()
        parser.skipWhitespace()
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.isAtEnd else { throw parser.failure("expected the end of the file after the value") }
        return value
    }

    /// How deep values may nest, so that a malformed file can't exhaust the stack.
    static let maximumDepth = 100
}

private struct Parser {
    let bytes: [UInt8]
    var offset = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { offset >= bytes.count }
    var current: UInt8? { isAtEnd ? nil : bytes[offset] }

    mutating func skipByteOrderMark() {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { offset = 3 }
    }

    mutating func skipWhitespace() {
        while let byte = current, byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 {
            offset += 1
        }
    }

    /// A failure at the current offset, with its line and column counted in characters.
    func failure(_ message: String, at position: Int? = nil) -> JSONParser.Failure {
        let position = min(position ?? offset, bytes.count)
        var line = 1
        var lineStart = 0
        for index in 0..<position where bytes[index] == 0x0A {
            line += 1
            lineStart = index + 1
        }
        let column = String(decoding: bytes[lineStart..<position], as: UTF8.self).count + 1
        return JSONParser.Failure(line: line, column: column, message: message)
    }

    func describeCurrent() -> String {
        guard let byte = current else { return "the end of the file" }
        if byte >= 0x20, byte < 0x7F { return "\"\(Character(Unicode.Scalar(byte)))\"" }
        return "a byte 0x\(String(byte, radix: 16, uppercase: true))"
    }

    mutating func value(depth: Int) throws(JSONParser.Failure) -> JSONValue {
        guard depth < JSONParser.maximumDepth else { throw failure("values nest too deeply") }
        guard let byte = current else { throw failure("expected a value, found the end of the file") }
        switch byte {
        case UInt8(ascii: "{"): return try object(depth: depth)
        case UInt8(ascii: "["): return try array(depth: depth)
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try number())
        default: throw failure("expected a value, found \(describeCurrent())")
        }
    }

    mutating func literal(_ word: String) throws(JSONParser.Failure) {
        let start = offset
        for byte in word.utf8 {
            guard current == byte else { throw failure("expected \(word)", at: start) }
            offset += 1
        }
    }

    mutating func object(depth: Int) throws(JSONParser.Failure) -> JSONValue {
        offset += 1
        var entries: [JSONObject.Entry] = []
        skipWhitespace()
        if current == UInt8(ascii: "}") {
            offset += 1
            return .object(JSONObject(entries))
        }
        while true {
            skipWhitespace()
            guard current == UInt8(ascii: "\"") else {
                throw failure("expected a key in quotes, found \(describeCurrent())")
            }
            let key = try string()
            skipWhitespace()
            guard current == UInt8(ascii: ":") else { throw failure("expected \":\" after the key, found \(describeCurrent())") }
            offset += 1
            skipWhitespace()
            entries.append(JSONObject.Entry(key: key, value: try value(depth: depth + 1)))
            skipWhitespace()
            switch current {
            case UInt8(ascii: ","):
                offset += 1
                skipWhitespace()
                if current == UInt8(ascii: "}") { throw failure("expected a key after \",\"; JSON has no trailing commas") }
            case UInt8(ascii: "}"):
                offset += 1
                return .object(JSONObject(entries))
            default:
                throw failure("expected \",\" or \"}\", found \(describeCurrent())")
            }
        }
    }

    mutating func array(depth: Int) throws(JSONParser.Failure) -> JSONValue {
        offset += 1
        var elements: [JSONValue] = []
        skipWhitespace()
        if current == UInt8(ascii: "]") {
            offset += 1
            return .array(elements)
        }
        while true {
            skipWhitespace()
            elements.append(try value(depth: depth + 1))
            skipWhitespace()
            switch current {
            case UInt8(ascii: ","):
                offset += 1
                skipWhitespace()
                if current == UInt8(ascii: "]") { throw failure("expected a value after \",\"; JSON has no trailing commas") }
            case UInt8(ascii: "]"):
                offset += 1
                return .array(elements)
            default:
                throw failure("expected \",\" or \"]\", found \(describeCurrent())")
            }
        }
    }

    mutating func string() throws(JSONParser.Failure) -> String {
        let start = offset
        offset += 1
        var scalars = String.UnicodeScalarView()
        var run = offset
        func flush(_ end: Int) {
            scalars.append(contentsOf: String(decoding: bytes[run..<end], as: UTF8.self).unicodeScalars)
        }
        while true {
            guard let byte = current else { throw failure("a string isn't closed", at: start) }
            switch byte {
            case UInt8(ascii: "\""):
                flush(offset)
                offset += 1
                return String(scalars)
            case UInt8(ascii: "\\"):
                flush(offset)
                offset += 1
                scalars.append(try escape())
                run = offset
            case 0x00..<0x20:
                throw failure("a string can't hold a control character unescaped; use \\n, \\t or \\u")
            default:
                offset += 1
            }
        }
    }

    mutating func escape() throws(JSONParser.Failure) -> Unicode.Scalar {
        guard let byte = current else { throw failure("a string isn't closed") }
        offset += 1
        switch byte {
        case UInt8(ascii: "\""): return "\""
        case UInt8(ascii: "\\"): return "\\"
        case UInt8(ascii: "/"): return "/"
        case UInt8(ascii: "b"): return "\u{08}"
        case UInt8(ascii: "f"): return "\u{0C}"
        case UInt8(ascii: "n"): return "\n"
        case UInt8(ascii: "r"): return "\r"
        case UInt8(ascii: "t"): return "\t"
        case UInt8(ascii: "u"):
            let high = try hexQuad()
            if (0xD800...0xDBFF).contains(high) {
                guard current == UInt8(ascii: "\\"), offset + 1 < bytes.count, bytes[offset + 1] == UInt8(ascii: "u") else {
                    throw failure("a \\u escape of half a surrogate pair needs its other half")
                }
                offset += 2
                let low = try hexQuad()
                guard (0xDC00...0xDFFF).contains(low) else { throw failure("a \\u escape of half a surrogate pair needs its other half") }
                return Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00))!
            }
            guard let scalar = Unicode.Scalar(high) else { throw failure("a \\u escape of half a surrogate pair needs its other half") }
            return scalar
        default:
            throw failure("unknown escape \"\\\(Character(Unicode.Scalar(byte)))\"", at: offset - 2)
        }
    }

    mutating func hexQuad() throws(JSONParser.Failure) -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = current, let digit = Self.hexDigit(byte) else { throw failure("expected four hex digits after \\u") }
            value = value * 16 + digit
            offset += 1
        }
        return value
    }

    static func hexDigit(_ byte: UInt8) -> UInt32? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): UInt32(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): UInt32(byte - UInt8(ascii: "a") + 10)
        case UInt8(ascii: "A")...UInt8(ascii: "F"): UInt32(byte - UInt8(ascii: "A") + 10)
        default: nil
        }
    }

    mutating func number() throws(JSONParser.Failure) -> Double {
        let start = offset
        if current == UInt8(ascii: "-") { offset += 1 }
        func digits() -> Int {
            let from = offset
            while let byte = current, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) { offset += 1 }
            return offset - from
        }
        if current == UInt8(ascii: "0") {
            offset += 1
            if let byte = current, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
                throw failure("a number can't start with 0 unless it's 0", at: start)
            }
        } else if digits() == 0 {
            throw failure("expected a digit", at: offset)
        }
        if current == UInt8(ascii: ".") {
            offset += 1
            guard digits() > 0 else { throw failure("expected a digit after \".\"") }
        }
        if current == UInt8(ascii: "e") || current == UInt8(ascii: "E") {
            offset += 1
            if current == UInt8(ascii: "+") || current == UInt8(ascii: "-") { offset += 1 }
            guard digits() > 0 else { throw failure("expected a digit in the exponent") }
        }
        let text = String(decoding: bytes[start..<offset], as: UTF8.self)
        guard let value = Double(text), value.isFinite else { throw failure("\(text) is too large a number", at: start) }
        return value
    }
}
