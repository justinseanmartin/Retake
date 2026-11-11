import Foundation
import RetakeCore
import Testing

struct ProjectValidatorTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RetakeValidateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        for folder in ["sets", "scenes", "edits", "data", "audio"] {
            try FileManager.default.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        }
        try write("retake.json", "{}")
        try write("sets/base.json", "{}")
        try write("data/notes.json", "[]")
        try write("audio/pop.m4a", "")
        let scene = #"{"set": "base", "steps": [{"id": "open", "tap": {"label": "a"}}, {"id": "done", "waitFor": {"label": "b"}}]}"#
        try write("scenes/walk.json", scene)
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

    @Test func aSceneIsReadForEachTypeWithItsOverridesAndSkipsTheStepsOfOthers() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("scenes/walk.json", #"{"set": "base", "steps": [{"id": "open", "tap": {"label": "a"}, "ipad": {"hold": 2}}, {"id": "turn", "orientation": "landscape-left", "devices": ["ipad"]}, {"id": "done", "waitFor": {"label": "b"}}]}"#)
        let files = ProjectFiles(project: try Project.locate(configuration: nil, currentDirectory: root))
        let report = ProjectFiles.Report()
        #expect(files.readScene("walk", for: .ipad, into: report)?.steps.map(\.hold) == [2, nil, nil], "the ipad override")
        #expect(files.readScene("walk", for: .iphone, into: report)?.steps.map(\.hold) == [nil, nil, nil])
        #expect(files.readScene("walk", for: .iphone, into: report)?.steps.map(\.isSkipped) == [false, true, false], "skipped, but still step 2")
        #expect(report.problems.isEmpty)
        try edit(#"{"take": "walk", "from": {"step": "open"}, "to": {"step": "done"}}"#)
        #expect(try validate() == [])
    }

    @Test func aSceneForOneTypeIsntTheOthers() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("scenes/walk.json", #"{"devices": ["ipad"], "set": "base", "steps": [{"id": "open", "tap": {"label": "a"}}, {"id": "done", "hold": 1}]}"#)
        let files = ProjectFiles(project: try Project.locate(configuration: nil, currentDirectory: root))
        #expect(files.sceneNames(for: .ipad) == ["walk"] && files.sceneNames(for: .iphone) == [])
        try edit(#"{"take": "walk", "from": {"step": "open"}, "to": {"step": "done"}}"#)
        #expect(try validate() == [#"edits/video.json: clips[0].take: scenes/walk.json doesn't play on iphone, which isn't one of its devices"#])
        try edit(#"{"take": "walk", "from": {"step": "open"}, "to": {"step": "done"}}"#, devices: #"["ipad"]"#)
        #expect(try validate() == [])
    }

    @Test func aScenesOverridesAndStepDevicesAreAmongItsDevices() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("scenes/walk.json", #"{"devices": ["iphone"], "set": "base", "ipad": {"tail": 2}, "steps": [{"tap": {"label": "a"}, "devices": ["ipad"]}]}"#)
        #expect(Set(try validate()) == [
            #"scenes/walk.json: ipad: overrides ipad, which isn't one of this scene's devices"#,
            #"scenes/walk.json: steps[0].devices[0]: "ipad" isn't one of this scene's devices"#,
        ])
    }

    @Test func scenesLeftInATypesFolderAreNamedNotRead() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "scenes/ipad"), withIntermediateDirectories: true)
        try write("scenes/ipad/old.json", #"{"set": "base", "steps": [{"hold": 1}]}"#)
        #expect(try validate() == [
            #"scenes/ipad/: isn't read: scenes are in scenes/ now, each naming the device types it plays on; move each one there, giving it "devices": ["ipad"], or merge it with the other type's as one scene, with "ipad" overrides where they differ"#,
        ])
    }

    @Test func anAnchorToAStepATypeSkipsIsRefusedThere() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("scenes/walk.json", #"{"set": "base", "steps": [{"id": "open", "tap": {"label": "a"}}, {"id": "turn", "orientation": "landscape-left", "devices": ["ipad"]}, {"id": "done", "waitFor": {"label": "b"}}]}"#)
        try edit(#"{"take": "walk", "from": {"step": "turn"}, "to": {"step": 2, "edge": "end"}}"#, devices: #"["iphone"]"#)
        #expect(try validate() == [
            #"edits/video.json: clips[0].from.step: scenes/walk.json's step "turn" doesn't play on iphone, so nothing can anchor to it there"#,
            #"edits/video.json: clips[0].to.step: scenes/walk.json's step 2 doesn't play on iphone, so nothing can anchor to it there"#,
        ])
    }

    @Test func everyFilesOwnProblemsAreReported() throws {
        try write("sets/broken.json", #"{"state": "fresh"}"#)
        try write("scenes/bad.json", #"{"devices": ["ipad"], "steps": [{"tapp": {}}]}"#)
        #expect(try validate() == [
            #"sets/broken.json: state: "fresh" isn't one of clean, cloned or live"#,
            #"scenes/bad.json: steps[0]: unknown key "tapp"; did you mean "tap"?"#,
        ])
    }

    @Test func namesThatMustExist() throws {
        try write("retake.json", #"{"defaultSet": "nowhere"}"#)
        try write("sets/top.json", #"{"extends": "missing", "files": {"Documents/a.json": "data/absent.json", "Documents/m/": "data/notes.json/"}}"#)
        try write("scenes/orphan.json", #"{"devices": ["iphone"], "set": "gone", "steps": [{"hold": 1}]}"#)
        try write("scenes/loose.json", #"{"devices": ["ipad"], "steps": [{"hold": 1}]}"#)
        #expect(Set(try validate()) == [
            #"retake.json: defaultSet: there's no set "nowhere" (sets/nowhere.json)"#,
            #"sets/top.json: extends: there's no set "missing" (sets/missing.json)"#,
            #"sets/top.json: files["Documents/a.json"]: "data/absent.json" doesn't exist"#,
            #"sets/top.json: files["Documents/m/"]: "data/notes.json/" is a file, not a folder"#,
            #"scenes/orphan.json: set: there's no set "gone" (sets/gone.json)"#,
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
        try write("scenes/loose.json", #"{"devices": ["ipad"], "steps": [{"hold": 1}]}"#)
        #expect(try validate() == ["scenes/loose.json: names no set, and retake.json has no defaultSet"])
    }

    @Test func anEditsScenesFilesAndAnchorsMustExist() throws {
        try edit(#"""
            {"take": "walk", "from": {"step": "opne"}, "to": {"step": 3}, "sounds": [{"file": "audio/missing.m4a", "at": {"step": "done"}}],
             "stills": [{"take": "elsewhere", "at": 1}]},
            {"take": "unrecorded", "from": 0, "to": 1}
            """#)
        #expect(try validate() == [
            #"edits/video.json: clips[0].from.step: scenes/walk.json has no step "opne""#,
            "edits/video.json: clips[0].to.step: scenes/walk.json has 2 steps, so there's no step 3",
            #"edits/video.json: clips[0].sounds[0].file: "audio/missing.m4a" doesn't exist in the project"#,
            #"edits/video.json: clips[0].stills[0].take: there's no scene "elsewhere" (scenes/elsewhere.json)"#,
            #"edits/video.json: clips[1].take: there's no scene "unrecorded" (scenes/unrecorded.json)"#,
        ])
    }

    @Test func anOverridesAnchorIsNamedWhereItsWritten() throws {
        try edit(#"{"take": "walk", "from": {"step": "open"}, "to": {"step": "done"}, "ipad": {"to": {"step": "dnoe"}}}"#)
        #expect(try validate() == [#"edits/video.json: clips[0].ipad.to.step: scenes/walk.json has no step "dnoe""#])
    }

    @Test func aCaptionRunningOnIsCheckedInTheLaterClipsScene() throws {
        try write("scenes/other.json", #"{"devices": ["iphone"], "set": "base", "steps": [{"id": "only", "hold": 1}]}"#)
        try edit(#"""
            {"take": "walk", "from": 0, "to": 1, "captions": [{"text": "a", "y": 0.1, "color": "#000000", "to": {"clip": "next", "step": "open"}}]},
            {"id": "next", "take": "other", "from": 0, "to": 1}
            """#, devices: #"["iphone"]"#)
        #expect(try validate() == [#"edits/video.json: clips[0].captions[0].to.step: scenes/other.json has no step "open""#])
    }

    @Test func deviceOnlyStepIDsNeedNotMatch() throws {
        try write("scenes/walk.json", #"{"set": "base", "steps": [{"id": "open", "tap": {"label": "a"}}, {"id": "done", "waitFor": {"label": "b"}, "devices": ["iphone"]}, {"id": "finish", "hold": 1, "devices": ["ipad"]}]}"#)
        try edit(#"{"take": "walk", "from": 0, "to": 1}"#)
        #expect(try validate() == [])
    }

    @Test func aReferencedStepIDMustExistForEachDevice() throws {
        try write("scenes/walk.json", #"{"set": "base", "steps": [{"id": "open", "tap": {"label": "a"}}, {"id": "done", "waitFor": {"label": "b"}, "devices": ["iphone"]}, {"id": "finish", "hold": 1, "devices": ["ipad"]}]}"#)
        try edit(#"{"take": "walk", "from": {"step": "open"}, "to": {"step": "done"}}"#)
        #expect(try validate() == [#"edits/video.json: clips[0].to.step: scenes/walk.json's step "done" doesn't play on ipad, so nothing can anchor to it there"#])
    }

    @Test func onlyTheNamedFilesAreReported() throws {
        try write("sets/broken.json", #"{"state": "fresh"}"#)
        try write("scenes/orphan.json", #"{"devices": ["iphone"], "set": "gone", "steps": [{"hold": 1}]}"#)
        #expect(try validate([.scene("orphan")]) == [#"scenes/orphan.json: set: there's no set "gone" (sets/gone.json)"#])
        #expect(try validate([.scene("walk")]) == [])
    }

    @Test func namesShareCanReadUnambiguously() throws {
        let scene = #"{"set": "base", "steps": [{"hold": 1}]}"#
        try write("scenes/a+b.json", scene)
        let edit = #"{"devices": ["ipad"], "clips": [{"take": "walk", "from": {"step": "open"}, "to": {"step": "done"}}]}"#
        try write("edits/c+d.json", edit)
        try write("edits/walk.json", edit)
        let joined = "can't have \"+\" in it, since `retake share` joins clips with it; rename the file"
        let clash = "is named \"walk\" too, so `retake share walk` can't tell a cut from a take; rename one of them"
        #expect(Set(try validate()) == [
            "scenes/a+b.json: a scene's name \(joined)",
            "edits/c+d.json: an edit's name \(joined)",
            "edits/walk.json: a scene \(clash)",
        ])
        // Checking only the scene, the clash is reported on it.
        #expect(try validate([.scene("walk")]) == ["scenes/walk.json: an edit \(clash)"])
    }

    @Test func filesAreRecognizedByWhereTheyAre() throws {
        let validator = ProjectValidator(files: ProjectFiles(project: try Project.locate(configuration: nil, currentDirectory: root)))
        #expect(validator.target(for: root.appending(path: "retake.json")) == .configuration)
        #expect(validator.target(for: root.appending(path: "sets/base.json")) == .set("base"))
        #expect(validator.target(for: root.appending(path: "scenes/walk.json")) == .scene("walk"))
        #expect(validator.target(for: root.appending(path: "scenes/ipad/walk.json")) == nil, "an earlier Retake's folder")
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
        try rename("sets", to: "Sets")
        // The tests' volume is case-insensitive, so both are still found; only their listing differs.
        #expect(try validate() == [
            "Sets/: should be named sets/; Retake's folders are lowercase",
            "Edits/: should be named edits/; Retake's folders are lowercase",
        ])
        #expect(try validate([.scene("walk")]) == [], "only the named files' folders are checked")
    }

    @Test func aFileMissingFromAFolderInAnotherCaseSaysWhy() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try rename("scenes", to: "Scenes")
        let files = ProjectFiles(project: try Project.locate(configuration: nil, currentDirectory: root))
        let report = ProjectFiles.Report()
        #expect(files.readScene("absent", for: .iphone, into: report) == nil)
        #expect(report.problems.map(\.description) == [
            "scenes/absent.json: doesn't exist: Scenes/ should be named scenes/; Retake's folders are lowercase",
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
