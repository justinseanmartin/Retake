import ButtonHeist
import Foundation
@testable import RetakeCore
import Testing

struct ComposeActionTests {
    func parse(_ line: String) throws(ComposeAction.Problem) -> ComposeAction { try ComposeAction.parse(line) }

    @Test func eachStepActionBecomesTheStepItsOptionsDescribe() throws {
        #expect(try parse(#"tap --label "New Note" --id new-note --hold 0.8"#) == .step(Step(id: "new-note", .tapElement(ElementTarget(label: "New Note")), hold: 0.8)))
        #expect(try parse("tap --x 195 --y 410.5") == .step(Step(.tapPoint(Position(Point(x: 195, y: 410.5))))))
        #expect(try parse("drag --from 120,590 --to 260,500") == .step(Step(.drag(from: .point(x: 120, y: 590), to: .point(x: 260, y: 500), duration: 0.5))))
        #expect(try parse(#"type --text "Groceries\n" --value Title"#) == .step(Step(.type(text: "Groceries\n", into: ElementTarget(value: "Title")))))
        #expect(try parse(#"type --text "a \"b\"""#) == .step(Step(.type(text: #"a "b""#, into: nil))))
        #expect(try parse(#"activate --label Delete --occurrence 2"#) == .step(Step(.activate(ElementTarget(label: "Delete", occurrence: 2)))))
        #expect(try parse(#"waitFor --label Done --gone --timeout 4"#) == .step(Step(.waitFor(ElementTarget(label: "Done"), gone: true, timeout: 4))))
        #expect(try parse("orientation --to landscape-left") == .step(Step(.orientation(.landscapeLeft))))
        #expect(try parse("hold --seconds 2 --id rest") == .step(Step(id: "rest", nil, hold: 2)))
    }

    @Test func aTapAtAPointOnAnElementOnlyItsLabelNamesSuggestsNamingIt() {
        func tap(_ x: Double, _ y: Double) -> Step { Step(.tapPoint(Position(Point(x: x, y: y)))) }
        let row = ScreenElement(label: "Groceries", traits: ["button"], frame: .init(x: 0, y: 100, width: 390, height: 44))
        let badge = ScreenElement(label: "Synced", traits: [], frame: .init(x: 300, y: 110, width: 60, height: 20))
        let elements = [row, badge, ScreenElement(label: "Library", traits: ["header"], frame: .init(x: 0, y: 40, width: 390, height: 40)),
                        ScreenElement(label: "Library", traits: ["button"], frame: .init(x: 0, y: 800, width: 100, height: 44))]
        #expect(Composer.naming(tap(20, 120), in: elements) == ElementTarget(label: "Groceries"))
        #expect(Composer.naming(tap(320, 120), in: elements) == ElementTarget(label: "Synced"), "the smallest under the point")
        #expect(Composer.naming(tap(20, 60), in: elements) == nil, "another element has its label")
        #expect(Composer.naming(tap(20, 500), in: elements) == nil, "nothing there")
    }

    @Test func actionsOnTheSceneAddNoStep() throws {
        #expect(try parse("inspect") == .inspect(nil))
        #expect(try parse(#"inspect --label "Delete""#) == .inspect(ElementTarget(label: "Delete")))
        #expect(try parse(#"tap --label Notes --traits header,selected,header --hint "Opens it""#)
            == .step(Step(.tapElement(ElementTarget(label: "Notes", hint: "Opens it", traits: ["header", "selected"])))))
        #expect(throws: ComposeAction.Problem.self) { try parse("tap --traits heading") }
        #expect(try parse("set --hold 1.5") == .set(hold: 1.5, id: nil))
        #expect(try parse("set --id synced --hold 0") == .set(hold: 0, id: "synced"))
        #expect(throws: ComposeAction.Problem.wrong("set needs --hold <seconds> or --id <name>, or both.")) { try parse("set") }
        #expect(try parse("undo") == .undo(1) && parse("undo 3") == .undo(3) && parse("replay") == .replay)
        #expect(try parse("steps") == .steps && parse("quit") == .quit)
        #expect(throws: ComposeAction.Problem.self) { try parse("undo 0") }
        #expect(throws: ComposeAction.Problem.self) { try parse("inspect --occurrence 2") }
        #expect(try parse("help") == .help(nil) && parse("help wait") == .help("wait"))
    }

    @Test func whatsMissingIsNamedForATerminalToAskFor() {
        #expect(throws: ComposeAction.Problem.missing(action: "tap", [.element])) { try parse("tap") }
        #expect(throws: ComposeAction.Problem.self) { try parse("drag --from 1,2") }
        do {
            _ = try parse("type --value Title")
            Issue.record("type without --text")
        } catch {
            #expect(error.message == "type needs --text <text>; `help type` lists its options.")
        }
    }

    @Test(arguments: [
        ("jump", "There's no action \"jump\"; `help` lists them."),
        ("tap --label", "--label needs <text>."),
        ("tap --size 3", "tap has no option --size; `help tap` lists its options."),
        ("tap Share", "\"Share\" isn't an option; give each as --name, such as --label \"Share\"."),
        ("tap --label a --x 1 --y 2", "tap takes an element or --x and --y, not both."),
        ("tap --x 1", "tap at a point needs both --x and --y."),
        ("drag --from 1 --to 2,3", "--from takes a point as <x>,<y>, such as 120,590."),
        ("waitFor --label a --timeout 0", "--timeout must be more than 0."),
        ("tap --label a --hold -1", "--hold can't be less than 0."),
        ("activate --label a --occurrence 0", "--occurrence counts from 1, not \"0\"."),
        ("orientation --to sideways", "--to is one of portrait, portrait-upside-down, landscape-left, landscape-right."),
        (#"tap --label "a"#, "A quote isn't closed."),
        ("tap --label a --label b", "--label is given twice."),
    ])
    func mistakesSayWhatsWrong(_ line: String, _ message: String) {
        #expect(throws: ComposeAction.Problem.wrong(message)) { try parse(line) }
    }

    @Test func helpSaysWhatsRequiredAndWhatsOptionalWithItsDefault() throws {
        let drag = try #require(ComposeActionSpec.all.first { $0.name == "drag" }).usage
        #expect(drag.contains("Required:\n  --from <x>,<y>"))
        #expect(drag.contains("Optional:\n  --duration <seconds>  how long it takes (0.5 if not given)"))
        let tap = try #require(ComposeActionSpec.all.first { $0.name == "tap" }).usage
        #expect(tap.contains("an element (--label, --value, --identifier, --hint or --traits, one at least), or a point (--x <x> --y <y>)"))
        #expect(!tap.contains("--x <x>  in screen points"), "x and y are in what's required, not listed again")
        #expect(ComposeActionSpec.overview.split(separator: "\n").contains { $0.hasPrefix("  inspect ") && $0.hasSuffix("numbered as --occurrence counts them.") })
    }
}

struct SceneDocumentTests {
    @Test func aNewSceneNamesItsSetAndWritesAStepALine() {
        var document = SceneDocument(url: URL(filePath: "/p/scenes/ipad/a.json"), scene: nil, text: nil, newOn: "returning-user")
        document.steps = [Step(id: "new-note", .tapElement(ElementTarget(label: "New Note")), hold: 0.8), Step(.waitFor(ElementTarget(label: "Synced"), gone: false, timeout: 10))]
        #expect(document.text == """
            {
              "set": "returning-user",
              "steps": [
                { "tap": { "label": "New Note" }, "hold": 0.8, "id": "new-note" },
                { "waitFor": { "label": "Synced" } }
              ]
            }

            """)
    }

    @Test func anExistingScenesOtherFieldsAreKept() throws {
        let text = #"{ "set": "base", "leadIn": 1.5, "steps": [{ "hold": 1 }], "tail": 2 }"#
        let scene = try #require(SceneFile.read(text, with: JSONReader(file: "a.json")))
        var document = SceneDocument(url: URL(filePath: "/p/a.json"), scene: scene, text: text, newOn: "ignored")
        document.steps.append(Step(.orientation(.landscapeLeft)))
        let written = try JSONParser.parse(document.text)
        #expect(written[path: "leadIn"] == .number(1.5) && written[path: "tail"] == .number(2) && written[path: "set"] == .string("base"))
        #expect(written[path: "$schema"] == nil, "Retake never adds one")
        #expect(SceneFile.read(document.text, with: JSONReader(file: "a.json"))?.steps == [Step(nil, hold: 1), Step(.orientation(.landscapeLeft))])
    }
}

/// Lines given one after another, as from a pipe.
final class ScriptedInput: ComposeInput, @unchecked Sendable {
    private var lines: [String]
    let isInteractive: Bool
    private var answers: [String]

    init(_ lines: [String], answers: [String] = []) {
        self.lines = lines
        self.answers = answers
        isInteractive = !answers.isEmpty
    }

    func next() async -> String? { lines.isEmpty ? nil : lines.removeFirst() }
    func ask(_ question: String) async -> String? { answers.isEmpty ? nil : answers.removeFirst() }
}

/// The replies a session made.
final class Replies: @unchecked Sendable {
    var all: [Composer.Reply] = []
    var failures: [String] { all.compactMap { if case .failed(let message) = $0 { message } else { nil } } }
}

@ButtonHeistActor
struct ComposerSessionTests {
    let url = FileManager.default.temporaryDirectory.appending(path: "retake-compose-\(UUID().uuidString)/a.json")

    func session(
        _ lines: [String], answers: [String] = [], driver: FakeDriver = FakeDriver(), steps: [Step] = [], time: FakeTime = FakeTime(),
    ) async throws -> (Composer.Ending, Composer.State, Replies) {
        var document = SceneDocument(url: url, scene: nil, text: nil, newOn: "base")
        document.steps = steps
        let state = Composer.State(document: document, scene: SceneFile(set: "base", steps: []))
        let replies = Replies()
        let ending = try await Composer.session("a", state: state, on: driver, input: ScriptedInput(lines, answers: answers), player: time.player()) {
            replies.all.append($0)
        }
        return (ending, state, replies)
    }

    @Test func aStepThatRunsIsAddedAndWrittenAndOneThatDoesntIsLeftOut() async throws {
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let driver = FakeDriver()
        driver.failingRun = 1
        let (ending, state, replies) = try await session([#"tap --label "New Note""#, #"tap --label Nowhere"#, "set --hold 2", "set --id new-note", "quit"], driver: driver)
        #expect(ending == .quit)
        #expect(state.document.steps == [Step(id: "new-note", .tapElement(ElementTarget(label: "New Note")), hold: 2)])
        #expect(replies.failures == [#"step 2 of 2, tap "Nowhere", didn't run: No match for: label="Send""#])
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written.contains(#"{ "tap": { "label": "New Note" }, "hold": 2, "id": "new-note" }"#))
    }

    @Test func undoDropsTheLastStepsAndEndsTheLaunchForAReplay() async throws {
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let steps = [Step(nil, hold: 1), Step(.tapElement(ElementTarget(label: "A"))), Step(.tapElement(ElementTarget(label: "B")))]
        let (ending, state, _) = try await session(["undo", "steps"], steps: steps)
        #expect(ending == .relaunch && state.document.steps == Array(steps.prefix(2)))
        let (_, two, replies) = try await session(["undo 4", "undo 2"], steps: steps)
        #expect(replies.failures == ["There are 3 steps to undo, not 4."])
        #expect(two.document.steps == [Step(nil, hold: 1)])
    }

    @Test func replayRelaunchesDroppingNothing() async throws {
        let steps = [Step(.tapElement(ElementTarget(label: "A")))]
        let (ending, state, _) = try await session(["replay"], steps: steps)
        #expect(ending == .relaunch && state.document.steps == steps)
    }

    @Test func aReplayWaitsOutEachStepsHoldButAStepGivenNowDoesnt() async throws {
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let time = FakeTime()
        let steps = [Step(.tapElement(ElementTarget(label: "A")), hold: 1.5), Step(nil, hold: 0.5)]
        _ = try await session([#"tap --label "B" --hold 2"#, "quit"], steps: steps, time: time)
        #expect(time.pauses == [1.5, 0.5])
    }

    @Test func inspectWithAnElementListsOnlyItsMatchesInOrder() async throws {
        let driver = FakeDriver()
        let delete = { (row: String) in ScreenElement(label: "Delete", value: row, traits: ["button"]) }
        driver.screens = [[delete("Groceries"), ScreenElement(label: "Delete", traits: ["header"]), delete("Book club")]]
        let (_, _, replies) = try await session([#"inspect --label "Delete" --traits button"#, #"inspect --label "Delete" --value "Book club""#, "inspect"], driver: driver)
        let matches = replies.all.compactMap { reply -> [ScreenElement]? in
            if case .matches(let elements) = reply { elements } else { nil }
        }
        #expect(matches == [[delete("Groceries"), delete("Book club")], [delete("Book club")]])
    }

    @Test func anIDMustBeOneAStepCanHave() async throws {
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (_, state, replies) = try await session(["tap --x 1 --y 2 --id start", "tap --x 1 --y 2 --id a", "tap --x 1 --y 2 --id a", "set --id 3"])
        #expect(state.document.steps.map(\.id) == ["a"])
        #expect(replies.failures.count == 3)
    }

    @Test func atATerminalWhatsMissingIsAskedFor() async throws {
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // No label, then a value, for the element; then the text, with a return in it.
        let (_, state, replies) = try await session(["type", "quit"], answers: [#"Groceries\n"#])
        #expect(replies.failures.isEmpty)
        #expect(state.document.steps == [Step(.type(text: "Groceries\n", into: nil))])
        let (_, asked, _) = try await session(["tap", "quit"], answers: ["", "Title"])
        #expect(asked.document.steps == [Step(.tapElement(ElementTarget(value: "Title")))])
    }

    @Test func fromAPipeWhatsMissingFailsAndNothingIsAsked() async throws {
        let (_, state, replies) = try await session(["tap"])
        #expect(state.document.steps.isEmpty)
        #expect(replies.failures == ["tap needs an element (--label, --value, --identifier, --hint or --traits); `help tap` lists its options."])
    }
}
