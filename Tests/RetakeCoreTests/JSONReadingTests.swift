import Foundation
import RetakeCore
import Testing

struct JSONParserTests {
    @Test func objectsKeepTheirKeysInTheFilesOrder() throws {
        guard case .object(let object) = try JSONParser.parse(#"{"zeta": 1, "alpha": [true, null], "mid": {"b": 2, "a": 1}}"#) else {
            Issue.record("not an object")
            return
        }
        #expect(object.keys == ["zeta", "alpha", "mid"])
        guard case .object(let inner) = object["mid"] else {
            Issue.record("mid isn't an object")
            return
        }
        #expect(inner.keys == ["b", "a"])
    }

    @Test func stringsDecodeEveryEscape() throws {
        let value = try JSONParser.parse(#""tab\tquote\"slash\/back\\ eé pair🎬""#)
        #expect(value == .string("tab\tquote\"slash/back\\ eé pair🎬"))
    }

    @Test func numbersReadAsJSONWritesThem() throws {
        #expect(try JSONParser.parse("-0.25") == .number(-0.25))
        #expect(try JSONParser.parse("1.5e3") == .number(1500))
        #expect(try JSONParser.parse("0") == .number(0))
    }

    @Test(arguments: [
        (#"{"a": 1,}"#, 1, 9, "JSON has no trailing commas"),
        ("[1, 2,\n]", 2, 1, "JSON has no trailing commas"),
        (#"{"a": "unclosed}"#, 1, 7, "isn't closed"),
        ("012", 1, 1, "can't start with 0"),
        (#"{"a": 1} {"#, 1, 10, "the end of the file"),
        ("// note\n{}", 1, 1, "expected a value"),
        (#"{a: 1}"#, 1, 2, "a key in quotes"),
        ("\"two\nlines\"", 1, 5, "control character"),
        (#""\ud83c""#, 1, 8, "surrogate pair"),
    ])
    func malformedJSONSaysWhereAndWhy(_ text: String, _ line: Int, _ column: Int, _ message: String) {
        do {
            _ = try JSONParser.parse(text)
            Issue.record("parsed \(text)")
        } catch {
            #expect(error.line == line && error.column == column, "\(error)")
            #expect(error.message.contains(message), "\(error)")
        }
    }

    @Test func columnsCountCharactersNotBytes() {
        do {
            _ = try JSONParser.parse(#"{"café": 1,}"#)
            Issue.record("parsed a trailing comma")
        } catch {
            #expect(error.column == 12)
        }
    }

    @Test func deepNestingFailsRatherThanOverflowing() {
        let text = String(repeating: "[", count: 10_000) + String(repeating: "]", count: 10_000)
        #expect(throws: JSONParser.Failure.self) { try JSONParser.parse(text) }
    }
}

struct JSONPathTests {
    @Test func pathsReadAsErrorsGiveThem() {
        let path = JSONPath.root.appending("clips").appending(3).appending("from").appending("fraction")
        #expect(path.description == "clips[3].from.fraction")
        #expect(JSONPath.root.appending("takes").appending("create-note").description == "takes.create-note")
        #expect(JSONPath.root.appending("$schema").description == "$schema")
    }

    @Test func keysThatArentPlainNamesAreQuoted() {
        let path = JSONPath.root.appending("files").appending("Documents/notes.json")
        #expect(path.description == #"files["Documents/notes.json"]"#)
        #expect(JSONPath.root.appending("say \"hi\"").description == #"["say \"hi\""]"#)
        #expect(JSONPath.root.appending("3d").description == #"["3d"]"#)
    }
}

/// A small type read the way every file's types are, to test the reader through.
fileprivate struct Clip {
    enum Turns: String, CaseIterable { case letterboxed, device }

    var take: String
    var speed: Double?
    var fraction: Double?
    var repeats: Int?
    var turns: Turns?
    var tags: [String]?
    var environment: [(key: String, value: String)]?

    static func read(_ value: JSONValue, at path: JSONPath, _ reader: JSONReader) -> Clip? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let take = object.required("take", reader.nonEmptyString)
        let clip = Clip(
            take: take ?? "",
            speed: object.optional("speed") { reader.number($0, at: $1, .above(0)) },
            fraction: object.optional("fraction") { reader.number($0, at: $1, .within(-1...1)) },
            repeats: object.optional("repeats") { reader.integer($0, at: $1, atLeast: 1) },
            turns: object.optional("turns") { reader.choice($0, at: $1, as: Turns.self) },
            tags: object.optional("tags") { reader.array($0, at: $1, element: reader.string) },
            environment: object.optional("environment") { reader.dictionary($0, at: $1, element: reader.string) },
        )
        return take == nil ? nil : clip
    }
}

struct JSONReaderTests {
    fileprivate func read(_ text: String) -> (clip: Clip?, problems: [String]) {
        let reader = JSONReader(file: "edits/video1.json")
        guard let value = reader.parse(text) else { return (nil, reader.problems.map(\.description)) }
        let clips = reader.object(value, at: .root).flatMap { object -> [Clip]? in
            var object = object
            defer { object.finish() }
            return object.required("clips") { reader.array($0, at: $1) { Clip.read($0, at: $1, reader) } }
        }
        return (clips?.first, reader.problems.map(\.description))
    }

    @Test func aWellFormedFileReadsWithNoProblems() {
        let result = read(#"""
            {"clips": [{"take": "create-note", "speed": 1.5, "fraction": -0.5, "repeats": 2, "turns": "device",
                        "tags": ["a", "b"], "environment": {"B": "2", "A": "1"}}]}
            """#)
        #expect(result.problems.isEmpty)
        #expect(result.clip?.speed == 1.5 && result.clip?.turns == .device && result.clip?.repeats == 2)
        #expect(result.clip?.environment?.map(\.key) == ["B", "A"])
    }

    @Test(arguments: [
        (#"{"clips": [{"take": "a", "fraction": 1.4}]}"#, "edits/video1.json: clips[0].fraction: 1.4 is outside -1 to 1"),
        (#"{"clips": [{"take": "a", "speed": 0}]}"#, "edits/video1.json: clips[0].speed: 0 must be more than 0"),
        (#"{"clips": [{"take": "a", "repeats": 2.5}]}"#, "edits/video1.json: clips[0].repeats: 2.5 isn't a whole number"),
        (#"{"clips": [{"take": "a", "repeats": 0}]}"#, "edits/video1.json: clips[0].repeats: 0 must be at least 1"),
        (#"{"clips": [{"take": "a", "turns": "sideways"}]}"#, #"edits/video1.json: clips[0].turns: "sideways" isn't one of letterboxed or device"#),
        (#"{"clips": [{"take": 3}]}"#, "edits/video1.json: clips[0].take: expected a string, found a number"),
        (#"{"clips": [{"take": ""}]}"#, "edits/video1.json: clips[0].take: can't be empty"),
        (#"{"clips": [{"speed": 1}]}"#, #"edits/video1.json: clips[0]: is missing "take""#),
        (#"{"clips": [{"take": "a", "speed": null}]}"#, "edits/video1.json: clips[0].speed: expected a number, found null"),
        (#"{"clips": [{"take": "a", "tags": ["x", 2]}]}"#, "edits/video1.json: clips[0].tags[1]: expected a string, found a number"),
        (#"{"clips": {"take": "a"}}"#, "edits/video1.json: clips: expected a list, found an object"),
        (#"{"clips": [{"take": "a", "spead": 1}]}"#, #"edits/video1.json: clips[0]: unknown key "spead"; did you mean "speed"?"#),
        (#"{"clips": [{"take": "a", "Speed": 1}]}"#, #"edits/video1.json: clips[0]: unknown key "Speed"; did you mean "speed"?"#),
        (#"{"clips": [{"take": "a", "colour": 1}]}"#, #"edits/video1.json: clips[0]: unknown key "colour""#),
        (#"{"clips": [{"take": "a", "take": "b"}]}"#, #"edits/video1.json: clips[0]: "take" is given more than once"#),
        (#"{"clips": [], "clips": []}"#, #"edits/video1.json: "clips" is given more than once"#),
        (#"{"clips": [{"take": "a"}],}"#, "edits/video1.json: isn't valid JSON: line 1, column 27: expected a key after \",\"; JSON has no trailing commas"),
    ])
    func eachProblemNamesTheFileAndField(_ text: String, _ expected: String) {
        #expect(read(text).problems == [expected])
    }

    @Test func everyProblemInAFileIsReported() {
        let problems = read(#"{"clips": [{"take": 1, "speed": -1}, {"fraction": 2}], "extra": true}"#).problems
        #expect(problems == [
            "edits/video1.json: clips[0].take: expected a string, found a number",
            "edits/video1.json: clips[0].speed: -1 must be more than 0",
            #"edits/video1.json: clips[1]: is missing "take""#,
            "edits/video1.json: clips[1].fraction: 2 is outside -1 to 1",
            #"edits/video1.json: unknown key "extra""#,
        ])
    }

    @Test func aDictionarysRepeatedKeyIsReportedOnce() {
        let problems = read(#"{"clips": [{"take": "a", "environment": {"A": "1", "A": "2", "A": "3"}}]}"#).problems
        #expect(problems == [#"edits/video1.json: clips[0].environment: "A" is given more than once"#])
    }
}

struct SchemaReferenceTests {
    func warnings(_ text: String, kind: String = "edit") -> [String] {
        let reader = JSONReader(file: "edits/video1.json")
        if var object = reader.root(try! JSONParser.parse(text), kind: kind) {
            object.know("clips")
            object.finish()
        }
        #expect(reader.problems.isEmpty)
        return reader.warnings.map(\.description)
    }

    @Test func thisRetakesSchemaOrNoneReadsQuietly() {
        let current = SchemaReference.current("edit").url
        #expect(warnings(#"{"$schema": "\#(current)", "clips": []}"#).isEmpty)
        #expect(warnings(#"{"clips": []}"#).isEmpty)
        #expect(warnings(#"{"$schema": "https://example.com/elsewhere.json"}"#).isEmpty)
    }

    @Test func anotherVersionsOrKindsSchemaWarns() {
        let other = SchemaReference(version: "9.9.9", kind: "edit").url
        #expect(warnings(#"{"$schema": "\#(other)"}"#) == [
            "edits/video1.json: \"$schema\" names Retake 9.9.9's schema; reading it as this Retake's (\(RetakeVersion.current.schemaVersion))",
        ])
        let scene = SchemaReference.current("scene").url
        #expect(warnings(#"{"$schema": "\#(scene)"}"#) == [
            "edits/video1.json: \"$schema\" names the scene schema, but this is read as a edit file",
        ])
    }

    @Test func urlsRoundTrip() {
        let reference = SchemaReference(version: "0.0.1", kind: "edit")
        #expect(reference.url == "https://justinseanmartin.github.io/Retake/schemas/0.0.1/edit.schema.json")
        #expect(SchemaReference(url: reference.url) == reference)
        #expect(SchemaReference(url: "https://justinseanmartin.github.io/Retake/schemas/0.0.1/") == nil)
    }
}

/// An object's keys, in order; none for anything else.
func keys(_ value: JSONValue?) -> [String] {
    if case .object(let object)? = value { object.entries.map(\.key) } else { [] }
}
