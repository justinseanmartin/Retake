import ArgumentParser
import Foundation
@testable import RetakeCLI
import RetakeCore
import Testing

/// `--config` and `--output-dir`, and the environment variables that stand in for them.
struct ProjectOptionsTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "RetakeCLITests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appending(path: "Previews"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appending(path: "retake.json"))
        try Data("{}".utf8).write(to: root.appending(path: "Previews/previews.json"))
    }

    func locate(_ arguments: [String], _ environment: [String: String] = [:]) throws -> Project {
        try ProjectOptions.parse(arguments).locate(environment: environment, currentDirectory: root.path)
    }

    @Test func withNothingGivenTheCurrentDirectoryIsUsed() throws {
        let project = try locate([])
        #expect(project.configuration.path == root.appending(path: "retake.json").path)
        #expect(project.output.path == root.appending(path: "output").path)
    }

    @Test func theEnvironmentStandsInForAbsentFlags() throws {
        let project = try locate([], ["RETAKE_CONFIG": "Previews/previews.json", "RETAKE_OUTPUT_DIR": "/tmp/retake-run"])
        #expect(project.configuration.path == root.appending(path: "Previews/previews.json").path)
        #expect(project.output.path == "/tmp/retake-run")
    }

    @Test func flagsWinOverTheEnvironment() throws {
        let project = try locate(
            ["--config", "retake.json", "--output-dir", "out"],
            ["RETAKE_CONFIG": "Previews/previews.json", "RETAKE_OUTPUT_DIR": "/tmp/retake-run"],
        )
        #expect(project.configuration.path == root.appending(path: "retake.json").path)
        #expect(project.output.path == root.appending(path: "out").path)
    }

    @Test func emptyVariablesCountAsUnset() throws {
        let project = try locate([], ["RETAKE_CONFIG": "", "RETAKE_OUTPUT_DIR": ""])
        #expect(project.configuration.path == root.appending(path: "retake.json").path)
        #expect(project.output.path == root.appending(path: "output").path)
    }

    @Test func aCommandThatNeedsNoProjectReadsOneOnlyWhenThereIsOne() throws {
        let outside = root.appending(path: "Previews").path
        #expect(try ConfigOption.parse([]).locateIfPresent(environment: [:], currentDirectory: outside) == nil)
        let named = try ConfigOption.parse([]).locateIfPresent(
            environment: ["RETAKE_CONFIG": "previews.json"], currentDirectory: outside,
        )
        #expect(named?.configuration.path == root.appending(path: "Previews/previews.json").path)
        #expect(throws: RetakeError.self) {
            try ConfigOption.parse(["--config", "missing.json"]).locateIfPresent(environment: [:], currentDirectory: outside)
        }
    }

    @Test func aMissingFileFromTheEnvironmentSaysSo() {
        do {
            _ = try locate([], ["RETAKE_CONFIG": "Elsewhere/retake.json"])
            Issue.record("Found a configuration file that doesn't exist")
        } catch let error as RetakeError {
            #expect(error.status == .usage)
            #expect(error.message.contains("RETAKE_CONFIG"))
        } catch {
            Issue.record("Threw \(error)")
        }
    }
}
