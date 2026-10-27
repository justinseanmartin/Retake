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
        let environment = SupportLibrary.environment(for: set, take: "create-note-3")
        #expect(environment["RETAKE_STATE"] == "cloned")
        #expect(environment["RETAKE_TAKE"] == "create-note-3")
        let defaults = try JSONParser.parse(try #require(environment["RETAKE_DEFAULTS"]))
        #expect(defaults == .object(JSONObject([
            .init(key: "hasSeenWelcome", value: .bool(true)),
            .init(key: "sortOrder", value: .string("title")),
            .init(key: "recent", value: .array([.number(1), .number(2)])),
        ])))
        #expect(SupportLibrary.environment(for: ResolvedSet(name: "plain"), take: "t")["RETAKE_DEFAULTS"] == "{}")
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
