import Foundation
import RetakeCore
import Testing

/// Takes on disk, as `takes` lists them and `clean` deletes them.
struct TakeStoreTests {
    let root: URL
    let project: Project

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "RetakeTakeStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        project = Project(configuration: root.appending(path: "retake.json"))
        try FileManager.default.createDirectory(at: project.edits, withIntermediateDirectories: true)
        // Two takes of a, the second, the latest, cut from by video1; one of b, failed; c's 1 has lost its movie.
        try record("a", 1)
        try record("a", 2)
        try record("b", 1, failure: "step 2 didn't run")
        try record("c", 1, movie: false)
        try record("a", 1, type: .iphone)
        for scene in ["a", "b", "c", "d"] { try write("scenes/ipad/\(scene).json", "{}") }
        try write("scenes/iphone/a.json", "{}")
        try write("edits/video1.json", #"{ "devices": ["ipad"], "clips": [{ "take": "a", "from": { "step": "start" }, "to": { "step": "end" }, "stills": [{ "take": "c", "at": 0 }] }] }"#)
        try write("output/cuts/ipad/video1/video1-ipad.mp4", "")
        try write("output/cuts/ipad/video2/video2-ipad.mp4", "")
    }

    func write(_ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func record(_ scene: String, _ take: Int, type: DeviceType = .ipad, failure: String? = nil, movie: Bool = true) throws {
        let log = TakeLogReadingTests.log(scene: scene, take: take, failure: failure)
        try write("output/takes/\(type.rawValue)/\(scene)/\(take).json", JSONWriter.write(log.json))
        if movie { try write("output/takes/\(type.rawValue)/\(scene)/\(take).mov", "") }
    }

    func names(_ takes: [TakeStore.Take]) -> [String] { takes.map { "\($0.type.rawValue) \($0.name)" } }

    @Test func takesAreListedByTypeSceneAndNumberWithTheEditsCutFromThem() {
        defer { try? FileManager.default.removeItem(at: root) }
        let takes = TakeStore.takes(for: DeviceType.allCases, in: project)
        #expect(names(takes) == ["iphone a@1", "ipad a@1", "ipad a@2", "ipad b@1", "ipad c@1"])
        #expect(takes.map(\.usedBy) == [[], [], ["video1"], [], []])
        #expect(takes.map(\.failed) == [false, false, false, true, false])
        #expect(takes[2].recorded?.dropped == 2)
        #expect(takes[4].problem == "output/takes/ipad/c/1.mov is missing")
        #expect(names(TakeStore.takes(of: "a", for: [.ipad], in: project)) == ["ipad a@1", "ipad a@2"])
    }

    @Test func aTakeANewerRetakeRecordedIsListedAsThatAndFailed() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let text = TakeLogReadingTests.text { $0.insert(.init(key: "format", value: 2), at: 0) }
        try write("output/takes/ipad/a/3.json", text)
        try write("output/takes/ipad/a/3.mov", "")
        let takes = TakeStore.takes(of: "a", for: [.ipad], in: project)
        #expect(takes.map(\.number) == [1, 2, 3])
        #expect(takes[2].failed && takes[2].problem == "output/takes/ipad/a/3.json: was recorded by a newer Retake, in step log format 2, which this Retake (\(RetakeVersion.current.version)) can't read; update Retake to use this take")
        #expect(takes[1].usedBy == ["video1"], "the latest take this Retake can read is still the one cut")
    }

    @Test func cleaningChoosesEverythingOrWhatsNamed() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let everything = try TakeStore.cleaning(takes: nil, cuts: nil, for: DeviceType.allCases, in: project)
        #expect(everything.takes.count == 5 && everything.cuts.map(\.lastPathComponent) == ["video1", "video2"])

        let allTakes = try TakeStore.cleaning(takes: [], cuts: nil, for: [.ipad], in: project)
        #expect(names(allTakes.takes) == ["ipad a@1", "ipad a@2", "ipad b@1", "ipad c@1"] && allTakes.cuts.isEmpty)

        let some = try TakeStore.cleaning(takes: [.take("a", 2), .scene("b")], cuts: ["video2"], for: DeviceType.allCases, in: project)
        #expect(names(some.takes) == ["ipad a@2", "ipad b@1"] && some.cuts.map(\.lastPathComponent) == ["video2"])
        #expect(names(some.used) == ["ipad a@2"])

        for (takes, cuts) in [([TakeStore.TakeChoice.take("a", 9)], nil), ([.scene("nowhere")], nil), (nil, ["video9"])] {
            #expect(throws: RetakeError.self) { try TakeStore.cleaning(takes: takes, cuts: cuts, for: DeviceType.allCases, in: project) }
        }
    }

    @Test func aTakeIsChosenAsASceneOrASceneAndNumber() throws {
        #expect(try TakeStore.TakeChoice.parse("create-note") == .scene("create-note"))
        #expect(try TakeStore.TakeChoice.parse("create-note@3") == .take("create-note", 3))
        for wrong in ["create-note@0", "create-note@x", "@3", "a@1@2"] {
            #expect(throws: RetakeError.self, "\(wrong)") { try TakeStore.TakeChoice.parse(wrong) }
        }
    }

    @Test func deletingTakesDeletesBothFilesButKeepsTheirNumbersUsed() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let cleaning = try TakeStore.cleaning(takes: [.scene("b"), .take("a", 2)], cuts: ["video1"], for: [.ipad], in: project)
        try TakeStore.delete(cleaning, in: project)
        #expect(names(TakeStore.takes(for: DeviceType.allCases, in: project)) == ["iphone a@1", "ipad a@1", "ipad c@1"])
        #expect(RecordRun.nextTake(of: "a", for: .ipad, in: project) == 3, "the deleted highest take's number isn't used again")
        #expect(RecordRun.nextTake(of: "b", for: .ipad, in: project) == 2, "nor a scene's whose every take is deleted")
        #expect(RecordRun.nextTake(of: "a", for: .iphone, in: project) == 2, "each device type is numbered apart")

        // Deleting again, with the marker there, keeps it.
        try TakeStore.delete(TakeStore.cleaning(takes: [.scene("a")], cuts: nil, for: [.ipad], in: project), in: project)
        #expect(RecordRun.nextTake(of: "a", for: .ipad, in: project) == 3)
        #expect(!FileManager.default.fileExists(atPath: project.cuts(for: .ipad).appending(path: "video1").path))
        #expect(FileManager.default.fileExists(atPath: project.cuts(for: .ipad).appending(path: "video2").path))
    }

    @Test func unusedKeepsNeededScenesAndTheirLatestSuccessfulTakes() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let cleaning = try TakeStore.unused(for: [.ipad], in: project)
        #expect(names(cleaning.takes) == ["ipad a@1", "ipad b@1", "ipad c@1"])
        #expect(cleaning.scenes.map(\.lastPathComponent) == ["b.json", "d.json"])
        #expect(cleaning.cuts.isEmpty)

        try TakeStore.delete(cleaning, in: project)

        #expect(names(TakeStore.takes(for: [.ipad], in: project)) == ["ipad a@2"])
        let files = ProjectFiles(project: project)
        #expect(files.names(in: project.scenes(for: .ipad)) == ["a", "c"])
        #expect(files.names(in: project.scenes(for: .iphone)) == ["a"], "--type leaves the other type alone")
    }

    @Test func unusedRefusesToGuessWhenAnEditCannotBeRead() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("edits/broken.json", #"{"clips": "not clips"}"#)
        #expect(throws: RetakeError.self) { try TakeStore.unused(for: DeviceType.allCases, in: project) }
        #expect(names(TakeStore.takes(for: DeviceType.allCases, in: project)).count == 5)
    }
}
