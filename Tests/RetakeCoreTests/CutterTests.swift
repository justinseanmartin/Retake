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
    func record(
        _ scene: String, _ number: Int, for type: DeviceType = .ipad,
        failure: String? = nil, screen: CGSize = CGSize(width: 834, height: 1194),
    ) throws {
        var log = TakeTimelineTests.timeline().log
        log.scene = scene
        log.take = number
        log.failure = failure
        log.screen = screen
        log.steps = Array(log.steps.prefix(2))
        try write("output/takes/\(type.rawValue)/\(scene)/\(number).json", JSONWriter.write(log.json))
        try write("output/takes/\(type.rawValue)/\(scene)/\(number).mov", "")
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

    @Test func aTakeNotRecordedOrFailedIsntCut() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try edit("")
        #expect(await failure() == "There's no successful ipad take of walk to pin; record it.")
        try edit(#""walk": 1"#)
        #expect(await failure() == "There's no successful ipad take of walk to pin; record it.")
        try record("walk", 1, failure: "step 2 didn't run")
        #expect(await failure() == "There's no successful ipad take of walk to pin; record it.")
    }

    @Test func anUnpinnedSuccessfulTakeIsSelectedBeforeCutting() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record("walk", 1)
        try edit("")
        #expect(await failure() == "video's ipad video is 5 s long; App Store Connect takes 15 to 30 s.")
        let text = try String(contentsOf: root.appending(path: "edits/video.json"), encoding: .utf8)
        let json = try JSONParser.parse(text)
        #expect(json[path: "takes"]?[path: "ipad"]?[path: "walk"] == .number(1))
    }

    @Test func everyTypeCanBePreparedBeforeAnyIsRendered() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let scene = #"{"set": "base", "steps": [{"tap": {"label": "a"}, "id": "a"}, {"waitFor": {"label": "b"}, "id": "b"}]}"#
        try write("scenes/iphone/walk.json", scene)
        try record("walk", 1, for: .iphone)
        try record("walk", 1, for: .ipad)
        try write("edits/video.json", #"{"devices": ["iphone", "ipad"], "clips": [{"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}}]}"#)

        try Cutter.prepare("video", for: .iphone, in: project)
        try Cutter.prepare("video", for: .ipad, in: project)
        let prepared = try String(contentsOf: root.appending(path: "edits/video.json"), encoding: .utf8)
        try Cutter.prepare("video", for: .iphone, in: project)
        try Cutter.prepare("video", for: .ipad, in: project)

        #expect(try String(contentsOf: root.appending(path: "edits/video.json"), encoding: .utf8) == prepared)
        let json = try JSONParser.parse(prepared)
        #expect(json[path: "takes"]?[path: "iphone"]?[path: "walk"] == .number(1))
        #expect(json[path: "takes"]?[path: "ipad"]?[path: "walk"] == .number(1))
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
