import Foundation

/// Reading a project's files, each strictly, collecting every problem across them.
public struct ProjectFiles {
    public let project: Project
    let fileManager: FileManager
    /// The names in a directory as it lists them, or nil when it can't be listed: the seam
    /// `misnamedFolder(_:)` looks through.
    let listing: (URL) -> [String]?

    public init(project: Project, fileManager: FileManager = .default, listing: ((URL) -> [String]?)? = nil) {
        self.project = project
        self.fileManager = fileManager
        self.listing = listing ?? { try? fileManager.contentsOfDirectory(atPath: $0.path) }
    }

    /// One of the project's folders there in another case: `Edits/` for `edits/`. A case-sensitive
    /// volume, such as a clone git made of a folder renamed on a Mac, has no `edits/` at all, and
    /// a Mac's case-insensitive one finds `edits/` though it's listed as `Edits/`.
    public struct MisnamedFolder: Equatable, Sendable, CustomStringConvertible {
        /// The folder as it's listed, relative to the project: `Edits`.
        public var found: String
        /// The folder as Retake names it: `edits`.
        public var expected: String

        public var message: String { "should be named \(expected)/; Retake's folders are lowercase" }
        public var description: String { "\(found)/ \(message)" }
    }

    /// `folder`, or the first folder on the way to it from the project's directory, when it's listed
    /// in another case than Retake names it; nil when every one is listed as named, or one isn't
    /// there at all. It lists each parent, not stats each casing, so it's for when a folder's
    /// contents can't be found, and for `validate`.
    public func misnamedFolder(_ folder: URL) -> MisnamedFolder? {
        let relative = project.displayPath(folder)
        guard !relative.hasPrefix("/") else { return nil }
        var parent = project.root
        var found: [String] = [], expected: [String] = []
        for name in relative.split(separator: "/").map(String.init) {
            guard let entries = listing(parent) else { return nil }
            expected.append(name)
            if entries.contains(name) {
                found.append(name)
            } else if let other = entries.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                found.append(other)
                return MisnamedFolder(found: found.joined(separator: "/"), expected: expected.joined(separator: "/"))
            } else {
                return nil
            }
            parent = parent.appending(path: name, directoryHint: .isDirectory)
        }
        return nil
    }

    /// What to add to a message that `url`, in one of the project's folders, isn't there: that its
    /// folder is named in another case, when it is; otherwise nothing.
    public func whyMissing(_ url: URL) -> String {
        misnamedFolder(url.deletingLastPathComponent()).map { ": \($0)" } ?? ""
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

        public func warning(_ warning: FileProblem) {
            warnings.append(warning)
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
            report.problem(FileProblem(file: name, path: .root, message: "doesn't exist\(whyMissing(url))"))
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
    public var previewAspect: Bool
    public var appearance: SetFile.Appearance?

    public init(
        name: String,
        state: SetFile.State = SetFile.defaultState,
        files: [SetFile.FileCopy] = [],
        defaults: [Named<JSONValue>] = [],
        environment: [Named<String>] = [],
        arguments: [String] = [],
        previewAspect: Bool = SetFile.defaultPreviewAspect,
        appearance: SetFile.Appearance? = nil,
    ) {
        self.name = name
        names = [name]
        self.state = state
        self.files = files
        self.defaults = defaults
        self.environment = environment
        self.arguments = arguments
        self.previewAspect = previewAspect
        self.appearance = appearance
    }

    /// Lays each set over the one before, from the base: a field a set gives replaces the base's,
    /// key by key for `files`, `defaults` and `environment`; `arguments` add up, the base's
    /// first.
    init(name: String, chain fromBase: [SetFile], names: [String]) {
        self.name = name
        self.names = names
        var state = SetFile.defaultState
        var files: [Named<String>] = []
        var defaults: [Named<JSONValue>] = []
        var environment: [Named<String>] = []
        var arguments: [String] = []
        var previewAspect = SetFile.defaultPreviewAspect
        var appearance: SetFile.Appearance?
        for set in fromBase {
            state = set.state ?? state
            files = files.overlaid(with: set.files.map { Named($0.destination, $0.source) })
            defaults = defaults.overlaid(with: set.defaults)
            environment = environment.overlaid(with: set.environment)
            arguments += set.arguments
            previewAspect = set.previewAspect ?? previewAspect
            appearance = set.appearance ?? appearance
        }
        self.state = state
        self.files = files.map { SetFile.FileCopy(destination: $0.name, source: $0.value) }
        self.defaults = defaults
        self.environment = environment
        self.arguments = arguments
        self.previewAspect = previewAspect
        self.appearance = appearance
    }

    /// The shapes the app's window takes on a device of `type`: with `previewAspect`, the App Store
    /// preview's in portrait and that turned in landscape; nil, filling the screen, without.
    public func aspect(for type: DeviceType) -> SetFile.AspectChoice? {
        guard previewAspect else { return nil }
        let shape = PreviewSpec.of(type).aspect
        return SetFile.AspectChoice(portrait: shape, landscape: shape.turned)
    }
}
