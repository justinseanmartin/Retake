import Foundation

/// What `retake init` does: creates a project, as Documentation/cli.md, "retake init", says.
public enum ProjectInitializer {
    /// Finds an Xcode workspace's or project's schemes, behind a seam so tests needn't run Xcode.
    public protocol SchemeLister {
        func schemes(in container: ProjectSettings.Container, at directory: URL) throws -> [String]
    }

    /// `xcodebuild -list`.
    public struct XcodebuildSchemeLister: SchemeLister {
        public init() {}

        public func schemes(in container: ProjectSettings.Container, at directory: URL) throws -> [String] {
            let arguments: [String] = switch container {
            case .workspace(let path): ["xcodebuild", "-list", "-json", "-workspace", path]
            case .project(let path): ["xcodebuild", "-list", "-json", "-project", path]
            }
            let result = try Subprocess.xcrun(arguments, in: directory)
            guard result.status == 0, case .object(let top)? = try? JSONParser.parse(result.outputText),
                  case .object(let listed)? = top["workspace"] ?? top["project"],
                  case .array(let schemes)? = listed["schemes"] else {
                return []
            }
            return schemes.compactMap { if case .string(let name) = $0 { name } else { nil } }
        }
    }

    public struct Result: Equatable, Sendable {
        public var settings: ProjectSettings
        /// The configuration file created.
        public var configuration: URL
        /// What a person should know about what was or wasn't found, one line each.
        public var notes: [String]
        /// The starter files written, relative to the project's folder, in `Starter.files`' order; none
        /// when the project's folders already held files.
        public var starters: [String] = []
    }

    /// The files a fresh project starts with: a set, a scene for each device type that records the
    /// app launching and holds it, and an edit that cuts the scene's whole take for both, with a
    /// caption. Together they validate, record and cut.
    public enum Starter {
        /// The set's name, which the project names as its `defaultSet`.
        public static let setName = "base"
        public static let sceneName = "launch"
        public static let editName = "preview"

        /// Each file by its path in the project's folder, in the order they're written.
        public static let files: KeyValuePairs<String, String> = [
            "sets/\(setName).json": set,
            "scenes/iphone/\(sceneName).json": scene,
            "scenes/ipad/\(sceneName).json": scene,
            "edits/\(editName).json": edit,
        ]

        static let set = """
            {
              "state": "clean"
            }

            """

        /// 15 seconds, with its lead-in and tail, after the launch: the shortest a preview runs.
        static let scene = """
            {
              "recordsLaunch": true,
              "steps": [
                { "hold": 13, "id": "launched" }
              ]
            }

            """

        static let edit = """
            {
              "intent": "A starting point: the app launching, held. Replace it with the flows the preview shows.",
              "devices": ["iphone", "ipad"],
              "clips": [
                {
                  "intent": "The whole take, from the launch screen on.",
                  "take": "\(sceneName)",
                  "from": { "step": "start" },
                  "to": { "step": "end" },
                  "captions": [
                    { "text": "Recorded by Retake!", "y": 0.8, "color": "#1F6FEB", "from": { "step": "launched" } }
                  ]
                }
              ]
            }

            """
    }

    /// Creates `configuration`, and beside it `sets/`, `scenes/iphone/`, `scenes/ipad/` and
    /// `edits/`, with the `Starter.files` in them unless they already hold JSON files, as
    /// Documentation/cli.md, "retake init", says. `output`, when given, is written as the
    /// project's `output`. The output directory is added to the project's `.gitignore`, or one
    /// outside the project to `currentDirectory`'s when it's below it. The scheme is `scheme` when given, else the only one the current directory's Xcode
    /// project has, else `ask`'s choice among several; with none, the project has no `build`, and
    /// `install` needs `--scheme` or `--app` until one is added.
    public static func initialize(
        configuration given: URL,
        output: URL? = nil,
        currentDirectory: URL,
        bundleID: String?,
        scheme: String?,
        lister: SchemeLister = XcodebuildSchemeLister(),
        ask: ([String]) -> String? = { _ in nil },
        fileManager: FileManager = .default,
    ) throws(RetakeError) -> Result {
        let configuration = given.standardizedFileURL
        let current = currentDirectory.standardizedFileURL
        let root = configuration.deletingLastPathComponent()
        guard !fileManager.fileExists(atPath: configuration.path) else {
            throw RetakeError(.usage, "\(configuration.path) already exists.")
        }
        if let bundleID {
            let reader = JSONReader(file: "--bundle-id")
            guard ProjectSettings.readBundleID(.string(bundleID), .root, reader) != nil else {
                throw RetakeError(.usage, reader.problems.map(\.message).joined(separator: "\n"))
            }
        }

        var notes: [String] = []
        let entries = (try? fileManager.contentsOfDirectory(atPath: current.path)) ?? []
        let workspaces = entries.filter { $0.hasSuffix(".xcworkspace") }.sorted()
        let projects = entries.filter { $0.hasSuffix(".xcodeproj") }.sorted()
        // Named relative to the project, where xcodebuild runs. Beside the configuration file, it's
        // named only when xcodebuild couldn't tell on its own which to build.
        let besideConfiguration = root == current
        func named(_ name: String) -> String { relativePath(of: current.appending(path: name), from: root) }
        let container: ProjectSettings.Container?
        let listed: ProjectSettings.Container?
        switch (workspaces.count, projects.count) {
        case (1, _):
            container = projects.isEmpty && besideConfiguration ? nil : .workspace(named(workspaces[0]))
            listed = .workspace(workspaces[0])
        case (0, 1):
            container = besideConfiguration ? nil : .project(named(projects[0]))
            listed = .project(projects[0])
        case (0, 0):
            container = nil
            listed = nil
            if scheme == nil { notes.append("No Xcode project here to find a scheme in; give \"build\" in retake.json, or --scheme to install.") }
        default:
            container = nil
            listed = nil
            notes.append(
                "More than one Xcode workspace or project here (\((workspaces + projects).joined(separator: ", "))); "
                    + "add \"workspace\" or \"xcodeproj\" to retake.json's \"build\".",
            )
        }

        var chosen = scheme
        if chosen == nil, let listed {
            let schemes = (try? lister.schemes(in: listed, at: current)) ?? []
            switch schemes.count {
            case 0: notes.append("Found no schemes in \(name(of: listed)); give \"build\" in retake.json, or --scheme to install.")
            case 1: chosen = schemes[0]
            default:
                chosen = ask(schemes)
                if chosen == nil {
                    notes.append("\(name(of: listed)) has several schemes (\(schemes.joined(separator: ", "))); add the one to build as \"scheme\" in retake.json's \"build\".")
                }
            }
        }

        // Relative to the project when it's in the same tree as the current directory, so the
        // project can move with its repository; otherwise as given.
        let outputDirectory = output?.standardizedFileURL
        let outputSetting = outputDirectory.map { directory in
            isInside(directory, current) || isInside(directory, root) ? relativePath(of: directory, from: root) : directory.path
        }
        let folders = ["sets", "scenes/iphone", "scenes/ipad", "edits"]
        // Starters only for a fresh project: beside files of its own, a starter would be clutter,
        // and could name what isn't there.
        let fresh = folders.allSatisfy { folder in
            let names = (try? fileManager.contentsOfDirectory(atPath: root.appending(path: folder).path)) ?? []
            return !names.contains { $0.hasSuffix(".json") }
        }
        let settings = ProjectSettings(
            bundleID: bundleID,
            build: chosen.map { .scheme(ProjectSettings.SchemeBuild(scheme: $0, container: container)) },
            defaultSet: fresh ? Starter.setName : nil,
            output: outputSetting,
        )
        do {
            for folder in folders {
                try fileManager.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
            }
            try Data(JSONWriter.write(settings.json).utf8).write(to: configuration)
            if fresh {
                for (path, text) in Starter.files {
                    try Data(text.utf8).write(to: root.appending(path: path))
                }
            }
            let outputs = outputDirectory ?? root.appending(path: Project.defaultOutputDirectoryName, directoryHint: .isDirectory)
            if isInside(outputs, root) {
                try ignore(["/\(relativePath(of: outputs, from: root))/"], in: root, fileManager: fileManager)
            } else if isInside(outputs, current) {
                try ignore(["/\(relativePath(of: outputs, from: current))/"], in: current, fileManager: fileManager)
            }
        } catch {
            throw RetakeError(.failed, "Couldn't create the project in \(root.path): \(error.localizedDescription)")
        }
        return Result(settings: settings, configuration: configuration, notes: notes, starters: fresh ? Starter.files.map(\.key) : [])
    }

    /// The configuration file `init` creates when none is named: `Retake/retake.json`. Misuse (2)
    /// when commands in `currentDirectory` would already find a project, so `init` run inside one
    /// doesn't make another within it.
    public static func defaultConfiguration(in currentDirectory: URL, fileManager: FileManager = .default) throws(RetakeError) -> URL {
        let current = currentDirectory.standardizedFileURL
        if let existing = Project.unnamedConfiguration(in: current, fileManager: fileManager) {
            throw RetakeError(
                .usage,
                "Commands here already find the project in \(relativePath(of: existing, from: current)); "
                    + "name another configuration file with --config to create one beside it.",
            )
        }
        return current.appending(path: "\(Project.defaultFolderName)/\(Project.configurationFileName)")
    }

    private static func name(of container: ProjectSettings.Container) -> String {
        switch container {
        case .workspace(let path), .project(let path): path
        }
    }

    /// Whether `url` is `directory` or inside it.
    static func isInside(_ url: URL, _ directory: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let folder = directory.standardizedFileURL.path
        return path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }

    /// `url`'s path from `directory`, with `..` for each folder up: `../MyApp.xcodeproj`.
    public static func relativePath(of url: URL, from directory: URL) -> String {
        let target = url.standardizedFileURL.pathComponents.filter { $0 != "/" }
        let base = directory.standardizedFileURL.pathComponents.filter { $0 != "/" }
        let shared = zip(target, base).prefix { $0 == $1 }.count
        let path = Array(repeating: "..", count: base.count - shared) + target.dropFirst(shared)
        return path.isEmpty ? "." : path.joined(separator: "/")
    }

    /// Adds each of `entries` to `directory`'s `.gitignore`, creating it if need be, unless an entry
    /// is there already, with or without its leading or trailing `/`.
    static func ignore(_ entries: [String], in directory: URL, fileManager: FileManager) throws {
        let file = directory.appending(path: ".gitignore")
        var text = fileManager.contents(atPath: file.path).map { String(decoding: $0, as: UTF8.self) } ?? ""
        func bare(_ line: some StringProtocol) -> String {
            line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        let present = Set(text.split(whereSeparator: \.isNewline).map(bare))
        let missing = entries.filter { !present.contains(bare($0)) }
        guard !missing.isEmpty else { return }
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        text += missing.map { $0 + "\n" }.joined()
        try Data(text.utf8).write(to: file)
    }
}
