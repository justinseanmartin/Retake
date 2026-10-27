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

    @Test func aProjectInRetakeIsFoundFromTheFolderHoldingIt() throws {
        let folder = root.appending(path: "Retake", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appending(path: "retake.json"))
        let fromAbove = try Project.locate(configuration: nil, currentDirectory: root)
        #expect(fromAbove.root.path == folder.path)
        #expect(fromAbove.devicesFile.path == folder.appending(path: "devices.json").path)
        let fromInside = try Project.locate(configuration: nil, currentDirectory: folder)
        #expect(fromInside.configuration == fromAbove.configuration)
    }

    @Test func retakeJSONHereComesBeforeRetakesOwn() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "Retake"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appending(path: "Retake/retake.json"))
        try Data("{}".utf8).write(to: root.appending(path: "retake.json"))
        #expect(try Project.locate(configuration: nil, currentDirectory: root).root.path == root.path)
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

    @Test func aConfigurationFileWithProblemsFailsNamingEachOne() throws {
        try Data(#"{"devise": "ipad", "build": {"scheme": 3}}"#.utf8).write(to: root.appending(path: "retake.json"))
        do {
            _ = try Project.locate(configuration: nil, currentDirectory: root)
            Issue.record("read a malformed retake.json")
        } catch {
            #expect(error.status == .failed)
            #expect(error.message == """
                retake.json: build.scheme: expected a string, found a number
                retake.json: unknown key "devise"; did you mean "device"?
                """)
        }
    }

    @Test func foldersFollowTheDeviceType() {
        let project = Project(configuration: root.appending(path: "retake.json"))
        #expect(project.scenes(for: .ipad).path == root.appending(path: "scenes/ipad").path)
        #expect(project.takes(for: .iphone).path == root.appending(path: "output/takes/iphone").path)
    }

    @Test func theOutputDirectoryCanMoveAnywhere() throws {
        try Data("{}".utf8).write(to: root.appending(path: "retake.json"))
        let scratch = root.appending(path: "scratch/run-1", directoryHint: .isDirectory)
        let project = try Project.locate(configuration: nil, output: scratch, currentDirectory: root)
        #expect(project.cuts(for: .ipad).path == scratch.appending(path: "cuts/ipad").path)
        #expect(project.scenes(for: .ipad).path == root.appending(path: "scenes/ipad").path)
    }

    @Test func theWorstStatusWins() {
        #expect([ExitStatus.done, .failed, .environment, .usage].max() == .environment)
    }
}
