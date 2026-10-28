import Foundation
@testable import RetakeCore
import Testing

/// What `cut` checks before it renders anything.
struct CutterTests {
    let root: URL
    let project: Project

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RetakeCutterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        project = Project(configuration: root.appending(path: "retake.json"))
        try write("retake.json", "{}")
        try write("sets/base.json", "{}")
        let scene = #"{"set": "base", "steps": [{"tap": {"label": "a"}, "id": "a"}, {"waitFor": {"label": "b"}, "id": "b"}]}"#
        try write("scenes/ipad/walk.json", scene)
        try write("scenes/ipad/other.json", scene)
    }

    func write(_ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// A take of `scene` as `TakeTimelineTests` lays it out, 6 s long.
    func record(_ scene: String, _ number: Int, failure: String? = nil, screen: CGSize = CGSize(width: 834, height: 1194)) throws {
        var log = TakeTimelineTests.timeline().log
        log.scene = scene
        log.take = number
        log.failure = failure
        log.screen = screen
        log.steps = Array(log.steps.prefix(2))
        try write("output/takes/ipad/\(scene)/\(number).json", JSONWriter.write(log.json))
        try write("output/takes/ipad/\(scene)/\(number).mov", "")
    }

    func edit(_ pins: String, clips: String = #"{"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}}"#) throws {
        try write("edits/video.json", #"{"devices": ["ipad"], "takes": {"ipad": {\#(pins)}}, "clips": [\#(clips)]}"#)
    }

    func failure(draft: Bool = false) async -> String? {
        do {
            _ = try await Cutter.cut("video", for: .ipad, in: project, draft: draft)
            return nil
        } catch {
            return error.message
        }
    }

    @Test func aTakeNotPinnedNotRecordedOrFailedIsntCut() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try edit("")
        #expect(await failure() == "video pins no ipad take of walk; run `retake conform video`.")
        try edit(#""walk": 1"#)
        #expect(await failure() == "Take 1 of walk, which video pins for ipad, isn't recorded; record it, or conform the edit.")
        try record("walk", 1, failure: "step 2 didn't run")
        #expect(await failure() == "Take 1 of walk for ipad failed (step 2 didn't run), so it can't be cut from.")
    }

    @Test func takesFromDifferentScreensArentCutTogether() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record("walk", 1)
        try record("other", 1, screen: CGSize(width: 820, height: 1180))
        try edit(#""walk": 1, "other": 1"#, clips: #"{"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}}, {"take": "other", "from": {"step": "a"}, "to": {"step": "end"}}"#)
        #expect(await failure() == "video's ipad takes come from devices with different screens: 820×1180 points: other take 1; 834×1194 points: walk take 1.")
    }

    @Test func aVideoOutsideAppStoreConnectsLengthsIsntCutButADraftIs() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record("walk", 1)
        try edit(#""walk": 1"#)
        #expect(await failure() == "video's ipad video is 5 s long; App Store Connect takes 15 to 30 s.")
        // A draft only warns, and goes on to compose, which fails here on the take's empty movie.
        #expect(await failure(draft: true)?.contains("App Store Connect") == false)
    }
}
