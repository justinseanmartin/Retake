import Foundation
import RetakeCore
import Testing

struct InsideJobFrameworkTests {
    let root: URL
    let executable: URL
    let cache: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RetakeInsideJob-\(UUID().uuidString)", directoryHint: .isDirectory)
        executable = root.appending(path: "release/bin/retake")
        cache = root.appending(path: "cache", directoryHint: .isDirectory)
    }

    /// A framework bundle at `bundle` naming `version`, with its device slice unless told otherwise.
    func make(_ bundle: URL, version: String, deviceSlice: Bool = true) throws {
        let framework = bundle.appending(path: deviceSlice ? "ios-arm64/TheInsideJob.framework" : "ios-arm64_x86_64-simulator/TheInsideJob.framework")
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try Data("\(version)\n".utf8).write(to: bundle.appending(path: "VERSION"))
    }

    func locate(builtFromClone: Bool = false) throws(RetakeError) -> InsideJobFramework {
        try InsideJobFramework.locate(executable: executable, cache: cache, builtFromClone: builtFromClone, expectedVersion: "0.7.1")
    }

    @Test func aReleaseCarriesItsOwnBesideTheBinary() throws {
        try make(root.appending(path: "release/share/retake/TheInsideJob.xcframework"), version: "0.7.1")
        try make(cache.appending(path: "0.7.1/TheInsideJob.xcframework"), version: "0.7.1")
        #expect(try locate().bundle.path.hasSuffix("release/share/retake/TheInsideJob.xcframework"))
    }

    @Test func aLocalBuildFindsTheFetchedOne() throws {
        try make(cache.appending(path: "0.7.1/TheInsideJob.xcframework"), version: "0.7.1")
        let framework = try locate()
        #expect(framework.version == "0.7.1")
        #expect(framework.deviceFramework.path.hasSuffix("0.7.1/TheInsideJob.xcframework/ios-arm64/TheInsideJob.framework"))
    }

    @Test func aBuildFromACloneFindsTheClonesAndNotTheReleases() throws {
        try make(cache.appending(path: "0.7.1/TheInsideJob.xcframework"), version: "0.7.1")
        #expect(throws: RetakeError.self) { try locate(builtFromClone: true) }
        try make(cache.appending(path: "clone/TheInsideJob.xcframework"), version: "0.7.1")
        try Data(#"{"path": "/src/TheButtonHeist", "commit": "5d05a318-dirty"}"#.utf8).write(to: cache.appending(path: "clone/clone.json"))
        #expect(try locate(builtFromClone: true).bundle.path.hasSuffix("clone/TheInsideJob.xcframework"))
        #expect(InsideJobFramework.clone(in: cache) == InsideJobFramework.Clone(path: "/src/TheButtonHeist", commit: "5d05a318-dirty"))
    }

    @Test func anotherVersionsFrameworkIsRefused() throws {
        try make(cache.appending(path: "0.7.1/TheInsideJob.xcframework"), version: "0.6.38")
        do {
            _ = try locate()
            Issue.record("used a framework of another version")
        } catch {
            #expect(error.status == .environment && error.message.contains("is TheInsideJob 0.6.38"))
        }
    }

    @Test func withNoneItSaysHowToGetOne() throws {
        do {
            _ = try locate()
            Issue.record("found a framework where there's none")
        } catch {
            #expect(error.status == .environment && error.message.contains("/Scripts/build.sh"), "\(error.message)")
        }
        try make(cache.appending(path: "0.7.1/TheInsideJob.xcframework"), version: "0.7.1", deviceSlice: false)
        #expect(throws: RetakeError.self) { try locate() }
    }
}
