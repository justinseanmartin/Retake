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

    /// A take of `scene` as `TakeTimelineTests` lays it out, 6 s long, recorded at `recordedAt`;
    /// one with a `failure` is kept as the scene's failure.
    func record(
        _ scene: String, for type: DeviceType = .ipad, failure: String? = nil,
        screen: CGSize = CGSize(width: 834, height: 1194), recordedAt: Date? = nil,
    ) throws {
        var log = TakeTimelineTests.timeline().log
        log.scene = scene
        log.failure = failure
        log.screen = screen
        if let recordedAt { log.recordedAt = recordedAt }
        log.steps = Array(log.steps.prefix(2))
        let name = "output/takes/\(type.rawValue)/\(scene)\(failure == nil ? "" : ".failed")"
        try write("\(name).json", JSONWriter.write(log.json))
        try write("\(name).mov", "")
    }

    func edit(clips: String = #"{"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}}"#) throws {
        try write("edits/video.json", #"{"devices": ["ipad"], "clips": [\#(clips)]}"#)
    }

    func failure() async -> String? {
        do {
            _ = try await Cutter.cut("video", for: .ipad, in: project)
            return nil
        } catch {
            return error.message
        }
    }

    @Test func aTakeNotRecordedOrFailedIsntCut() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try edit()
        #expect(await failure() == "There's no successful ipad take of walk for video to be cut from; record it.")
        try record("walk", failure: "step 2 didn't run")
        #expect(await failure() == "There's no successful ipad take of walk for video to be cut from; record it.")
    }

    @Test func aTakeANewerRetakeRecordedIsntCutAndSaysSo() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try edit()
        try write("output/takes/ipad/walk.json", TakeLogReadingTests.text { $0.insert(.init(key: "format", value: 2), at: 0) })
        try write("output/takes/ipad/walk.mov", "")
        #expect(await failure() == "There's no successful ipad take of walk for video to be cut from: output/takes/ipad/walk.json: was recorded by a newer Retake, in step log format 2, which this Retake (\(RetakeVersion.current.version)) can't read; update Retake to use this take.")
    }

    @Test func cuttingLeavesAnEditWhoseTimesAreAnchorsAsItIs() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record("walk")
        try edit()
        let before = try String(contentsOf: root.appending(path: "edits/video.json"), encoding: .utf8)
        #expect(await failure() == "video's ipad video is 5 s long; App Store Connect takes 15 to 30 s.")
        #expect(try String(contentsOf: root.appending(path: "edits/video.json"), encoding: .utf8) == before)
    }

    @Test func everyTypeCanBePreparedBeforeAnyIsRendered() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let scene = #"{"set": "base", "steps": [{"tap": {"label": "a"}, "id": "a"}, {"waitFor": {"label": "b"}, "id": "b"}]}"#
        try write("scenes/iphone/walk.json", scene)
        try record("walk", for: .iphone)
        try record("walk", for: .ipad)
        try write("edits/video.json", #"{"devices": ["iphone", "ipad"], "clips": [{"take": "walk", "from": 1.25, "to": {"step": "end"}}]}"#)

        try Cutter.prepare("video", for: .iphone, in: project)
        try Cutter.prepare("video", for: .ipad, in: project)
        let prepared = try String(contentsOf: root.appending(path: "edits/video.json"), encoding: .utf8)
        try Cutter.prepare("video", for: .iphone, in: project)
        try Cutter.prepare("video", for: .ipad, in: project)

        #expect(try String(contentsOf: root.appending(path: "edits/video.json"), encoding: .utf8) == prepared)
        #expect(prepared.contains(#""from": { "step": "a", "offset": 0.25 }"#), "its time in seconds is an anchor")
    }

    @Test func takesFromDifferentScreensArentCutTogether() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record("walk")
        try record("other", screen: CGSize(width: 820, height: 1180))
        try edit(clips: #"{"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}}, {"take": "other", "from": {"step": "a"}, "to": {"step": "end"}}"#)
        #expect(await failure() == "video's ipad takes come from devices with different screens: 820×1180 points: other; 834×1194 points: walk.")
    }

    @Test func aVideoOutsideAppStoreConnectsLengthsIsntCut() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record("walk")
        try edit()
        #expect(await failure() == "video's ipad video is 5 s long; App Store Connect takes 15 to 30 s.")
    }
}

struct CutLengthTests {
    @Test func devicesVideosOfAnEditDifferingByMoreThanAFrameAreWarnedAbout() {
        #expect(Cutter.lengthMismatch(of: "showcase", [.iphone: 26.533, .ipad: 27]) == "showcase's videos differ in length: iphone 26.53 s, ipad 27 s, 0.47 s apart, so side by side one ends first; lengthen or shorten a clip on one to match.")
        #expect(Cutter.lengthMismatch(of: "showcase", [.iphone: 26.99, .ipad: 27]) == nil, "within a frame")
        #expect(Cutter.lengthMismatch(of: "showcase", [.ipad: 27]) == nil, "only one cut")
    }
}
