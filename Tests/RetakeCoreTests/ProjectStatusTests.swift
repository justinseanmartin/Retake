import Foundation
@testable import RetakeCore
import Testing

/// What `status` reports of scenes, edits and videos.
struct ProjectStatusTests {
    let tests: CutterTests

    init() throws {
        tests = try CutterTests()
    }

    /// The status, each video's record saying it was cut from takes of `cutFrom` recorded at those times.
    func status(cutFrom takes: [(String, Date)] = []) async -> ProjectStatus {
        var video = MovieMetadata.Video(edit: "video", type: .ipad, bundleID: "com.example.notes", takes: [])
        video.takes = takes.map { var log = TakeLogReadingTests.log(scene: $0.0); log.recordedAt = $0.1; return log }
        let info = MovieInfo.video(video.json)
        return await ProjectStatus.of(tests.project) { _ throws(RetakeError) in info }
    }

    func age(_ path: String, by seconds: Double) throws {
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-seconds)], ofItemAtPath: tests.root.appending(path: path).path)
    }

    @Test func eachScenesTakeAndFailureAndTheTakeEachEditIsCutFrom() async throws {
        defer { try? FileManager.default.removeItem(at: tests.root) }
        let recorded = Date(timeIntervalSince1970: 1_800_000_000)
        try tests.record("walk", recordedAt: recorded)
        try tests.record("walk", failure: "step 2 didn't run")
        try tests.edit(clips: #"{"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}}, {"take": "other", "from": {"step": "a"}, "to": {"step": "end"}}"#)
        let status = await status()
        let section = try #require(status.sections.first)
        #expect(status.sections.map(\.type) == [.ipad])
        #expect(section.scenes.map(\.name) == ["other", "walk"] && section.scenes.map { $0.take != nil } == [false, true])
        #expect(section.scenes[1].failed?.recorded?.failure == "step 2 didn't run" && section.scenes[1].previous == nil)
        let uses = try #require(section.edits.first?.uses)
        #expect(uses.map(\.scene) == ["walk", "other"])
        #expect(uses.map(\.recordedAt) == [recorded, nil], "a failure isn't cut from")
    }

    @Test func aVideoIsOutOfDateWhenItsEditChangesOrItsTakeIsntTheOneItWasCutFrom() async throws {
        defer { try? FileManager.default.removeItem(at: tests.root) }
        let first = Date(timeIntervalSince1970: 1_800_000_000), second = first.addingTimeInterval(60)
        try tests.record("walk", recordedAt: first)
        try tests.edit()
        try tests.write("output/cuts/ipad/video/video-ipad.mp4", "")
        try age("edits/video.json", by: 60)
        func changes(cutFrom recorded: Date) async throws -> [String] {
            try #require(await status(cutFrom: [("walk", recorded)]).sections.first?.videos.first).changes
        }
        #expect(try await changes(cutFrom: first) == [])
        #expect(try await changes(cutFrom: first.addingTimeInterval(0.5)) == [], "a log gives its time to the second")

        try tests.record("walk", recordedAt: second)
        #expect(try await changes(cutFrom: first) == ["walk has been recorded again"])
        #expect(try await changes(cutFrom: second.addingTimeInterval(60)) == ["walk's take isn't the one it was cut from"], "such as a previous one put back")

        let video = try #require(await status(cutFrom: [("walk", second)]).sections.first?.videos.first)
        #expect(video.changes == [] && video.edit == "video" && !video.draft)

        try FileManager.default.removeItem(at: tests.root.appending(path: "output/takes/ipad/walk.json"))
        #expect(try await changes(cutFrom: second) == ["walk has no successful take now"])
        try FileManager.default.removeItem(at: tests.root.appending(path: "edits/video.json"))
        #expect(try await changes(cutFrom: second) == ["its edit is gone"])
    }

    @Test func aVideoCutFromNumberedTakesSaysItsRecordCantTell() async throws {
        defer { try? FileManager.default.removeItem(at: tests.root) }
        try tests.record("walk")
        try tests.edit()
        try tests.write("output/cuts/ipad/video/video-ipad.mp4", "")
        try age("edits/video.json", by: 60)
        let record = #"{"edit": "video", "retake": {"version": "0.0.1"}, "takes": [{"scene": "walk", "take": 2}]}"#
        let status = await ProjectStatus.of(tests.project) { _ throws(RetakeError) in .video(try! JSONParser.parse(record)) }
        #expect(status.sections.first?.videos.first?.changes == ["its record doesn't say when walk's take was recorded, as an earlier Retake cut it"])
    }
}
