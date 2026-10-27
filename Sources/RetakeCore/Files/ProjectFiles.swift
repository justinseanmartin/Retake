import Foundation

/// Reading a project's files, each strictly, collecting every problem across them.
public struct ProjectFiles {
    public let project: Project
    let fileManager: FileManager

    public init(project: Project, fileManager: FileManager = .default) {
        self.project = project
        self.fileManager = fileManager
    }

    /// Problems found across the files read, and warnings, each naming its file.
    public final class Report {
        public private(set) var problems: [FileProblem] = []
        public private(set) var warnings: [FileProblem] = []

        public init() {}

        public func add(_ reader: JSONReader) {
            problems += reader.problems
            warnings += reader.warnings
        }

        public func problem(_ problem: FileProblem) {
            problems.append(problem)
        }

        /// A command's failure (1), listing every problem.
        public var error: RetakeError {
            RetakeError(.failed, problems.map(\.description).joined(separator: "\n"))
        }
    }

    /// The names of the files of a kind in a folder: `create-note` for `scenes/iphone/create-note.json`.
    public func names(in folder: URL) -> [String] {
        let entries = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        return entries.filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.map { String($0.dropLast(5)) }.sorted()
    }

    public func setURL(_ name: String) -> URL { project.sets.appending(path: "\(name).json") }

    /// A file's text, or nil with a problem when it's missing or isn't text.
    func text(of url: URL, into report: Report) -> String? {
        let name = project.displayPath(url)
        guard let data = fileManager.contents(atPath: url.path) else {
            report.problem(FileProblem(file: name, path: .root, message: "doesn't exist"))
            return nil
        }
        guard let text = String(data: data, encoding: .utf8) else {
            report.problem(FileProblem(file: name, path: .root, message: "isn't UTF-8 text"))
            return nil
        }
        return text
    }

    public func sceneURL(_ name: String, for type: DeviceType) -> URL {
        project.scenes(for: type).appending(path: "\(name).json")
    }

    /// A scene for a device type, or nil with problems in `report`.
    public func readScene(_ name: String, for type: DeviceType, into report: Report) -> SceneFile? {
        let url = sceneURL(name, for: type)
        guard let text = text(of: url, into: report) else { return nil }
        let reader = JSONReader(file: project.displayPath(url))
        let scene = SceneFile.read(text, with: reader)
        report.add(reader)
        return scene
    }

    public func editURL(_ name: String) -> URL { project.edits.appending(path: "\(name).json") }

    /// An edit, each device type's overrides laid over it, or nil with problems in `report`.
    public func readEdit(_ name: String, into report: Report) -> EditFile? {
        let url = editURL(name)
        guard let text = text(of: url, into: report) else { return nil }
        let reader = JSONReader(file: project.displayPath(url))
        let edit = EditFile.read(text, with: reader)
        report.add(reader)
        return edit
    }

    /// A set as its own file says it, without what it extends.
    public func readSet(_ name: String, into report: Report) -> SetFile? {
        let url = setURL(name)
        guard let text = text(of: url, into: report) else { return nil }
        let reader = JSONReader(file: project.displayPath(url))
        let set = SetFile.read(text, with: reader)
        report.add(reader)
        return set
    }

    /// A set with what it extends laid under it, or nil with problems in `report`: a set it names
    /// that doesn't exist, or `extends` coming back round to a set already in the chain.
    public func resolveSet(_ name: String, into report: Report) -> ResolvedSet? {
        var chain: [(name: String, set: SetFile)] = []
        var next: String? = name
        while let current = next {
            if let loop = chain.firstIndex(where: { $0.name == current }) {
                let names = chain[loop...].map(\.name) + [current]
                report.problem(FileProblem(
                    file: project.displayPath(setURL(chain.last!.name)),
                    path: JSONPath.root.appending("extends"),
                    message: "sets extend each other in a loop: \(names.joined(separator: " → "))",
                ))
                return nil
            }
            if !chain.isEmpty, !fileManager.fileExists(atPath: setURL(current).path) {
                report.problem(FileProblem(
                    file: project.displayPath(setURL(chain.last!.name)),
                    path: JSONPath.root.appending("extends"),
                    message: "there's no set \"\(current)\" (\(project.displayPath(setURL(current))))",
                ))
                return nil
            }
            guard let set = readSet(current, into: report) else { return nil }
            chain.append((current, set))
            next = set.extends
        }
        return ResolvedSet(name: name, chain: chain.map(\.set).reversed(), names: chain.map(\.name))
    }
}

/// A set with the sets it extends laid under it: what a take actually starts from.
public struct ResolvedSet: Equatable, Sendable {
    public var name: String
    /// The set and those it extends, from itself to the one at the base.
    public var names: [String]
    public var state: SetFile.State
    public var files: [SetFile.FileCopy]
    public var defaults: [Named<JSONValue>]
    public var environment: [Named<String>]
    public var arguments: [String]
    public var aspect: [DeviceType: SetFile.AspectChoice]

    /// Lays each set over the one before, from the base: a field a set gives replaces the base's,
    /// key by key for `files`, `defaults`, `environment` and `aspect`; `arguments` add up, the
    /// base's first.
    init(name: String, chain fromBase: [SetFile], names: [String]) {
        self.name = name
        self.names = names
        var state = SetFile.State.clean
        var files: [Named<String>] = []
        var defaults: [Named<JSONValue>] = []
        var environment: [Named<String>] = []
        var arguments: [String] = []
        var aspect: [DeviceType: SetFile.AspectChoice] = [:]
        for set in fromBase {
            state = set.state ?? state
            files = files.overlaid(with: set.files.map { Named($0.destination, $0.source) })
            defaults = defaults.overlaid(with: set.defaults)
            environment = environment.overlaid(with: set.environment)
            arguments += set.arguments
            aspect.merge(set.aspect) { $1 }
        }
        self.state = state
        self.files = files.map { SetFile.FileCopy(destination: $0.name, source: $0.value) }
        self.defaults = defaults
        self.environment = environment
        self.arguments = arguments
        self.aspect = aspect
    }
}
