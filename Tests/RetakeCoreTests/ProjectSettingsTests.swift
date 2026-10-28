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
        #expect(Project(configuration: file).output.path == "/work/Previews/output")
        #expect(Project(configuration: file, settings: configured).output.path == "/work/Takes")
        #expect(Project(configuration: file, settings: configured, output: URL(filePath: "/tmp/run")).output.path == "/tmp/run")
    }

    @Test func theExamplesConfigurationReadsCleanly() throws {
        let example = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Examples/Notes/Retake/retake.json")
        let text = try String(contentsOf: example, encoding: .utf8)
        let result = read(text)
        #expect(result.problems.isEmpty)
        #expect(result.settings?.bundleID == nil, "the example's bundle ID differs per developer, so it names none")
        guard case .scheme(let build)? = result.settings?.build else {
            Issue.record("the example builds with a scheme")
            return
        }
        #expect(build.scheme == "Notes")
        #expect(build.container == .project("../Notes.xcodeproj"), "xcodebuild runs in Retake/, beside no Xcode project")
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
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func file(_ path: String) -> String? {
        FileManager.default.contents(atPath: directory.appending(path: path).path).map { String(decoding: $0, as: UTF8.self) }
    }

    func folder(_ name: String) throws {
        try FileManager.default.createDirectory(at: directory.appending(path: name), withIntermediateDirectories: true)
    }

    @discardableResult
    func initialize(
        _ configuration: String = "Retake/retake.json",
        output: URL? = nil,
        bundleID: String? = nil,
        scheme: String? = nil,
        schemes: [String] = [],
        ask: ([String]) -> String? = { _ in nil },
    ) throws(RetakeError) -> ProjectInitializer.Result {
        try ProjectInitializer.initialize(
            configuration: directory.appending(path: configuration),
            output: output,
            currentDirectory: directory,
            bundleID: bundleID,
            scheme: scheme,
            lister: Lister(schemes: schemes),
            ask: ask,
        )
    }

    @Test func createsTheProjectInRetakeNamingTheXcodeProjectAboveIt() throws {
        try folder("Notes.xcodeproj")
        let result = try initialize(schemes: ["Notes"])
        #expect(result.notes.isEmpty)
        for folder in ["sets", "scenes/iphone", "scenes/ipad", "edits"] {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: directory.appending(path: "Retake/\(folder)").path, isDirectory: &isDirectory) && isDirectory.boolValue)
        }
        let project = try Project.locate(configuration: nil, currentDirectory: directory)
        #expect(project.root.path == directory.appending(path: "Retake").path)
        // xcodebuild runs in the project's folder, which holds no Xcode project of its own.
        #expect(project.settings.build == .scheme(.init(scheme: "Notes", container: .project("../Notes.xcodeproj"))))
        #expect(file("Retake/.gitignore") == "/output/\n")
        #expect(file(".gitignore") == nil)
    }

    @Test func besideItsXcodeProjectTheProjectNamesItOnlyWhenXcodebuildCouldntTell() throws {
        try folder("Notes.xcodeproj")
        #expect(try initialize("retake.json", schemes: ["Notes"]).settings.build == .scheme(.init(scheme: "Notes")))

        try FileManager.default.removeItem(at: directory.appending(path: "retake.json"))
        try folder("Notes.xcworkspace")
        let result = try initialize("retake.json", bundleID: "com.example.notes", schemes: ["Notes"])
        #expect(result.settings == ProjectSettings(bundleID: "com.example.notes", build: .scheme(.init(scheme: "Notes", container: .workspace("Notes.xcworkspace")))))
    }

    @Test func severalSchemesAreAskedAboutOrLeftForThePersonToGive() throws {
        try folder("Notes.xcodeproj")
        var asked: [String] = []
        let unanswered = try initialize(schemes: ["Notes", "NotesKit"]) {
            asked = $0
            return nil
        }
        #expect(asked == ["Notes", "NotesKit"])
        #expect(unanswered.settings.build == nil)
        #expect(unanswered.notes.count == 1 && unanswered.notes[0].contains("several schemes"))
    }

    @Test func aGivenSchemeNeedsNoXcodeProject() throws {
        let result = try initialize(scheme: "Notes")
        #expect(result.settings.build == .scheme(.init(scheme: "Notes")))
        #expect(result.notes.isEmpty)
    }

    @Test func anExistingProjectIsLeftAlone() throws {
        try initialize(scheme: "Notes")
        do {
            try initialize(scheme: "Other")
            Issue.record("initialized twice")
        } catch {
            #expect(error.status == .usage)
        }
    }

    @Test func gitignoreGainsEachEntryOnce() throws {
        try folder("Retake")
        try Data("build/\noutput".utf8).write(to: directory.appending(path: "Retake/.gitignore"))
        try initialize(scheme: "Notes")
        #expect(file("Retake/.gitignore") == "build/\noutput", "output is there already, without its slashes")
    }

    @Test func anOutputDirectoryIsWrittenRelativeToTheProjectAndIgnoredWhereItLives() throws {
        let inside = try initialize("Inside/retake.json", output: directory.appending(path: "Inside/takes-here"), scheme: "Notes")
        #expect(inside.settings.output == "takes-here")
        #expect(file("Inside/.gitignore") == "/takes-here/\n")

        let elsewhere = try initialize("Elsewhere/retake.json", output: directory.appending(path: "build/retake"), scheme: "Notes")
        #expect(elsewhere.settings.output == "../build/retake")
        #expect(file("Elsewhere/.gitignore") == nil)
        #expect(file(".gitignore") == "/build/retake/\n")
        let project = try Project.locate(configuration: directory.appending(path: "Elsewhere/retake.json"), currentDirectory: directory)
        #expect(project.output.path == directory.appending(path: "build/retake").path)

        let outside = URL(filePath: "/Volumes/Scratch/retake", directoryHint: .isDirectory)
        #expect(try initialize("Outside/retake.json", output: outside, scheme: "Notes").settings.output == "/Volumes/Scratch/retake")
        #expect(file("Outside/.gitignore") == nil)
    }

    @Test func unnamedTheProjectGoesInRetakeButNotInsideOneCommandsWouldFind() throws {
        #expect(try ProjectInitializer.defaultConfiguration(in: directory).path == directory.appending(path: "Retake/retake.json").path)
        try initialize(scheme: "Notes")
        for place in [directory, directory.appending(path: "Retake")] {
            #expect(throws: RetakeError.self, "\(place.lastPathComponent)") { try ProjectInitializer.defaultConfiguration(in: place) }
        }
    }

    @Test func aMalformedBundleIDIsMisuse() {
        #expect(throws: RetakeError.self) {
            try initialize(bundleID: "not a bundle id", scheme: "Notes")
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "Retake/retake.json").path))
    }
}

struct FittingWriterTests {
    @Test func anEditLaidOutByHandIsWrittenBackTheSame() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Examples/Notes/Retake/edits/tour.json")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(JSONWriter.fitting(try JSONParser.parse(text)) == text)
    }

    @Test func whatFitsWhereItStartsIsOneLineAndWhatDoesntIsLaidOut() throws {
        let value = try JSONParser.parse(#"{"a": {"b": [1, 2]}, "long": ["\#(String(repeating: "x", count: 90))", "y"]}"#)
        #expect(JSONWriter.fitting(value, width: 40) == """
            {
              "a": { "b": [1, 2] },
              "long": [
                "\(String(repeating: "x", count: 90))",
                "y"
              ]
            }

            """)
    }
}
