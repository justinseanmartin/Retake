import Foundation
import RetakeCore
import Testing

struct ProjectSettingsTests {
    func read(_ text: String) -> (settings: ProjectSettings?, problems: [String]) {
        let reader = JSONReader(file: "retake.json")
        let settings = ProjectSettings.read(text, with: reader)
        return (settings, reader.problems.map(\.description))
    }

    @Test func anEmptyFileIsAProjectWithNothingSet() {
        #expect(read("{}").settings == ProjectSettings())
    }

    @Test func everyFieldReads() {
        let result = read(#"""
            {"bundleID": "com.example.notes", "device": "ipad", "defaultSet": "returning-user", "output": "../Takes",
             "build": {"scheme": "Notes", "workspace": "Notes.xcworkspace", "configuration": "Preview", "allowProvisioningUpdates": true}}
            """#)
        #expect(result.problems.isEmpty)
        #expect(result.settings == ProjectSettings(
            bundleID: "com.example.notes",
            build: .scheme(.init(scheme: "Notes", container: .workspace("Notes.xcworkspace"), configuration: "Preview", allowProvisioningUpdates: true)),
            device: "ipad",
            defaultSet: "returning-user",
            output: "../Takes",
        ))
        #expect(read(#"{"build": {"command": "scripts/build.sh", "app": "build/Notes.app"}}"#).settings?.build
            == .command(.init(command: "scripts/build.sh", app: "build/Notes.app")))
    }

    @Test(arguments: [
        (#"{"build": {"scheme": "A", "command": "b"}}"#, #"retake.json: build: give "scheme", for Retake to build it with xcodebuild, or "command", to run your own build, not both"#),
        (#"{"build": {}}"#, #"retake.json: build: needs "scheme", for Retake to build it with xcodebuild, or "command", to run your own build"#),
        (#"{"build": {"scheme": "A", "workspace": "a", "xcodeproj": "b"}}"#, #"retake.json: build: give "workspace" or "xcodeproj", not both"#),
        (#"{"build": {"command": "b", "app": "a", "allowProvisioningUpdates": true}}"#, #"retake.json: build: "allowProvisioningUpdates" goes with "scheme"; with "command", your own build decides it"#),
        (#"{"build": {"scheme": "A", "app": "a"}}"#, #"retake.json: build: "app" goes with "command"; with "scheme", Retake finds the app from the build"#),
        (#"{"build": {"command": "b"}}"#, #"retake.json: build: is missing "app""#),
        (#"{"bundleID": "com.example notes"}"#, #"retake.json: bundleID: "com.example notes" isn't a bundle ID: letters, digits, "-" and ".", such as com.example.notes"#),
        (#"{"bundleID": "com..notes"}"#, #"retake.json: bundleID: "com..notes" isn't a bundle ID: letters, digits, "-" and ".", such as com.example.notes"#),
        (#"{"device": ""}"#, "retake.json: device: can't be empty"),
        (#"{"defaultset": "a"}"#, #"retake.json: unknown key "defaultset"; did you mean "defaultSet"?"#),
        (#"{"build": {"scheme": "A", "sheme": "B"}}"#, #"retake.json: build: unknown key "sheme"; did you mean "scheme"?"#),
    ])
    func mistakesAreNamed(_ text: String, _ expected: String) {
        let result = read(text)
        #expect(result.problems == [expected])
        #expect(result.settings == nil)
    }

    @Test func whatsWrittenReadsBackTheSame() {
        let settings = ProjectSettings(
            bundleID: "com.example.notes",
            build: .scheme(.init(scheme: "Notes", container: .project("Notes.xcodeproj"))),
            defaultSet: "returning-user",
        )
        let text = JSONWriter.write(settings.json)
        #expect(read(text).settings == settings)
        #expect(text.hasPrefix(#"{\#n  "$schema": "\#(SchemaReference.current("retake").url)",\#n  "bundleID""#))
    }

    @Test func theOutputDirectoryIsTheCommandsThenTheFilesThenTheDefault() {
        let file = URL(filePath: "/work/Previews/retake.json")
        let configured = ProjectSettings(output: "../Takes")
        #expect(Project(configuration: file).output.path == "/work/Previews/RetakeOutput")
        #expect(Project(configuration: file, settings: configured).output.path == "/work/Takes")
        #expect(Project(configuration: file, settings: configured, output: URL(filePath: "/tmp/run")).output.path == "/tmp/run")
    }

    @Test func theExamplesConfigurationReadsCleanly() throws {
        let example = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Examples/RetakeNotes/retake.json")
        let text = try String(contentsOf: example, encoding: .utf8)
        let result = read(text)
        #expect(result.problems.isEmpty)
        #expect(result.settings?.bundleID == nil, "the example's bundle ID differs per developer, so it names none")
        guard case .scheme(let build)? = result.settings?.build else {
            Issue.record("the example builds with a scheme")
            return
        }
        #expect(build.scheme == "RetakeNotes")
    }
}

struct JSONWriterTests {
    @Test func writesInOrderAndReadsBack() throws {
        let text = #"{"z": 1, "list": [1, "two", true, null], "nested": {"b": [], "a": {}}, "rows": [{"x": 1}]}"#
        let value = try JSONParser.parse(text)
        let written = JSONWriter.write(value)
        #expect(written == """
            {
              "z": 1,
              "list": [1, "two", true, null],
              "nested": {
                "b": [],
                "a": {}
              },
              "rows": [
                {
                  "x": 1
                }
              ]
            }

            """)
        #expect(try JSONParser.parse(written) == value)
    }

    @Test func stringsRoundTripEveryCharacter() throws {
        let value = JSONValue.string("quote\" back\\ tab\t bell\u{07} é 🎬")
        #expect(try JSONParser.parse(JSONWriter.write(value)) == value)
    }
}

struct ProjectInitializerTests {
    struct Lister: ProjectInitializer.SchemeLister {
        var schemes: [String]
        func schemes(in container: ProjectSettings.Container, at directory: URL) throws -> [String] { schemes }
    }

    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "RetakeInitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func file(_ path: String) -> String? {
        FileManager.default.contents(atPath: directory.appending(path: path).path).map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func createsTheProjectWithTheOnlySchemeFound() throws {
        try FileManager.default.createDirectory(at: directory.appending(path: "Notes.xcodeproj"), withIntermediateDirectories: true)
        let result = try ProjectInitializer.initialize(in: directory, bundleID: nil, scheme: nil, lister: Lister(schemes: ["Notes"]))
        #expect(result.notes.isEmpty)
        for folder in ["sets", "scenes/iphone", "scenes/ipad", "edits"] {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: directory.appending(path: folder).path, isDirectory: &isDirectory) && isDirectory.boolValue)
        }
        let project = try Project.locate(configuration: nil, currentDirectory: directory)
        #expect(project.settings.build == .scheme(.init(scheme: "Notes")))
        #expect(file(".gitignore") == "RetakeOutput/\n")
    }

    @Test func aWorkspaceBesideItsProjectIsNamed() throws {
        for name in ["Notes.xcodeproj", "Notes.xcworkspace"] {
            try FileManager.default.createDirectory(at: directory.appending(path: name), withIntermediateDirectories: true)
        }
        let result = try ProjectInitializer.initialize(in: directory, bundleID: "com.example.notes", scheme: nil, lister: Lister(schemes: ["Notes"]))
        #expect(result.settings == ProjectSettings(bundleID: "com.example.notes", build: .scheme(.init(scheme: "Notes", container: .workspace("Notes.xcworkspace")))))
    }

    @Test func severalSchemesAreAskedAboutOrLeftForThePersonToGive() throws {
        try FileManager.default.createDirectory(at: directory.appending(path: "Notes.xcodeproj"), withIntermediateDirectories: true)
        var asked: [String] = []
        let unanswered = try ProjectInitializer.initialize(in: directory, bundleID: nil, scheme: nil, lister: Lister(schemes: ["Notes", "NotesKit"])) {
            asked = $0
            return nil
        }
        #expect(asked == ["Notes", "NotesKit"])
        #expect(unanswered.settings.build == nil)
        #expect(unanswered.notes.count == 1 && unanswered.notes[0].contains("several schemes"))
    }

    @Test func aGivenSchemeNeedsNoXcodeProject() throws {
        let result = try ProjectInitializer.initialize(in: directory, bundleID: nil, scheme: "Notes", lister: Lister(schemes: []))
        #expect(result.settings.build == .scheme(.init(scheme: "Notes")))
        #expect(result.notes.isEmpty)
    }

    @Test func anExistingProjectIsLeftAlone() throws {
        _ = try ProjectInitializer.initialize(in: directory, bundleID: nil, scheme: "Notes", lister: Lister(schemes: []))
        do {
            _ = try ProjectInitializer.initialize(in: directory, bundleID: nil, scheme: "Other", lister: Lister(schemes: []))
            Issue.record("initialized twice")
        } catch {
            #expect(error.status == .usage)
        }
    }

    @Test func gitignoreGainsTheOutputDirectoryOnce() throws {
        try Data("build/".utf8).write(to: directory.appending(path: ".gitignore"))
        _ = try ProjectInitializer.initialize(in: directory, bundleID: nil, scheme: "Notes", lister: Lister(schemes: []))
        #expect(file(".gitignore") == "build/\nRetakeOutput/\n")

        let other = directory.appending(path: "other", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("/RetakeOutput\n".utf8).write(to: other.appending(path: ".gitignore"))
        _ = try ProjectInitializer.initialize(in: other, bundleID: nil, scheme: "Notes", lister: Lister(schemes: []))
        #expect(FileManager.default.contents(atPath: other.appending(path: ".gitignore").path) == Data("/RetakeOutput\n".utf8))
    }

    @Test func aMalformedBundleIDIsMisuse() {
        #expect(throws: RetakeError.self) {
            try ProjectInitializer.initialize(in: directory, bundleID: "not a bundle id", scheme: "Notes", lister: Lister(schemes: []))
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "retake.json").path))
    }
}
