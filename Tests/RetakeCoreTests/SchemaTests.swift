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
        case "scene": SceneFile.read(text, with: reader) != nil
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
        let project = Self.repository.appending(path: "Examples/Notes/Retake")
        var files: [(URL, String)] = [(project.appending(path: "retake.json"), "retake")]
        for (folder, kind) in [("sets", "set"), ("scenes/iphone", "scene"), ("scenes/ipad", "scene"), ("edits", "edit")] {
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

    /// Files a reader takes, then ones it refuses, each of which the schema should judge the same.
    static let corpus: [(kind: String, text: String, right: Bool)] = [
        ("retake", ##"{"$schema": "x", "bundleID": "com.example.notes", "build": {"scheme": "Notes", "workspace": "N.xcworkspace", "configuration": "Debug", "allowProvisioningUpdates": true, "optimize": false}, "device": "ipad", "defaultSet": "base", "output": "out"}"##, true),
        ("retake", ##"{"build": {"command": "make", "app": "build/N.app"}}"##, true),
        ("retake", ##"{"build": {"scheme": "N", "command": "make"}}"##, false),
        ("retake", ##"{"build": {"command": "make"}}"##, false),
        ("retake", ##"{"build": {"scheme": "N", "app": "N.app"}}"##, false),
        ("retake", ##"{"bundleID": "com example"}"##, false),
        ("retake", ##"{"devices": "ipad"}"##, false),

        ("set", ##"{"extends": "base", "state": "cloned", "files": {"Documents/a.json": "data/a.json", "Library/M/": "data/m/"}, "defaults": {"a": [1, {"b": true}]}, "environment": {"MY_FLAG": "1"}, "arguments": ["-x"], "aspect": {"ipad": "3:4", "iphone": {"landscape": "16:10"}}}"##, true),
        ("set", ##"{"state": "fresh"}"##, false),
        ("set", ##"{"environment": {"RETAKE_X": "1"}}"##, false),
        ("set", ##"{"environment": {"1X": "1"}}"##, false),
        ("set", ##"{"aspect": {"ipad": "wide"}}"##, false),
        ("set", ##"{"aspect": {"ipad": {}}}"##, false),
        ("set", ##"{"aspect": {"watch": "1:1"}}"##, false),
        ("set", ##"{"defaults": {"a": null}}"##, false),

        ("scene", ##"{"set": "a", "setup": [{"activate": {"label": "Library"}}], "leadIn": 1.5, "tail": 2, "defaultHold": 0.5, "recordsLaunch": true, "orientation": "landscape-left", "steps": [{"tap": {"label": "New", "traits": ["button"], "occurrence": 2}, "hold": 1, "id": "new"}, {"tap": {"x": 1, "y": 2}}, {"type": {"text": "Hi\n", "into": {"value": ""}}}, {"drag": {"from": {"x": 1, "y": 2}, "to": {"x": 3, "y": 4}, "duration": 0.8}}, {"orientation": "portrait"}, {"waitFor": {"hint": "Sends it", "gone": true, "timeout": 5}}, {"activate": {"identifier": "a"}}, {"hold": 2}]}"##, true),
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

    @Test(arguments: corpus.indices)
    func theSchemaAndTheReaderAgree(_ index: Int) throws {
        let (kind, text, right) = Self.corpus[index]
        #expect(Self.reads(text, as: kind) == right, "the reader, on \(kind) \(index)")
        let problem = try Self.schemaProblem(text, as: kind)
        #expect((problem == nil) == right, "the schema, on \(kind) \(index): \(problem ?? "no problem")")
    }
}
