import Foundation
@testable import RetakeCore
import Testing

/// Pinning an edit to its scenes' latest takes.
struct CutPreparerTests {
    let root: URL
    let project: Project

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RetakeConformTests-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    @Test func secondsBecomeAnchorsAgainstTheOldTakeAndTheLatestTakeIsPinned() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record(1)
        try record(2)
        try record(3, failure: "step 2 didn't run")
        try write("edits/video.json", """
            {
              "devices": ["ipad"],
              "takes": { "ipad": { "walk": 1 } },
              "clips": [
                { "take": "walk", "from": 0.5, "to": 2.25, "sounds": [{ "file": "pop.m4a", "at": 1 }] }
              ]
            }

            """)
        let result = try CutPreparer.prepare("video", in: project)
        #expect(result.text == """
            {
              "devices": ["ipad"],
              "takes": { "ipad": { "walk": 2 } },
              "clips": [
                {
                  "take": "walk",
                  "from": { "step": "start", "offset": 0.5 },
                  "to": { "step": "b", "offset": 0.25, "edge": "start" },
                  "sounds": [{ "file": "pop.m4a", "at": { "step": "a" } }]
                }
              ]
            }

            """)
        #expect(result.changes == [
            #"clips[0].from: 0.5 s into walk take 1 (ipad) becomes { "step": "start", "offset": 0.5 }"#,
            #"clips[0].to: 2.25 s into walk take 1 (ipad) becomes { "step": "b", "offset": 0.25, "edge": "start" }"#,
            #"clips[0].sounds[0].at: 1 s into walk take 1 (ipad) becomes { "step": "a" }"#,
            "takes.ipad.walk: take 1 becomes take 2",
        ], "the failed take 3 isn't pinned")
    }

    @Test func secondsInANeverPinnedEditUseTheLatestSuccessfulTake() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record(1)
        try record(2)
        try record(3, failure: "step 2 didn't run")
        try write("edits/video.json", #"{"devices": ["ipad"], "clips": [{"take": "walk", "from": 2.25, "to": 3}]}"#)

        let result = try CutPreparer.prepare("video", in: project)

        #expect(result.text == """
            {
              "devices": ["ipad"],
              "takes": { "ipad": { "walk": 2 } },
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
            "takes.ipad.walk: nothing becomes take 2",
        ])
    }

    @Test func anEditAlreadyOnTheLatestTakesHasNoChanges() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record(1)
        try write("edits/video.json", #"{"devices": ["ipad"], "takes": {"ipad": {"walk": 1}}, "clips": [{"take": "walk", "from": {"step": "a"}, "to": {"step": "b"}}]}"#)
        #expect(try CutPreparer.prepare("video", in: project).changes.isEmpty)
    }

    @Test func onlyRetakesOwnSchemaIsBroughtUpToDate() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try record(1)
        func conformed(_ schema: String) throws -> JSONValue? {
            try write("edits/video.json", #"{"$schema": "\#(schema)", "devices": ["ipad"], "clips": [{"take": "walk", "from": {"step": "a"}, "to": {"step": "b"}}]}"#)
            return try JSONParser.parse(CutPreparer.prepare("video", in: project).text)[path: "$schema"]
        }
        let old = SchemaReference(version: "0.0.0", kind: "edit").url
        #expect(try conformed(old) == .string(SchemaReference.current("edit").url))
        #expect(try conformed("schemas/edit.json") == .string("schemas/edit.json"), "a project's own copy is left as it is")
    }

    @Test func nothingIsConformedWithoutATakeOrWithAnAnchorTheNewTakeCantHold() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("edits/video.json", #"{"devices": ["ipad"], "clips": [{"take": "walk", "from": {"step": "a"}, "to": {"step": "b", "offset": 2.5}}]}"#)
        #expect(throws: RetakeError.self) { try CutPreparer.prepare("video", in: project) }
        try record(1, duration: 4)
        do {
            _ = try CutPreparer.prepare("video", in: project)
            Issue.record("conformed onto a take too short for it")
        } catch {
            #expect(error.message == "In the new takes, nothing was written:\nclips[0].to (ipad): is 5.5 s into the take, outside it: it's 4 s long")
        }
    }
}
