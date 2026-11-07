import Foundation
@testable import RetakeCore
import Testing

/// Takes on disk, as `record` keeps them, `takes` lists them and `clean` deletes them.
struct TakeStoreTests {
    let root: URL
    let project: Project

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "RetakeTakeStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        project = Project(configuration: root.appending(path: "retake.json"))
        try FileManager.default.createDirectory(at: project.edits, withIntermediateDirectories: true)
        // a has a take, cut from by video1, and a previous one; b only a failure; c's take has lost
        // its movie; and the iPhone has a take of a.
        try record("a", at: 2)
        try record("a", .previous, at: 1)
        try record("b", .failed, at: 1, failure: "step 2 didn't run")
        try record("c", at: 1, movie: false)
        try record("a", at: 1, type: .iphone)
        for scene in ["a", "b", "c", "d"] { try write("scenes/ipad/\(scene).json", "{}") }
        try write("scenes/iphone/a.json", "{}")
        try write("edits/video1.json", #"{ "devices": ["ipad"], "clips": [{ "take": "a", "from": { "step": "start" }, "to": { "step": "end" }, "stills": [{ "take": "c", "at": 0 }] }] }"#)
        try write("output/cuts/ipad/video1/video1-ipad.mp4", "")
        try write("output/cuts/ipad/video2/video2-ipad.mp4", "")
    }

    func write(_ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// A take of `scene` as `kind`, or as a recording in progress, recorded `minute` minutes in.
    func record(
        _ scene: String, _ kind: TakeStore.Kind = .take, recording: Bool = false, at minute: Int, type: DeviceType = .ipad,
        failure: String? = nil, movie: Bool = true,
    ) throws {
        var log = TakeLogReadingTests.log(scene: scene, failure: failure)
        log.recordedAt = Date(timeIntervalSince1970: 1_800_000_000 + Double(minute * 60))
        let suffix = recording ? ".recording" : kind.suffix
        try write("output/takes/\(type.rawValue)/\(scene)\(suffix).json", JSONWriter.write(log.json))
        if movie { try write("output/takes/\(type.rawValue)/\(scene)\(suffix).mov", "") }
    }

    func names(_ takes: [TakeStore.Take]) -> [String] { takes.map { "\($0.type.rawValue) \($0.name)" } }

    /// Each of a scene's takes on disk, by kind, as the minute it was recorded in.
    func minutes(_ scene: String) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: TakeStore.takes(of: scene, for: [.ipad], in: project).map { take in
            (take.kind.rawValue, Int(take.recorded!.recordedAt.timeIntervalSince1970 - 1_800_000_000) / 60)
        })
    }

    func keep(_ scene: String, at minute: Int, failure: String? = nil) throws {
        try record(scene, recording: true, at: minute, failure: failure)
        try TakeStore.keepRecording(of: scene, in: project.takes(for: .ipad), failed: failure != nil)
    }

    @Test func eachScenesTakePreviousAndFailureAreListedWithTheEditsCutFromTheTake() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record("a", recording: true, at: 3)
        let takes = TakeStore.takes(for: DeviceType.allCases, in: project)
        #expect(names(takes) == ["iphone a", "ipad a", "ipad a (previous)", "ipad b (failed)", "ipad c"], "a recording in progress isn't a take yet")
        #expect(takes.map(\.usedBy) == [[], ["video1"], [], [], []], "only the take is cut from, and c's can't be")
        #expect(takes.map(\.failed) == [false, false, false, true, false])
        #expect(takes[4].problem == "output/takes/ipad/c.mov is missing")
        #expect(TakeStore.take(of: "b", for: .ipad, in: project) == nil, "a failure isn't the take")
    }

    @Test func aSuccessReplacesTheTakeKeepingItAsPreviousAndDroppingTheOlderPreviousAndTheFailure() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record("a", .failed, at: 3, failure: "step 1 didn't run")
        try keep("a", at: 4)
        #expect(minutes("a") == ["take": 4, "previous": 2], "the failure is no longer the latest news")

        try keep("b", at: 2)
        #expect(minutes("b") == ["take": 2], "a first success has nothing to keep as previous")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: project.takes(for: .ipad).path).filter { $0.contains(".recording") }
        #expect(leftovers.isEmpty)
    }

    @Test func aFailureKeepsTheTakeAndReplacesTheLastFailure() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try keep("a", at: 3, failure: "step 1 didn't run")
        #expect(minutes("a") == ["take": 2, "previous": 1, "failed": 3])
        try keep("a", at: 4, failure: "step 2 didn't run")
        #expect(minutes("a") == ["take": 2, "previous": 1, "failed": 4])
        #expect(TakeStore.takes(of: "a", for: [.ipad], in: project).last?.recorded?.failure == "step 2 didn't run")
    }

    @Test func anInterruptedRecordingLeavesTheTakesAlone() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record("a", recording: true, at: 3, movie: true)
        let before = minutes("a")
        TakeStore.discardRecording(of: "a", in: project.takes(for: .ipad))
        #expect(minutes("a") == before && before == ["take": 2, "previous": 1])
        #expect(!FileManager.default.fileExists(atPath: project.takes(for: .ipad).appending(path: "a.recording.mov").path))
    }

    @Test func restoringSwapsTheTakeAndThePreviousOne() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try TakeStore.restore("a", for: .ipad, in: project)
        #expect(minutes("a") == ["take": 1, "previous": 2])
        try TakeStore.restore("a", for: .ipad, in: project)
        #expect(minutes("a") == ["take": 2, "previous": 1], "restoring again undoes it")
        #expect(throws: RetakeError.self) { try TakeStore.restore("c", for: .ipad, in: project) }
        #expect(minutes("c") == ["take": 1], "c, with no previous, is left as it was")
    }

    @Test func cleaningAScenesTakesDeletesItsTakePreviousAndFailure() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record("a", .failed, at: 3, failure: "step 1 didn't run")
        let everything = try TakeStore.cleaning(takes: nil, cuts: nil, for: DeviceType.allCases, in: project)
        #expect(everything.takes.count == 6 && everything.cuts.map(\.lastPathComponent) == ["video1", "video2"])

        let some = try TakeStore.cleaning(takes: ["a"], cuts: ["video1"], for: [.ipad], in: project)
        #expect(names(some.takes) == ["ipad a", "ipad a (previous)", "ipad a (failed)"])
        #expect(names(some.used) == ["ipad a"])
        try TakeStore.delete(some, in: project)
        #expect(names(TakeStore.takes(for: DeviceType.allCases, in: project)) == ["iphone a", "ipad b (failed)", "ipad c"])
        #expect(!FileManager.default.fileExists(atPath: project.cuts(for: .ipad).appending(path: "video1").path))
        #expect(FileManager.default.fileExists(atPath: project.cuts(for: .ipad).appending(path: "video2").path))

        for (takes, cuts) in [(["nowhere"], nil), (nil, ["video9"])] {
            #expect(throws: RetakeError.self) { try TakeStore.cleaning(takes: takes, cuts: cuts, for: DeviceType.allCases, in: project) }
        }
    }

    @Test func unusedKeepsOnlyTheTakesOfNeededScenes() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let cleaning = try TakeStore.unused(for: [.ipad], in: project)
        #expect(names(cleaning.takes) == ["ipad a (previous)", "ipad b (failed)"])
        #expect(cleaning.scenes.map(\.lastPathComponent) == ["b.json", "d.json"])
        try TakeStore.delete(cleaning, in: project)
        #expect(names(TakeStore.takes(for: DeviceType.allCases, in: project)) == ["iphone a", "ipad a", "ipad c"], "--type leaves the other type alone")

        try write("edits/broken.json", #"{"clips": "not clips"}"#)
        #expect(throws: RetakeError.self, "an edit that can't be read isn't guessed at") { try TakeStore.unused(for: DeviceType.allCases, in: project) }
    }

    @Test func anEarlierRetakesNumberedTakesAreRefusedNamingTheWayOutWhichCleanTakes() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("output/takes/ipad/walk/1.json", "{}")
        try write("output/takes/ipad/walk/1.mov", "")
        try write("output/takes/ipad/walk/.last-take", "1\n")
        try TakeStore.refuseOldLayout(for: [.iphone], in: project)
        let error = #expect(throws: RetakeError.self) { try TakeStore.refuseOldLayout(for: [.ipad], in: project) }
        #expect(error?.message == "output/takes/ipad/walk/ holds numbered takes from an earlier Retake, which this one doesn't read. Delete it with `retake clean --takes walk`, or remove the folder, and record the scene again.")
        #expect(throws: RetakeError.self) { try RecordRun.scenes(named: [], edit: nil, force: false, for: .ipad, in: project) }
        #expect(throws: RetakeError.self) { try TakeStore.unused(for: [.ipad], in: project) }

        let cleaning = try TakeStore.cleaning(takes: ["walk"], cuts: nil, for: DeviceType.allCases, in: project)
        #expect(cleaning.takes.isEmpty && cleaning.oldTakes.map(\.lastPathComponent) == ["walk"])
        try TakeStore.delete(cleaning, in: project)
        try TakeStore.refuseOldLayout(for: [.ipad], in: project)
    }
}
