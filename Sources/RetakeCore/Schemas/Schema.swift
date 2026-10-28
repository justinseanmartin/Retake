/// A JSON Schema (draft 2020-12), as Retake's file types describe themselves, for `retake schema`
/// and the reference. See Documentation/cli.md, "Schemas".
///
/// Only the keywords Retake's files need. An object is closed (`additionalProperties: false`) unless
/// it's a dictionary, whose keys are names and whose values share a schema.
public struct Schema: Sendable {
    public var description: String?
    var type: [String] = []
    var properties: [Property] = []
    var required: [String] = []
    /// A dictionary's values; an object without them is closed.
    var values: [Schema] = []
    var keys: [Schema] = []
    var items: [Schema] = []
    var minItems: Int?
    var uniqueItems = false
    var choices: [JSONValue] = []
    var pattern: String?
    var minLength: Int?
    var minimum: Double?
    var exclusiveMinimum: Double?
    var maximum: Double?
    var not: [Schema] = []
    var oneOf: [Schema] = []
    var anyOf: [Schema] = []
    /// The name of a definition in `$defs`.
    var ref: String?
    var defaultValue: JSONValue?
    var examples: [JSONValue] = []

    public struct Property: Sendable {
        public var name: String
        public var schema: Schema

        public init(_ name: String, _ schema: Schema) {
            self.name = name
            self.schema = schema
        }
    }

    public init(description: String? = nil) {
        self.description = description
    }
}

// MARK: - Building

extension Schema {
    static func object(_ description: String? = nil, _ properties: [Property], required: [String] = []) -> Schema {
        var schema = Schema(description: description)
        schema.type = ["object"]
        schema.properties = properties
        schema.required = required
        return schema
    }

    /// An object whose keys are names, and whose values all have the same schema.
    static func dictionary(_ description: String? = nil, keys: Schema? = nil, values: Schema) -> Schema {
        var schema = Schema(description: description)
        schema.type = ["object"]
        schema.values = [values]
        schema.keys = keys.map { [$0] } ?? []
        return schema
    }

    static func array(_ description: String? = nil, of items: Schema, minItems: Int? = nil, unique: Bool = false) -> Schema {
        var schema = Schema(description: description)
        schema.type = ["array"]
        schema.items = [items]
        schema.minItems = minItems
        schema.uniqueItems = unique
        return schema
    }

    static func string(_ description: String? = nil, pattern: String? = nil, nonEmpty: Bool = false) -> Schema {
        var schema = Schema(description: description)
        schema.type = ["string"]
        schema.pattern = pattern
        schema.minLength = nonEmpty ? 1 : nil
        return schema
    }

    static func choice(_ description: String? = nil, _ values: [String]) -> Schema {
        var schema = Schema(description: description)
        schema.type = ["string"]
        schema.choices = values.map(JSONValue.string)
        return schema
    }

    static func number(_ description: String? = nil, atLeast: Double? = nil, above: Double? = nil, atMost: Double? = nil) -> Schema {
        var schema = Schema(description: description)
        schema.type = ["number"]
        schema.minimum = atLeast
        schema.exclusiveMinimum = above
        schema.maximum = atMost
        return schema
    }

    static func integer(_ description: String? = nil, atLeast: Double? = nil) -> Schema {
        var schema = Schema(description: description)
        schema.type = ["integer"]
        schema.minimum = atLeast
        return schema
    }

    static func bool(_ description: String? = nil) -> Schema {
        var schema = Schema(description: description)
        schema.type = ["boolean"]
        return schema
    }

    /// Any JSON value but `null`.
    static func anyValue(_ description: String? = nil) -> Schema {
        var schema = Schema(description: description)
        schema.type = ["string", "number", "boolean", "array", "object"]
        return schema
    }

    static func ref(_ name: String, _ description: String? = nil) -> Schema {
        var schema = Schema(description: description)
        schema.ref = name
        return schema
    }

    static func oneOf(_ description: String? = nil, _ schemas: [Schema]) -> Schema {
        var schema = Schema(description: description)
        schema.oneOf = schemas
        return schema
    }

    /// Requires exactly one of `keys`, as `oneOf` of each key required.
    func exactlyOne(of keys: [String]) -> Schema {
        var schema = self
        schema.oneOf = keys.map { key in var branch = Schema(); branch.required = [key]; return branch }
        return schema
    }

    /// Requires at least one of `keys`, as `anyOf` of each key required.
    func atLeastOne(of keys: [String]) -> Schema {
        var schema = self
        schema.anyOf = keys.map { key in var branch = Schema(); branch.required = [key]; return branch }
        return schema
    }

    func defaulting(to value: JSONValue) -> Schema {
        var schema = self
        schema.defaultValue = value
        return schema
    }

    func example(_ values: JSONValue...) -> Schema {
        var schema = self
        schema.examples += values
        return schema
    }

    func described(_ description: String) -> Schema {
        var schema = self
        schema.description = description
        return schema
    }
}

// MARK: - Per-device overrides

extension Schema {
    /// The override for each device type `keys` names: this object's partial copy, which is laid over
    /// it key by key, less the keys in `excluding`, which an override can't give.
    func overridden(by keys: [String], excluding: [String] = [], as partial: Schema? = nil) -> Schema {
        var schema = self
        var override = partial ?? self.partial
        override.properties.removeAll { excluding.contains($0.name) }
        schema.properties += keys.map { Property($0, override.described("Overrides for \($0)'s video, laid over the rest key by key.")) }
        return schema
    }

    /// Every key optional, all the way down, and a definition's partial copy in place of it. A list
    /// in an override replaces the list, so its items are whole.
    var partial: Schema {
        var schema = self
        schema.required = []
        schema.properties = properties.map { Property($0.name, $0.schema.partial) }
        schema.items = items
        schema.defaultValue = nil
        if type == ["object"], values.isEmpty {
            // Which keys go together is checked once the override is laid over the rest.
            schema.oneOf = oneOf.filter { $0.ref != nil || !$0.type.isEmpty }.map(\.partial)
            schema.anyOf = anyOf.filter { $0.ref != nil || !$0.type.isEmpty }.map(\.partial)
        } else {
            schema.oneOf = oneOf.map(\.partial)
            schema.anyOf = anyOf.map(\.partial)
        }
        schema.ref = ref.map { "\($0)-override" }
        return schema
    }
}

// MARK: - Writing

extension Schema {
    /// The schema as JSON, an object's keys in the order JSON Schema's own documents use.
    public var json: JSONValue {
        var entries: [JSONObject.Entry] = []
        func add(_ key: String, _ value: JSONValue?) {
            if let value { entries.append(.init(key: key, value: value)) }
        }
        add("$ref", ref.map { .string("#/$defs/\($0)") })
        add("description", description.map(JSONValue.string))
        if type.count == 1 { add("type", .string(type[0])) } else if !type.isEmpty { add("type", .array(type.map(JSONValue.string))) }
        if !choices.isEmpty { add("enum", .array(choices)) }
        add("pattern", pattern.map(JSONValue.string))
        add("minLength", minLength.map { .number(Double($0)) })
        add("minimum", minimum.map(JSONValue.number))
        add("exclusiveMinimum", exclusiveMinimum.map(JSONValue.number))
        add("maximum", maximum.map(JSONValue.number))
        if !properties.isEmpty {
            add("properties", .object(JSONObject(properties.map { .init(key: $0.name, value: $0.schema.json) })))
        }
        if !required.isEmpty { add("required", .array(required.map(JSONValue.string))) }
        if type == ["object"] {
            add("propertyNames", keys.first?.json)
            add("additionalProperties", values.first?.json ?? .bool(false))
        }
        add("items", items.first?.json)
        add("minItems", minItems.map { .number(Double($0)) })
        if uniqueItems { add("uniqueItems", .bool(true)) }
        if !not.isEmpty { add("not", not[0].json) }
        if !oneOf.isEmpty { add("oneOf", .array(oneOf.map(\.json))) }
        if !anyOf.isEmpty { add("anyOf", .array(anyOf.map(\.json))) }
        add("default", defaultValue)
        if !examples.isEmpty { add("examples", .array(examples)) }
        return .object(JSONObject(entries))
    }
}

/// The schema of one kind of file: its top-level object, and the definitions it refers to.
public struct FileSchema: Sendable {
    public var kind: String
    public var title: String
    public var root: Schema
    public var definitions: [Schema.Property]

    /// The kinds of file, in the order `retake schema` lists them.
    public static let kinds = ["retake", "set", "scene", "edit"]

    public static func named(_ kind: String) -> FileSchema? {
        switch kind {
        case "retake": ProjectSettings.schema
        case "set": SetFile.schema
        case "scene": SceneFile.schema
        case "edit": EditFile.schema
        default: nil
        }
    }

    /// The whole document, as published at its `$id`.
    public var json: JSONValue {
        guard case .object(let root) = root.json else { return root.json }
        var entries: [JSONObject.Entry] = [
            .init(key: "$schema", value: .string("https://json-schema.org/draft/2020-12/schema")),
            .init(key: "$id", value: .string(SchemaReference.current(kind).url)),
            .init(key: "title", value: .string(title)),
        ]
        entries += root.entries
        if !definitions.isEmpty {
            entries.append(.init(key: "$defs", value: .object(JSONObject(definitions.map { .init(key: $0.name, value: $0.schema.json) }))))
        }
        return .object(JSONObject(entries))
    }

    /// The file's text, as `retake schema` prints it and the reference checks it in.
    public var text: String { JSONWriter.write(json) }

    /// The `"$schema"` key every file may give.
    static var schemaKey: Schema.Property {
        Schema.Property("$schema", .string(
            "The URL of the schema the file is written against, for editors. Optional; a file is read against this Retake's schema whatever it names.",
        ))
    }
}
