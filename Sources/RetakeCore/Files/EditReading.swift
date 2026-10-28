import Foundation

extension EditFile {
    /// The edit in a file's text, or nil with problems in `reader`. Each device type's overrides are
    /// laid over the rest, objects key by key and lists and plain values replaced, and the result is
    /// read for that type; a problem is named where its value is written, in an override or not, and
    /// once however many device types share it.
    public static func read(_ text: String, with reader: JSONReader) -> EditFile? {
        guard let value = reader.parse(text), var root = reader.root(value, kind: "edit") else { return nil }
        let problemsBefore = reader.problems.count
        let intent = root.optional("intent", reader.string)
        let devices = root.required("devices") { value, path -> [DeviceType]? in
            guard let devices = reader.array(value, at: path, element: { reader.choice($0, at: $1, as: DeviceType.self) }) else { return nil }
            if case .array(let values) = value, values.isEmpty {
                reader.problem("needs at least one device type: iphone, ipad", at: path)
            }
            var seen = Set<DeviceType>()
            for (index, device) in devices.enumerated() where !seen.insert(device).inserted {
                reader.problem("\"\(device.rawValue)\" is given more than once", at: path.appending(index))
            }
            return devices
        }
        let takes = root.optional("takes") { readTakes($0, $1, reader) } ?? [:]
        root.know("$schema", "music", "tapSound", "takeAudioVolume", "background", "turns", "turnBlur", "clips")
        for type in DeviceType.allCases {
            guard let override = root.value(type.rawValue) else { continue }
            if let devices, !devices.contains(type) {
                reader.problem("overrides \(type.rawValue), which isn't one of this edit's devices", at: root.path(type.rawValue))
            }
            if case .object(let object) = override {
                for key in notOverridable where object[key] != nil {
                    reader.problem("\"\(key)\" can't be given for one device type", at: root.path(type.rawValue))
                }
            }
        }
        if let devices {
            for type in takes.keys where !devices.contains(type) {
                reader.problem("pins takes for \(type.rawValue), which isn't one of this edit's devices", at: root.path("takes"))
            }
        }
        root.finish()

        var videos: [DeviceType: Edit] = [:]
        var allOrigins: [DeviceType: Origins] = [:]
        var seen = Set(reader.problems.map(\.description))
        if case .object(let object) = value {
            for type in devices ?? [] {
                var origins = Origins()
                let merged = Overrides.merge(object, for: type, at: .root, into: .root, origins: &origins, reader: reader)
                let typeReader = JSONReader(file: reader.file)
                let edit = readEdit(merged, typeReader)
                for problem in typeReader.problems {
                    // A problem about a key is named at its object, wherever the key was written.
                    let path = problem.about.map { JSONPath(origins.source(of: $0).components.dropLast()) }
                        ?? origins.source(of: problem.path)
                    if seen.insert(FileProblem(file: problem.file, path: path, message: problem.message).description).inserted {
                        reader.problem(problem.message, at: path)
                    }
                }
                videos[type] = edit
                allOrigins[type] = origins
            }
        }
        guard reader.problems.count == problemsBefore, let devices, videos.count == devices.count else { return nil }
        return EditFile(intent: intent, devices: devices, takes: takes, videos: videos, origins: allOrigins)
    }

    static func readTakes(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> [DeviceType: [Named<Int>]]? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        var takes: [DeviceType: [Named<Int>]] = [:]
        for type in DeviceType.allCases {
            takes[type] = object.optional(type.rawValue) { value, path in
                reader.dictionary(value, at: path) { reader.integer($0, at: $1, atLeast: 1) }?.map { Named($0.key, $0.value) }
            }
        }
        return takes
    }

    /// One device type's edit, from its merged object, with the keys that belong only to the base
    /// (`devices`, `takes`, `$schema`) read already.
    static func readEdit(_ object: JSONObject, _ reader: JSONReader) -> Edit? {
        var root = ObjectReader(reader: reader, object: object, path: .root)
        root.know("$schema", "devices", "takes")
        defer { root.finish() }
        let problemsBefore = reader.problems.count
        let intent = root.optional("intent", reader.string)
        let music = root.optional("music") { value, path -> Edit.Music? in
            guard var object = reader.object(value, at: path) else { return nil }
            defer { object.finish() }
            let file = object.required("file", reader.nonEmptyString)
            let volume = object.optional("volume") { reader.number($0, at: $1, .atLeast(0)) } ?? 1
            let fadeOut = object.optional("fadeOut") { reader.number($0, at: $1, .atLeast(0)) } ?? 0
            return file.map { Edit.Music(file: $0, volume: volume, fadeOut: fadeOut) }
        }
        let tapSound = root.optional("tapSound") { readSound($0, $1, reader) }
        let takeAudioVolume = root.optional("takeAudioVolume") { reader.number($0, at: $1, .atLeast(0)) } ?? 1
        let background = root.optional("background") { readColor($0, $1, reader) } ?? .black
        let turns = root.optional("turns") { reader.choice($0, at: $1, as: Edit.Turns.self) } ?? .letterboxed
        let turnBlur = root.optional("turnBlur") { readTurnBlur($0, $1, reader) }
        let clips = root.required("clips") { value, path -> [Edit.Clip]? in
            guard let clips = reader.array(value, at: path, element: { readClip($0, $1, reader) }) else { return nil }
            if case .array(let values) = value, values.isEmpty { reader.problem("needs at least one clip", at: path) }
            return clips
        }
        // Clips that couldn't be read are left out, so the checks across them wait until each has.
        if let clips, case .array(let values)? = root.object["clips"], clips.count == values.count {
            checkClips(clips, root.object["clips"], at: root.path("clips"), reader)
        }
        guard reader.problems.count == problemsBefore, let clips else { return nil }
        return Edit(
            intent: intent, music: music, tapSound: tapSound, takeAudioVolume: takeAudioVolume, background: background,
            turns: turns, turnBlur: turnBlur, clips: clips,
        )
    }

    /// Clip ids are unique, the first clip can't cross-fade from one before it, and a caption that
    /// runs on names a clip after its own.
    static func checkClips(_ clips: [Edit.Clip], _ value: JSONValue?, at path: JSONPath, _ reader: JSONReader) {
        var ids: [String: Int] = [:]
        for (index, clip) in clips.enumerated() {
            if let id = clip.id {
                if let earlier = ids[id] {
                    reader.problem("\"\(id)\" is already clips[\(earlier)]'s id; ids are unique in an edit", at: path.appending(index).appending("id"))
                } else {
                    ids[id] = index
                }
            }
        }
        if let first = clips.first, first.crossfade > 0 {
            reader.problem("has no clip before it to cross-fade from", at: path.appending(0).appending("crossfade"))
        }
        for (index, clip) in clips.enumerated() {
            for (captionIndex, caption) in clip.captions.enumerated() {
                guard let name = caption.to?.clip else { continue }
                let at = path.appending(index).appending("captions").appending(captionIndex).appending("to").appending("clip")
                guard let target = ids[name] else {
                    reader.problem("there's no clip with the id \"\(name)\"", at: at)
                    continue
                }
                if target <= index {
                    reader.problem("names clips[\(target)], which isn't after this caption's own clip; a caption runs on only into later clips", at: at)
                }
            }
        }
    }

    static func readClip(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Edit.Clip? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let problemsBefore = reader.problems.count
        let id = object.optional("id", reader.nonEmptyString)
        let intent = object.optional("intent", reader.string)
        let take = object.required("take", reader.nonEmptyString)
        let from = object.required("from") { readAnchor($0, $1, reader) }
        let to = object.required("to") { readAnchor($0, $1, reader) }
        let speed = object.optional("speed") { reader.number($0, at: $1, .above(0)) } ?? 1
        let crossfade = object.optional("crossfade") { reader.number($0, at: $1, .atLeast(0)) } ?? 0
        let audioCrossfade = object.optional("audioCrossfade") { reader.number($0, at: $1, .atLeast(0)) }
        if let audioCrossfade, audioCrossfade < crossfade {
            reader.problem(
                "\(JSONReader.format(audioCrossfade)) is shorter than the clip's crossfade, \(JSONReader.format(crossfade)); the sound fades over at least as long as the picture",
                at: object.path("audioCrossfade"),
            )
        }
        let touches = object.optional("touches", reader.bool) ?? false
        let takeAudio = object.optional("takeAudio", reader.bool) ?? false
        let captions = object.optional("captions") { reader.array($0, at: $1) { readCaption($0, $1, reader) } } ?? []
        let sounds = object.optional("sounds") { reader.array($0, at: $1) { readEffect($0, $1, reader) } } ?? []
        let spotlight = object.optional("spotlight") { readSpotlight($0, $1, reader) }
        let blurs = object.optional("blurs") { reader.array($0, at: $1) { readBlur($0, $1, reader) } } ?? []
        let stills = object.optional("stills") { reader.array($0, at: $1) { readStill($0, $1, reader) } } ?? []
        let turns = object.optional("turns") { reader.choice($0, at: $1, as: Edit.Turns.self) }
        let turnBlur = object.optional("turnBlur") { readTurnBlur($0, $1, reader) }
        guard reader.problems.count == problemsBefore, let take, let from, let to else { return nil }
        return Edit.Clip(
            id: id, intent: intent, take: take, from: from, to: to, speed: speed, crossfade: crossfade,
            audioCrossfade: audioCrossfade, touches: touches, takeAudio: takeAudio, captions: captions, sounds: sounds,
            spotlight: spotlight, blurs: blurs, stills: stills, turns: turns, turnBlur: turnBlur,
        )
    }

    static func readCaption(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Edit.Caption? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let problemsBefore = reader.problems.count
        let text = object.required("text", reader.nonEmptyString)
        let y = object.required("y") { reader.number($0, at: $1, .within(0...1)) }
        let color = object.required("color") { readColor($0, $1, reader) }
        let from = object.optional("from") { readAnchor($0, $1, reader) }
        let to = object.optional("to") { value, path -> Edit.CaptionEnd? in
            if case .object(let anchor) = value, anchor["clip"] != nil {
                var end = ObjectReader(reader: reader, object: anchor, path: path)
                let clip = end.required("clip", reader.nonEmptyString)
                end.know("step", "offset", "fraction", "edge")
                end.finish()
                let rest = JSONObject(anchor.entries.filter { $0.key != "clip" })
                guard let clip else { return nil }
                if rest.entries.isEmpty { return Edit.CaptionEnd(clip: clip, anchor: nil) }
                return readAnchor(.object(rest), path, reader).map { Edit.CaptionEnd(clip: clip, anchor: $0) }
            }
            return readAnchor(value, path, reader).map { Edit.CaptionEnd(clip: nil, anchor: $0) }
        }
        let symbol = object.optional("symbol") { value, path -> Edit.Symbol? in
            guard var object = reader.object(value, at: path) else { return nil }
            defer { object.finish() }
            let name = object.required("name", reader.nonEmptyString)
            let rotation = object.optional("animation") { value, path -> Edit.Symbol.Rotation? in
                guard var animation = reader.object(value, at: path) else { return nil }
                defer { animation.finish() }
                if animation.object.entries.isEmpty {
                    reader.problem("needs an animation; \"rotate\" is the one there is", at: path)
                    return nil
                }
                return animation.optional("rotate") { value, path -> Edit.Symbol.Rotation? in
                    guard var rotate = reader.object(value, at: path) else { return nil }
                    defer { rotate.finish() }
                    let degrees = rotate.required("degrees") { reader.number($0, at: $1) }
                    let duration = rotate.required("duration") { reader.number($0, at: $1, .above(0)) }
                    guard let degrees, let duration else { return nil }
                    return Edit.Symbol.Rotation(degrees: degrees, duration: duration)
                }
            }
            return name.map { Edit.Symbol(name: $0, rotation: rotation) }
        }
        guard reader.problems.count == problemsBefore, let text, let y, let color else { return nil }
        return Edit.Caption(text: text, y: y, color: color, from: from, to: to, symbol: symbol)
    }

    static func readEffect(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Edit.Effect? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let file = object.required("file", reader.nonEmptyString)
        let at = object.required("at") { readAnchor($0, $1, reader) }
        let volume = object.optional("volume") { reader.number($0, at: $1, .atLeast(0)) } ?? 1
        let duration = object.optional("duration") { reader.number($0, at: $1, .above(0)) }
        guard let file, let at else { return nil }
        return Edit.Effect(file: file, at: at, volume: volume, duration: duration)
    }

    static func readSound(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Edit.Sound? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let file = object.required("file", reader.nonEmptyString)
        let volume = object.optional("volume") { reader.number($0, at: $1, .atLeast(0)) } ?? 1
        return file.map { Edit.Sound(file: $0, volume: volume) }
    }

    static func readTurnBlur(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Edit.TurnBlur? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        return object.required("duration") { reader.number($0, at: $1, .above(0)) }.map(Edit.TurnBlur.init)
    }

    static func readSpotlight(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Edit.Spotlight? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let region = readRegion(&object, reader)
        let padding = object.optional("padding") { reader.number($0, at: $1, .atLeast(0)) } ?? 8
        let color = object.optional("color") { readColor($0, $1, reader) } ?? .white
        let from = object.optional("from") { readAnchor($0, $1, reader) }
        let to = object.optional("to") { readAnchor($0, $1, reader) }
        return region.map { Edit.Spotlight(region: $0, padding: padding, color: color, from: from, to: to) }
    }

    static func readBlur(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Edit.Blur? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let region = readRegion(&object, reader)
        let from = object.optional("from") { readAnchor($0, $1, reader) }
        let to = object.optional("to") { readAnchor($0, $1, reader) }
        let radius = object.optional("radius") { reader.number($0, at: $1, .above(0)) } ?? 20
        return region.map { Edit.Blur(region: $0, from: from, to: to, radius: radius) }
    }

    static func readStill(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Edit.Still? {
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let take = object.required("take", reader.nonEmptyString)
        let at = object.required("at") { readAnchor($0, $1, reader) }
        guard let take, let at else { return nil }
        return Edit.Still(take: take, at: at)
    }

    /// An `element`, found in the step log, or a `rect` in screen points: one of them.
    static func readRegion(_ object: inout ObjectReader, _ reader: JSONReader) -> Edit.Region? {
        let hasElement = object.has("element")
        let hasRect = object.has("rect")
        switch (hasElement, hasRect) {
        case (true, true):
            reader.problem("names an \"element\" or a \"rect\", not both", at: object.path)
            return nil
        case (false, false):
            reader.problem("needs an \"element\" to find in the step log, or a \"rect\" in screen points", at: object.path)
            return nil
        case (true, false):
            return object.required("element") { value, path in
                reader.object(value, at: path).flatMap { var element = $0; defer { element.finish() }; return SceneFile.readElement(&element, reader) }
            }.map(Edit.Region.element)
        case (false, true):
            return object.required("rect") { value, path -> Edit.Rect? in
                guard var rect = reader.object(value, at: path) else { return nil }
                defer { rect.finish() }
                let x = rect.required("x") { reader.number($0, at: $1, .atLeast(0)) }
                let y = rect.required("y") { reader.number($0, at: $1, .atLeast(0)) }
                let width = rect.required("width") { reader.number($0, at: $1, .above(0)) }
                let height = rect.required("height") { reader.number($0, at: $1, .above(0)) }
                guard let x, let y, let width, let height else { return nil }
                return Edit.Rect(x: x, y: y, width: width, height: height)
            }.map(Edit.Region.rect)
        }
    }

    static func readColor(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Color? {
        guard let text = reader.string(value, at: path) else { return nil }
        guard let color = Color(hex: text) else {
            reader.problem("\"\(text)\" isn't a colour: #RRGGBB, or #RRGGBBAA with its opacity, such as #1F6FEB", at: path)
            return nil
        }
        return color
    }

    /// An anchor: plain seconds from the take's start, or a step and where to go from it.
    public static func readAnchor(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Anchor? {
        if case .number = value {
            return reader.number(value, at: path, .atLeast(0)).map(Anchor.seconds)
        }
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let step = object.required("step") { value, path -> Anchor.StepReference? in
            switch value {
            case .string("start"): return .start
            case .string("end"): return .end
            case .string(let id) where !id.isEmpty: return .id(id)
            case .number:
                guard let number = reader.integer(value, at: path) else { return nil }
                guard number != 0 else {
                    reader.problem("steps are numbered from 1, or from the last as -1; there's no step 0", at: path)
                    return nil
                }
                return .number(number)
            default:
                reader.problem("expected a step's id, its number, \"start\" or \"end\", found \(value.kind)", at: path)
                return nil
            }
        }
        let offset = object.optional("offset") { reader.number($0, at: $1) }
        let fraction = object.optional("fraction") { reader.number($0, at: $1, .within(-1...1)) }
        let edge = object.optional("edge") { reader.choice($0, at: $1, as: Anchor.Edge.self) }
        if object.object["offset"] != nil, object.object["fraction"] != nil {
            reader.problem("moves by an \"offset\" or a \"fraction\", not both", at: path)
            return nil
        }
        if edge != nil, offset == nil, fraction == nil {
            reader.problem("\"edge\" says which edge an offset or a fraction counts from, and there's neither", at: path)
            return nil
        }
        guard let step else { return nil }
        return .step(Anchor.StepAnchor(step: step, offset: offset, fraction: fraction, edge: edge))
    }
}

/// Where each part of a merged object came from, so a problem in it is named where it's written.
public struct Origins: Equatable, Sendable {
    private var entries: [Entry] = []

    private struct Entry: Equatable, Sendable {
        var merged: JSONPath
        var source: JSONPath
    }

    public init() {}

    mutating func record(_ merged: JSONPath, from source: JSONPath) {
        entries.append(Entry(merged: merged, source: source))
    }

    /// The path a problem at `path` in the merged object is written at: the longest recorded prefix
    /// of it, rewritten to where that part came from.
    public func source(of path: JSONPath) -> JSONPath {
        let match = entries.filter { path.components.starts(with: $0.merged.components) }
            .max { $0.merged.components.count < $1.merged.components.count }
        guard let match else { return path }
        return JSONPath(match.source.components + path.components.dropFirst(match.merged.components.count))
    }
}

/// Laying a device type's overrides over an edit.
enum Overrides {
    static let deviceKeys = Set(DeviceType.allCases.map(\.rawValue))

    /// `object` with each object it holds merged for `type`, then its own `type` override laid over
    /// it: objects key by key, lists and plain values replaced. Other device types' overrides are
    /// dropped. `takes` is left as it is, since its device keys are pins rather than overrides.
    static func merge(
        _ object: JSONObject,
        for type: DeviceType,
        at source: JSONPath,
        into merged: JSONPath,
        origins: inout Origins,
        reader: JSONReader,
    ) -> JSONObject {
        var result = JSONObject()
        for entry in object.entries where !deviceKeys.contains(entry.key) {
            let value = entry.key == "takes" && source.isRoot
                ? entry.value
                : mergeValue(entry.value, for: type, at: source.appending(entry.key), into: merged.appending(entry.key), origins: &origins, reader: reader)
            result.entries.append(.init(key: entry.key, value: value))
        }
        guard case .object(let override)? = object[type.rawValue] else {
            if let value = object[type.rawValue] {
                reader.problem("expected an object, found \(value.kind)", at: source.appending(type.rawValue))
            }
            return result
        }
        let overrideSource = source.appending(type.rawValue)
        lay(override, over: &result, for: type, from: overrideSource, at: merged, origins: &origins, reader: reader)
        return result
    }

    static func lay(
        _ override: JSONObject,
        over result: inout JSONObject,
        for type: DeviceType,
        from source: JSONPath,
        at merged: JSONPath,
        origins: inout Origins,
        reader: JSONReader,
    ) {
        for entry in override.entries {
            let entrySource = source.appending(entry.key)
            let entryMerged = merged.appending(entry.key)
            if deviceKeys.contains(entry.key) {
                reader.problem("an override can't hold another device type's", at: entrySource)
                continue
            }
            if let index = result.entries.firstIndex(where: { $0.key == entry.key }),
               case .object(var existing) = result.entries[index].value, case .object(let inner) = entry.value {
                lay(inner, over: &existing, for: type, from: entrySource, at: entryMerged, origins: &origins, reader: reader)
                result.entries[index].value = .object(existing)
                continue
            }
            let value = mergeValue(entry.value, for: type, at: entrySource, into: entryMerged, origins: &origins, reader: reader)
            origins.record(entryMerged, from: entrySource)
            if let index = result.entries.firstIndex(where: { $0.key == entry.key }) {
                result.entries[index].value = value
            } else {
                result.entries.append(.init(key: entry.key, value: value))
            }
        }
    }

    static func mergeValue(
        _ value: JSONValue,
        for type: DeviceType,
        at source: JSONPath,
        into merged: JSONPath,
        origins: inout Origins,
        reader: JSONReader,
    ) -> JSONValue {
        switch value {
        case .object(let object):
            return .object(merge(object, for: type, at: source, into: merged, origins: &origins, reader: reader))
        case .array(let values):
            return .array(values.enumerated().map { index, value in
                mergeValue(value, for: type, at: source.appending(index), into: merged.appending(index), origins: &origins, reader: reader)
            })
        default:
            return value
        }
    }
}
