import Foundation
import RetakeCore
import Testing

struct SupportLibraryTests {
    @Test func theContractVersionIsTheHeaders() throws {
        let header = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Support/RetakeSupport.h")
        let text = try String(contentsOf: header, encoding: .utf8)
        #expect(text.contains("#define RETAKE_SUPPORT_CONTRACT \(SupportLibrary.contractVersion)\n"))
    }

    @Test func aSetBecomesTheEnvironmentTheLibraryReads() throws {
        let set = ResolvedSet(
            name: "returning-user",
            state: .cloned,
            defaults: [Named("hasSeenWelcome", .bool(true)), Named("sortOrder", .string("title")), Named("recent", .array([.number(1), .number(2)]))],
        )
        let environment = SupportLibrary.environment(for: set, type: .ipad, take: "create-note-3")
        #expect(environment["RETAKE_STATE"] == "cloned")
        #expect(environment["RETAKE_TAKE"] == "create-note-3")
        let defaults = try JSONParser.parse(try #require(environment["RETAKE_DEFAULTS"]))
        #expect(defaults == .object(JSONObject([
            .init(key: "hasSeenWelcome", value: .bool(true)),
            .init(key: "sortOrder", value: .string("title")),
            .init(key: "recent", value: .array([.number(1), .number(2)])),
        ])))
        #expect(SupportLibrary.environment(for: ResolvedSet(name: "plain"), type: .ipad, take: "t")["RETAKE_DEFAULTS"] == "{}")
        #expect(environment["RETAKE_ASPECT_PORTRAIT"] == nil)
    }

    @Test func aSetsAppearanceHoldsTheAppToIt() {
        #expect(SupportLibrary.environment(for: ResolvedSet(name: "plain"), type: .ipad, take: "t")["RETAKE_APPEARANCE"] == nil)
        let light = ResolvedSet(name: "a", appearance: .light)
        #expect(SupportLibrary.environment(for: light, type: .ipad, take: "t")["RETAKE_APPEARANCE"] == "light")
        let reader = JSONReader(file: "sets/a.json")
        #expect(SetFile.read(#"{"appearance": "dark"}"#, with: reader)?.appearance == .dark)
        #expect(SetFile.read(#"{"appearance": "sepia"}"#, with: reader) == nil)
    }

    @Test func aSetsAspectForTheDeviceTypeBecomesItsShapes() {
        let set = ResolvedSet(name: "a", aspect: [
            .ipad: SetFile.AspectChoice(portrait: .init(width: 3, height: 4)),
            .iphone: SetFile.AspectChoice(portrait: .init(width: 9, height: 19.5), landscape: .init(width: 16, height: 9)),
        ])
        let ipad = SupportLibrary.environment(for: set, type: .ipad, take: "t")
        #expect(ipad["RETAKE_ASPECT_PORTRAIT"] == "3:4" && ipad["RETAKE_ASPECT_LANDSCAPE"] == "4:3")
        let iphone = SupportLibrary.environment(for: set, type: .iphone, take: "t")
        #expect(iphone["RETAKE_ASPECT_PORTRAIT"] == "9:19.5" && iphone["RETAKE_ASPECT_LANDSCAPE"] == "16:9")
    }

    @Test func theLaunchReportIsCheckedAgainstTheTakeAndTheContract() throws {
        let data = Data(#"{"contract":2,"home":"~/tmp/RetakeTakes/a2","milliseconds":5.49,"state":"clean","take":"a2"}"#.utf8)
        let report = try #require(LaunchReport.parse(data))
        #expect(report == LaunchReport(contract: 2, take: "a2", state: "clean", milliseconds: 5.49))
        try report.check(take: "a2")
        #expect(throws: RetakeError.self) { try report.check(take: "a3") }
        #expect(throws: RetakeError.self) { try LaunchReport(contract: 99, take: "a2", state: "clean").check(take: "a2") }
        #expect(LaunchReport.parse(Data(#"{"cleanedUp":true,"contract":1,"state":"","take":""}"#.utf8))?.cleanedUp == true)
        #expect(LaunchReport.parse(Data("{}".utf8)) == nil)
    }

    @Test func aReleasesLibraryIsFoundBeforeALocalBuild() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "RetakeSupport-\(UUID().uuidString)", directoryHint: .isDirectory)
        let executable = root.appending(path: "release/bin/retake")
        let cache = root.appending(path: "cache", directoryHint: .isDirectory)
        #expect(throws: RetakeError.self) { try SupportLibrary.locate(executable: executable, cache: cache) }
        let built = cache.appending(path: "\(SupportLibrary.contractVersion)/RetakeSupport.dylib")
        try FileManager.default.createDirectory(at: built.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: built)
        #expect(try SupportLibrary.locate(executable: executable, cache: cache).file.path == built.path)
        let shipped = root.appending(path: "release/share/retake/RetakeSupport.dylib")
        try FileManager.default.createDirectory(at: shipped.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: shipped)
        #expect(try SupportLibrary.locate(executable: executable, cache: cache).file.path == shipped.path)
    }
}
