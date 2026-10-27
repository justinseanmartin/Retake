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
        // Two takes of a, the second pinned by video1; one of b, failed; c's 1 has lost its movie.
        try record("a", 1)
        try record("a", 2)
        try record("b", 1, failure: "step 2 didn't run")
        try record("c", 1, movie: false)
        try record("a", 1, type: .iphone)
        try write("edits/video1.json", #"{ "devices": ["ipad"], "takes": { "ipad": { "a": 2 } }, "clips": [{ "take": "a", "from": { "step": "start" }, "to": { "step": "end" } }] }"#)
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

    @Test func takesAreListedByTypeSceneAndNumberWithWhatPinsThem() {
        defer { try? FileManager.default.removeItem(at: root) }
        let takes = TakeStore.takes(for: DeviceType.allCases, in: project)
        #expect(names(takes) == ["iphone a@1", "ipad a@1", "ipad a@2", "ipad b@1", "ipad c@1"])
        #expect(takes.map(\.pinnedBy) == [[], [], ["video1"], [], []])
        #expect(takes.map(\.failed) == [false, false, false, true, false])
        #expect(takes[2].recorded?.dropped == 2)
        #expect(takes[4].problem == "output/takes/ipad/c/1.mov is missing")
        #expect(names(TakeStore.takes(of: "a", for: [.ipad], in: project)) == ["ipad a@1", "ipad a@2"])
    }

    @Test func cleaningChoosesEverythingOrWhatsNamed() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let everything = try TakeStore.cleaning(takes: nil, cuts: nil, for: DeviceType.allCases, in: project)
        #expect(everything.takes.count == 5 && everything.cuts.map(\.lastPathComponent) == ["video1", "video2"])

        let allTakes = try TakeStore.cleaning(takes: [], cuts: nil, for: [.ipad], in: project)
        #expect(names(allTakes.takes) == ["ipad a@1", "ipad a@2", "ipad b@1", "ipad c@1"] && allTakes.cuts.isEmpty)

        let some = try TakeStore.cleaning(takes: [.take("a", 2), .scene("b")], cuts: ["video2"], for: DeviceType.allCases, in: project)
        #expect(names(some.takes) == ["ipad a@2", "ipad b@1"] && some.cuts.map(\.lastPathComponent) == ["video2"])
        #expect(names(some.pinned) == ["ipad a@2"])

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

    @Test func deletingTakesBothFilesAndASceneFolderLeftEmpty() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let cleaning = try TakeStore.cleaning(takes: [.scene("b"), .take("a", 1)], cuts: ["video1"], for: [.ipad], in: project)
        try TakeStore.delete(cleaning, in: project)
        #expect(names(TakeStore.takes(for: DeviceType.allCases, in: project)) == ["iphone a@1", "ipad a@2", "ipad c@1"])
        #expect(!FileManager.default.fileExists(atPath: project.takes(for: .ipad).appending(path: "b").path))
        #expect(!FileManager.default.fileExists(atPath: project.cuts(for: .ipad).appending(path: "video1").path))
        #expect(FileManager.default.fileExists(atPath: project.cuts(for: .ipad).appending(path: "video2").path))
    }
}
