import Foundation
@testable import RetakeCore
import Testing

/// The reference is what the schemas generate, and every JSON block in the README and
/// Documentation/ fits the schema its marker names.
struct ReferenceTests {
    static let repository = SchemaTests.repository

    @Test(arguments: FileSchema.kinds)
    func theCheckedInReferenceIsWhatTheSchemasGenerate(_ kind: String) throws {
        let url = Self.repository.appending(path: "Documentation/reference/\(kind).md")
        let generated = Reference.page(try #require(FileSchema.named(kind)))
        if ProcessInfo.processInfo.environment["RETAKE_REGENERATE"] == "1" {
            try Data(generated.utf8).write(to: url)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == generated, "run RETAKE_REGENERATE=1 swift test --filter Reference")
    }

    /// A JSON block, and what the comment before it says it is: `<!-- schema: <kind> -->` for a whole
    /// file, or keys at its top when the block starts with a key; `<!-- schema: <kind> <definition> -->`
    /// for keys of a definition; `<!-- schema: none -->` for JSON that isn't one of Retake's files.
    struct Block {
        var file: String
        var line: Int
        var marker: [String]?
        var text: String
    }

    static func blocks(in url: URL, named name: String) throws -> [Block] {
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        var blocks: [Block] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard line == "```json" else { index += 1; continue }
            var marker: [String]?
            if index > 0 {
                let before = lines[index - 1].trimmingCharacters(in: .whitespaces)
                if before.hasPrefix("<!-- schema:"), before.hasSuffix("-->") {
                    marker = before.dropFirst("<!-- schema:".count).dropLast(3).split(separator: " ").map(String.init)
                }
            }
            var body: [String] = []
            index += 1
            while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces) != "```" {
                body.append(lines[index])
                index += 1
            }
            blocks.append(Block(file: name, line: index - body.count, marker: marker, text: body.joined(separator: "\n")))
            index += 1
        }
        return blocks
    }

    static var documents: [(URL, String)] {
        var documents = [(repository.appending(path: "README.md"), "README.md")]
        let folder = repository.appending(path: "Documentation")
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md", !url.path.contains("/records/"), !url.path.contains("/reference/") else { continue }
            documents.append((url, "Documentation/" + url.path.dropFirst(folder.path.count + 1)))
        }
        return documents
    }

    /// Where the docs name a release, it's this one, so a release leaves none behind: an install pin
    /// (`Retake@x.y.z`), a schema URL, a link into the repository at a tag, and a link into The
    /// Button Heist at the release Retake is built against. And RELEASE.md has this release's entry.
    @Test func theDocsNameOnlyThisRelease() throws {
        let version = RetakeVersion.current.schemaVersion
        var patterns: [(String, String)] = [
            (#"Retake@(\d+\.\d+\.\d+)"#, version),
            (#"/Retake/schemas/(\d+\.\d+\.\d+)/"#, version),
            (#"/Retake/(?:tree|blob)/v(\d+\.\d+\.\d+)"#, version),
        ]
        // Built against a clone, The Button Heist's version is the clone's, which links needn't name.
        if !InsideJobFramework.isBuiltFromClone {
            let heist = String(RetakeVersion.current.buttonHeist.version.prefix { $0 != "-" })
            patterns.append((#"/TheButtonHeist/(?:tree|blob)/v(\d+\.\d+\.\d+)"#, heist))
        }
        var documents = Self.documents
        for name in ["CONTRIBUTING.md", "Example/README.md"] {
            documents.append((Self.repository.appending(path: name), name))
        }
        for (url, name) in documents {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (pattern, expected) in patterns {
                for match in text.matches(of: try Regex<(Substring, Substring)>(pattern)) where match.output.1 != expected {
                    let line = text[..<match.range.lowerBound].count { $0 == "\n" } + 1
                    Issue.record("\(name):\(line): \(match.output.0) names \(match.output.1), not \(expected)")
                }
            }
        }
        let notes = try String(contentsOf: Self.repository.appending(path: "RELEASE.md"), encoding: .utf8)
        #expect(notes.contains("\n## \(version) ("), "RELEASE.md has no entry for \(version), such as ## \(version) (unreleased)")
    }

    @Test func everyJSONBlockInTheDocsFitsItsSchema() throws {
        var count = 0
        for (url, name) in Self.documents {
            for block in try Self.blocks(in: url, named: name) {
                count += 1
                let place = "\(block.file):\(block.line)"
                guard let marker = block.marker, let kind = marker.first else {
                    Issue.record("\(place): mark the block with <!-- schema: <kind> -->, <!-- schema: <kind> <definition> --> or <!-- schema: none -->")
                    continue
                }
                if kind == "none" { continue }
                let schema = try #require(FileSchema.named(kind), "\(place): no kind \(kind)")
                let document = schema.json
                let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if marker.count == 1, trimmed.hasPrefix("{") {
                    #expect(SchemaValidator(document: document).problem(try JSONParser.parse(trimmed)) == nil, "\(place)")
                    #expect(SchemaTests.reads(trimmed, as: kind), "\(place): the reader")
                    continue
                }
                // Keys from inside an object: each is checked against that object's own field.
                let target = marker.count > 1 ? document[path: "$defs", marker[1]] : document
                let properties = try #require(target?[path: "properties"], "\(place): nothing has fields there")
                guard case .object(let keys) = try JSONParser.parse("{\(trimmed)}") else { continue }
                for entry in keys.entries {
                    let field = try #require(properties[path: entry.key], "\(place): no field \(entry.key)")
                    let validator = SchemaValidator(document: document)
                    #expect(validator.problem(entry.value, against: field) == nil, "\(place): \(entry.key)")
                }
            }
        }
        #expect(count >= 8)
    }
}
