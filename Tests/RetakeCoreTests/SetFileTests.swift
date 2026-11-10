import Foundation
import RetakeCore
import Testing

struct SetFileTests {
    func read(_ text: String) -> (set: SetFile?, problems: [String]) {
        let reader = JSONReader(file: "sets/a.json")
        let set = SetFile.read(text, with: reader)
        return (set, reader.problems.map(\.description))
    }

    @Test func theREADMEsExampleReads() {
        let result = read(#"""
            {
              "extends": "base",
              "state": "clean",
              "files": {
                "Documents/notes.sqlite": "data/returning-user/notes.sqlite",
                "Library/Application Support/Media/": "data/returning-user/media/"
              },
              "defaults": { "hasSeenOnboarding": true, "sortOrder": "recent" },
              "environment": { "MYAPP_REGION_NEUTRAL_PRICES": "1" },
              "arguments": ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"],
              "previewAspect": true
            }
            """#)
        #expect(result.problems.isEmpty)
        #expect(result.set?.files.map(\.isFolder) == [false, true])
        #expect(result.set?.previewAspect == true)
    }

    @Test func previewAspectGivesEachDeviceTypeItsPreviewsShapeAndItsTurn() throws {
        let set = ResolvedSet(name: "a", previewAspect: true)
        #expect(set.aspect(for: .iphone) == SetFile.AspectChoice(portrait: .init(width: 443, height: 960), landscape: .init(width: 960, height: 443)))
        #expect(set.aspect(for: .ipad) == SetFile.AspectChoice(portrait: .init(width: 3, height: 4), landscape: .init(width: 4, height: 3)))
        for type in DeviceType.allCases {
            let shape = try #require(set.aspect(for: type)?.portrait)
            let spec = PreviewSpec.of(type)
            #expect(shape.width * Double(spec.height) == shape.height * Double(spec.width), "the preview's own shape, for \(type)")
        }
        #expect(ResolvedSet(name: "a").aspect(for: .ipad) == nil, "without it the app fills the screen")
    }

    @Test(arguments: [
        (#"{"state": "fresh"}"#, #"sets/a.json: state: "fresh" isn't one of clean, cloned or live"#),
        (#"{"files": {"/etc/hosts": "a"}}"#, #"sets/a.json: files["/etc/hosts"]: isn't a path inside the app's data, such as Documents/notes.json"#),
        (#"{"files": {"Documents/../../x": "a"}}"#, #"sets/a.json: files["Documents/../../x"]: isn't a path inside the app's data, such as Documents/notes.json"#),
        (#"{"files": {"Documents/a": "/tmp/secrets"}}"#, #"sets/a.json: files["Documents/a"]: "/tmp/secrets" isn't a relative path"#),
        (#"{"files": {"Documents/media/": "data/media"}}"#, #"sets/a.json: files["Documents/media/"]: is a folder, ending in "/", so "data/media" must be one too"#),
        (#"{"files": {"Documents/a.json": "data/"}}"#, #"sets/a.json: files["Documents/a.json"]: is a file, so "data/" can't be a folder ending in "/""#),
        (#"{"defaults": {"name": null}}"#, "sets/a.json: defaults.name: can't hold null, which UserDefaults can't store; leave the key out instead"),
        (#"{"defaults": {"list": [1, null]}}"#, "sets/a.json: defaults.list: can't hold null, which UserDefaults can't store; leave the key out instead"),
        (#"{"environment": {"DYLD_INSERT_LIBRARIES": "x"}}"#, "sets/a.json: environment.DYLD_INSERT_LIBRARIES: is Retake's to set: it launches the app with its own DYLD_ variables"),
        (#"{"environment": {"INSIDEJOB_PORT": "1"}}"#, "sets/a.json: environment.INSIDEJOB_PORT: is Retake's to set: it launches the app with its own INSIDEJOB_ variables"),
        (#"{"environment": {"MY-FLAG": "1"}}"#, #"sets/a.json: environment.MY-FLAG: isn't an environment variable's name: letters, digits and "_", not starting with a digit"#),
        (#"{"environment": {"FLAG": 1}}"#, "sets/a.json: environment.FLAG: expected a string, found a number"),
        (#"{"aspect": {"ipad": "3:4"}}"#, #"sets/a.json: aspect: is now "previewAspect": true, which gives the app the App Store preview's shape"#),
        (#"{"arguments": "-AppleLanguages (en)"}"#, "sets/a.json: arguments: expected a list, found a string"),
    ])
    func mistakesAreNamed(_ text: String, _ expected: String) {
        let result = read(text)
        #expect(result.problems == [expected])
        #expect(result.set == nil)
    }

    @Test func aSourceMayBeRelativeToAParentDirectory() {
        let result = read(#"{"files": {"Documents/a": "../shared/a"}}"#)
        #expect(result.problems.isEmpty)
        #expect(result.set?.files == [SetFile.FileCopy(destination: "Documents/a", source: "../shared/a")])
    }
}

struct ResolvedSetTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RetakeSetTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "sets"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appending(path: "retake.json"))
    }

    func write(_ name: String, _ text: String) throws {
        try Data(text.utf8).write(to: root.appending(path: "sets/\(name).json"))
    }

    func resolve(_ name: String) -> (set: ResolvedSet?, problems: [String]) {
        let files = ProjectFiles(project: Project(configuration: root.appending(path: "retake.json")))
        let report = ProjectFiles.Report()
        let set = files.resolveSet(name, into: report)
        return (set, report.problems.map(\.description))
    }

    @Test func aSetLiesOverTheSetsItExtends() throws {
        try write("base", #"""
            {"state": "cloned", "files": {"Documents/a.json": "data/base-a.json", "Documents/b.json": "data/base-b.json"},
             "defaults": {"x": 1, "y": 1}, "environment": {"A": "base", "B": "base"}, "arguments": ["-one"], "previewAspect": true}
            """#)
        try write("middle", #"{"extends": "base", "defaults": {"y": 2}, "arguments": ["-two"]}"#)
        try write("top", #"""
            {"extends": "middle", "files": {"Documents/b.json": "data/top-b.json", "Documents/c.json": "data/top-c.json"},
             "environment": {"B": "top"}, "arguments": ["-three"]}
            """#)
        let result = resolve("top")
        #expect(result.problems.isEmpty)
        guard let set = result.set else { return }
        #expect(set.names == ["top", "middle", "base"])
        #expect(set.state == .cloned, "state is the base's until a set above it gives one")
        #expect(set.files.map { "\($0.destination)=\($0.source)" } == [
            "Documents/a.json=data/base-a.json", "Documents/b.json=data/top-b.json", "Documents/c.json=data/top-c.json",
        ])
        #expect(set.defaults == [Named("x", .number(1)), Named("y", .number(2))])
        #expect(set.environment == [Named("A", "base"), Named("B", "top")])
        #expect(set.arguments == ["-one", "-two", "-three"])
        #expect(set.previewAspect, "previewAspect is the base's until a set above it gives one")
    }

    @Test func anExtendingSetsPreviewAspectOverridesItsBasesEitherWay() throws {
        try write("shaped", #"{"previewAspect": true}"#)
        try write("filled", #"{"extends": "shaped", "previewAspect": false}"#)
        try write("reshaped", #"{"extends": "filled", "previewAspect": true}"#)
        #expect(resolve("filled").set?.previewAspect == false)
        #expect(resolve("reshaped").set?.previewAspect == true)
    }

    @Test func aSetWithNoStateIsClean() throws {
        try write("plain", "{}")
        #expect(resolve("plain").set?.state == .clean)
    }

    @Test func aLoopOfExtendsIsNamed() throws {
        try write("a", #"{"extends": "b"}"#)
        try write("b", #"{"extends": "a"}"#)
        #expect(resolve("a").problems == ["sets/b.json: extends: sets extend each other in a loop: a → b → a"])
        try write("self", #"{"extends": "self"}"#)
        #expect(resolve("self").problems == ["sets/self.json: extends: sets extend each other in a loop: self → self"])
    }

    @Test func aMissingSetIsNamedWhereItsExtended() throws {
        try write("child", #"{"extends": "nowhere"}"#)
        #expect(resolve("child").problems == [#"sets/child.json: extends: there's no set "nowhere" (sets/nowhere.json)"#])
        #expect(resolve("absent").problems == ["sets/absent.json: doesn't exist"])
    }

    @Test func problemsInEverySetOfTheChainAreReported() throws {
        try write("base", #"{"state": "fresh"}"#)
        try write("top", #"{"extends": "base", "arguments": [1]}"#)
        #expect(resolve("top").problems == ["sets/top.json: arguments[0]: expected a string, found a number"])
    }

    @Test func theExamplesSetsResolve() throws {
        let example = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Examples/Notes").standardizedFileURL
        let files = ProjectFiles(project: try Project.locate(configuration: nil, currentDirectory: example))
        #expect(files.names(in: files.project.sets) == ["base", "first-launch", "returning-user", "screenshots"])
        for name in files.names(in: files.project.sets) {
            let report = ProjectFiles.Report()
            #expect(files.resolveSet(name, into: report) != nil, "\(name): \(report.problems)")
            #expect(report.warnings.isEmpty)
        }
    }
}
