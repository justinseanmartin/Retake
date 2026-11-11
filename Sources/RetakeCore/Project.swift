import Foundation

/// A Retake project: a configuration file, `retake.json` by default, what it says, and the folders
/// beside it, in `Retake/` unless `init` was told otherwise.
public struct Project: Sendable, Equatable {
    public static let configurationFileName = "retake.json"
    /// The folder `init` makes a project in, and commands look in, in the current directory.
    public static let defaultFolderName = "Retake"
    /// Where takes and cuts go unless the command or the configuration file says otherwise.
    public static let defaultOutputDirectoryName = "output"

    /// The project's configuration file. Everything else in the project, and every relative path
    /// the file gives, is found relative to the directory holding it.
    public var configuration: URL
    /// What the configuration file says.
    public var settings: ProjectSettings
    /// What reading the configuration file warned about, for the command to print.
    public var warnings: [FileProblem]

    /// Where Retake writes takes and cuts: what the command names, else the configuration file's
    /// `output`, else `output/` beside it. It holds the takes edits are cut from, so one that's
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

    /// `scenes/`, each scene naming the device types it plays on, every one unless it says.
    public var scenes: URL { root.appending(path: "scenes", directoryHint: .isDirectory) }

    /// Where an earlier Retake kept one device type's scenes, which nothing reads now.
    public func oldScenes(for type: DeviceType) -> URL {
        root.appending(path: "scenes/\(type.rawValue)", directoryHint: .isDirectory)
    }

    public func takes(for type: DeviceType) -> URL {
        output.appending(path: "takes/\(type.rawValue)", directoryHint: .isDirectory)
    }

    /// Where `record` keeps the stills scenes capture, a folder for each scene.
    public func captures(for type: DeviceType) -> URL {
        output.appending(path: "captures/\(type.rawValue)", directoryHint: .isDirectory)
    }

    public func cuts(for type: DeviceType) -> URL {
        output.appending(path: "cuts/\(type.rawValue)", directoryHint: .isDirectory)
    }

    /// Where `share` writes its videos.
    public var shares: URL { output.appending(path: "share", directoryHint: .isDirectory) }

    /// The configuration file a command finds unnamed: `retake.json` in the current directory, else
    /// `Retake/retake.json`, whichever exists first; nil when neither does.
    public static func unnamedConfiguration(in currentDirectory: URL, fileManager: FileManager = .default) -> URL? {
        let candidates = [
            currentDirectory.appending(path: configurationFileName),
            currentDirectory.appending(path: "\(defaultFolderName)/\(configurationFileName)"),
        ]
        return candidates.first { candidate in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }?.standardizedFileURL
    }

    /// A path in the project as messages name it: relative to its directory, `edits/video1.json`.
    public func displayPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    /// The project a command runs in: the configuration file `configuration` names (`--config`, else
    /// `RETAKE_CONFIG`), otherwise `retake.json` or `Retake/retake.json` in the current directory,
    /// read strictly. No other directory is searched, so a command never acts on a project it wasn't
    /// pointed at.
    /// `output` (`--output-dir`) moves where it writes; it needn't exist yet. A file that can't be found
    /// is misuse (2); one that can't be read, or says something it shouldn't, fails (1), naming
    /// each problem.
    public static func locate(
        configuration: URL?,
        output: URL? = nil,
        currentDirectory: URL,
        fileManager: FileManager = .default,
    ) throws(RetakeError) -> Project {
        let file: URL
        if let configuration {
            file = configuration.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory) else {
                throw RetakeError(.usage, "No configuration file at \(file.path).")
            }
            guard !isDirectory.boolValue else {
                throw RetakeError(
                    .usage,
                    "\(file.path) is a directory; --config names the configuration file, "
                        + "such as \(file.appending(path: configurationFileName).path).",
                )
            }
        } else if let found = unnamedConfiguration(in: currentDirectory, fileManager: fileManager) {
            file = found
        } else {
            throw RetakeError(
                .usage,
                "No \(configurationFileName) or \(defaultFolderName)/\(configurationFileName) in the current directory, "
                    + "\(currentDirectory.standardizedFileURL.path). Run where it is, name it with --config, "
                    + "or create one with `retake init`.",
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
