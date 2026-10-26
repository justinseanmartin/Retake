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
        throw RetakeError.notImplemented("check")
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
        _ = try project.locate()
        throw RetakeError.notImplemented("validate")
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
        let version = RetakeVersion.current
        if output.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(version), as: UTF8.self))
        } else {
            print("Retake \(version.version)")
            if let commit = version.buttonHeist.commit {
                print("The Button Heist \(version.buttonHeist.version) (\(commit))")
            } else {
                print("The Button Heist \(version.buttonHeist.version)")
            }
        }
    }
}
