import Foundation
@testable import RetakeCore
import Testing

struct EditFileTests {
    func read(_ text: String) -> (edit: EditFile?, problems: [String]) {
        let reader = JSONReader(file: "edits/video1.json")
        let edit = EditFile.read(text, with: reader)
        return (edit, reader.problems.map(\.description))
    }

    /// An edit for both device types whose clips are `clips`, given as the JSON inside `"clips": [ … ]`.
    func clips(_ clips: String, devices: String = #"["iphone", "ipad"]"#) -> (edit: EditFile?, problems: [String]) {
        read(#"{"devices": \#(devices), "clips": [\#(clips)]}"#)
    }

    let readme = #"""
        {
          "intent": "The core loop in 20 s: create a note, share it, see it sync.",
          "devices": ["iphone", "ipad"],
          "music": { "file": "audio/theme.m4a", "volume": 0.6, "fadeOut": 1.5 },
          "tapSound": { "file": "audio/tap.m4a", "volume": 0.5 },
          "background": "#F4F1EA",
          "clips": [
            {
              "intent": "The empty library, then New Note tapped.",
              "take": "create-note",
              "from": { "step": "start", "offset": 1.2 },
              "to": { "step": "new-note", "offset": 0.6, "edge": "end" },
              "speed": 1.5,
              "touches": true,
              "sounds": [{ "file": "audio/pop.m4a", "at": { "step": "new-note" } }],
              "captions": [
                {
                  "text": "Jot it down",
                  "y": 0.12,
                  "color": "#1F6FEB",
                  "to": { "clip": "sync", "step": "synced", "offset": -0.2 },
                  "ipad": { "y": 0.08 }
                }
              ]
            },
            {
              "id": "sync",
              "intent": "The note syncing, cut just before its badge settles.",
              "take": "create-note",
              "from": { "step": "reorder", "fraction": 0.5, "edge": "end" },
              "to": { "step": "synced", "offset": -0.2 },
              "speed": 1,
              "ipad": { "speed": 1.3 },
              "takeAudio": true,
              "sounds": [
                { "file": "audio/chime.m4a", "at": { "step": "synced" }, "volume": 0.8, "duration": 1.2 }
              ],
              "crossfade": 0.4
            }
          ]
        }
        """#

    @Test func theREADMEsExampleReadsForEachDeviceType() throws {
        let result = read(readme)
        #expect(result.problems.isEmpty)
        let edit = try #require(result.edit)
        #expect(edit.devices == [.iphone, .ipad])
        let iphone = try #require(edit.videos[.iphone])
        let ipad = try #require(edit.videos[.ipad])
        #expect(iphone.clips[1].speed == 1 && ipad.clips[1].speed == 1.3)
        #expect(iphone.clips[0].captions[0].y == 0.12 && ipad.clips[0].captions[0].y == 0.08)
        #expect(ipad.clips[0].captions[0].text == "Jot it down", "an override merges into the caption, keeping what it doesn't give")
        #expect(iphone.clips[0].captions[0].to == Edit.CaptionEnd(
            clip: "sync",
            anchor: .step(Anchor.StepAnchor(step: .id("synced"), offset: -0.2)),
        ))
        #expect(iphone.background == Color(hex: "#F4F1EA") && iphone.clips[1].crossfade == 0.4)
        #expect(iphone.clips[0].from == .step(Anchor.StepAnchor(step: .start, offset: 1.2)))
        #expect(iphone.clips[1].sounds[0] == Edit.Effect(file: "audio/chime.m4a", at: .step(Anchor.StepAnchor(step: .id("synced"))), volume: 0.8, duration: 1.2))
    }

    @Test func anchorsTakeEveryFormTheREADMEGives() {
        let edit = clips(#"""
            {"take": "a", "from": 1.5, "to": {"step": -1, "fraction": -0.5, "edge": "end"}},
            {"take": "a", "from": {"step": 2}, "to": {"step": "end"}},
            {"take": "a", "from": {"step": "x", "edge": "end"}, "to": {"step": "end"}}
            """#, devices: #"["iphone"]"#).edit
        let clips = edit?.videos[.iphone]?.clips
        #expect(clips?[0].from == .seconds(1.5))
        #expect(clips?[0].to == .step(Anchor.StepAnchor(step: .number(-1), fraction: -0.5, edge: .end)))
        #expect(clips?[1].from == .step(Anchor.StepAnchor(step: .number(2))))
        #expect(clips?[1].to == .step(Anchor.StepAnchor(step: .end)))
        #expect(clips?[2].from == .step(Anchor.StepAnchor(step: .id("x"), edge: .end)), "an edge alone is that edge")
    }

    @Test func aListInAnOverrideReplacesTheWholeList() throws {
        let edit = try #require(clips(#"""
            {"take": "a", "from": 0, "to": 1,
             "captions": [{"text": "One", "y": 0.1, "color": "#000000"}, {"text": "Two", "y": 0.2, "color": "#000000"}],
             "ipad": {"captions": [{"text": "Only", "y": 0.5, "color": "#FFFFFF"}]}}
            """#).edit)
        #expect(edit.videos[.iphone]?.clips[0].captions.map(\.text) == ["One", "Two"])
        #expect(edit.videos[.ipad]?.clips[0].captions.map(\.text) == ["Only"])
    }

    @Test func topLevelFieldsAreOverriddenToo() throws {
        let edit = try #require(read(#"""
            {"intent": "Phone tour", "devices": ["iphone", "ipad"], "turns": "letterboxed",
             "ipad": {"intent": "Tablet tour", "turns": "device", "music": {"file": "ipad.m4a"}},
             "clips": [{"take": "a", "from": 0, "to": 1}]}
            """#).edit)
        #expect(edit.videos[.iphone]?.intent == "Phone tour" && edit.videos[.ipad]?.intent == "Tablet tour")
        #expect(edit.videos[.iphone]?.turns == .letterboxed && edit.videos[.iphone]?.music == nil)
        #expect(edit.videos[.ipad]?.turns == .device && edit.videos[.ipad]?.music?.file == "ipad.m4a")
    }

    @Test(arguments: [
        // A mistake in an override is named where it's written, not in the merged edit.
        (#"{"take": "a", "from": 0, "to": 1, "ipad": {"speed": 0}}"#, "edits/video1.json: clips[0].ipad.speed: 0 must be more than 0"),
        (#"{"take": "a", "from": 0, "to": 1, "ipad": {"spead": 2}}"#, #"edits/video1.json: clips[0].ipad: unknown key "spead"; did you mean "speed"?"#),
        (##"{"take": "a", "from": 0, "to": 1, "captions": [{"text": "a", "y": 0.1, "color": "#000000", "ipad": {"y": 2}}]}"##, "edits/video1.json: clips[0].captions[0].ipad.y: 2 is outside 0 to 1"),
        // A mistake both device types share is named once.
        (#"{"take": "a", "from": 0, "to": 1, "speed": -1}"#, "edits/video1.json: clips[0].speed: -1 must be more than 0"),
        (#"{"take": "a", "from": {"step": "x", "offset": 1, "fraction": 0.5}, "to": 1}"#, #"edits/video1.json: clips[0].from: moves by an "offset" or a "fraction", not both"#),
        (#"{"take": "a", "from": {"step": 0}, "to": 1}"#, "edits/video1.json: clips[0].from.step: steps are numbered from 1, or from the last as -1; there's no step 0"),
        (#"{"take": "a", "from": {"step": "x", "fraction": 1.4}, "to": 1}"#, "edits/video1.json: clips[0].from.fraction: 1.4 is outside -1 to 1"),
        (#"{"take": "a", "from": -1, "to": 1}"#, "edits/video1.json: clips[0].from: -1 must be at least 0"),
        (#"{"take": "a", "from": 0, "to": 1, "crossfade": 0.5}"#, "edits/video1.json: clips[0].crossfade: has no clip before it to cross-fade from"),
        (#"{"take": "a", "from": 0, "to": 1, "captions": [{"text": "a", "y": 0.1, "color": "blue"}]}"#, #"edits/video1.json: clips[0].captions[0].color: "blue" isn't a colour: #RRGGBB, or #RRGGBBAA with its opacity, such as #1F6FEB"#),
        (##"{"take": "a", "from": 0, "to": 1, "captions": [{"text": "a", "y": 0.1, "color": "#000000", "to": {"clip": "later"}}]}"##, ##"edits/video1.json: clips[0].captions[0].to.clip: there's no clip with the id "later""##),
        (#"{"take": "a", "from": 0, "to": 1, "spotlight": {"padding": 4}}"#, #"edits/video1.json: clips[0].spotlight: needs an "element" to find in the step log, or a "rect" in screen points"#),
        (#"{"take": "a", "from": 0, "to": 1, "blurs": [{"element": {"label": "Name"}, "rect": {"x": 0, "y": 0, "width": 1, "height": 1}}]}"#, #"edits/video1.json: clips[0].blurs[0]: names an "element" or a "rect", not both"#),
        (##"{"take": "a", "from": 0, "to": 1, "captions": [{"text": "a", "y": 0.1, "color": "#000000", "symbol": {"name": "rotate.right", "animation": {"spin": {}}}}]}"##, ##"edits/video1.json: clips[0].captions[0].symbol.animation: unknown key "spin""##),
        (#"{"take": "a", "from": 0, "to": 1, "ipad": {"iphone": {"speed": 2}}}"#, "edits/video1.json: clips[0].ipad.iphone: an override can't hold another device type's"),
        (#"{"take": "a", "from": 0, "to": 1, "crossfade": 0, "audioCrossfade": -1}"#, "edits/video1.json: clips[0].audioCrossfade: -1 must be at least 0"),
    ])
    func clipMistakesAreNamedWhereTheyreWritten(_ clip: String, _ expected: String) {
        let result = clips(clip)
        #expect(result.problems == [expected])
        #expect(result.edit == nil)
    }

    @Test func aCaptionRunsOnOnlyIntoALaterClip() {
        let result = clips(#"""
            {"id": "first", "take": "a", "from": 0, "to": 1},
            {"take": "a", "from": 0, "to": 1, "captions": [{"text": "a", "y": 0.1, "color": "#000000", "to": {"clip": "first"}}]}
            """#)
        #expect(result.problems == ["edits/video1.json: clips[1].captions[0].to.clip: names clips[0], which isn't after this caption's own clip; a caption runs on only into later clips"])
    }

    @Test(arguments: [
        (#"{"devices": [], "clips": [{"take": "a", "from": 0, "to": 1}]}"#, "edits/video1.json: devices: needs at least one device type: iphone, ipad"),
        (#"{"devices": ["iphone", "iphone"], "clips": [{"take": "a", "from": 0, "to": 1}]}"#, #"edits/video1.json: devices[1]: "iphone" is given more than once"#),
        (#"{"devices": ["iphone"], "ipad": {"turns": "device"}, "clips": [{"take": "a", "from": 0, "to": 1}]}"#, "edits/video1.json: ipad: overrides ipad, which isn't one of this edit's devices"),
        (#"{"devices": ["iphone"], "iphone": {"devices": ["ipad"]}, "clips": [{"take": "a", "from": 0, "to": 1}]}"#, #"edits/video1.json: iphone: "devices" can't be given for one device type"#),
        (#"{"devices": ["iphone"], "takes": {"iphone": {"a": 1}}, "clips": [{"take": "a", "from": 0, "to": 1}]}"#, #"edits/video1.json: takes: an edit doesn't name its takes: cut uses each scene's latest successful take, and `retake clean --takes` goes back to an earlier one; delete "takes""#),
        (#"{"devices": ["iphone"], "clips": []}"#, "edits/video1.json: clips: needs at least one clip"),
        (#"{"devices": ["iphone"], "clips": [{"id": "x", "take": "a", "from": 0, "to": 1}, {"id": "x", "take": "a", "from": 0, "to": 1}]}"#, #"edits/video1.json: clips[1].id: "x" is already clips[0]'s id; ids are unique in an edit"#),
        (#"{"devices": ["iphone"], "clips": [{"take": "a", "from": 0, "to": 1, "blurs": [{"rect": {"x": 0, "y": 0, "width": 1, "height": 1}, "part": {"x": "50%"}}]}]}"#, #"edits/video1.json: clips[0].blurs[0].part: is a part of an "element", which isn't given"#),
        (##"{"devices": ["iphone"], "clips": [{"take": "a", "from": 0, "to": 1, "stillsBackground": "#FFFFFF"}]}"##, "edits/video1.json: clips[0].stillsBackground: the clip has no stills for it to go behind"),
    ])
    func editMistakesAreNamed(_ text: String, _ expected: String) {
        #expect(read(text).problems == [expected])
    }

    @Test func theExamplesEditsRead() throws {
        let example = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Examples/Notes").standardizedFileURL
        let files = ProjectFiles(project: try Project.locate(configuration: nil, currentDirectory: example))
        #expect(files.names(in: files.project.edits) == ["showcase", "tour"])
        let report = ProjectFiles.Report()
        let edit = files.readEdit("tour", into: report)
        let showcase = files.readEdit("showcase", into: report)
        #expect(report.problems.isEmpty && report.warnings.isEmpty, "\(report.problems)")
        #expect(showcase?.devices == [.iphone, .ipad])
        #expect(edit?.videos[.ipad]?.clips[0].captions[0].y == 0.08 && edit?.videos[.iphone]?.clips[0].captions[0].y == 0.1, "the iPad's override")
    }

    @Test func coloursReadAndPrintAsWritten() {
        #expect(Color(hex: "#1F6FEB")?.description == "#1F6FEB")
        #expect(Color(hex: "#00000080")?.alpha == Double(0x80) / 255)
        #expect(Color(hex: "1F6FEB") == nil && Color(hex: "#12345") == nil && Color(hex: "#GGGGGG") == nil)
    }

    @Test func aClipNamingDevicesIsInOnlyTheirVideosAndAProblemAfterItIsNamedWhereItsWritten() throws {
        let edit = try #require(clips(#"{"take": "a", "from": 0, "to": 1}, {"take": "card", "from": 0, "to": 1, "devices": ["iphone"]}, {"take": "c", "from": 0, "to": 1}"#).edit)
        #expect(edit.videos[.iphone]?.clips.map(\.take) == ["a", "card", "c"])
        #expect(edit.videos[.ipad]?.clips.map(\.take) == ["a", "c"])
        // The iPad's second clip is the file's third, in an override or not.
        let problems = clips(#"""
            {"take": "a", "from": 0, "to": 1}, {"take": "b", "from": 0, "to": 1, "devices": ["iphone"]},
            {"take": "c", "from": 0, "to": 1, "ipad": {"crossfade": -1}}, {"take": "d", "from": 0, "to": 1, "speed": 0}
            """#).problems
        #expect(problems.contains { $0.hasPrefix("edits/video1.json: clips[2].ipad.crossfade:") }, "\(problems)")
        #expect(problems.filter { $0.contains("clips[3].speed") }.count == 1, "once, at the file's place, for both types: \(problems)")
        let elsewhere = clips(#"{"take": "a", "from": 0, "to": 1, "devices": ["iphone"]}"#, devices: #"["ipad"]"#).problems
        #expect(elsewhere.contains { $0.contains("clips[0].devices[0]: \"iphone\" isn't one of this edit's devices") }, "\(elsewhere)")
    }

    @Test func aClipThatCantBeReadDoesntShiftTheChecksAcrossClips() {
        let read = clips(#"{"take": "a", "from": 0}, {"id": "b", "take": "a", "from": 0, "to": 1, "crossfade": 0.4}"#, devices: #"["ipad"]"#)
        #expect(read.problems == ["edits/video1.json: clips[0]: is missing \"to\""])
    }
}
