import Foundation
@testable import RetakeCore
import Testing
import ThePlans

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

    @Test func aWaitLongerThanTheButtonHeistTakesIsRefusedUnlessItsLimitIsRaised() {
        let long = #"{"waitFor": {"label": "Synced", "timeout": 61}}"#
        Step.$environment.withValue([:]) {
            #expect(steps(long).problems == [
                "scenes/ipad/create-note.json: steps[0].waitFor.timeout: 61 s is longer than The Button Heist waits, at most 60 s; BUTTONHEIST_MAX_WAIT_TIMEOUT raises that, set where Retake runs and in the set's environment, for the app",
            ])
            #expect(steps(#"{"waitFor": {"label": "Synced", "timeout": 60}}"#).problems.isEmpty)
        }
        Step.$environment.withValue([Step.maximumWaitTimeoutVariable: "120"]) {
            #expect(steps(long).scene?.steps.first?.action == .waitFor(ElementTarget(label: "Synced"), gone: false, timeout: 61))
            #expect(steps(#"{"waitFor": {"label": "Synced", "timeout": 121}}"#).problems.first?.contains("at most 120 s") == true)
        }
        Step.$environment.withValue([Step.maximumWaitTimeoutVariable: "10"]) {
            #expect(Step.maximumWaitTimeout == 60, "The Button Heist ignores a limit under 30")
        }
        #expect(Step.maximumWaitTimeout == WaitTimeout.maximumSeconds, "read where The Button Heist reads it, as a step's plan is made")
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
                { "capture": "synced-list" },
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
                Step(.tapPoint(Position(Point(x: 195, y: 410)))),
                Step(id: "reorder", .drag(from: .point(x: 120, y: 590), to: .point(x: 260, y: 500), duration: 0.8)),
                Step(id: "synced", .waitFor(ElementTarget(label: "Synced"), gone: false, timeout: Step.defaultWaitTimeout)),
                Step(.capture("synced-list")),
                Step(nil, hold: 2),
            ],
            leadIn: 1.5,
            tail: 2,
            defaultHold: 0.5,
        ))
    }

    @Test func aCaptureNamesItsStillsFileUniquelyAndIsntInSetup() {
        #expect(steps(#"{"capture": "home.1_a-b"}, {"capture": "list", "hold": 1, "id": "list"}"#).scene?.steps == [
            Step(.capture("home.1_a-b")), Step(id: "list", .capture("list"), hold: 1),
        ])
        #expect(steps(#"{"capture": "home"}, {"tap": {"label": "Add"}}, {"capture": "home"}"#).problems == [
            #"scenes/ipad/create-note.json: steps[2].capture: "home" is already steps[0]'s capture; each capture names a still of its own"#,
        ])
        #expect(steps(#"{"capture": "home"}, {"capture": "Home"}"#).problems == [
            #"scenes/ipad/create-note.json: steps[1].capture: "Home" is already steps[0]'s capture ("home", in another case, names the same file); each capture names a still of its own"#,
        ])
        for bad in ["../home", ".home", "home screen", "home/1"] {
            #expect(steps(#"{"capture": "\#(bad)"}"#).problems == [
                #"scenes/ipad/create-note.json: steps[0].capture: "\#(bad)" names the still's file, so it's letters, digits, -, _ and ., starting with a letter or digit"#,
            ])
        }
        #expect(read(#"{"setup": [{"capture": "home"}], "steps": [{"hold": 1}]}"#).problems == [
            "scenes/ipad/create-note.json: setup[0].capture: setup steps aren't recorded, so nothing is captured in them; move it into the steps",
        ])
        #expect(steps(#"{"capture": "home", "tap": {"label": "Add"}}"#).problems.first?.contains(#""tap" and "capture" can't be given together"#) == true)
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
            Step(.drag(from: .point(x: 1, y: 2), to: .point(x: 3, y: 4), duration: 0.5)),
            Step(.waitFor(ElementTarget(value: "Title"), gone: true, timeout: 10)),
        ])
    }

    @Test func aPointCanBeAShareOfTheScreenAndADragsEndsElements() {
        let scene = steps(#"""
            {"tap": {"x": "50%", "y": 410}},
            {"drag": {"from": {"label": "Reorder Book club"}, "to": {"label": "Reorder Weekend plans"}, "duration": 0.6}},
            {"capture": "list", "hold": 1}
            """#).scene
        #expect(scene?.steps.map(\.action) == [
            .tapPoint(Position(x: .share(0.5), y: .points(410))),
            .drag(from: .element(ElementTarget(label: "Reorder Book club")), to: .element(ElementTarget(label: "Reorder Weekend plans")), duration: 0.6),
            .capture("list"),
        ])
        #expect(scene?.steps.map(\.json) == [
            .object(JSONObject([.init(key: "tap", value: .object(JSONObject([.init(key: "x", value: .string("50%")), .init(key: "y", value: .number(410))])))])),
            try! JSONParser.parse(#"{"drag": {"from": {"label": "Reorder Book club"}, "to": {"label": "Reorder Weekend plans"}, "duration": 0.6}}"#),
            try! JSONParser.parse(#"{"capture": "list", "hold": 1}"#),
        ], "written back as given")
    }

    @Test(arguments: [
        (#"{"tap": {"x": "150%", "y": 1}}"#, #"scenes/ipad/create-note.json: steps[0].tap.x: is a number of points, or a percentage of the screen up to 100%, such as "50%""#),
        (#"{"tap": {"x": "half", "y": 1}}"#, #"scenes/ipad/create-note.json: steps[0].tap.x: is a number of points, or a percentage of the screen up to 100%, such as "50%""#),
        (#"{"drag": {"from": {"x": 1, "y": 2, "label": "A"}, "to": {"x": 3, "y": 4}}}"#, #"scenes/ipad/create-note.json: steps[0].drag.from: is a point ("x" and "y") or an element, not both"#),
    ])
    func aPointThatIsntOneSaysWhy(_ step: String, _ expected: String) {
        #expect(steps(step).problems == [expected])
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
        (#"{"id": "pause"}"#, "scenes/ipad/create-note.json: steps[0]: has nothing to do: give an action (tap, drag, type, activate, orientation, waitFor, capture) or a hold"),
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
