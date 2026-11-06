import Foundation
import RetakeCore

/// Checks a value against a JSON Schema document, for the keywords Retake's schemas use: enough to
/// hold the schemas to what the readers accept, without a library.
struct SchemaValidator {
    let document: JSONValue

    /// The first place the value doesn't fit, or nil when it fits.
    func problem(_ value: JSONValue) -> String? {
        problem(value, document, at: "")
    }

    /// The first place the value doesn't fit a part of the document, such as one field's schema.
    func problem(_ value: JSONValue, against schema: JSONValue) -> String? {
        problem(value, schema, at: "")
    }

    private func problem(_ value: JSONValue, _ schema: JSONValue, at path: String) -> String? {
        guard case .object(let schema) = schema else {
            return schema == .bool(false) ? "\(path): not allowed" : nil
        }
        if let ref = schema["$ref"]?.stringValue {
            let name = String(ref.dropFirst("#/$defs/".count))
            guard let definition = document[path: "$defs", name] else { return "\(path): no definition \(name)" }
            if let problem = problem(value, definition, at: path) { return problem }
        }
        if let type = schema["type"] {
            let types: [String] = if case .array(let names) = type { names.compactMap(\.stringValue) } else { [type.stringValue ?? ""] }
            guard types.contains(where: { Self.matches(value, $0) }) else { return "\(path): expected \(types.joined(separator: " or "))" }
        }
        if case .array(let choices)? = schema["enum"], !choices.contains(value) { return "\(path): not one of the choices" }
        if case .string(let string) = value {
            if let pattern = schema["pattern"]?.stringValue, string.range(of: pattern, options: .regularExpression) == nil {
                return "\(path): doesn't match \(pattern)"
            }
            if case .number(let length)? = schema["minLength"], Double(string.count) < length { return "\(path): too short" }
        }
        if case .number(let number) = value {
            if case .number(let minimum)? = schema["minimum"], number < minimum { return "\(path): below \(minimum)" }
            if case .number(let minimum)? = schema["exclusiveMinimum"], number <= minimum { return "\(path): not above \(minimum)" }
            if case .number(let maximum)? = schema["maximum"], number > maximum { return "\(path): above \(maximum)" }
        }
        if case .object(let object) = value {
            let properties: JSONObject = if case .object(let properties)? = schema["properties"] { properties } else { JSONObject() }
            if case .array(let required)? = schema["required"] {
                for key in required.compactMap(\.stringValue) where object[key] == nil { return "\(path): needs \(key)" }
            }
            for entry in object.entries {
                let at = "\(path).\(entry.key)"
                if let names = schema["propertyNames"], let problem = problem(.string(entry.key), names, at: at) { return problem }
                if let property = properties[entry.key] {
                    if let problem = problem(entry.value, property, at: at) { return problem }
                } else if let additional = schema["additionalProperties"], let problem = problem(entry.value, additional, at: at) {
                    return problem
                }
            }
        }
        if case .array(let values) = value {
            if case .number(let minimum)? = schema["minItems"], Double(values.count) < minimum { return "\(path): too few" }
            if case .number(let maximum)? = schema["maxItems"], Double(values.count) > maximum { return "\(path): too many" }
            if schema["uniqueItems"] == .bool(true), Set(values.map(JSONWriter.compact)).count < values.count { return "\(path): repeats" }
            if let items = schema["items"] {
                for (index, item) in values.enumerated() {
                    if let problem = problem(item, items, at: "\(path)[\(index)]") { return problem }
                }
            }
        }
        if let not = schema["not"], problem(value, not, at: path) == nil { return "\(path): matches what it mustn't" }
        if case .array(let branches)? = schema["oneOf"] {
            let fits = branches.filter { problem(value, $0, at: path) == nil }.count
            if fits != 1 {
                return fits == 0 ? branches.compactMap { problem(value, $0, at: path) }.first.map { "\(path): fits no choice (\($0))" } : "\(path): fits \(fits) choices"
            }
        }
        if case .array(let branches)? = schema["anyOf"], !branches.contains(where: { problem(value, $0, at: path) == nil }) {
            return "\(path): fits none of anyOf"
        }
        return nil
    }

    static func matches(_ value: JSONValue, _ type: String) -> Bool {
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool), ("number", .number), ("null", .null): true
        case ("integer", .number(let number)): number.rounded() == number
        default: false
        }
    }
}
