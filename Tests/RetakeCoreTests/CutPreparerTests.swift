import Foundation
@testable import RetakeCore
import Testing

/// Turning an edit's times in seconds into anchors in its scenes' latest takes.
struct CutPreparerTests {
    let root: URL
    let project: Project

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RetakeCutPreparerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        project = Project(configuration: root.appending(path: "retake.json"))
        try write("retake.json", "{}")
        try write("sets/base.json", "{}")
        try write("scenes/ipad/walk.json", #"{"set": "base", "steps": [{"tap": {"label": "a"}, "id": "a"}, {"waitFor": {"label": "b"}, "id": "b"}]}"#)
    }

    func write(_ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Take `number` of walk: `a` at 1–1.5 s, `b` at 2–3 s, `duration` long.
    func record(_ number: Int, duration: Double = 6, failure: String? = nil) throws {
        var log = TakeTimelineTests.timeline().log
        log.scene = "walk"
        log.take = number
        log.failure = failure
        log.duration = duration
        log.steps = Array(log.steps.prefix(2))
        try write("output/takes/ipad/walk/\(number).json", JSONWriter.write(log.json))
        try write("output/takes/ipad/walk/\(number).mov", "")
    }

    @Test func anEditThatNamesItsTakesIsRefused() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record(1)
        try write("edits/video.json", #"{"devices": ["ipad"], "takes": {"ipad": {"walk": 1}}, "clips": [{"take": "walk", "from": {"step": "a"}, "to": {"step": "b"}}]}"#)
        let error = #expect(throws: RetakeError.self) { try CutPreparer.prepare("video", in: project) }
        #expect(error?.message.contains("an edit doesn't name its takes") == true)
    }

    @Test func secondsBecomeAnchorsInTheLatestSuccessfulTake() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record(1)
        try record(2)
        try record(3, failure: "step 2 didn't run")
        try write("edits/video.json", #"{"devices": ["ipad"], "clips": [{"take": "walk", "from": 2.25, "to": 3}]}"#)

        let result = try CutPreparer.prepare("video", in: project)

        #expect(result.text == """
            {
              "devices": ["ipad"],
              "clips": [
                {
                  "take": "walk",
                  "from": { "step": "b", "offset": 0.25, "edge": "start" },
                  "to": { "step": "b", "offset": 1, "edge": "start" }
                }
              ]
            }

            """)
        #expect(result.changes == [
            #"clips[0].from: 2.25 s into walk take 2 (ipad) becomes { "step": "b", "offset": 0.25, "edge": "start" }"#,
            #"clips[0].to: 3 s into walk take 2 (ipad) becomes { "step": "b", "offset": 1, "edge": "start" }"#,
        ], "the failed take 3 isn't the latest successful one")
    }

    @Test func theStillsTimesInSecondsBecomeAnchorsToo() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record(1)
        try write("edits/video.json", #"{"devices": ["ipad"], "clips": [{"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}, "stillsIn": 2.25, "stillsOut": 4, "stills": [{"take": "walk", "at": 1}]}]}"#)
        let edit = try #require(EditFile.read(try CutPreparer.prepare("video", in: project).text, with: JSONReader(file: "video.json"))?.videos[.ipad])
        #expect(edit.clips[0].stillsIn == .step(.init(step: .id("b"), offset: 0.25, edge: .start)))
        #expect(edit.clips[0].stillsOut == .step(.init(step: .id("b"), offset: 2, edge: .start)))
    }

    @Test func aCaptionsTimeThatsItsDefaultMomentIsDroppedRatherThanAnchored() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record(1)
        // The first clip plays 1–3 s; the next fades in over its last 0.5 s, so its caption, unless
        // told, is up from 1 s, and goes at 2.5 s.
        try write("edits/video.json", #"""
            {"devices": ["ipad"], "clips": [
              {"take": "walk", "from": {"step": "a"}, "to": {"step": "b", "offset": 1, "edge": "start"},
               "captions": [{"text": "Default", "y": 0.1, "color": "#000000", "from": 1, "to": 2.5}, {"text": "Own", "y": 0.2, "color": "#000000", "to": 2}]},
              {"take": "walk", "from": {"step": "b"}, "to": {"step": "end"}, "crossfade": 0.5}
            ]}
            """#)
        let result = try CutPreparer.prepare("video", in: project)
        let edit = try #require(EditFile.read(result.text, with: JSONReader(file: "video.json"))?.videos[.ipad])
        #expect(edit.clips[0].captions[0].from == nil && edit.clips[0].captions[0].to == nil)
        #expect(edit.clips[0].captions[1].to?.anchor == .step(.init(step: .id("b"))), "a moment of its own is anchored: b starts at 2 s")
        #expect(result.changes.contains("clips[0].captions[0].to: 2.5 s into walk take 1 is when the caption ends anyway; it's dropped"), "\(result.changes)")
    }

    @Test func anEditWhoseTimesAreAnchorsHasNoChanges() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record(1)
        try write("edits/video.json", #"{"devices": ["ipad"], "clips": [{"take": "walk", "from": {"step": "a"}, "to": {"step": "b"}}]}"#)
        #expect(try CutPreparer.prepare("video", in: project).changes.isEmpty)
    }

    @Test func onlyRetakesOwnSchemaIsBroughtUpToDate() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record(1)
        func prepared(_ schema: String) throws -> JSONValue? {
            try write("edits/video.json", #"{"$schema": "\#(schema)", "devices": ["ipad"], "clips": [{"take": "walk", "from": {"step": "a"}, "to": {"step": "b"}}]}"#)
            return try JSONParser.parse(CutPreparer.prepare("video", in: project).text)[path: "$schema"]
        }
        let old = SchemaReference(version: "0.0.0", kind: "edit").url
        #expect(try prepared(old) == .string(SchemaReference.current("edit").url))
        #expect(try prepared("schemas/edit.json") == .string("schemas/edit.json"), "a project's own copy is left as it is")
    }

    @Test func nothingIsRewrittenWithoutATakeOrWithAnAnchorTheNewTakeCantHold() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("edits/video.json", #"{"devices": ["ipad"], "clips": [{"take": "walk", "from": 1, "to": {"step": "b", "offset": 2.5}}]}"#)
        #expect(throws: RetakeError.self) { try CutPreparer.prepare("video", in: project) }
        try record(1, duration: 4)
        do {
            _ = try CutPreparer.prepare("video", in: project)
            Issue.record("rewritten onto a take too short for it")
        } catch {
            #expect(error.message == "In the new takes, nothing was written:\nclips[0].to (ipad): is 5.5 s into the take, outside it: it's 4 s long")
        }
    }
}
