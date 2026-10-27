import Foundation

/// A Retake project: a configuration file, `retake.json` by default, what it says, and the folders
/// beside it.
public struct Project: Sendable, Equatable {
    public static let configurationFileName = "retake.json"
    /// Where takes, videos and builds go unless the command or the configuration file says otherwise.
    public static let defaultOutputDirectoryName = "RetakeOutput"

    /// The project's configuration file. Everything else in the project, and every relative path
    /// the file gives, is found relative to the directory holding it.
    public var configuration: URL
    /// What the configuration file says.
    public var settings: ProjectSettings
    /// What reading the configuration file warned about, for the command to print.
    public var warnings: [FileProblem]

    /// Where Retake writes takes, videos and builds: what the command names, else the configuration
    /// file's `output`, else `RetakeOutput/` beside it. It holds the takes edits pin, so one that's
    /// thrown away takes them with it.
    public var output: URL

    public init(configuration: URL, settings: ProjectSettings = ProjectSettings(), output: URL? = nil, warnings: [FileProblem] = []) {
        self.configuration = configuration.standardizedFileURL
        self.settings = settings
        self.warnings = warnings
        let root = self.configuration.deletingLastPathComponent()
        let configured = settings.output.map { URL(filePath: $0, directoryHint: .isDirectory, relativeTo: root) }
        self.output = (output ?? configured ?? root.appending(path: Project.defaultOutputDirectoryName, directoryHint: .isDirectory))
            .standardizedFileURL
    }

    /// The directory holding the configuration file.
    public var root: URL { configuration.deletingLastPathComponent() }

    public var sets: URL { root.appending(path: "sets", directoryHint: .isDirectory) }
    public var edits: URL { root.appending(path: "edits", directoryHint: .isDirectory) }

    public func scenes(for type: DeviceType) -> URL {
        root.appending(path: "scenes/\(type.rawValue)", directoryHint: .isDirectory)
    }

    public func takes(for type: DeviceType) -> URL {
        output.appending(path: "takes/\(type.rawValue)", directoryHint: .isDirectory)
    }

    public func videos(for type: DeviceType) -> URL {
        output.appending(path: "videos/\(type.rawValue)", directoryHint: .isDirectory)
    }

    /// A path in the project as messages name it: relative to its directory, `edits/video1.json`.
    public func displayPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    /// The project a command runs in: the configuration file `configuration` names (`--config`),
    /// otherwise `retake.json` in the current directory, read strictly. No other directory is
    /// searched, so a command never acts on a project it wasn't pointed at. `output`
    /// (`--output-dir`) moves where it writes; it needn't exist yet. A file that can't be found
    /// is misuse (2); one that can't be read, or says something it shouldn't, fails (1), naming
    /// each problem.
    public static func locate(
        configuration: URL?,
        output: URL? = nil,
        currentDirectory: URL,
        fileManager: FileManager = .default,
    ) throws(RetakeError) -> Project {
        let file = (configuration ?? currentDirectory.appending(path: configurationFileName)).standardizedFileURL
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory)
        if configuration != nil {
            guard exists else {
                throw RetakeError(.usage, "No configuration file at \(file.path).")
            }
            guard !isDirectory.boolValue else {
                throw RetakeError(
                    .usage,
                    "\(file.path) is a directory; --config names the configuration file, "
                        + "such as \(file.appending(path: configurationFileName).path).",
                )
            }
        } else if !exists || isDirectory.boolValue {
            throw RetakeError(
                .usage,
                "No \(configurationFileName) in the current directory, \(file.deletingLastPathComponent().path). Run where it is, "
                    + "name it with --config, or create one with `retake init`.",
            )
        }

        let reader = JSONReader(file: file.lastPathComponent)
        guard let data = fileManager.contents(atPath: file.path), let text = String(data: data, encoding: .utf8) else {
            throw RetakeError(.failed, "\(file.lastPathComponent): can't be read as UTF-8 text.")
        }
        guard let settings = ProjectSettings.read(text, with: reader), reader.problems.isEmpty else {
            throw RetakeError(.failed, reader.problems.map(\.description).joined(separator: "\n"))
        }
        return Project(configuration: file, settings: settings, output: output, warnings: reader.warnings)
    }
}
