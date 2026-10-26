import Foundation

/// A Retake project: a configuration file, `retake.json` by default, and the folders beside it.
public struct Project: Sendable, Equatable {
    public static let configurationFileName = "retake.json"
    /// Where takes, videos and builds go unless the command or the configuration file says otherwise.
    public static let defaultOutputDirectoryName = "RetakeOutput"

    /// The project's configuration file. Everything else in the project, and every relative path
    /// the file gives, is found relative to the directory holding it.
    public var configuration: URL

    /// Where Retake writes takes, videos and builds: `RetakeOutput/` beside the configuration file
    /// unless given. It holds the takes edits pin, so one that's thrown away takes them with it.
    public var output: URL

    public init(configuration: URL, output: URL? = nil) {
        self.configuration = configuration.standardizedFileURL
        self.output = (output ?? self.configuration.deletingLastPathComponent()
            .appending(path: Project.defaultOutputDirectoryName, directoryHint: .isDirectory)).standardizedFileURL
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

    /// The project a command runs in: the configuration file `configuration` names (`--config`),
    /// otherwise `retake.json` in the current directory. No other directory is searched, so a
    /// command never acts on a project it wasn't pointed at. `output` (`--output-dir`) moves
    /// where it writes; it needn't exist yet.
    public static func locate(
        configuration: URL?,
        output: URL? = nil,
        currentDirectory: URL,
        fileManager: FileManager = .default,
    ) throws(RetakeError) -> Project {
        let project = Project(
            configuration: configuration ?? currentDirectory.appending(path: configurationFileName),
            output: output,
        )
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: project.configuration.path, isDirectory: &isDirectory)
        if configuration != nil {
            guard exists else {
                throw RetakeError(.usage, "No configuration file at \(project.configuration.path).")
            }
            guard !isDirectory.boolValue else {
                throw RetakeError(
                    .usage,
                    "\(project.configuration.path) is a directory; --config names the configuration file, "
                        + "such as \(project.configuration.appending(path: configurationFileName).path).",
                )
            }
        } else if !exists || isDirectory.boolValue {
            throw RetakeError(
                .usage,
                "No \(configurationFileName) in the current directory, \(project.root.path). Run where it is, "
                    + "name it with --config, or create one with `retake init`.",
            )
        }
        return project
    }
}
