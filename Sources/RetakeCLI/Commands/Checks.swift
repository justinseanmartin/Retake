import ArgumentParser
import Foundation
import RetakeCore

struct Check: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Checks an archive for TheInsideJob.",
        discussion: """
            Checks an .xcarchive, .ipa or .app for TheInsideJob and Retake's support library, in its \
            frameworks and executables. Exits 1 if either is found, naming where, and 0 if neither is.
            """,
    )

    @Argument(help: ArgumentHelp("An .xcarchive, .ipa or .app.", valueName: "path"))
    var path: String

    func run() async throws {
        let current = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
        let url = URL(filePath: path, relativeTo: current).standardizedFileURL
        let found = try ArchiveCheck.check(url)
        guard !found.isEmpty else {
            print("Neither TheInsideJob nor Retake's support library is in \(url.lastPathComponent).")
            return
        }
        for place in found { print("\(url.lastPathComponent): \(place)") }
        throw RetakeError(.failed, "\(url.lastPathComponent) contains TheInsideJob or Retake's support library, which must never ship.")
    }
}

struct Validate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Checks the project's files.",
        discussion: """
            Checks the project's files, or the files named, against the schemas, then what a schema \
            can't say. Prints every problem, and fails (1) if there's any. Needs no device.
            """,
    )

    @Argument(help: ArgumentHelp("Only these files.", valueName: "file"), completion: .file(extensions: ["json"]))
    var files: [String] = []

    @Flag(help: "Skip the checks that need takes: anchors resolving, and elements in step logs.")
    var offline = false

    @OptionGroup var output: OutputOptions
    @OptionGroup var project: ProjectOptions

    func run() async throws {
        let located = try project.locate()
        let validator = ProjectValidator(files: ProjectFiles(project: located))
        let current = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
        var targets: [ProjectValidator.Target]?
        if !files.isEmpty {
            targets = try files.map { file in
                let url = URL(filePath: file, relativeTo: current).standardizedFileURL
                guard let target = validator.target(for: url) else {
                    throw RetakeError(
                        .usage,
                        "\(file) isn't one of the project's files: its configuration file, or a file in sets/, scenes/iphone/, scenes/ipad/ or edits/.",
                    )
                }
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw RetakeError(.usage, "\(file) doesn't exist.")
                }
                return target
            }
        }
        let report = validator.validate(targets)
        if output.json {
            func entries(_ problems: [FileProblem]) -> JSONValue {
                .array(problems.map { problem in
                    .object(JSONObject([
                        .init(key: "file", value: .string(problem.file)),
                        .init(key: "path", value: .string(problem.path.description)),
                        .init(key: "message", value: .string(problem.message)),
                    ]))
                })
            }
            print(JSONWriter.write(.object(JSONObject([
                .init(key: "problems", value: entries(report.problems)),
                .init(key: "warnings", value: entries(report.warnings)),
            ]))), terminator: "")
        } else {
            for warning in report.warnings { Console.warn(warning.description) }
            for problem in report.problems { print(problem.description) }
            let count = report.problems.count
            print(count == 0 ? "No problems." : "\(count) problem\(count == 1 ? "" : "s").")
        }
        if !offline {
            Console.note("anchors and elements aren't checked against takes yet; these are the --offline checks.")
        }
        if !report.problems.isEmpty { throw ExitCode.failure }
    }
}

struct Schema: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Prints the schemas.",
        discussion: """
            Prints the schema for one kind of file, or with --output writes all of them there, as \
            <kind>.schema.json.
            """,
    )

    enum Kind: String, CaseIterable, ExpressibleByArgument {
        case retake, set, scene, edit
    }

    @Argument(help: ArgumentHelp("The kind of file.", valueName: "kind"))
    var kind: Kind?

    @Option(help: ArgumentHelp("Write every schema to this directory.", valueName: "dir"), completion: .directory)
    var output: String?

    func validate() throws {
        if kind != nil, output != nil {
            throw ValidationError("Name a kind to print, or give --output to write them all, not both.")
        }
        if kind == nil, output == nil {
            throw ValidationError("Name a kind to print (retake, set, scene or edit), or give --output.")
        }
    }

    func run() async throws {
        throw RetakeError.notImplemented("schema")
    }
}

struct Version: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Prints Retake's version and The Button Heist's it's built against.",
    )

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let version = RetakeVersion.withClone()
        if output.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(version), as: UTF8.self))
        } else {
            print("Retake \(version.version)")
            if let commit = version.buttonHeist.commit {
                print("The Button Heist \(version.buttonHeist.version) (\(commit)), built from \(version.buttonHeist.clonePath ?? "a local clone")")
            } else {
                print("The Button Heist \(version.buttonHeist.version)")
            }
        }
    }
}
