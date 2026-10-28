import Foundation
@testable import RetakeCore
import Testing

struct ArchiveCheckTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RetakeCheck-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// An app at `path` under the root, with frameworks named `frameworks`, and extensions.
    @discardableResult
    func app(_ path: String, frameworks: [String] = [], extensions: [String: [String]] = [:]) throws -> URL {
        let url = root.appending(path: path, directoryHint: .isDirectory)
        func make(_ bundle: URL, _ executable: String, _ frameworks: [String]) throws {
            try FileManager.default.createDirectory(at: bundle.appending(path: "Frameworks"), withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleExecutable": executable, "CFBundleIdentifier": "com.example.\(executable)"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appending(path: "Info.plist"))
            try Data().write(to: bundle.appending(path: executable))
            for name in frameworks {
                let framework = bundle.appending(path: "Frameworks/\(name)")
                if name.hasSuffix(".framework") {
                    try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
                } else {
                    try Data().write(to: framework)
                }
            }
        }
        try make(url, "Notes", frameworks)
        for (name, frameworks) in extensions {
            try make(url.appending(path: "PlugIns/\(name).appex", directoryHint: .isDirectory), name, frameworks)
        }
        return url
    }

    func check(_ path: String, symbols: @escaping (URL) throws(RetakeError) -> [String] = { _ in [] }) throws -> [String] {
        try ArchiveCheck.check(root.appending(path: path), symbols: symbols)
    }

    @Test func aCleanAppArchiveOrIPAHasNothing() throws {
        try app("Notes.app", frameworks: ["Firebase.framework"])
        #expect(try check("Notes.app") == [])
        try app("Notes.xcarchive/Products/Applications/Notes.app", frameworks: ["Firebase.framework"])
        #expect(try check("Notes.xcarchive") == [])
    }

    @Test func anEmbeddedAppIsCaughtInAnArchive() throws {
        try app("Notes.xcarchive/Products/Applications/Notes.app", frameworks: ["TheInsideJob.framework", "RetakeSupport.dylib"])
        #expect(try check("Notes.xcarchive") == [
            "Products/Applications/Notes.app/Frameworks/RetakeSupport.dylib",
            "Products/Applications/Notes.app/Frameworks/TheInsideJob.framework",
        ])
    }

    @Test func whatCantBeReadFailsTheCheckRatherThanPassingIt() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try app("Notes.app", frameworks: ["TheInsideJob.framework"])
        let frameworks = app.appending(path: "Frameworks")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: frameworks.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: frameworks.path) }
        #expect(throws: RetakeError.self, "a sandboxed build phase can't list it") { try check("Notes.app") }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: frameworks.path)
        #expect(throws: RetakeError.self, "nm couldn't read an executable") {
            try check("Notes.app") { _ throws(RetakeError) in throw RetakeError(.failed, "unreadable") }
        }
    }

    @Test func whatCantBeReadSaysWhatToDo() {
        let frameworks = URL(filePath: "/b/Notes.app/Frameworks")
        let inPhase = AppBundle.unreadable(frameworks, because: "Operation not permitted", environment: ["SCRIPT_INPUT_FILE_COUNT": "1"])
        #expect(inPhase.status == .failed)
        #expect(inPhase.message.hasPrefix("Couldn't read /b/Notes.app/Frameworks (Operation not permitted), so the app can't be cleared of TheInsideJob."))
        #expect(inPhase.message.contains("add /b/Notes.app/Frameworks to the phase's Input Files"))
        let elsewhere = AppBundle.unreadable(frameworks, because: "Permission denied", environment: [:])
        #expect(elsewhere.message.hasSuffix("Make it readable, and run `retake check` again."))
    }

    @Test func aStaticLinkIsCaughtByItsSymbols() throws {
        try app("Notes.app")
        let found = try check("Notes.app") { $0.lastPathComponent == "Notes" ? ["_$s12TheInsideJob6ServerC"] : [] }
        #expect(found == ["Notes (TheInsideJob linked into it)"])
    }

    @Test func anExtensionsFrameworksAreLookedThroughToo() throws {
        try app("Notes.app", extensions: ["Widget": ["TheInsideJob.framework"]])
        #expect(try check("Notes.app") == ["PlugIns/Widget.appex/Frameworks/TheInsideJob.framework"])
    }

    @Test func anIPAIsUnpackedAndLookedThrough() throws {
        try app("ipa/Payload/Notes.app", frameworks: ["TheInsideJob.framework"])
        let ipa = root.appending(path: "Notes.ipa")
        let result = try Subprocess.run("/usr/bin/ditto", ["-c", "-k", root.appending(path: "ipa").path, ipa.path])
        #expect(result.status == 0)
        let found = try check("Notes.ipa")
        #expect(found == ["Payload/Notes.app/Frameworks/TheInsideJob.framework"])
    }

    @Test func somethingElseIsMisuse() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appending(path: "notes.txt"))
        do {
            _ = try check("notes.txt")
            Issue.record("checked a text file")
        } catch let error as RetakeError {
            #expect(error.status == .usage)
        }
    }
}
