import ArgumentParser
import Foundation
@testable import RetakeCLI
import RetakeCore
import Testing

/// The command line's shape and exit statuses, against docs/cli.md.
struct CommandLineTests {
    @Test(arguments: [
        ["init", "--bundle-id", "com.example.notes", "--scheme", "Notes"],
        ["doctor", "--device", "ipad"],
        ["devices", "--json"],
        ["devices", "add", "iphone"],
        ["devices", "add", "ipad", "00008103-0000000000000001"],
        ["devices", "add", "ipad", "Sam’s iPad (2)"],
        ["devices", "--config", "Previews/retake.json"],
        ["devices", "remove", "iphone"],
        ["embed", "build/MyApp.app", "--output", "out/MyApp.app", "--identity", "ABC", "--profile", "p.mobileprovision", "--json"],
        ["install", "--scheme", "MyApp", "--workspace", "MyApp.xcworkspace", "--configuration", "Debug", "--allow-provisioning-updates"],
        ["install", "--app", "build/MyApp.app", "--device", "ipad", "--identity", "ABC", "--profile", "p.mobileprovision"],
        ["compose", "create-note", "--set", "returning-user", "--device", "ipad", "--json"],
        ["record", "create-note", "--dry-run"],
        ["record", "--for", "video1", "--dry-run"],
        ["record"],
        ["record", "--force"],
        ["record", "--for", "video1", "--force", "--stop-on-failure"],
        ["record", "create-note", "share-note", "--device", "iphone"],
        ["takes", "create-note", "--type", "ipad", "--json"],
        ["clean", "--takes", "--type", "ipad", "--yes"],
        ["clean", "--takes", "create-note,share-note@2", "--cuts"],
        ["clean", "--cuts", "video1,video2", "--yes"],
        ["clean", "--yes", "--takes"],
        ["clean", "--on-device"],
        ["clean", "--on-device", "--device", "ipad"],
        ["conform", "video1", "--dry-run"],
        ["conform", "video1", "--type", "ipad"],
        ["cut", "video1", "video2", "--type", "iphone", "--draft", "--open"],
        ["cut", "--all", "--draft"],
        ["status", "--json"],
        ["info", "a.mov", "b.mp4", "--json"],
        ["check", "MyApp.xcarchive"],
        ["validate", "edits/video1.json", "--offline", "--json"],
        ["schema", "edit"],
        ["schema", "--output", "schemas"],
        ["version", "--json"],
        ["record", "--config", "Previews/retake.json", "create-note"],
        ["cut", "video1", "--config", "Previews/retake.json", "--output-dir", "/tmp/retake"],
    ])
    func parsesTheDocumentedForms(_ arguments: [String]) throws {
        _ = try Retake.parseAsRoot(Retake.optionalValuesGiven(arguments))
    }

    @Test(arguments: [
        ["install", "--app", "MyApp.app", "--scheme", "MyApp"],
        ["install", "--scheme", "MyApp", "--workspace", "a", "--xcodeproj", "b"],
        ["install", "--workspace", "MyApp.xcworkspace"],
        ["install", "--app", "MyApp.app", "--allow-provisioning-updates"],
        ["record", "create-note", "--dry-run", "--from", "3"],
        ["record", "create-note", "--for", "video1"],
        ["takes", "--device", "ipad", "--type", "ipad"],
        ["discard", "create-note", "2"],
        ["clean", "--videos"],
        ["clean", "--on-device", "--takes"],
        ["clean", "--on-device", "--yes"],
        ["clean", "--device", "ipad"],
        ["conform", "video1", "--to", "latest"],
        ["cut"],
        ["cut", "video1", "--all"],
        ["cut", "--all", "--open"],
        ["takes", "--type", "android"],
        ["info"],
        ["schema"],
        ["schema", "edit", "--output", "schemas"],
        ["schema", "storyboard"],
        ["record", "--speed", "2"],
        ["frobnicate"],
        ["record", "--project", "Previews"],
        ["devices", "add", "ipad", "--device", "00008103-0000000000000001"],
        ["devices", "--output-dir", "out"],
    ])
    func refusesMisuseWithStatus2(_ arguments: [String]) async {
        let outcome = await Retake.run(arguments)
        #expect(outcome.status == ExitStatus.usage.rawValue)
        #expect(!outcome.error.isEmpty)
    }

    @Test func cleansBareTakesAndCutsMeanEveryOne() throws {
        #expect(Retake.optionalValuesGiven(["clean", "--takes", "--cuts", "video1", "--yes"]) == ["clean", "--takes=*", "--cuts", "video1", "--yes"])
        #expect(Retake.optionalValuesGiven(["clean", "--cuts"]) == ["clean", "--cuts=*"])
        #expect(Retake.optionalValuesGiven(["record", "--takes"]) == ["record", "--takes"], "only clean's")
        #expect(Clean.list("*") == [] && Clean.list(nil) == nil && Clean.list("a, b@2,") == ["a", "b@2"])
    }

    @Test func helpExitsWith0OnStandardOutput() async {
        let outcome = await Retake.run(["record", "--help"])
        #expect(outcome.status == 0)
        #expect(outcome.output.contains("--stop-on-failure"))
        #expect(outcome.error.isEmpty)
    }

    @Test func versionRunsOutsideAProject() async {
        let outcome = await Retake.run(["version"])
        #expect(outcome.status == 0)
    }

    @Test func validateFailsWhenAFileHasAProblem() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "RetakeCLIValidate-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "sets"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appending(path: "retake.json"))
        let config = root.appending(path: "retake.json").path
        #expect(await Retake.run(["validate", "--offline", "--config", config]).status == 0)
        try Data(#"{"state": "fresh"}"#.utf8).write(to: root.appending(path: "sets/broken.json"))
        #expect(await Retake.run(["validate", "--offline", "--config", config]).status == 1)
        #expect(await Retake.run(["validate", "--offline", "--config", config, root.appending(path: "notes.txt").path]).status == 2)
    }

    @Test func retakeErrorsKeepTheirStatus() {
        let outcome = Retake.outcome(of: RetakeError(.environment, "No device is connected by USB."))
        #expect(outcome.status == 3)
        #expect(outcome.error == "✖ No device is connected by USB.")
    }
}
