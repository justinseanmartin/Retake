import Foundation

/// A set, as its file in `sets/` says it: the state a take starts from. See README.md, "Sets: the
/// state a take starts from".
public struct SetFile: Equatable, Sendable {
    /// What the app's data starts as for a take, and whether the take's changes are kept.
    public enum State: String, CaseIterable, Sendable {
        case clean, cloned, live
    }

    /// A file or folder put in the app's data before launch.
    public struct FileCopy: Equatable, Sendable {
        /// Where it goes in the app's data, such as `Documents/notes.json`; a folder ends in `/`.
        public var destination: String
        /// The file or folder in the project it's copied from, relative to the project's directory.
        public var source: String

        public init(destination: String, source: String) {
            self.destination = destination
            self.source = source
        }

        public var isFolder: Bool { destination.hasSuffix("/") }
    }

    /// A preview's shape, as its width over its height: `3:4`.
    public struct Aspect: Equatable, Sendable, CustomStringConvertible {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }

        /// The same shape turned a quarter: 4:3 for 3:4.
        public var turned: Aspect { Aspect(width: height, height: width) }

        public var description: String { "\(JSONReader.format(width)):\(JSONReader.format(height))" }
    }

    /// The shape for each orientation; landscape is portrait's turned unless it's given.
    public struct AspectChoice: Equatable, Sendable {
        public var portrait: Aspect?
        public var landscape: Aspect?

        public init(portrait: Aspect? = nil, landscape: Aspect? = nil) {
            self.portrait = portrait
            self.landscape = landscape
        }

        public var landscapeShape: Aspect? { landscape ?? portrait?.turned }
    }

    public var extends: String?
    public var state: State?
    public var files: [FileCopy]
    public var defaults: [Named<JSONValue>]
    public var environment: [Named<String>]
    public var arguments: [String]
    public var aspect: [DeviceType: AspectChoice]

    public init(
        extends: String? = nil,
        state: State? = nil,
        files: [FileCopy] = [],
        defaults: [Named<JSONValue>] = [],
        environment: [Named<String>] = [],
        arguments: [String] = [],
        aspect: [DeviceType: AspectChoice] = [:],
    ) {
        self.extends = extends
        self.state = state
        self.files = files
        self.defaults = defaults
        self.environment = environment
        self.arguments = arguments
        self.aspect = aspect
    }

    /// The environment variables Retake sets itself to launch the app, which a set can't.
    public static let reservedEnvironmentPrefixes = ["DYLD_", "INSIDEJOB_", "RETAKE_"]
}

extension SetFile {
    /// The set in a file's text, or nil with problems in `reader`.
    public static func read(_ text: String, with reader: JSONReader) -> SetFile? {
        guard let value = reader.parse(text), var object = reader.root(value, kind: "set") else { return nil }
        let problemsBefore = reader.problems.count
        let set = SetFile(
            extends: object.optional("extends", reader.nonEmptyString),
            state: object.optional("state") { reader.choice($0, at: $1, as: State.self) },
            files: object.optional("files") { readFiles($0, $1, reader) } ?? [],
            defaults: object.optional("defaults") { readDefaults($0, $1, reader) } ?? [],
            environment: object.optional("environment") { readEnvironment($0, $1, reader) } ?? [],
            arguments: object.optional("arguments") { reader.array($0, at: $1, element: reader.string) } ?? [],
            aspect: object.optional("aspect") { readAspects($0, $1, reader) } ?? [:],
        )
        object.finish()
        return reader.problems.count == problemsBefore ? set : nil
    }

    static func readFiles(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> [FileCopy]? {
        reader.dictionary(value, at: path) { value, path in
            guard case .key(let destination)? = path.components.last, let source = reader.nonEmptyString(value, at: path) else { return nil }
            let components = destination.split(separator: "/", omittingEmptySubsequences: false)
            if destination.isEmpty || destination.hasPrefix("/") || components.contains("..") || components.dropLast().contains("") {
                reader.problem("isn't a path inside the app's data, such as Documents/notes.json", at: path)
                return nil
            }
            if source.hasPrefix("/") {
                reader.problem("\"\(source)\" isn't a relative path", at: path)
                return nil
            }
            if destination.hasSuffix("/") != source.hasSuffix("/") {
                reader.problem(
                    destination.hasSuffix("/")
                        ? "is a folder, ending in \"/\", so \"\(source)\" must be one too"
                        : "is a file, so \"\(source)\" can't be a folder ending in \"/\"",
                    at: path,
                )
                return nil
            }
            return source
        }?.map { FileCopy(destination: $0.key, source: $0.value) }
    }

    static func readDefaults(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> [Named<JSONValue>]? {
        reader.dictionary(value, at: path) { value, path in
            guard !contains(null: value) else {
                reader.problem("can't hold null, which UserDefaults can't store; leave the key out instead", at: path)
                return nil
            }
            return value
        }?.map { Named($0.key, $0.value) }
    }

    private static func contains(null value: JSONValue) -> Bool {
        switch value {
        case .null: true
        case .array(let values): values.contains(where: contains(null:))
        case .object(let object): object.entries.contains { contains(null: $0.value) }
        default: false
        }
    }

    static func readEnvironment(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> [Named<String>]? {
        reader.dictionary(value, at: path) { value, path in
            guard case .key(let name)? = path.components.last else { return nil }
            let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_")
            guard let first = name.first, !first.isNumber, name.allSatisfy(allowed.contains) else {
                reader.problem("isn't an environment variable's name: letters, digits and \"_\", not starting with a digit", at: path)
                return nil
            }
            if let prefix = reservedEnvironmentPrefixes.first(where: { name.hasPrefix($0) }) {
                reader.problem("is Retake's to set: it launches the app with its own \(prefix) variables", at: path)
                return nil
            }
            return reader.string(value, at: path)
        }?.map { Named($0.key, $0.value) }
    }

    static func readAspects(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> [DeviceType: AspectChoice]? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        var aspects: [DeviceType: AspectChoice] = [:]
        for type in DeviceType.allCases {
            aspects[type] = object.optional(type.rawValue) { readAspectChoice($0, $1, reader) }
        }
        return aspects
    }

    static func readAspectChoice(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> AspectChoice? {
        if case .string = value {
            return readAspect(value, path, reader).map { AspectChoice(portrait: $0) }
        }
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let choice = AspectChoice(
            portrait: object.optional("portrait") { readAspect($0, $1, reader) },
            landscape: object.optional("landscape") { readAspect($0, $1, reader) },
        )
        if choice.portrait == nil, choice.landscape == nil, !object.has("portrait"), !object.has("landscape") {
            reader.problem("needs \"portrait\", \"landscape\", or both", at: path)
            return nil
        }
        return choice
    }

    /// `"3:4"`: a width and a height, each more than 0.
    static func readAspect(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Aspect? {
        guard let text = reader.string(value, at: path) else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]), width > 0, height > 0,
              width.isFinite, height.isFinite else {
            reader.problem("\"\(text)\" isn't a shape: a width and a height, such as 3:4", at: path)
            return nil
        }
        return Aspect(width: width, height: height)
    }
}
