import Foundation
@testable import RetakeCore
import Testing

/// Choosing scenes and numbering takes, in a project made up in a temporary folder.
struct RecordRunTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "retake-record-\(UUID().uuidString)")
    var project: Project { Project(configuration: root.appending(path: "retake.json")) }

    func write(_ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Scenes `a`, `b` and `c` for the iPad; `a` has a good take 1, `b` a failed take 2 after a good
    /// take 1 was discarded, `c` none; and an edit using `c` then `a`.
    func makeProject() throws {
        for scene in ["a", "b", "c"] { try write("scenes/ipad/\(scene).json", #"{ "steps": [{ "hold": 1 }] }"#) }
        try write("RetakeOutput/takes/ipad/a/1.json", #"{ "scene": "a" }"#)
        try write("RetakeOutput/takes/ipad/b/2.json", #"{ "scene": "b", "failure": "step 1 didn't run" }"#)
        try write("edits/video1.json", """
            { "devices": ["ipad"], "takes": { "ipad": {} }, "clips": [
              { "take": "c", "from": { "step": "start" }, "to": { "step": "end" } },
              { "take": "a", "from": { "step": "start" }, "to": { "step": "end" } }
            ] }
            """)
    }

    @Test func takesAreNumberedAfterTheLastOnDiskFailedOrNot() throws {
        try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(RecordRun.nextTake(of: "a", for: .ipad, in: project) == 2)
        #expect(RecordRun.nextTake(of: "b", for: .ipad, in: project) == 3)
        #expect(RecordRun.nextTake(of: "c", for: .ipad, in: project) == 1)
        #expect(RecordRun.takes(of: "b", for: .ipad, in: project) == [.init(number: 2, failed: true)])
    }

    @Test func withNoneNamedOnlyScenesWithoutAGoodTakeAreChosenUnlessForced() throws {
        try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let unforced = try RecordRun.scenes(named: [], edit: nil, force: false, for: .ipad, in: project)
        #expect(unforced.chosen == ["b", "c"] && unforced.alreadyTaken == ["a"], "a failed take isn't one an edit can pin")
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
