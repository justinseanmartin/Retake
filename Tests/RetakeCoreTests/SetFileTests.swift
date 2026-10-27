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
              "aspect": { "ipad": "3:4" }
            }
            """#)
        #expect(result.problems.isEmpty)
        #expect(result.set?.files.map(\.isFolder) == [false, true])
        #expect(result.set?.aspect[.ipad]?.landscapeShape == SetFile.Aspect(width: 4, height: 3))
        #expect(result.set?.aspect[.iphone] == nil)
    }

    @Test func eachOrientationsShapeCanBeGiven() {
        let set = read(#"{"aspect": {"ipad": {"portrait": "3:4", "landscape": "16:10"}, "iphone": {"landscape": "19.5:9"}}}"#).set
        #expect(set?.aspect[.ipad] == SetFile.AspectChoice(portrait: .init(width: 3, height: 4), landscape: .init(width: 16, height: 10)))
        #expect(set?.aspect[.iphone]?.portrait == nil)
        #expect(set?.aspect[.iphone]?.landscapeShape == SetFile.Aspect(width: 19.5, height: 9))
    }

    @Test(arguments: [
        (#"{"state": "fresh"}"#, #"sets/a.json: state: "fresh" isn't one of clean, cloned or live"#),
        (#"{"files": {"/etc/hosts": "a"}}"#, #"sets/a.json: files["/etc/hosts"]: isn't a path inside the app's data, such as Documents/notes.json"#),
        (#"{"files": {"Documents/../../x": "a"}}"#, #"sets/a.json: files["Documents/../../x"]: isn't a path inside the app's data, such as Documents/notes.json"#),
        (#"{"files": {"Documents/a": "../secrets"}}"#, #"sets/a.json: files["Documents/a"]: "../secrets" isn't a path inside the project"#),
        (#"{"files": {"Documents/media/": "data/media"}}"#, #"sets/a.json: files["Documents/media/"]: is a folder, ending in "/", so "data/media" must be one too"#),
        (#"{"files": {"Documents/a.json": "data/"}}"#, #"sets/a.json: files["Documents/a.json"]: is a file, so "data/" can't be a folder ending in "/""#),
        (#"{"defaults": {"name": null}}"#, "sets/a.json: defaults.name: can't hold null, which UserDefaults can't store; leave the key out instead"),
        (#"{"defaults": {"list": [1, null]}}"#, "sets/a.json: defaults.list: can't hold null, which UserDefaults can't store; leave the key out instead"),
        (#"{"environment": {"DYLD_INSERT_LIBRARIES": "x"}}"#, "sets/a.json: environment.DYLD_INSERT_LIBRARIES: is Retake's to set: it launches the app with its own DYLD_ variables"),
        (#"{"environment": {"INSIDEJOB_PORT": "1"}}"#, "sets/a.json: environment.INSIDEJOB_PORT: is Retake's to set: it launches the app with its own INSIDEJOB_ variables"),
        (#"{"environment": {"MY-FLAG": "1"}}"#, #"sets/a.json: environment.MY-FLAG: isn't an environment variable's name: letters, digits and "_", not starting with a digit"#),
        (#"{"environment": {"FLAG": 1}}"#, "sets/a.json: environment.FLAG: expected a string, found a number"),
        (#"{"aspect": {"ipad": "3x4"}}"#, #"sets/a.json: aspect.ipad: "3x4" isn't a shape: a width and a height, such as 3:4"#),
        (#"{"aspect": {"ipad": "0:4"}}"#, #"sets/a.json: aspect.ipad: "0:4" isn't a shape: a width and a height, such as 3:4"#),
        (#"{"aspect": {"ipad": {}}}"#, #"sets/a.json: aspect.ipad: needs "portrait", "landscape", or both"#),
        (#"{"aspect": {"android": "3:4"}}"#, #"sets/a.json: aspect: unknown key "android""#),
        (#"{"aspect": {"iPad": "3:4"}}"#, #"sets/a.json: aspect: unknown key "iPad"; did you mean "ipad"?"#),
        (#"{"arguments": "-AppleLanguages (en)"}"#, "sets/a.json: arguments: expected a list, found a string"),
    ])
    func mistakesAreNamed(_ text: String, _ expected: String) {
        let result = read(text)
        #expect(result.problems == [expected])
        #expect(result.set == nil)
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
             "defaults": {"x": 1, "y": 1}, "environment": {"A": "base", "B": "base"}, "arguments": ["-one"], "aspect": {"ipad": "3:4"}}
            """#)
        try write("middle", #"{"extends": "base", "defaults": {"y": 2}, "arguments": ["-two"]}"#)
        try write("top", #"""
            {"extends": "middle", "files": {"Documents/b.json": "data/top-b.json", "Documents/c.json": "data/top-c.json"},
             "environment": {"B": "top"}, "arguments": ["-three"], "aspect": {"iphone": "9:16"}}
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
        #expect(set.aspect.keys.sorted { $0.rawValue < $1.rawValue } == [.ipad, .iphone])
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
        let example = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Examples/RetakeNotes").standardizedFileURL
        let files = ProjectFiles(project: try Project.locate(configuration: nil, currentDirectory: example))
        #expect(files.names(in: files.project.sets) == ["base", "first-launch", "returning-user"])
        for name in files.names(in: files.project.sets) {
            let report = ProjectFiles.Report()
            #expect(files.resolveSet(name, into: report) != nil, "\(name): \(report.problems)")
            #expect(report.warnings.isEmpty)
        }
    }
}
