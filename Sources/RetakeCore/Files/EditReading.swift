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
        if root.value("takes") != nil {
            reader.problem("an edit doesn't name its takes: cut uses each scene's latest successful take, and `retake clean --takes` goes back to an earlier one; delete \"takes\"", at: root.path("takes"))
        }
        root.know("$schema", "takes", "music", "tapSound", "takeAudioVolume", "background", "turns", "turnBlur", "touchColor", "clips")
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
        // A clip's devices are among the edit's.
        if let devices, case .array(let clips)? = root.value("clips") {
            for (index, clip) in clips.enumerated() {
                guard case .object(let clip) = clip, case .array(let named)? = clip["devices"] else { continue }
                for (deviceIndex, name) in named.enumerated() {
                    guard case .string(let name) = name, let type = DeviceType(rawValue: name), !devices.contains(type) else { continue }
                    reader.problem("\"\(name)\" isn't one of this edit's devices", at: root.path("clips").appending(index).appending("devices").appending(deviceIndex))
                }
            }
        }
        root.finish()

        var videos: [DeviceType: Edit] = [:]
        var allOrigins: [DeviceType: Origins] = [:]
        var seen = Set(reader.problems.map(\.description))
        if case .object(let object) = value {
            for type in devices ?? [] {
                var origins = Origins()
                let merged = Overrides.clips(of: Overrides.merge(object, for: type, at: .root, into: .root, origins: &origins, reader: reader), for: type, origins: &origins)
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
        return EditFile(intent: intent, devices: devices, videos: videos, origins: allOrigins)
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
        let touchColor = root.optional("touchColor") { readColor($0, $1, reader) } ?? .white
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
            turns: turns, turnBlur: turnBlur, touchColor: touchColor, clips: clips,
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
        let touches = object.optional("touches", reader.bool) ?? true
        let touchColor = object.optional("touchColor") { readColor($0, $1, reader) }
        let touchColors = object.optional("touchColors") { value, path in
            reader.array(value, at: path) { value, path -> Edit.TouchColor? in
                guard var entry = reader.object(value, at: path) else { return nil }
                defer { entry.finish() }
                let step = entry.required("step") { readStepReference($0, $1, reader) }
                let color = entry.required("color") { readColor($0, $1, reader) }
                guard let step, let color else { return nil }
                return Edit.TouchColor(step: step, color: color)
            }
        } ?? []
        let takeAudio = object.optional("takeAudio", reader.bool) ?? false
        let captions = object.optional("captions") { reader.array($0, at: $1) { readCaption($0, $1, reader) } } ?? []
        let sounds = object.optional("sounds") { reader.array($0, at: $1) { readEffect($0, $1, reader) } } ?? []
        let spotlight = object.optional("spotlight") { readSpotlight($0, $1, reader) }
        let blurs = object.optional("blurs") { reader.array($0, at: $1) { readBlur($0, $1, reader) } } ?? []
        let stills = object.optional("stills") { reader.array($0, at: $1) { readStill($0, $1, reader) } } ?? []
        let stillsBackground = object.optional("stillsBackground") { readColor($0, $1, reader) }
        if stillsBackground != nil, stills.isEmpty {
            reader.problem("the clip has no stills for it to go behind", at: object.path("stillsBackground"))
        }
        let stillsIn = object.optional("stillsIn") { readAnchor($0, $1, reader) }
        if stillsIn != nil, stills.isEmpty {
            reader.problem("the clip has no stills to pop in", at: object.path("stillsIn"))
        }
        let stillsOut = object.optional("stillsOut") { readAnchor($0, $1, reader) }
        if stillsOut != nil, stills.isEmpty {
            reader.problem("the clip has no stills to pop out", at: object.path("stillsOut"))
        }
        let turns = object.optional("turns") { reader.choice($0, at: $1, as: Edit.Turns.self) }
        let turnBlur = object.optional("turnBlur") { readTurnBlur($0, $1, reader) }
        let card = object.optional("card") { value, path -> Edit.Card? in
            guard var card = reader.object(value, at: path) else { return nil }
            defer { card.finish() }
            let color = card.required("color") { readColor($0, $1, reader) }
            let from = card.optional("from") { readAnchor($0, $1, reader) }
            let to = card.optional("to") { readAnchor($0, $1, reader) }
            return color.map { Edit.Card(color: $0, from: from, to: to) }
        }
        // Read for the edit's types already, and only those it names kept; checked here.
        _ = object.optional("devices") { value, path -> [DeviceType]? in
            guard let devices = reader.array(value, at: path, element: { reader.choice($0, at: $1, as: DeviceType.self) }) else { return nil }
            if devices.isEmpty { reader.problem("needs at least one device type: iphone, ipad", at: path) }
            for (index, device) in devices.enumerated() where devices[..<index].contains(device) {
                reader.problem("\"\(device.rawValue)\" is given more than once", at: path.appending(index))
            }
            return devices
        }
        guard reader.problems.count == problemsBefore, let take, let from, let to else { return nil }
        return Edit.Clip(
            id: id, intent: intent, take: take, from: from, to: to, speed: speed, crossfade: crossfade,
            audioCrossfade: audioCrossfade, touches: touches, touchColor: touchColor, touchColors: touchColors, takeAudio: takeAudio, captions: captions, sounds: sounds,
            spotlight: spotlight, blurs: blurs, stills: stills, stillsBackground: stillsBackground, stillsIn: stillsIn, stillsOut: stillsOut, card: card, turns: turns, turnBlur: turnBlur,
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
        let radius = object.optional("radius") { reader.number($0, at: $1, .above(0)) } ?? Edit.Blur.defaultRadius
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

    /// An `element`, found in the step log, and perhaps a `part` of it, or a `rect` of the screen:
    /// one of them.
    static func readRegion(_ object: inout ObjectReader, _ reader: JSONReader) -> Edit.Region? {
        let hasElement = object.has("element")
        let hasRect = object.has("rect")
        if object.has("part"), !hasElement {
            reader.problem("is a part of an \"element\", which isn't given", at: object.path("part"))
            return nil
        }
        switch (hasElement, hasRect) {
        case (true, true):
            reader.problem("names an \"element\" or a \"rect\", not both", at: object.path)
            return nil
        case (false, false):
            reader.problem("needs an \"element\" to find in the step log, or a \"rect\" in screen points", at: object.path)
            return nil
        case (true, false):
            let element = object.required("element") { value, path in
                reader.object(value, at: path).flatMap { var element = $0; defer { element.finish() }; return SceneFile.readElement(&element, reader) }
            }
            let part = object.optional("part") { readRect($0, $1, reader, whole: true) }
            if object.has("part"), part == nil { return nil }
            return element.map { Edit.Region.element($0, part: part) }
        case (false, true):
            return object.required("rect") { readRect($0, $1, reader) }.map(Edit.Region.rect)
        }
    }

    /// A rectangle of points or shares, each of its sides given; or, for a `whole` element's part,
    /// any of them, the rest the whole's.
    static func readRect(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader, whole: Bool = false) -> Edit.Rect? {
        guard var rect = reader.object(value, at: path) else { return nil }
        defer { rect.finish() }
        let problems = reader.problems.count
        func side(_ key: String, aboveZero: Bool, otherwise: Length) -> Length? {
            whole ? rect.optional(key) { SceneFile.readLength($0, $1, reader, aboveZero: aboveZero) } ?? otherwise
                : rect.required(key) { SceneFile.readLength($0, $1, reader, aboveZero: aboveZero) }
        }
        let x = side("x", aboveZero: false, otherwise: .share(0)), y = side("y", aboveZero: false, otherwise: .share(0))
        let width = side("width", aboveZero: true, otherwise: .share(1)), height = side("height", aboveZero: true, otherwise: .share(1))
        guard reader.problems.count == problems, let x, let y, let width, let height else { return nil }
        return Edit.Rect(x: x, y: y, width: width, height: height)
    }

    static func readColor(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Color? {
        guard let text = reader.string(value, at: path) else { return nil }
        guard let color = Color(hex: text) else {
            reader.problem("\"\(text)\" isn't a colour: #RRGGBB, or #RRGGBBAA with its opacity, such as #1F6FEB", at: path)
            return nil
        }
        return color
    }

    /// A step: its id, its number from 1 or from the last as -1, or the take's start or end.
    static func readStepReference(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Anchor.StepReference? {
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

    /// An anchor: plain seconds from the take's start, or a step and where to go from it.
    public static func readAnchor(_ value: JSONValue, _ path: JSONPath, _ reader: JSONReader) -> Anchor? {
        if case .number = value {
            return reader.number(value, at: path, .atLeast(0)).map(Anchor.seconds)
        }
        guard var object = reader.object(value, at: path) else { return nil }
        defer { object.finish() }
        let step = object.required("step") { readStepReference($0, $1, reader) }
        let offset = object.optional("offset") { reader.number($0, at: $1) }
        let fraction = object.optional("fraction") { reader.number($0, at: $1, .within(-1...1)) }
        let edge = object.optional("edge") { reader.choice($0, at: $1, as: Anchor.Edge.self) }
        if object.object["offset"] != nil, object.object["fraction"] != nil {
            reader.problem("moves by an \"offset\" or a \"fraction\", not both", at: path)
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

    /// Moves what's recorded under `old` in the merged object to `new`, an earlier place, as when
    /// what was before it is dropped, and records that it's written where `old` was.
    mutating func move(_ old: JSONPath, to new: JSONPath) {
        let source = source(of: old)
        for index in entries.indices where entries[index].merged.components.starts(with: old.components) {
            entries[index].merged = JSONPath(new.components + entries[index].merged.components.dropFirst(old.components.count))
        }
        record(new, from: source)
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
    /// dropped.
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
            let value = mergeValue(entry.value, for: type, at: source.appending(entry.key), into: merged.appending(entry.key), origins: &origins, reader: reader)
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

    /// `object`, a device type's merged edit, without the clips whose `devices` leave `type` out.
    static func clips(of object: JSONObject, for type: DeviceType, origins: inout Origins) -> JSONObject {
        guard let index = object.entries.firstIndex(where: { $0.key == "clips" }), case .array(let clips) = object.entries[index].value else { return object }
        var kept: [JSONValue] = []
        for (old, clip) in clips.enumerated() {
            if case .object(let clip) = clip, case .array(let devices)? = clip["devices"], !devices.contains(.string(type.rawValue)) { continue }
            let path = JSONPath.root.appending("clips")
            if kept.count != old { origins.move(path.appending(old), to: path.appending(kept.count)) }
            kept.append(clip)
        }
        var result = object
        result.entries[index].value = .array(kept)
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
