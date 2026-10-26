import Foundation
import RetakeCore
import Testing

struct ProjectTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "RetakeCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appending(path: "a/b"), withIntermediateDirectories: true)
    }

    @Test func theCurrentDirectorysRetakeJSONIsTheDefault() throws {
        try Data("{}".utf8).write(to: root.appending(path: "retake.json"))
        let project = try Project.locate(configuration: nil, currentDirectory: root)
        #expect(project.configuration.path == root.appending(path: "retake.json").path)
        #expect(project.root.path == root.path)
    }

    @Test func directoriesAboveAreNeverSearched() throws {
        try Data("{}".utf8).write(to: root.appending(path: "retake.json"))
        do {
            _ = try Project.locate(configuration: nil, currentDirectory: root.appending(path: "a/b"))
            Issue.record("Found the project above the current directory")
        } catch {
            #expect(error.status == .usage)
        }
    }

    @Test func aConfigurationFileAnywhereSetsTheProjectsDirectory() throws {
        let file = root.appending(path: "a/previews.json")
        try Data("{}".utf8).write(to: file)
        let project = try Project.locate(configuration: file, currentDirectory: root.appending(path: "a/b"))
        #expect(project.root.path == root.appending(path: "a").path)
        #expect(project.edits.path == root.appending(path: "a/edits").path)
    }

    @Test func aConfigurationFileMustExistAndNotBeADirectory() throws {
        #expect(throws: RetakeError.self) {
            try Project.locate(configuration: root.appending(path: "retake.json"), currentDirectory: root)
        }
        #expect(throws: RetakeError.self) {
            try Project.locate(configuration: root.appending(path: "a"), currentDirectory: root)
        }
    }

    @Test func foldersFollowTheDeviceType() {
        let project = Project(configuration: root.appending(path: "retake.json"))
        #expect(project.scenes(for: .ipad).path == root.appending(path: "scenes/ipad").path)
        #expect(project.takes(for: .iphone).path == root.appending(path: "RetakeOutput/takes/iphone").path)
    }

    @Test func theOutputDirectoryCanMoveAnywhere() throws {
        try Data("{}".utf8).write(to: root.appending(path: "retake.json"))
        let scratch = root.appending(path: "scratch/run-1", directoryHint: .isDirectory)
        let project = try Project.locate(configuration: nil, output: scratch, currentDirectory: root)
        #expect(project.videos(for: .ipad).path == scratch.appending(path: "videos/ipad").path)
        #expect(project.scenes(for: .ipad).path == root.appending(path: "scenes/ipad").path)
    }

    @Test func theWorstStatusWins() {
        #expect([ExitStatus.done, .failed, .environment, .usage].max() == .environment)
    }
}
