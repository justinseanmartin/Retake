import Foundation

/// What `retake init` does: creates a project in a directory, as docs/cli.md, "retake init", says.
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
        /// What a person should know about what was or wasn't found, one line each.
        public var notes: [String]
    }

    /// Creates `retake.json`, `sets/`, `scenes/iphone/`, `scenes/ipad/` and `edits/` in `directory`,
    /// and adds `RetakeOutput/` to its `.gitignore`. The scheme is `scheme` when given, else the
    /// only one the directory's Xcode project has, else `ask`'s choice among several; with none, the
    /// project has no `build`, and `install` needs `--scheme` or `--app` until one is added.
    public static func initialize(
        in directory: URL,
        bundleID: String?,
        scheme: String?,
        lister: SchemeLister = XcodebuildSchemeLister(),
        ask: ([String]) -> String? = { _ in nil },
        fileManager: FileManager = .default,
    ) throws(RetakeError) -> Result {
        let configuration = directory.appending(path: Project.configurationFileName)
        guard !fileManager.fileExists(atPath: configuration.path) else {
            throw RetakeError(.usage, "\(Project.configurationFileName) already exists in \(directory.path).")
        }
        if let bundleID {
            let reader = JSONReader(file: "--bundle-id")
            guard ProjectSettings.readBundleID(.string(bundleID), .root, reader) != nil else {
                throw RetakeError(.usage, reader.problems.map(\.message).joined(separator: "\n"))
            }
        }

        var notes: [String] = []
        let entries = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        let workspaces = entries.filter { $0.hasSuffix(".xcworkspace") }.sorted()
        let projects = entries.filter { $0.hasSuffix(".xcodeproj") }.sorted()
        // The container is named only when xcodebuild couldn't tell on its own which to build.
        let container: ProjectSettings.Container?
        let listed: ProjectSettings.Container?
        switch (workspaces.count, projects.count) {
        case (1, _):
            container = projects.isEmpty ? nil : .workspace(workspaces[0])
            listed = .workspace(workspaces[0])
        case (0, 1):
            container = nil
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
            let schemes = (try? lister.schemes(in: listed, at: directory)) ?? []
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

        let settings = ProjectSettings(
            bundleID: bundleID,
            build: chosen.map { .scheme(ProjectSettings.SchemeBuild(scheme: $0, container: container)) },
        )
        do {
            for folder in ["sets", "scenes/iphone", "scenes/ipad", "edits"] {
                try fileManager.createDirectory(at: directory.appending(path: folder), withIntermediateDirectories: true)
            }
            try Data(JSONWriter.write(settings.json).utf8).write(to: configuration)
            try ignoreOutput(in: directory, fileManager: fileManager)
        } catch {
            throw RetakeError(.failed, "Couldn't create the project in \(directory.path): \(error.localizedDescription)")
        }
        return Result(settings: settings, notes: notes)
    }

    private static func name(of container: ProjectSettings.Container) -> String {
        switch container {
        case .workspace(let path), .project(let path): path
        }
    }

    /// Adds `RetakeOutput/` to `.gitignore`, creating it if need be, unless it's there already.
    static func ignoreOutput(in directory: URL, fileManager: FileManager) throws {
        let file = directory.appending(path: ".gitignore")
        let entry = "\(Project.defaultOutputDirectoryName)/"
        var text = fileManager.contents(atPath: file.path).map { String(decoding: $0, as: UTF8.self) } ?? ""
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard !lines.contains(where: { [entry, "/" + entry, Project.defaultOutputDirectoryName, "/" + Project.defaultOutputDirectoryName].contains($0) }) else {
            return
        }
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        text += entry + "\n"
        try Data(text.utf8).write(to: file)
    }
}
