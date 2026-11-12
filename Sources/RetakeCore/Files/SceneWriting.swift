import Foundation

extension Step {
    /// The step as a scene file gives it: led by its action under the action's key, then its
    /// `hold`, and last its `id`, with options left out where they're their defaults.
    public var json: JSONValue {
        var entries: [JSONObject.Entry] = []
        if let action { entries.append(.init(key: action.key, value: action.json)) }
        if let hold, hold > 0 || action == nil { entries.append(.init(key: "hold", value: .number(hold))) }
        if let id { entries.append(.init(key: "id", value: .string(id))) }
        return .object(JSONObject(entries))
    }
}

extension Step.Action {
    var json: JSONValue {
        switch self {
        case .tapPoint(let position): return position.fileJSON
        case .tapElement(let element, let offset): return Spot.element(element, offset: offset).fileJSON
        case .drag(let from, let to, let duration):
            var entries: [JSONObject.Entry] = [.init(key: "from", value: from.fileJSON), .init(key: "to", value: to.fileJSON)]
            if duration != Step.defaultDragDuration { entries.append(.init(key: "duration", value: .number(duration))) }
            return .object(JSONObject(entries))
        case .type(let text, let into):
            var entries: [JSONObject.Entry] = [.init(key: "text", value: .string(text))]
            if let into { entries.append(.init(key: "into", value: into.json)) }
            return .object(JSONObject(entries))
        case .activate(let element): return element.json
        case .orientation(let orientation): return .string(orientation.rawValue)
        case .capture(let name): return .string(name)
        case .waitFor(let element, let gone, let timeout):
            guard case .object(var object) = element.json else { return element.json }
            if gone { object.entries.append(.init(key: "gone", value: .bool(true))) }
            if timeout != Step.defaultWaitTimeout { object.entries.append(.init(key: "timeout", value: .number(timeout))) }
            return .object(object)
        }
    }
}

extension Position {
    /// As a scene file gives a point: `{ "x": 195, "y": "50%" }`.
    var fileJSON: JSONValue {
        .object(JSONObject([.init(key: "x", value: x.fileJSON), .init(key: "y", value: y.fileJSON)]))
    }
}

extension Length {
    var fileJSON: JSONValue {
        switch self {
        case .points(let points): .number(points)
        case .share(let share): .string("\(Point.number(share * 100))%")
        }
    }
}

extension Spot {
    var fileJSON: JSONValue {
        switch self {
        case .position(let position): return position.fileJSON
        case .element(let element, let offset):
            guard case .object(var object) = element.json else { return element.json }
            func point(_ point: Point) -> JSONValue {
                .object(JSONObject([.init(key: "x", value: .number(point.x)), .init(key: "y", value: .number(point.y))]))
            }
            if offset.points != SpotOffset.none.points { object.entries.append(.init(key: "offset", value: point(offset.points))) }
            if offset.percent != SpotOffset.none.percent { object.entries.append(.init(key: "offsetPercent", value: point(offset.percent))) }
            return .object(object)
        }
    }
}

extension ElementTarget {
    public var json: JSONValue {
        var entries: [JSONObject.Entry] = []
        if let label { entries.append(.init(key: "label", value: .string(label))) }
        if let value { entries.append(.init(key: "value", value: .string(value))) }
        if let identifier { entries.append(.init(key: "identifier", value: .string(identifier))) }
        if let hint { entries.append(.init(key: "hint", value: .string(hint))) }
        if let traits { entries.append(.init(key: "traits", value: .array(traits.map(JSONValue.string)))) }
        if let occurrence { entries.append(.init(key: "occurrence", value: .number(Double(occurrence)))) }
        return .object(JSONObject(entries))
    }
}

/// A scene's file as `compose` edits it: its other fields kept as they were, and its steps written
/// back after each change, each one it read as its file wrote it, with its overrides and `devices`,
/// since compose reads the scene for one device type.
public struct SceneDocument: Sendable {
    public var url: URL
    /// The file's top-level fields, `steps` among them.
    var fields: JSONObject
    public var steps: [Step]
    /// The steps the file had, as read and as written, which a step left as it was is written back as.
    var read: [(step: Step, json: JSONValue)]

    /// The scene in `url`, or a new one on `set` when there's no file yet.
    public init(url: URL, scene: SceneFile?, text: String?, newOn set: String) {
        self.url = url
        if let text, case .object(let object)? = try? JSONParser.parse(text) {
            fields = object
        } else {
            fields = JSONObject([
                .init(key: "set", value: .string(set)),
                .init(key: "steps", value: .array([])),
            ])
        }
        steps = scene?.steps ?? []
        if case .array(let written)? = fields["steps"], written.count == steps.count {
            read = Array(zip(steps, written))
        } else {
            read = []
        }
    }

    /// The step at `index` as it's written: as the file wrote it when compose read it and only its
    /// hold or id has changed since, those written over; as Retake writes a step otherwise.
    func written(_ index: Int) -> JSONValue {
        let step = steps[index]
        guard read.indices.contains(index), read[index].step.action == step.action, case .object(var object) = read[index].json else {
            return step.json
        }
        if read[index].step == step { return .object(object) }
        func set(_ key: String, _ value: JSONValue?) {
            let at = object.entries.firstIndex { $0.key == key }
            switch (at, value) {
            case (let at?, let value?): object.entries[at].value = value
            case (nil, let value?): object.entries.append(.init(key: key, value: value))
            case (let at?, nil): object.entries.remove(at: at)
            case (nil, nil): break
            }
        }
        set("hold", step.hold.map(JSONValue.number))
        set("id", step.id.map(JSONValue.string))
        return .object(object)
    }

    /// The file's text with its steps as they are now, a step to a line, as scenes are written by
    /// hand; its other fields as Retake writes any file.
    public var text: String {
        var fields = fields
        // A placeholder the steps replace, a line each, once the rest is written.
        let marker = "retake-compose-steps"
        if let index = fields.entries.firstIndex(where: { $0.key == "steps" }) {
            fields.entries[index].value = .string(marker)
        } else {
            fields.entries.append(.init(key: "steps", value: .string(marker)))
        }
        let steps = self.steps.isEmpty ? "[]" : "[\n" + self.steps.indices.map { "    " + JSONWriter.compact(written($0)) }.joined(separator: ",\n") + "\n  ]"
        return JSONWriter.write(.object(fields)).replacingOccurrences(of: "\"\(marker)\"", with: steps)
    }

    public func write() throws(RetakeError) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        } catch {
            throw RetakeError(.failed, "Couldn't write \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
