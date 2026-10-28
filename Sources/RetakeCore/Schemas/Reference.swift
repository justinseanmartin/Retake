/// The reference: a Markdown page for each kind of file, generated from its schema, listing every
/// field with its type, default and description. Checked in at `Documentation/reference/<kind>.md`.
public enum Reference {
    /// The page for a kind of file.
    public static func page(_ file: FileSchema) -> String {
        let devices = Set(DeviceType.allCases.map(\.rawValue))
        var sections: [(title: String, anchor: String, schema: Schema)] = []
        var lines = [
            "<!-- Generated from Retake's schemas: RETAKE_REGENERATE=1 swift test --filter Reference. Don't edit. -->",
            "",
            "# \(file.title)",
            "",
        ]
        if let description = file.root.description { lines += [description, ""] }
        lines += [
            "Its schema is published at <\(SchemaReference.current(file.kind).url)>, and `retake schema \(file.kind)` prints it.",
            "",
        ]
        let overrides = file.definitions.contains { $0.name.hasSuffix("-override") }
        if overrides {
            lines += [
                "Every object in an edit, at the top and in each of the definitions below, can be given again under `iphone` or",
                "`ipad`, with any of its fields, and applies only to that device type's video. An object in an override is laid over",
                "the one it overrides key by key; a list, or a single value, replaces it. At the top, an override can't give",
                "`devices` or `takes`.",
                "",
            ]
        }

        /// The fields of an object, and its nested objects queued as sections of their own.
        func table(_ schema: Schema, path: String) -> [String] {
            var rows = ["| Field | Type | Default | Description |", "| --- | --- | --- | --- |"]
            for property in schema.properties where !(overrides && devices.contains(property.name) && property.schema.description?.hasPrefix("Overrides for") == true) {
                let fieldPath = path.isEmpty ? property.name : "\(path).\(property.name)"
                let type = typeText(property.schema, path: fieldPath, queue: &sections)
                let fallback = schema.required.contains(property.name) ? "required" : property.schema.defaultValue.map { "`\(JSONWriter.compact($0))`" } ?? ""
                rows.append("| `\(property.name)` | \(type) | \(fallback) | \(cell(property.schema.description ?? "")) |")
            }
            if let rule = rule(schema) { rows += ["", rule] }
            return rows
        }

        lines += ["## Fields", ""] + table(file.root, path: "")
        var index = 0
        while index < sections.count {
            let section = sections[index]
            lines += ["", "### \(section.title)", ""]
            if let description = section.schema.description { lines += [description, ""] }
            lines += table(section.schema, path: section.anchor)
            index += 1
        }

        let definitions = file.definitions.filter { !$0.name.hasSuffix("-override") }
        if !definitions.isEmpty {
            lines += ["", "## Definitions"]
            for definition in definitions {
                lines += ["", "### \(definition.name)", ""]
                if let description = definition.schema.description { lines += [description, ""] }
                let schema = definition.schema
                if schema.type == ["object"], !schema.properties.isEmpty {
                    let before = sections.count
                    lines += table(schema, path: definition.name)
                    // Objects nested in a definition follow it.
                    var nested = before
                    while nested < sections.count {
                        let section = sections[nested]
                        lines += ["", "#### \(section.title)", ""]
                        if let description = section.schema.description { lines += [description, ""] }
                        lines += table(section.schema, path: section.anchor)
                        nested += 1
                    }
                } else {
                    var queue: [(title: String, anchor: String, schema: Schema)] = []
                    lines.append("Type: \(typeText(schema, path: definition.name, queue: &queue)).")
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// What a `oneOf` or `anyOf` of required keys says about which keys go together.
    static func rule(_ schema: Schema) -> String? {
        func list(_ names: [String], _ last: String) -> String {
            let quoted = names.map { "`\($0)`" }
            return quoted.count == 1 ? quoted[0] : quoted.dropLast().joined(separator: ", ") + " \(last) " + quoted.last!
        }
        func plain(_ branch: Schema) -> Bool { branch.type.isEmpty && branch.ref == nil && branch.required.count == 1 }
        if !schema.oneOf.isEmpty, schema.oneOf.allSatisfy(plain) {
            let names = schema.oneOf.filter { $0.not.isEmpty }.map { $0.required[0] }
            let alone = schema.oneOf.first { !$0.not.isEmpty }?.required[0]
            return "Gives exactly one of \(list(names, "or"))" + (alone.map { ", or only `\($0)`." } ?? ".")
        }
        if !schema.anyOf.isEmpty, schema.anyOf.allSatisfy(plain) {
            return "Gives at least one of \(list(schema.anyOf.map { $0.required[0] }, "and"))."
        }
        return nil
    }

    /// A field's type, as the reference writes it; an inline object is queued as a section of its own.
    static func typeText(
        _ schema: Schema, path: String, label: String? = nil, queue: inout [(title: String, anchor: String, schema: Schema)],
    ) -> String {
        if let ref = schema.ref { return "[\(ref)](#\(ref))" }
        if !schema.oneOf.isEmpty, schema.type.isEmpty {
            let branches = schema.oneOf.map { branch in
                typeText(branch, path: path, label: branch.type == ["object"] ? branch.required.first.map { "with `\($0)`" } : nil, queue: &queue)
            }
            return branches.joined(separator: ", or ")
        }
        switch schema.type.first {
        case "string" where !schema.choices.isEmpty:
            let names = schema.choices.map { "`\(JSONWriter.compact($0))`" }
            return names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " or " + names.last!
        case "string":
            if let pattern = schema.pattern { return "string matching `\(pattern.replacingOccurrences(of: "|", with: "\\|"))`" }
            return schema.minLength == 1 ? "string, not empty" : "string"
        case "number", "integer":
            var text = schema.type[0]
            if let minimum = schema.minimum, let maximum = schema.maximum {
                text += " from \(JSONReader.format(minimum)) to \(JSONReader.format(maximum))"
            } else if let minimum = schema.minimum {
                text += " ≥ \(JSONReader.format(minimum))"
            } else if let minimum = schema.exclusiveMinimum {
                text += " > \(JSONReader.format(minimum))"
            }
            if !schema.not.isEmpty, schema.not[0].choices == [0] { text += ", not 0" }
            return text
        case "boolean":
            return "boolean"
        case "array":
            var text = "list of " + (schema.items.first.map { typeText($0, path: path, queue: &queue) } ?? "anything")
            if let minimum = schema.minItems { text += ", at least \(minimum)" }
            if schema.uniqueItems { text += ", each once" }
            return text
        case "object" where !schema.values.isEmpty:
            return "object of names to " + typeText(schema.values[0], path: "\(path).*", queue: &queue)
        case "object":
            let title = "`\(path)`" + (label.map { ", \($0)" } ?? "")
            queue.append((title: title, anchor: path, schema: schema))
            return "[object](#\(slug(title)))"
        default:
            return schema.type.count > 1 ? "any value but `null`" : "anything"
        }
    }

    /// GitHub's anchor for a heading.
    static func slug(_ title: String) -> String {
        String(title.lowercased().compactMap { character -> Character? in
            if character.isLetter || character.isNumber || character == "-" || character == "_" { return character }
            if character == " " { return "-" }
            return nil
        })
    }

    static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}
