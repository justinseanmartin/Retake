import Foundation
import RetakeCore
import Testing

struct ProjectValidatorTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RetakeValidateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        for folder in ["sets", "scenes/iphone", "scenes/ipad", "edits", "data", "audio"] {
            try FileManager.default.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        }
        try write("retake.json", "{}")
        try write("sets/base.json", "{}")
        try write("data/notes.json", "[]")
        try write("audio/pop.m4a", "")
        let scene = #"{"set": "base", "steps": [{"id": "open", "tap": {"label": "a"}}, {"id": "done", "waitFor": {"label": "b"}}]}"#
        try write("scenes/iphone/walk.json", scene)
        try write("scenes/ipad/walk.json", scene)
    }

    func write(_ path: String, _ text: String) throws {
        try Data(text.utf8).write(to: root.appending(path: path))
    }

    func validate(_ targets: [ProjectValidator.Target]? = nil) throws -> [String] {
        let project = try Project.locate(configuration: nil, currentDirectory: root)
        return ProjectValidator(files: ProjectFiles(project: project)).validate(targets).problems.map(\.description)
    }

    func edit(_ clips: String, devices: String = #"["iphone", "ipad"]"#) throws {
        try write("edits/video.json", #"{"devices": \#(devices), "clips": [\#(clips)]}"#)
    }

    @Test func aSoundProjectHasNoProblems() throws {
        try write("sets/top.json", #"{"extends": "base", "files": {"Documents/notes.json": "data/notes.json"}}"#)
        try edit(#"{"take": "walk", "from": {"step": "open"}, "to": {"step": 2, "offset": 0.5, "edge": "end"}, "sounds": [{"file": "audio/pop.m4a", "at": {"step": -1}}]}"#)
        #expect(try validate() == [])
    }

    @Test func everyFilesOwnProblemsAreReported() throws {
        try write("sets/broken.json", #"{"state": "fresh"}"#)
        try write("scenes/ipad/bad.json", #"{"steps": [{"tapp": {}}]}"#)
        #expect(try validate() == [
            #"sets/broken.json: state: "fresh" isn't one of clean, cloned or live"#,
            #"scenes/ipad/bad.json: steps[0]: unknown key "tapp"; did you mean "tap"?"#,
        ])
    }

    @Test func namesThatMustExist() throws {
        try write("retake.json", #"{"defaultSet": "nowhere"}"#)
        try write("sets/top.json", #"{"extends": "missing", "files": {"Documents/a.json": "data/absent.json", "Documents/m/": "data/notes.json/"}}"#)
        try write("scenes/iphone/orphan.json", #"{"set": "gone", "steps": [{"hold": 1}]}"#)
        try write("scenes/ipad/loose.json", #"{"steps": [{"hold": 1}]}"#)
        #expect(Set(try validate()) == [
            #"retake.json: defaultSet: there's no set "nowhere" (sets/nowhere.json)"#,
            #"sets/top.json: extends: there's no set "missing" (sets/missing.json)"#,
            #"sets/top.json: files["Documents/a.json"]: "data/absent.json" doesn't exist"#,
            #"sets/top.json: files["Documents/m/"]: "data/notes.json/" is a file, not a folder"#,
            #"scenes/iphone/orphan.json: set: there's no set "gone" (sets/gone.json)"#,
        ], "a scene with no set uses defaultSet, which is reported once, on retake.json")
    }

    @Test func aSetMayUseAFileOutsideTheProject() throws {
        let external = root.deletingLastPathComponent().appending(path: "\(root.lastPathComponent)-fixture.json")
        defer { try? FileManager.default.removeItem(at: external) }
        try Data("[]".utf8).write(to: external)
        try write("sets/top.json", #"{"files": {"Documents/a.json": "../\#(external.lastPathComponent)"}}"#)
        #expect(try validate([.set("top")]) == [])
    }

    @Test func aSceneWithNoSetNeedsADefaultSet() throws {
        try write("scenes/ipad/loose.json", #"{"steps": [{"hold": 1}]}"#)
        #expect(try validate() == ["scenes/ipad/loose.json: names no set, and retake.json has no defaultSet"])
    }

    @Test func anEditsScenesFilesAndAnchorsMustExist() throws {
        try edit(#"""
            {"take": "walk", "from": {"step": "opne"}, "to": {"step": 3}, "sounds": [{"file": "audio/missing.m4a", "at": {"step": "done"}}],
             "stills": [{"take": "elsewhere", "at": 1}]},
            {"take": "unrecorded", "from": 0, "to": 1}
            """#)
        #expect(try validate() == [
            #"edits/video.json: clips[0].from.step: scenes/iphone/walk.json has no step "opne""#,
            "edits/video.json: clips[0].to.step: scenes/iphone/walk.json has 2 steps, so there's no step 3",
            #"edits/video.json: clips[0].sounds[0].file: "audio/missing.m4a" doesn't exist in the project"#,
            #"edits/video.json: clips[0].stills[0].take: there's no scene "elsewhere" for iphone (scenes/iphone/elsewhere.json)"#,
            #"edits/video.json: clips[1].take: there's no scene "unrecorded" for iphone (scenes/iphone/unrecorded.json)"#,
            #"edits/video.json: clips[0].from.step: scenes/ipad/walk.json has no step "opne""#,
            "edits/video.json: clips[0].to.step: scenes/ipad/walk.json has 2 steps, so there's no step 3",
            #"edits/video.json: clips[0].stills[0].take: there's no scene "elsewhere" for ipad (scenes/ipad/elsewhere.json)"#,
            #"edits/video.json: clips[1].take: there's no scene "unrecorded" for ipad (scenes/ipad/unrecorded.json)"#,
        ])
    }

    @Test func anOverridesAnchorIsNamedWhereItsWritten() throws {
        try edit(#"{"take": "walk", "from": {"step": "open"}, "to": {"step": "done"}, "ipad": {"to": {"step": "dnoe"}}}"#)
        #expect(try validate() == [#"edits/video.json: clips[0].ipad.to.step: scenes/ipad/walk.json has no step "dnoe""#])
    }

    @Test func aCaptionRunningOnIsCheckedInTheLaterClipsScene() throws {
        try write("scenes/iphone/other.json", #"{"set": "base", "steps": [{"id": "only", "hold": 1}]}"#)
        try edit(#"""
            {"take": "walk", "from": 0, "to": 1, "captions": [{"text": "a", "y": 0.1, "color": "#000000", "to": {"clip": "next", "step": "open"}}]},
            {"id": "next", "take": "other", "from": 0, "to": 1}
            """#, devices: #"["iphone"]"#)
        #expect(try validate() == [#"edits/video.json: clips[0].captions[0].to.step: scenes/iphone/other.json has no step "open""#])
    }

    @Test func deviceOnlyStepIDsNeedNotMatch() throws {
        try write("scenes/ipad/walk.json", #"{"set": "base", "steps": [{"id": "open", "tap": {"label": "a"}}, {"id": "finish", "hold": 1}]}"#)
        try edit(#"{"take": "walk", "from": 0, "to": 1}"#)
        #expect(try validate() == [])
    }

    @Test func aReferencedStepIDMustExistForEachDevice() throws {
        try write("scenes/ipad/walk.json", #"{"set": "base", "steps": [{"id": "open", "tap": {"label": "a"}}, {"id": "finish", "hold": 1}]}"#)
        try edit(#"{"take": "walk", "from": {"step": "open"}, "to": {"step": "done"}}"#)
        #expect(try validate() == [#"edits/video.json: clips[0].to.step: scenes/ipad/walk.json has no step "done""#])
    }

    @Test func onlyTheNamedFilesAreReported() throws {
        try write("sets/broken.json", #"{"state": "fresh"}"#)
        try write("scenes/iphone/orphan.json", #"{"set": "gone", "steps": [{"hold": 1}]}"#)
        #expect(try validate([.scene("orphan", .iphone)]) == [#"scenes/iphone/orphan.json: set: there's no set "gone" (sets/gone.json)"#])
        #expect(try validate([.scene("walk", .ipad)]) == [])
    }

    @Test func filesAreRecognisedByWhereTheyAre() throws {
        let validator = ProjectValidator(files: ProjectFiles(project: try Project.locate(configuration: nil, currentDirectory: root)))
        #expect(validator.target(for: root.appending(path: "retake.json")) == .configuration)
        #expect(validator.target(for: root.appending(path: "sets/base.json")) == .set("base"))
        #expect(validator.target(for: root.appending(path: "scenes/ipad/walk.json")) == .scene("walk", .ipad))
        #expect(validator.target(for: root.appending(path: "edits/video.json")) == .edit("video"))
        #expect(validator.target(for: root.appending(path: "data/notes.json")) == nil)
    }

    // MARK: Folders named in another case

    /// Renames a folder to another case, in two moves, as a case-insensitive volume needs.
    func rename(_ path: String, to other: String) throws {
        let aside = root.appending(path: "\(path)-aside")
        try FileManager.default.moveItem(at: root.appending(path: path), to: aside)
        try FileManager.default.moveItem(at: aside, to: root.appending(path: other))
    }

    @Test func aFolderListedInAnotherCaseIsReportedThoughItsFound() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try edit(#"{"take": "walk", "from": {"step": "open"}, "to": {"step": "done"}}"#)
        try rename("edits", to: "Edits")
        try rename("scenes/ipad", to: "scenes/iPad")
        // The tests' volume is case-insensitive, so both are still found; only their listing differs.
        #expect(try validate() == [
            "scenes/iPad/: should be named scenes/ipad/; Retake's folders are lowercase",
            "Edits/: should be named edits/; Retake's folders are lowercase",
        ])
        #expect(try validate([.scene("walk", .iphone)]) == [], "only the named files' folders are checked")
    }

    @Test func aFileMissingFromAFolderInAnotherCaseSaysWhy() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try rename("scenes", to: "Scenes")
        let files = ProjectFiles(project: try Project.locate(configuration: nil, currentDirectory: root))
        let report = ProjectFiles.Report()
        #expect(files.readScene("absent", for: .iphone, into: report) == nil)
        #expect(report.problems.map(\.description) == [
            "scenes/iphone/absent.json: doesn't exist: Scenes/ should be named scenes/; Retake's folders are lowercase",
        ])
    }

    @Test func aCaseSensitiveCloneWithOnlyTheOtherCaseSaysWhyItsEmpty() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        // A clone keeping `Edits/`: there's no `edits/` to stat, and the root lists `Edits`.
        try FileManager.default.removeItem(at: root.appending(path: "edits"))
        let project = try Project.locate(configuration: nil, currentDirectory: root)
        let files = ProjectFiles(project: project) { folder in
            let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
            return folder.standardizedFileURL.path == project.root.path ? (names ?? []) + ["Edits"] : names
        }
        #expect(ProjectValidator(files: files).validate().problems.map(\.description) == [
            "Edits/: should be named edits/; Retake's folders are lowercase",
        ])
        #expect(files.whyMissing(files.editURL("video1")) == ": Edits/ should be named edits/; Retake's folders are lowercase")
        #expect(files.misnamedFolder(project.sets) == nil)
    }

    // MARK: Against the takes

    func validateWithTakes() throws -> (problems: [String], warnings: [String]) {
        let project = try Project.locate(configuration: nil, currentDirectory: root)
        let report = ProjectValidator(files: ProjectFiles(project: project), offline: false).validate()
        return (report.problems.map(\.description), report.warnings.map(\.description))
    }

    /// The take of `walk` for iPad, as `TakeTimelineTests` lays it out: `a` at 1–1.5 s, `b` at 2–3 s,
    /// 6 s long, its screen read after `b`.
    func recordWalk(failure: String? = nil) throws {
        var log = TakeTimelineTests.timeline().log
        log.scene = "walk"
        log.failure = failure
        log.steps = log.steps.prefix(2).map { var step = $0; step.id = step.id == "a" ? "open" : "done"; return step }
        try FileManager.default.createDirectory(at: root.appending(path: "output/takes/ipad"), withIntermediateDirectories: true)
        try write("output/takes/ipad/walk.json", JSONWriter.write(log.json))
        try write("output/takes/ipad/walk.mov", "")
    }

    @Test func anchorsAndElementsAreCheckedInTheLatestSuccessfulTake() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try recordWalk()
        try write("edits/video.json", #"""
            {"devices": ["ipad"], "clips": [
              {"take": "walk", "from": {"step": "open"}, "to": {"step": "done", "offset": 9, "edge": "end"},
               "captions": [{"text": "a", "y": 0.1, "color": "#000000", "from": {"step": "start"}}]},
              {"take": "walk", "from": {"step": "done"}, "to": {"step": "open"}},
              {"take": "walk", "from": {"step": "open"}, "to": {"step": "end"},
               "spotlight": {"element": {"label": "Share"}, "from": {"step": "done", "offset": 0.1, "edge": "end"}},
               "blurs": [{"element": {"label": "Send"}, "from": {"step": "done", "offset": 0.1, "edge": "end"}}]}
            ]}
            """#)
        let (problems, warnings) = try validateWithTakes()
        #expect(problems == [
            "edits/video.json: clips[0].to: is 12 s into the take, outside it: it's 6 s long",
            "edits/video.json: clips[1].to: is 1 s into the take, not after from, at 2 s",
            #"edits/video.json: clips[2].blurs[0].element: "Send" isn't on screen after step 2, at 3 s"#,
        ])
        #expect(warnings.isEmpty)
        #expect(try validate().isEmpty, "--offline checks none of it")
    }

    @Test func stillsInIsWithinItsClipAndBeforeStillsOut() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try recordWalk()
        try write("edits/video.json", #"""
            {"devices": ["ipad"], "clips": [
              {"take": "walk", "from": {"step": "open"}, "to": {"step": "done"}, "stillsIn": {"step": "done", "offset": 1, "edge": "end"}, "stills": [{"take": "walk", "at": 1}]},
              {"take": "walk", "from": {"step": "open"}, "to": {"step": "end"}, "stillsIn": {"step": "done"}, "stillsOut": {"step": "open"}, "stills": [{"take": "walk", "at": 1}]},
              {"take": "walk", "from": {"step": "open"}, "to": {"step": "end"}, "stillsIn": {"step": "open"}, "stillsOut": {"step": "done"}, "stills": [{"take": "walk", "at": 1}]}
            ]}
            """#)
        #expect(try validateWithTakes().problems == [
            "edits/video.json: clips[0].stillsIn: is 4 s into the take, outside the stretch its clip plays, 1 s to 2 s",
            "edits/video.json: clips[1].stillsIn: is 2 s into the take, not before stillsOut, at 1 s; the stills pop in before they pop out",
        ])
    }

    @Test func noSuccessfulTakeOnlyWarns() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try edit(#"{"take": "walk", "from": {"step": "open"}, "to": {"step": "done"}}"#, devices: #"["ipad"]"#)
        var (problems, warnings) = try validateWithTakes()
        #expect(problems.isEmpty)
        #expect(warnings == ["edits/video.json: clips[0].take: there's no successful ipad take of walk, so what's cut from it isn't checked; record it"])

        try recordWalk(failure: "step 2 didn't run")
        try write("edits/video.json", #"{"devices": ["ipad"], "clips": [{"take": "walk", "from": {"step": "open"}, "to": {"step": "done"}}]}"#)
        (problems, warnings) = try validateWithTakes()
        #expect(problems.isEmpty)
        #expect(warnings == ["edits/video.json: clips[0].take: there's no successful ipad take of walk, so what's cut from it isn't checked; record it"])
    }
}
