import Foundation
@testable import RetakeCore
import Testing

struct EmbeddingTests {
    let app: AppBundle

    init() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "RetakeEmbed-\(UUID().uuidString)/Notes.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url.appending(path: "Frameworks"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.example.notes", "CFBundleExecutable": "Notes", "CFBundleSupportedPlatforms": ["iPhoneOS"],
                                   "CFBundleShortVersionString": "1.9.0", "CFBundleVersion": "412"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: url.appending(path: "Info.plist"))
        try Data().write(to: url.appending(path: "Notes"))
        try Data().write(to: url.appending(path: "Notes.debug.dylib"))
        app = AppBundle(url: url)
    }

    func addFramework(_ name: String) throws {
        let framework = app.frameworks.appending(path: "\(name).framework")
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try Data().write(to: framework.appending(path: name))
    }

    @Test func anAppIsReadForWhatEmbedNeeds() throws {
        #expect(app.bundleID == "com.example.notes" && app.isForDevices)
        #expect(app.version.version == "1.9.0" && app.version.build == "412")
        #expect(try app.executables().map(\.lastPathComponent) == ["Notes", "Notes.debug.dylib"])
    }

    @Test func theInsideJobIsFoundByNameAndBySymbol() throws {
        #expect(try InsideJobDetector.find(in: app, symbols: { _ in [] }) == [])
        try addFramework("Firebase")
        try addFramework("TheInsideJob")
        #expect(try InsideJobDetector.find(in: app, symbols: { _ in [] }) == ["Frameworks/TheInsideJob.framework"])
        let linked = try InsideJobDetector.find(in: app, symbols: { url in
            url.lastPathComponent == "Notes.debug.dylib" ? ["_$s12TheInsideJob6ServerC5startyyF"] : []
        })
        #expect(linked == ["Frameworks/TheInsideJob.framework", "Notes.debug.dylib (TheInsideJob linked into it)"])
    }

    @Test func otherButtonHeistModulesArentMistakenForIt() throws {
        let found = try InsideJobDetector.find(in: app, symbols: { _ in ["_$s8TheScore7MessageO", "_TheInsideJobVersionString", "_$s11ButtonHeist8TheFenceC"] })
        #expect(found.isEmpty, "\(found)")
    }

    @Test func whatAnEarlierEmbedAddedIsLeftForEmbedToReplace() throws {
        try addFramework("TheInsideJob")
        try Data().write(to: app.frameworks.appending(path: "RetakeSupport.dylib"))
        let ignoring: Set = ["Frameworks/TheInsideJob.framework", "Frameworks/RetakeSupport.dylib"]
        let symbols = { (url: URL) in url.lastPathComponent == "TheInsideJob" ? ["_$s12TheInsideJob6ServerC"] : [] }
        #expect(try InsideJobDetector.find(in: app, ignoring: ignoring, symbols: symbols) == [])
        #expect(try InsideJobDetector.find(in: app, symbols: { _ in [] }) == ["Frameworks/RetakeSupport.dylib", "Frameworks/TheInsideJob.framework"])
    }

    @Test func theEmbedRecordIsWrittenInTheAppsOwnFormat() throws {
        let record = AppBundle.EmbedRecord(retakeVersion: "0.0.1", supportContract: 1, buttonHeistVersion: "0.7.1", added: ["Frameworks/TheInsideJob.framework"])
        var (info, format) = try app.readInfo()
        #expect(format == .binary)
        info[AppBundle.recordKey] = record.plist
        try app.writeInfo(info, format: format)
        #expect(app.embedRecord == record)
        #expect(try app.readInfo().format == .binary)
        #expect(app.bundleID == "com.example.notes", "the rest of Info.plist is kept")
    }

    let profile: [String: Any] = ["Entitlements": [
        "application-identifier": "ABCDE12345.*",
        "com.apple.developer.team-identifier": "ABCDE12345",
        "get-task-allow": true,
        "keychain-access-groups": ["ABCDE12345.*", "com.apple.token"],
    ] as [String: Any]]

    @Test func anUnsignedAppGetsTheProfilesEntitlementsForItsBundleID() throws {
        let entitlements = try Signing.entitlements(fromProfile: profile, bundleID: "com.example.notes")
        #expect(entitlements["application-identifier"] as? String == "ABCDE12345.com.example.notes")
        #expect(entitlements["keychain-access-groups"] as? [String] == ["ABCDE12345.com.example.notes"])
        #expect(Signing.isDevelopment(entitlements))
    }

    @Test func aProfileThatCantSignTheAppIsRefused() {
        var explicit = profile
        explicit["Entitlements"] = ["application-identifier": "ABCDE12345.com.example.other", "com.apple.developer.team-identifier": "ABCDE12345", "get-task-allow": true]
        #expect(throws: RetakeError.self) { try Signing.entitlements(fromProfile: explicit, bundleID: "com.example.notes") }
        var distribution = profile
        distribution["Entitlements"] = ["application-identifier": "ABCDE12345.*", "com.apple.developer.team-identifier": "ABCDE12345", "get-task-allow": false]
        #expect(throws: RetakeError.self) { try Signing.entitlements(fromProfile: distribution, bundleID: "com.example.notes") }
        #expect(throws: RetakeError.self) { try Signing.entitlements(fromProfile: [:], bundleID: "com.example.notes") }
    }
}
