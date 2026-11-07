import Foundation

/// What a project's configuration file, `retake.json`, says: the app, how to build it, the
/// default device and set, and where output goes. Every field is optional.
public struct ProjectSettings: Equatable, Sendable {
    /// The app's bundle ID; without it, the bundle ID comes from the app `install` last built (see
    /// Documentation/cli.md, "Finding the app").
    public var bundleID: String?
    /// How `install` builds the app when it isn't given one.
    public var build: Build?
    /// The device commands use when none is named; see Documentation/cli.md, "Choosing a device".
    public var device: String?
    /// The set a scene starts on when it names none, and `compose` writes a new scene on.
    public var defaultSet: String?
    /// Where output goes, relative to the configuration file's directory; see Documentation/cli.md, "The
    /// output directory".
    public var output: String?
    /// The milliseconds a hitch, the app's main thread missing frames, must last to be warned about.
    public var hitchWarning: Double?

    public static let defaultHitchWarning = 50.0

    /// `hitchWarning`, or its default, in milliseconds.
    public var hitchWarningOrDefault: Double { hitchWarning ?? Self.defaultHitchWarning }

    /// `hitchWarning`, or its default, in seconds.
    public var hitchThreshold: Double { hitchWarningOrDefault / 1000 }

    public init(
        bundleID: String? = nil, build: Build? = nil, device: String? = nil, defaultSet: String? = nil, output: String? = nil,
        hitchWarning: Double? = nil,
    ) {
        self.bundleID = bundleID
        self.build = build
        self.device = device
        self.defaultSet = defaultSet
        self.output = output
        self.hitchWarning = hitchWarning
    }

    /// How `install` builds the app, in one of Documentation/cli.md's two forms.
    public enum Build: Equatable, Sendable {
        /// Retake builds a scheme with `xcodebuild`.
        case scheme(SchemeBuild)
        /// The project's own command builds the app, at a path it gives.
        case command(CommandBuild)
    }

    public struct SchemeBuild: Equatable, Sendable {
        public var scheme: String
        /// The workspace or project holding the scheme, needed only when the directory holds more
        /// than one; relative to the configuration file's directory.
        public var container: Container?
        /// The build configuration; `Debug` when not given.
        public var configuration: String?
        /// Whether `xcodebuild` may register the device and update profiles on the team.
        public var allowProvisioningUpdates: Bool
        /// Whether the compiler optimises, whatever the configuration says: Swift at `-O`, C and
        /// Objective-C at `-Os`, so the app runs as fast as its users see it.
        public var optimize: Bool

        public static let defaultConfiguration = "Debug"
        public static let defaultAllowProvisioningUpdates = false
        public static let defaultOptimize = true

        /// `configuration`, or its default.
        public var configurationName: String { configuration ?? Self.defaultConfiguration }

        public init(
            scheme: String, container: Container? = nil, configuration: String? = nil,
            allowProvisioningUpdates: Bool = SchemeBuild.defaultAllowProvisioningUpdates, optimize: Bool = SchemeBuild.defaultOptimize,
        ) {
            self.scheme = scheme
            self.container = container
            self.configuration = configuration
            self.allowProvisioningUpdates = allowProvisioningUpdates
            self.optimize = optimize
        }
    }

    public enum Container: Equatable, Sendable {
        case workspace(String)
        case project(String)
    }

    public struct CommandBuild: Equatable, Sendable {
        /// Run with `/bin/sh` in the configuration file's directory.
        public var command: String
        /// The `.app` the command leaves, relative to the configuration file's directory.
        public var app: String

        public init(command: String, app: String) {
            self.command = command
            self.app = app
        }
    }
}

extension ProjectSettings {
    /// The settings in a configuration file's text, or nil with problems in `reader`.
    public static func read(_ text: String, with reader: JSONReader) -> ProjectSettings? {
        guard let value = reader.parse(text), var object = reader.root(value, kind: "retake") else { return nil }
        let problemsBefore = reader.problems.count
        let settings = ProjectSettings(
            bundleID: object.optional("bundleID") { readBundleID($0, $1, reader) },
            build: object.optional("build") { readBuild($0, $1, reader) },
            device: object.optional("device", reader.nonEmptyString),
            defaultSet: object.optional("defaultSet", reader.nonEmptyString),
            output: object.optional("output", reader.nonEmptyString),
            hitchWarning: object.optional("hitchWarning") { reader.number($0, at: $1, .atLeast(0)) },
        )
        object.finish()
        return reader.problems.count == problemsBefore ? settings : nil
    }

    /// The settings as a configuration file writes them.
    public var json: JSONValue {
        var entries: [JSONObject.Entry] = []
        if let bundleID { entries.append(.init(key: "bundleID", value: .string(bundleID))) }
        if let build {
            var fields: [JSONObject.Entry] = []
            switch build {
            case .scheme(let scheme):
                fields.append(.init(key: "scheme", value: .string(scheme.scheme)))
                switch scheme.container {
                case .workspace(let path): fields.append(.init(key: "workspace", value: .string(path)))
                case .project(let path): fields.append(.init(key: "xcodeproj", value: .string(path)))
                case nil: break
                }
                if let configuration = scheme.configuration { fields.append(.init(key: "configuration", value: .string(configuration))) }
                if scheme.allowProvisioningUpdates != SchemeBuild.defaultAllowProvisioningUpdates {
                    fields.append(.init(key: "allowProvisioningUpdates", value: .bool(scheme.allowProvisioningUpdates)))
                }
                if scheme.optimize != SchemeBuild.defaultOptimize { fields.append(.init(key: "optimize", value: .bool(scheme.optimize))) }
            case .command(let command):
                fields.append(.init(key: "command", value: .string(command.command)))
                fields.append(.init(key: "app", value: .string(command.app)))
            }
            entries.append(.init(key: "build", value: .object(JSONObject(fields))))
        }
        if let device { entries.append(.init(key: "device", value: .string(device))) }
        if let defaultSet { entries.append(.init(key: "defaultSet", value: .string(defaultSet))) }
        if let output { entries.append(.init(key: "output", value: .string(output))) }
        if let hitchWarning { entries.append(.init(key: "hitchWarning", value: .number(hitchWarning))) }
        return .object(JSONObject(entries))
    }

    /// Letters, digits, `-` and `.`, as Apple's bundle IDs are.
    static func readBundleID(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> String? {
        guard let id = reader.nonEmptyString(value, at: path) else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
        guard id.allSatisfy(allowed.contains), !id.hasPrefix("."), !id.hasSuffix("."), !id.contains("..") else {
            reader.problem("\"\(id)\" isn't a bundle ID: letters, digits, \"-\" and \".\", such as com.example.notes", at: path)
            return nil
        }
        return id
    }

    static func readBuild(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Build? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let hasScheme = object.has("scheme")
        let hasCommand = object.has("command")
        object.know("workspace", "xcodeproj", "configuration", "allowProvisioningUpdates", "optimize", "app")
        switch (hasScheme, hasCommand) {
        case (true, true):
            reader.problem("give \"scheme\", for Retake to build it with xcodebuild, or \"command\", to run your own build, not both", at: path)
            return nil
        case (false, false):
            reader.problem("needs \"scheme\", for Retake to build it with xcodebuild, or \"command\", to run your own build", at: path)
            return nil
        case (true, false):
            for key in ["app"] where object.has(key) {
                reader.problem("\"\(key)\" goes with \"command\"; with \"scheme\", Retake finds the app from the build", at: path)
            }
            if object.has("workspace"), object.has("xcodeproj") {
                reader.problem("give \"workspace\" or \"xcodeproj\", not both", at: path)
            }
            let scheme = object.required("scheme", reader.nonEmptyString)
            let workspace = object.optional("workspace", reader.nonEmptyString)
            let project = object.optional("xcodeproj", reader.nonEmptyString)
            let configuration = object.optional("configuration", reader.nonEmptyString)
            let allow = object.optional("allowProvisioningUpdates", reader.bool) ?? SchemeBuild.defaultAllowProvisioningUpdates
            let optimize = object.optional("optimize", reader.bool) ?? SchemeBuild.defaultOptimize
            guard let scheme else { return nil }
            let container: Container? = workspace.map(Container.workspace) ?? project.map(Container.project)
            return .scheme(SchemeBuild(scheme: scheme, container: container, configuration: configuration, allowProvisioningUpdates: allow, optimize: optimize))
        case (false, true):
            for key in ["workspace", "xcodeproj", "configuration", "allowProvisioningUpdates", "optimize"] where object.has(key) {
                reader.problem(
                    "\"\(key)\" goes with \"scheme\"; with \"command\", your own build decides it",
                    at: path,
                )
            }
            let command = object.required("command", reader.nonEmptyString)
            let app = object.required("app", reader.nonEmptyString)
            guard let command, let app else { return nil }
            return .command(CommandBuild(command: command, app: app))
        }
    }
}
