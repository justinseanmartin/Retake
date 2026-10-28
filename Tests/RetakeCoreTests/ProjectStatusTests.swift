import Foundation
@testable import RetakeCore
import Testing

/// What `status` reports of scenes, edits and videos.
struct ProjectStatusTests {
    let tests: CutterTests

    init() throws {
        tests = try CutterTests()
    }

    /// The status, each video's record saying it was cut from `cutFrom`.
    func status(cutFrom takes: [(String, Int)] = []) async -> ProjectStatus {
        var video = MovieMetadata.Video(edit: "video", type: .ipad, bundleID: "com.example.notes", takes: [])
        video.takes = takes.map { TakeLogReadingTests.log(scene: $0.0, take: $0.1) }
        let info = MovieInfo.video(video.json)
        return await ProjectStatus.of(tests.project) { _ throws(RetakeError) in info }
    }

    func age(_ path: String, by seconds: Double) throws {
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-seconds)], ofItemAtPath: tests.root.appending(path: path).path)
    }

    @Test func eachScenesLatestTakeAndEachPinsNewerTake() async throws {
        defer { try? FileManager.default.removeItem(at: tests.root) }
        try tests.record("walk", 1)
        try tests.record("walk", 2)
        try tests.record("walk", 3, failure: "step 2 didn't run")
        try tests.edit(#""walk": 1, "other": 1"#)
        let status = await status()
        let section = try #require(status.sections.first)
        #expect(status.sections.map(\.type) == [.ipad])
        #expect(section.scenes.map(\.name) == ["other", "walk"] && section.scenes.map(\.latest?.number) == [nil, 3])
        let pins = try #require(section.edits.first?.pins)
        #expect(pins.map(\.scene) == ["walk", "other"])
        #expect(pins[0].newer == 2 && pins[0].problem == nil, "a failed take isn't one to move to")
        #expect(pins[1].newer == nil && pins[1].problem == "isn't recorded")
    }

    @Test func aVideoIsOutOfDateWhenItsEditOrPinsChangeOrATakeIsRecordedAgain() async throws {
        defer { try? FileManager.default.removeItem(at: tests.root) }
        try tests.record("walk", 1)
        try tests.edit(#""walk": 1"#)
        try tests.write("output/cuts/ipad/video/video-ipad.mp4", "")
        try age("edits/video.json", by: 60)
        try age("output/takes/ipad/walk/1.json", by: 60)
        #expect(try await #require(status(cutFrom: [("walk", 1)]).sections.first?.videos.first).changes == [])

        try tests.record("walk", 1)
        #expect(try await #require(status(cutFrom: [("walk", 1)]).sections.first?.videos.first).changes == ["walk@1 has been recorded again"])

        try tests.record("walk", 2)
        try tests.edit(#""walk": 2"#)
        let video = try #require(await status(cutFrom: [("walk", 1)]).sections.first?.videos.first)
        #expect(video.changes == ["its edit has changed", "walk is pinned to take 2 now, not 1"])
        #expect(video.edit == "video" && !video.draft)

        try FileManager.default.removeItem(at: tests.root.appending(path: "edits/video.json"))
        #expect(try await #require(status(cutFrom: [("walk", 1)]).sections.first?.videos.first).changes == ["its edit is gone"])
    }
}
