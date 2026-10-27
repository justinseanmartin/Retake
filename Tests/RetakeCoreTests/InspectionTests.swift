import ButtonHeist
import Foundation
@testable import RetakeCore
import Testing

/// What an inspection showed.
final class Shown: @unchecked Sendable {
    var screens: [[ScreenElement]] = []
}

@ButtonHeistActor
struct InspectionTests {
    func label(_ text: String) -> ScreenElement { ScreenElement(label: text) }

    @Test func theFirstScreenIsShownOnceItHasSettled() async throws {
        let driver = FakeDriver()
        driver.screens = [[label("Loading")], [label("Library")], [label("Library")]]
        let shown = Shown()
        try await Inspection(pause: { _ in }, show: { shown.screens.append($0) }).look(on: driver, watching: false)
        #expect(shown.screens == [[label("Library")]])
    }

    @Test func watchingShowsEachChangeOnceItHoldsAndNothingInBetween() async throws {
        let driver = FakeDriver()
        // Settled; unchanged; a frame mid-change; the change, twice; back; back again.
        driver.screens = [[label("A")], [label("A")], [label("A")], [label("A→B")], [label("B")], [label("B")], [label("A")], [label("A")]]
        let shown = Shown()
        let watch = Inspection(pause: { _ in }, stopped: { shown.screens.count >= 3 }, show: { shown.screens.append($0) })
        try await watch.look(on: driver, watching: true)
        #expect(shown.screens == [[label("A")], [label("B")], [label("A")]])
    }

    @Test func aScreenThatNeverSettlesIsShownAnyway() async throws {
        let driver = FakeDriver()
        driver.screens = (0..<20).map { [label("frame \($0)")] }
        let shown = Shown()
        try await Inspection(pause: { _ in }, show: { shown.screens.append($0) }).look(on: driver, watching: false)
        #expect(shown.screens.count == 1, "after \(Inspection.settleTimeout) s")
    }

    @Test func theSetIsTheOneNamedOrTheProjectsDefault() throws {
        let example = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Examples/RetakeNotes").standardizedFileURL
        let project = try Project.locate(configuration: nil, currentDirectory: example)
        #expect(try Inspection.set("returning-user", in: project).name == "returning-user")
        #expect(throws: RetakeError.self) { try Inspection.set(nil, in: project) }
        let withDefault = Project(configuration: project.configuration, settings: ProjectSettings(defaultSet: "base"))
        #expect(try Inspection.set(nil, in: withDefault).name == "base")
        do {
            _ = try Inspection.set("nope", in: project)
            Issue.record("a set that doesn't exist")
        } catch {
            #expect(error.status == .usage && error.message.hasPrefix("--set: there's no set \"nope\""))
        }
    }
}
