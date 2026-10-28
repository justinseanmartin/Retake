import Foundation
import RetakeCore
import Testing

struct SceneFileTests {
    func read(_ text: String) -> (scene: SceneFile?, problems: [String]) {
        let reader = JSONReader(file: "scenes/ipad/create-note.json")
        let scene = SceneFile.read(text, with: reader)
        return (scene, reader.problems.map(\.description))
    }

    /// A scene's steps, given as the JSON inside `"steps": [ … ]`.
    func steps(_ steps: String) -> (scene: SceneFile?, problems: [String]) {
        read(#"{"steps": [\#(steps)]}"#)
    }

    @Test func theREADMEsExampleReads() {
        let result = read(#"""
            {
              "set": "returning-user",
              "setup": [{ "activate": { "label": "Library" } }],
              "leadIn": 1.5,
              "tail": 2,
              "defaultHold": 0.5,
              "steps": [
                { "id": "new-note", "tap": { "label": "New Note" }, "hold": 1.2 },
                { "type": { "text": "Groceries\n", "into": { "value": "Title" } } },
                { "tap": { "x": 195, "y": 410 } },
                { "id": "reorder", "drag": { "from": { "x": 120, "y": 590 }, "to": { "x": 260, "y": 500 }, "duration": 0.8 } },
                { "id": "synced", "waitFor": { "label": "Synced" } },
                { "hold": 2 }
              ]
            }
            """#)
        #expect(result.problems.isEmpty)
        #expect(result.scene == SceneFile(
            set: "returning-user",
            setup: [Step(.activate(ElementTarget(label: "Library")))],
            steps: [
                Step(id: "new-note", .tapElement(ElementTarget(label: "New Note")), hold: 1.2),
                Step(.type(text: "Groceries\n", into: ElementTarget(value: "Title"))),
                Step(.tapPoint(Point(x: 195, y: 410))),
                Step(id: "reorder", .drag(from: Point(x: 120, y: 590), to: Point(x: 260, y: 500), duration: 0.8)),
                Step(id: "synced", .waitFor(ElementTarget(label: "Synced"), gone: false, timeout: Step.defaultWaitTimeout)),
                Step(nil, hold: 2),
            ],
            leadIn: 1.5,
            tail: 2,
            defaultHold: 0.5,
        ))
    }

    @Test func aScenesLaunchIsItsSetsAlone() {
        let reader = JSONReader(file: "scenes/ipad/create-note.json")
        #expect(SceneFile.read(#"{"environment": {"FLAG": "1"}, "steps": [{"hold": 1}]}"#, with: reader) == nil)
        #expect(reader.problems.map(\.description) == [#"scenes/ipad/create-note.json: unknown key "environment""#])
    }

    @Test func whatsLeftOutHasItsDefault() {
        let scene = steps(#"{"drag": {"from": {"x": 1, "y": 2}, "to": {"x": 3, "y": 4}}}, {"waitFor": {"value": "Title", "gone": true}}"#).scene
        #expect(scene?.leadIn == 1 && scene?.tail == 1 && scene?.orientation == .portrait && scene?.recordsLaunch == false)
        #expect(scene?.set == nil)
        #expect(scene?.steps == [
            Step(.drag(from: Point(x: 1, y: 2), to: Point(x: 3, y: 4), duration: 0.5)),
            Step(.waitFor(ElementTarget(value: "Title"), gone: true, timeout: 10)),
        ])
    }

    @Test func elementsCanBeNamedEveryWayTogether() {
        let scene = steps(#"{"tap": {"label": "Delete", "identifier": "row.delete", "occurrence": 2}}, {"type": {"text": "a"}}, {"orientation": "landscape-left"}"#).scene
        #expect(scene?.steps.map(\.action) == [
            .tapElement(ElementTarget(label: "Delete", identifier: "row.delete", occurrence: 2)),
            .type(text: "a", into: nil),
            .orientation(.landscapeLeft),
        ])
        let named = steps(#"{"tap": {"label": "Notes", "traits": ["header"]}}, {"activate": {"hint": "Opens the note"}}"#).scene
        #expect(named?.steps.map(\.action) == [
            .tapElement(ElementTarget(label: "Notes", traits: ["header"])),
            .activate(ElementTarget(hint: "Opens the note")),
        ])
    }

    @Test(arguments: [
        (#"{"tap": {"traits": ["heading"]}}"#, #"scenes/ipad/create-note.json: steps[0].tap.traits[0]: "heading" isn't a trait The Button Heist knows; `retake compose` shows each element's"#),
        (#"{"tap": {"traits": []}}"#, "scenes/ipad/create-note.json: steps[0].tap.traits: needs at least one trait"),
        (#"{"tap": {"traits": ["button", "button"]}}"#, #"scenes/ipad/create-note.json: steps[0].tap.traits: names "button" more than once"#),
        (#"{"tap": {"label": "a", "hint": ""}}"#, "scenes/ipad/create-note.json: steps[0].tap.hint: can't be empty"),
    ])
    func traitsAndHintsMistakesAreNamed(_ step: String, _ expected: String) {
        #expect(steps(step).problems == [expected])
    }

    @Test(arguments: [
        (#"{"tapp": {"label": "a"}}"#, #"scenes/ipad/create-note.json: steps[0]: unknown key "tapp"; did you mean "tap"?"#),
        (#"{"tap": {"label": "a"}, "drag": {"from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 2}}}"#, #"scenes/ipad/create-note.json: steps[0]: does one thing, so "tap" and "drag" can't be given together"#),
        (#"{"id": "pause"}"#, "scenes/ipad/create-note.json: steps[0]: has nothing to do: give an action (tap, drag, type, activate, orientation, waitFor) or a hold"),
        (#"{"tap": {"x": 10, "y": 10, "label": "a"}}"#, #"scenes/ipad/create-note.json: steps[0].tap: taps a point ("x" and "y") or an element, not both"#),
        (#"{"tap": {"x": 10}}"#, #"scenes/ipad/create-note.json: steps[0].tap: is missing "y""#),
        (#"{"tap": {"occurrence": 2}}"#, #"scenes/ipad/create-note.json: steps[0].tap: needs an element to name: its "label", "value", "identifier", "hint" or "traits""#),
        (#"{"tap": {"label": "a", "occurrence": 0}}"#, "scenes/ipad/create-note.json: steps[0].tap.occurrence: 0 must be at least 1"),
        (#"{"waitFor": {"label": "a", "timeout": 0}}"#, "scenes/ipad/create-note.json: steps[0].waitFor.timeout: 0 must be more than 0"),
        (#"{"type": {"text": ""}}"#, "scenes/ipad/create-note.json: steps[0].type.text: can't be empty"),
        (#"{"type": {"text": "a", "into": {}}}"#, #"scenes/ipad/create-note.json: steps[0].type.into: needs an element to name: its "label", "value", "identifier", "hint" or "traits""#),
        (#"{"orientation": "sideways"}"#, #"scenes/ipad/create-note.json: steps[0].orientation: "sideways" isn't one of portrait, portrait-upside-down, landscape-left or landscape-right"#),
        (#"{"inspect": true}"#, "scenes/ipad/create-note.json: steps[0]: unknown key \"inspect\""),
        (#"{"hold": -1}"#, "scenes/ipad/create-note.json: steps[0].hold: -1 must be at least 0"),
        (#"{"id": "3", "hold": 1}"#, #"scenes/ipad/create-note.json: steps[0].id: "3" looks like a number, which anchors count steps by; give it a name"#),
        (#"{"id": "-1", "hold": 1}"#, #"scenes/ipad/create-note.json: steps[0].id: "-1" looks like a number, which anchors count steps by; give it a name"#),
        (#"{"id": "end", "hold": 1}"#, #"scenes/ipad/create-note.json: steps[0].id: "end" names the take's own end, so a step can't have it"#),
        (#"{"id": "a", "hold": 1}, {"id": "a", "hold": 1}"#, #"scenes/ipad/create-note.json: steps[1].id: "a" is already steps[0]'s id; ids are unique in a scene"#),
        (#"{"drag": {"from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 2}, "duration": 0}}"#, "scenes/ipad/create-note.json: steps[0].drag.duration: 0 must be more than 0"),
        (#"{"tap": {"x": -5, "y": 1}}"#, "scenes/ipad/create-note.json: steps[0].tap.x: -5 must be at least 0"),
    ])
    func stepMistakesAreNamed(_ step: String, _ expected: String) {
        let result = steps(step)
        #expect(result.problems == [expected])
        #expect(result.scene == nil)
    }

    @Test(arguments: [
        (#"{}"#, #"scenes/ipad/create-note.json: is missing "steps""#),
        (#"{"steps": []}"#, "scenes/ipad/create-note.json: steps: needs at least one step"),
        (#"{"steps": [{"hold": 1}], "setup": [{"id": "go", "tap": {"label": "a"}}]}"#, "scenes/ipad/create-note.json: setup[0].id: setup steps aren't recorded, so nothing can anchor to them; leave the id out"),
        (#"{"steps": [{"hold": 1}], "orientation": "upside-down"}"#, #"scenes/ipad/create-note.json: orientation: "upside-down" isn't one of portrait, portrait-upside-down, landscape-left or landscape-right"#),
        (#"{"steps": [{"hold": 1}], "leadIn": -0.5}"#, "scenes/ipad/create-note.json: leadIn: -0.5 must be at least 0"),
    ])
    func sceneMistakesAreNamed(_ text: String, _ expected: String) {
        #expect(read(text).problems == [expected])
    }

    @Test func theExamplesScenesRead() throws {
        let example = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Examples/Notes").standardizedFileURL
        let files = ProjectFiles(project: try Project.locate(configuration: nil, currentDirectory: example))
        for type in DeviceType.allCases {
            let names = files.names(in: files.project.scenes(for: type))
            #expect(names.starts(with: ["create-note", "first-launch"]), "each type has at least these")
            for name in names {
                let report = ProjectFiles.Report()
                #expect(files.readScene(name, for: type, into: report) != nil, "\(type)/\(name): \(report.problems)")
                #expect(report.warnings.isEmpty)
            }
        }
    }

    @Test func aStepThatCantBeReadDoesntShiftTheIDChecks() {
        let read = steps(#"{"tap": {}}, {"hold": 1, "id": "a"}, {"hold": 1, "id": "a"}"#)
        #expect(read.problems.count == 1 && read.problems[0].hasPrefix("scenes/ipad/create-note.json: steps[0].tap:"))
    }
}
