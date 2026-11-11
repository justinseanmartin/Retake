import Foundation
@testable import RetakeCore
import Testing

/// The schemas say what the readers read: the checked-in copies are what the types generate, and on
/// every file below, a schema and its reader agree on whether it's right.
struct SchemaTests {
    static let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Whether the reader for `kind` reads `text` without a problem.
    static func reads(_ text: String, as kind: String) -> Bool {
        let reader = JSONReader(file: "\(kind).json")
        let read: Bool = switch kind {
        case "retake": ProjectSettings.read(text, with: reader) != nil
        case "set": SetFile.read(text, with: reader) != nil
        // Under The Button Heist's default longest wait, which the schema gives.
        case "scene": Step.$environment.withValue([:]) { SceneFile.read(text, with: reader) != nil }
        case "take": TakeLog.read(text, with: reader) != nil
        default: EditFile.read(text, with: reader) != nil
        }
        return read && reader.problems.isEmpty
    }

    /// Where the schema for `kind` says `text` is wrong, or nil.
    static func schemaProblem(_ text: String, as kind: String) throws -> String? {
        SchemaValidator(document: try #require(FileSchema.named(kind)).json).problem(try JSONParser.parse(text))
    }

    @Test(arguments: FileSchema.kinds)
    func theCheckedInSchemaIsWhatTheTypesGenerate(_ kind: String) throws {
        let url = Self.repository.appending(path: "Documentation/reference/\(kind).schema.json")
        let checkedIn = try String(contentsOf: url, encoding: .utf8)
        #expect(checkedIn == FileSchema.named(kind)?.text, "run `retake schema --output Documentation/reference`")
    }

    @Test func theExamplesFilesFitTheirSchemasAndRead() throws {
        let project = Self.repository.appending(path: "Example/Retake")
        var files: [(URL, String)] = [(project.appending(path: "retake.json"), "retake")]
        for (folder, kind) in [("sets", "set"), ("scenes", "scene"), ("edits", "edit")] {
            let url = project.appending(path: folder)
            for name in try FileManager.default.contentsOfDirectory(atPath: url.path).sorted() where name.hasSuffix(".json") {
                files.append((url.appending(path: name), kind))
            }
        }
        #expect(files.count >= 8)
        for (url, kind) in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(try Self.schemaProblem(text, as: kind) == nil, "\(url.lastPathComponent)")
            #expect(Self.reads(text, as: kind), "\(url.lastPathComponent)")
        }
    }

    /// The example project's takes, where it has been recorded, and the tests' own step logs: each
    /// fits the schema and reads.
    @Test func theNewestTakesAndTheFixturesStepLogsFitTheSchemaAndRead() throws {
        var logs: [(String, String)] = [
            ("the fixture", JSONWriter.write(TakeLogReadingTests.log(failure: "step 2 didn't run").json)),
            ("the timeline's", JSONWriter.write(TakeTimelineTests.timeline().log.json)),
        ]
        let takes = Self.repository.appending(path: "Example/Retake/output/takes")
        let files = FileManager.default
        for type in DeviceType.allCases {
            let folder = takes.appending(path: type.rawValue)
            for name in ((try? files.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() where TakeStore.parse(name) != nil && name.hasSuffix(".json") {
                logs.append(("\(type.rawValue)/\(name)", try String(contentsOf: folder.appending(path: name), encoding: .utf8)))
            }
        }
        for (name, text) in logs {
            #expect(try Self.schemaProblem(text, as: "take") == nil, "\(name)")
            #expect(Self.reads(text, as: "take"), "\(name)")
        }
    }

    /// A step log, the fixture's, with its top-level keys changed.
    static func take(_ change: (inout [JSONObject.Entry]) -> Void) -> String {
        TakeLogReadingTests.text(TakeLogReadingTests.log(failure: "step 2 didn't run")) { entries in
            entries.append(.init(key: "hitches", value: json(#"[{"at": 1.2, "duration": 0.53}]"#)))
            change(&entries)
        }
    }

    static func json(_ text: String) -> JSONValue { try! JSONParser.parse(text) }

    static func set(_ key: String, _ text: String) -> (inout [JSONObject.Entry]) -> Void { set(key, json(text)) }

    static func set(_ key: String, _ value: JSONValue) -> (inout [JSONObject.Entry]) -> Void {
        { entries in
            if let index = entries.firstIndex(where: { $0.key == key }) { entries[index].value = value } else { entries.append(.init(key: key, value: value)) }
        }
    }

    static func remove(_ keys: String...) -> (inout [JSONObject.Entry]) -> Void {
        { entries in entries.removeAll { keys.contains($0.key) } }
    }

    static let takeCorpus: [(kind: String, text: String, right: Bool)] = [
        ("take", take { _ in }, true),
        ("take", take(set("format", "1")), true),
        ("take", take(set("take", "3")), true),
        ("take", take(set("take", "0")), false),
        ("take", take { entries in entries[entries.firstIndex { $0.key == "previewAspect" }!].key = "aspect" }, true),
        ("take", take(set("previewAspect", #""3:4""#)), true),
        ("take", take(set("previewAspect", #"{"landscape": "4:3"}"#)), true),
        ("take", take { remove("previewAspect", "launch", "hitches", "failure")(&$0); set("clock", .object(JSONObject()))(&$0) }, true),
        ("take", take(set("format", "2")), false),
        ("take", take(set("format", "0")), false),
        ("take", take(set("format", "1.5")), false),
        ("take", take(set("format", #""1""#)), false),
        ("take", take { set("aspect", #"{"portrait": "3:4"}"#)(&$0) }, false),
        ("take", take(remove("screen")), false),
        ("take", take(remove("frames")), false),
        ("take", take(remove("dropped")), false),
        ("take", take(set("screen", "[834]")), false),
        ("take", take(set("screen", "[834, 0]")), false),
        ("take", take(set("size", "[1200, 1718, 1]")), false),
        ("take", take(set("previewAspect", .object(JSONObject()))), false),
        ("take", take(set("previewAspect", #"{"portrait": "tall"}"#)), false),
        ("take", take(set("recordedAt", #""yesterday""#)), false),
        ("take", take(set("state", #""fresh""#)), false),
        ("take", take(set("steps", #"[{"number": 1, "action": "tap", "start": 1, "end": 2, "timedBy": "phone"}]"#)), false),
        ("take", take(set("steps", #"[{"number": 1, "action": "tap", "start": 1, "end": 2, "timedBy": "mac", "touch": [1, 2, 3]}]"#)), false),
        ("take", take(set("shapes", #"[{"at": 0, "size": [1200, 1718]}]"#)), false),
        ("take", take(set("hitches", #"[{"at": 1, "duration": -1}]"#)), false),
        ("take", take(set("pins", "true")), false),
        ("take", take(set("beforeSteps", #"{"at": 0.9, "elements": [{"label": "Notes", "traits": ["header"], "frame": [20, 60, 200, 41]}]}"#)), true),
        ("take", take(set("beforeSteps", #"{"at": 0.9, "elements": []}"#)), true),
        ("take", take(set("beforeSteps", #"{"at": 0.9}"#)), false),
        ("take", take(set("beforeSteps", #"{"elements": []}"#)), false),
        ("take", take(set("beforeSteps", #"{"at": 0.9, "elements": [], "number": 1}"#)), false),
    ] + shapeAndDateCorpus

    /// Shapes and dates at the edge of what's taken: a shape is two positive decimals with digits
    /// either side of any point, and a date has a time to the second, any fraction, and Z or an
    /// offset, as ISO8601DateFormatter takes more loosely.
    static let shapeAndDateCorpus: [(kind: String, text: String, right: Bool)] =
        [("0.75:1", true), ("886:1920", true), ("010:4", true), (".5:1", false), ("3.:4", false), ("3:0", false), ("0.0:4", false),
         ("1e3:4", false), ("+3:4", false), ("3:4:5", false), ("3 :4", false)]
        .map { ("take", take(set("previewAspect", .object(JSONObject([.init(key: "landscape", value: .string($0))])))), $1) }
        + [("2026-11-06T09:30:00.250Z", true), ("2026-11-06T10:30:00+01:00", true), ("2026-11-06T04:00:00.5-0530", true),
           ("2026-11-06T09:30:00z", false), ("2026-11-06T09:30:00", false), ("2026-11-06T09:30:00GMT", false),
           ("2026-11-06T09:30:00+01", false), ("2026-11-06T09:30:00.Z", false), ("2026-11-06T24:00:00Z", false),
           ("2026-11-06T09:30:00Zjunk", false), ("2026-13-06T09:30:00Z", false), ("2026-11-06 09:30:00Z", false)]
        .map { ("take", take(set("recordedAt", .string($0))), $1) }

    /// Files a reader takes, then ones it refuses, each of which the schema should judge the same.
    static let corpus: [(kind: String, text: String, right: Bool)] = takeCorpus + [
        ("retake", ##"{"$schema": "x", "bundleID": "com.example.notes", "build": {"scheme": "Notes", "workspace": "N.xcworkspace", "configuration": "Debug", "allowProvisioningUpdates": true, "optimize": false}, "device": "ipad", "defaultSet": "base", "output": "out"}"##, true),
        ("retake", ##"{"build": {"command": "make", "app": "build/N.app"}}"##, true),
        ("retake", ##"{"build": {"scheme": "N", "command": "make"}}"##, false),
        ("retake", ##"{"build": {"command": "make"}}"##, false),
        ("retake", ##"{"build": {"scheme": "N", "app": "N.app"}}"##, false),
        ("retake", ##"{"bundleID": "com example"}"##, false),
        ("retake", ##"{"devices": "ipad"}"##, false),

        ("set", ##"{"extends": "base", "state": "cloned", "files": {"Documents/a.json": "data/a.json", "Library/M/": "data/m/"}, "defaults": {"a": [1, {"b": true}]}, "environment": {"MY_FLAG": "1"}, "arguments": ["-x"], "previewAspect": true}"##, true),
        ("set", ##"{"state": "fresh"}"##, false),
        ("set", ##"{"environment": {"RETAKE_X": "1"}}"##, false),
        ("set", ##"{"environment": {"1X": "1"}}"##, false),
        ("set", ##"{"aspect": {"ipad": "3:4"}}"##, false),
        ("set", ##"{"previewAspect": "yes"}"##, false),
        ("set", ##"{"defaults": {"a": null}}"##, false),

        ("scene", ##"{"set": "a", "setup": [{"activate": {"label": "Library"}}], "leadIn": 1.5, "tail": 2, "defaultHold": 0.5, "recordsLaunch": true, "orientation": "landscape-left", "steps": [{"tap": {"label": "New", "traits": ["button"], "occurrence": 2}, "hold": 1, "id": "new"}, {"tap": {"x": 1, "y": 2}}, {"type": {"text": "Hi\n", "into": {"value": ""}}}, {"drag": {"from": {"x": 1, "y": 2}, "to": {"x": 3, "y": 4}, "duration": 0.8}}, {"orientation": "portrait"}, {"waitFor": {"hint": "Sends it", "gone": true, "timeout": 5}}, {"activate": {"identifier": "a"}}, {"hold": 2}]}"##, true),
        ("scene", ##"{"steps": [{"waitFor": {"label": "Synced", "timeout": 60}}]}"##, true),
        ("scene", ##"{"steps": [{"waitFor": {"label": "Synced", "timeout": 61}}]}"##, false),
        ("scene", ##"{"steps": []}"##, false),
        ("scene", ##"{"steps": [{"id": "a"}]}"##, false),
        ("scene", ##"{"steps": [{"tap": {"label": "a"}, "drag": {"from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 2}}}]}"##, false),
        ("scene", ##"{"steps": [{"tap": {"label": "a", "x": 1, "y": 2}}]}"##, false),
        ("scene", ##"{"steps": [{"tap": {"x": 1}}]}"##, false),
        ("scene", ##"{"steps": [{"tap": {"occurrence": 1}}]}"##, false),
        ("scene", ##"{"steps": [{"tap": {"traits": ["shiny"]}}]}"##, false),
        ("scene", ##"{"steps": [{"tap": {"traits": []}}]}"##, false),
        ("scene", ##"{"steps": [{"type": {"text": ""}}]}"##, false),
        ("scene", ##"{"steps": [{"orientation": "sideways"}]}"##, false),
        ("scene", ##"{"steps": [{"hold": -1}]}"##, false),
        ("scene", ##"{"steps": [{"hold": 1, "id": "end"}]}"##, false),
        ("scene", ##"{"steps": [{"press": {"label": "a"}}]}"##, false),

        ("edit", #"""
        {"intent": "x", "devices": ["iphone", "ipad"],
         "music": {"file": "m.m4a", "volume": 0.6, "fadeOut": 1.5}, "tapSound": {"file": "t.m4a", "volume": 0.5},
         "takeAudioVolume": 0.8, "background": "#F4F1EA", "turns": "device", "turnBlur": {"duration": 0.6},
         "ipad": {"background": "#000000", "music": {"volume": 0.4}},
         "clips": [
           {"intent": "y", "take": "a", "from": {"step": "start", "offset": 1.2}, "to": {"step": -1, "fraction": 0.5, "edge": "start"},
            "speed": 1.5, "touches": true, "takeAudio": true, "turns": "letterboxed", "turnBlur": {"duration": 0.3},
            "sounds": [{"file": "p.m4a", "at": {"step": "new"}, "volume": 0.8, "duration": 1.2}],
            "captions": [{"text": "Hi", "y": 0.12, "color": "#1F6FEB80", "from": 2, "to": {"clip": "b", "step": "s", "offset": -0.2},
                          "symbol": {"name": "rotate.right", "animation": {"rotate": {"degrees": 90, "duration": 0.4}}}, "ipad": {"y": 0.08}}],
            "spotlight": {"element": {"label": "Share"}, "padding": 8, "color": "#FFFFFF", "from": {"step": 1}, "to": {"step": 2}},
            "blurs": [{"rect": {"x": 0, "y": 0, "width": 10, "height": 10}, "radius": 30}],
            "stills": [{"take": "a", "at": 1}],
            "iphone": {"speed": 1.2, "to": {"fraction": 0.25}}},
           {"id": "b", "take": "a", "from": 0, "to": {"step": "end"}, "crossfade": 0.4, "audioCrossfade": 0.6,
            "captions": [{"text": "x", "y": 0.5, "color": "#000000", "to": {"step": "end"}}]}
         ]}
        """#, true),
        ("edit", ##"{"devices": [], "clips": [{"take": "a", "from": 0, "to": 1}]}"##, false),
        ("edit", ##"{"devices": ["ipad", "ipad"], "clips": [{"take": "a", "from": 0, "to": 1}]}"##, false),
        ("edit", ##"{"devices": ["ipad"], "clips": []}"##, false),
        ("edit", ##"{"devices": ["ipad"], "clips": [{"take": "a", "from": 0}]}"##, false),
        ("edit", ##"{"devices": ["ipad"], "clips": [{"take": "a", "from": -1, "to": 1}]}"##, false),
        ("edit", ##"{"devices": ["ipad"], "clips": [{"take": "a", "from": {"step": 0}, "to": 1}]}"##, false),
        ("edit", ##"{"devices": ["ipad"], "clips": [{"take": "a", "from": {"step": 1, "offset": 1, "fraction": 0.5}, "to": 1}]}"##, false),
        ("edit", ##"{"devices": ["ipad"], "clips": [{"take": "a", "from": {"step": 1, "fraction": 2}, "to": 1}]}"##, false),
        ("edit", ##"{"devices": ["ipad"], "clips": [{"take": "a", "from": 0, "to": 1, "speed": 0}]}"##, false),
        ("edit", ##"{"devices": ["ipad"], "clips": [{"take": "a", "from": 0, "to": 1, "captions": [{"text": "a", "y": 2, "color": "#000000"}]}]}"##, false),
        ("edit", ##"{"devices": ["ipad"], "clips": [{"take": "a", "from": 0, "to": 1, "captions": [{"text": "a", "y": 0.5, "color": "black"}]}]}"##, false),
        ("edit", ##"{"devices": ["ipad"], "clips": [{"take": "a", "from": 0, "to": 1, "spotlight": {"padding": 2}}]}"##, false),
        ("edit", ##"{"devices": ["ipad"], "clips": [{"take": "a", "from": 0, "to": 1, "blurs": [{"element": {"label": "a"}, "rect": {"x": 0, "y": 0, "width": 1, "height": 1}}]}]}"##, false),
        ("edit", ##"{"devices": ["ipad"], "clips": [{"take": "a", "from": 0, "to": 1, "fadeIn": 1}]}"##, false),
        ("edit", ##"{"devices": ["ipad"], "ipad": {"devices": ["iphone"]}, "clips": [{"take": "a", "from": 0, "to": 1}]}"##, false),
        ("edit", ##"{"devices": ["ipad"], "takes": {"ipad": {"a": 0}}, "clips": [{"take": "a", "from": 0, "to": 1}]}"##, false),
        ("edit", ##"{"devices": ["ipad"], "turns": "sideways", "clips": [{"take": "a", "from": 0, "to": 1}]}"##, false),
    ]

    /// Every default a schema gives, by where it is: `build.optimize`, or `#clip.speed` in a
    /// definition.
    static func defaults(of file: FileSchema) -> [String: JSONValue] {
        var found: [String: JSONValue] = [:]
        func walk(_ schema: Schema, _ path: String) {
            for property in schema.properties {
                let at = path.isEmpty ? property.name : "\(path).\(property.name)"
                if let value = property.schema.defaultValue { found[at] = value }
                walk(property.schema, at)
            }
            for branch in schema.oneOf + schema.anyOf + schema.items { walk(branch, path) }
        }
        walk(file.root, "")
        for definition in file.definitions where !definition.name.hasSuffix("-override") { walk(definition.schema, "#\(definition.name)") }
        return found
    }

    /// What the reader makes of each field a schema gives a default, read from a file that gives
    /// none of them, by the schema's paths.
    static func readersDefaults(_ kind: String) throws -> [String: JSONValue] {
        let reader = JSONReader(file: "\(kind).json")
        switch kind {
        case "retake":
            let settings = try #require(ProjectSettings.read(#"{"build": {"scheme": "N"}}"#, with: reader))
            guard case .scheme(let build)? = settings.build else { Issue.record("not a scheme build"); return [:] }
            let project = Project(configuration: URL(filePath: "/p/retake.json"), settings: settings)
            return [
                "build.configuration": .string(build.configurationName), "build.allowProvisioningUpdates": .bool(build.allowProvisioningUpdates),
                "build.optimize": .bool(build.optimize), "output": .string(project.output.lastPathComponent),
                "hitchWarning": .number(settings.hitchWarningOrDefault),
            ]
        case "set":
            let set = ResolvedSet(name: "a", chain: [try #require(SetFile.read("{}", with: reader))], names: ["a"])
            return ["state": .string(set.state.rawValue), "previewAspect": .bool(set.previewAspect)]
        case "scene":
            let scene = try #require(SceneFile.read(#"{"steps": [{"drag": {"from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 2}}}, {"waitFor": {"label": "a"}}]}"#, with: reader))
            guard case .drag(_, _, let duration)? = scene.steps[0].action, case .waitFor(_, let gone, let timeout)? = scene.steps[1].action else {
                Issue.record("not a drag and a waitFor"); return [:]
            }
            return [
                "#step.drag.duration": .number(duration), "#step.waitFor.gone": .bool(gone), "#step.waitFor.timeout": .number(timeout),
                "leadIn": .number(scene.leadIn), "tail": .number(scene.tail), "defaultHold": .number(scene.defaultHold),
                "recordsLaunch": .bool(scene.recordsLaunch), "orientation": .string(scene.orientation.rawValue),
            ]
        case "edit":
            let file = try #require(EditFile.read(##"""
            {"devices": ["ipad"], "music": {"file": "m.m4a"}, "tapSound": {"file": "t.m4a"},
             "clips": [{"take": "a", "from": 0, "to": 1, "sounds": [{"file": "s.m4a", "at": 0}],
                        "spotlight": {"rect": {"x": 0, "y": 0, "width": 1, "height": 1}}, "blurs": [{"element": {"label": "a"}, "part": {}}]}]}
            """##, with: reader))
            let edit = try #require(file.videos[.ipad]), clip = edit.clips[0]
            let spotlight = try #require(clip.spotlight), music = try #require(edit.music)
            guard case .element(_, let part?) = clip.blurs[0].region else { Issue.record("not an element's part"); return [:] }
            return [
                "takeAudioVolume": .number(edit.takeAudioVolume), "background": .string(edit.background.description),
                "turns": .string(edit.turns.rawValue), "touchColor": .string(edit.touchColor.description),
                "#clip.speed": .number(clip.speed), "#clip.crossfade": .number(clip.crossfade), "#clip.touches": .bool(clip.touches),
                "#clip.takeAudio": .bool(clip.takeAudio), "#sound.volume": .number(clip.sounds[0].volume),
                "#music.volume": .number(music.volume), "#music.fadeOut": .number(music.fadeOut),
                "#tap-sound.volume": .number(try #require(edit.tapSound).volume),
                "#spotlight.padding": .number(spotlight.padding), "#spotlight.color": .string(spotlight.color.description),
                "#blur.radius": .number(clip.blurs[0].radius),
                "#part.x": part.x.fileJSON, "#part.y": part.y.fileJSON, "#part.width": part.width.fileJSON, "#part.height": part.height.fileJSON,
            ]
        default:
            return [:]
        }
    }

    @Test(arguments: FileSchema.kinds)
    func theSchemasDefaultsAreWhatTheReadersTake(_ kind: String) throws {
        let schema = Self.defaults(of: try #require(FileSchema.named(kind)))
        let readers = try Self.readersDefaults(kind)
        #expect(Set(schema.keys) == Set(readers.keys))
        for (path, value) in schema { #expect(readers[path] == value, "\(kind): \(path)") }
    }

    @Test(arguments: corpus.indices)
    func theSchemaAndTheReaderAgree(_ index: Int) throws {
        let (kind, text, right) = Self.corpus[index]
        #expect(Self.reads(text, as: kind) == right, "the reader, on \(kind) \(index)")
        let problem = try Self.schemaProblem(text, as: kind)
        #expect((problem == nil) == right, "the schema, on \(kind) \(index): \(problem ?? "no problem")")
    }
}
