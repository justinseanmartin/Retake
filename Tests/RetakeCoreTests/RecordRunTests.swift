import Foundation
@testable import RetakeCore
import Testing

/// Choosing scenes to record, in a project made up in a temporary folder.
struct RecordRunTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "retake-record-\(UUID().uuidString)")
    var project: Project { Project(configuration: root.appending(path: "retake.json")) }

    func write(_ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Scenes `a`, `b` and `c` for the iPad; `a` has a take, `b` only a failure, `c` none; and an
    /// edit using `c` then `a`.
    func makeProject() throws {
        for scene in ["a", "b", "c"] { try write("scenes/\(scene).json", #"{ "devices": ["ipad"], "steps": [{ "hold": 1 }] }"#) }
        try write("output/takes/ipad/a.json", JSONWriter.write(TakeLogReadingTests.log(scene: "a").json))
        try write("output/takes/ipad/a.mov", "")
        try write("output/takes/ipad/b.failed.json", JSONWriter.write(TakeLogReadingTests.log(scene: "b", failure: "step 1 didn't run").json))
        try write("edits/video1.json", """
            { "devices": ["ipad"], "clips": [
              { "take": "c", "from": { "step": "start" }, "to": { "step": "end" } },
              { "take": "a", "from": { "step": "start" }, "to": { "step": "end" } }
            ] }
            """)
    }

    @Test func withNoneNamedOnlyScenesWithoutAGoodTakeAreChosenUnlessForced() throws {
        try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let unforced = try RecordRun.scenes(named: [], edit: nil, force: false, for: .ipad, in: project)
        #expect(unforced.chosen == ["b", "c"] && unforced.alreadyTaken == ["a"], "a failure isn't a take an edit can be cut from")
        #expect(try RecordRun.scenes(named: [], edit: nil, force: true, for: .ipad, in: project).chosen == ["a", "b", "c"])
    }

    @Test func anEditsScenesAreChosenInTheOrderItUsesThem() throws {
        try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try RecordRun.scenes(named: [], edit: "video1", force: true, for: .ipad, in: project).chosen == ["c", "a"])
        #expect(try RecordRun.scenes(named: [], edit: "video1", force: false, for: .ipad, in: project).chosen == ["c"])
        #expect(throws: RetakeError.self) { try RecordRun.scenes(named: [], edit: "video1", force: false, for: .iphone, in: project) }
        #expect(throws: RetakeError.self) { try RecordRun.scenes(named: [], edit: "video9", force: false, for: .ipad, in: project) }
    }

    @Test func stillsOnlyChoosesScenesThatCaptureWithoutCapturesYetUnlessForced() throws {
        try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("scenes/home.json", #"{ "devices": ["ipad"], "steps": [{ "capture": "home" }] }"#)
        try write("scenes/list.json", #"{ "devices": ["ipad"], "steps": [{ "capture": "list" }] }"#)
        try write("output/captures/ipad/home/home.png", "")
        let unforced = try RecordRun.scenes(named: [], edit: nil, force: false, stillsOnly: true, for: .ipad, in: project)
        #expect(unforced.chosen == ["list"] && unforced.alreadyTaken == ["home"])
        #expect(try RecordRun.scenes(named: [], edit: nil, force: true, stillsOnly: true, for: .ipad, in: project).chosen == ["home", "list"])
        #expect(try RecordRun.scenes(named: ["home"], edit: nil, force: false, stillsOnly: true, for: .ipad, in: project).chosen == ["home"])
        do {
            _ = try RecordRun.scenes(named: ["a"], edit: nil, force: false, stillsOnly: true, for: .ipad, in: project)
            Issue.record("a scene that captures nothing")
        } catch {
            #expect(error.status == .usage && error.message == "a has no capture steps, so --stills-only has nothing to take of it.")
        }
    }

    @Test func scenesNamedAreChosenTakeOrNotOnceEach() throws {
        try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try RecordRun.scenes(named: ["a", "c", "a"], edit: nil, force: false, for: .ipad, in: project).chosen == ["a", "c"])
        do {
            _ = try RecordRun.scenes(named: ["d"], edit: nil, force: false, for: .ipad, in: project)
            Issue.record("a scene that doesn't exist")
        } catch {
            #expect(error.status == .usage && error.message.contains("there's a, b, c"))
        }
    }
}
