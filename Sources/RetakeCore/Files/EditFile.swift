import Foundation

/// An edit, as its file in `edits/` says it: the video cut from the takes, for each device type it
/// names, with each type's overrides already laid over the rest. See README.md, "Edits: the video
/// cut from the takes".
public struct EditFile: Equatable, Sendable {
    public var intent: String?
    public var devices: [DeviceType]
    /// The edit as each device type's video is cut from it.
    public var videos: [DeviceType: Edit]
    /// Where each device type's values were written, for naming a problem found in them later.
    public var origins: [DeviceType: Origins]

    public init(
        intent: String? = nil,
        devices: [DeviceType],
        videos: [DeviceType: Edit],
        origins: [DeviceType: Origins] = [:],
    ) {
        self.intent = intent
        self.devices = devices
        self.videos = videos
        self.origins = origins
    }

    /// Where a value in a device type's video is written in the file.
    public func source(of path: JSONPath, for type: DeviceType) -> JSONPath {
        origins[type]?.source(of: path) ?? path
    }

    /// The keys a device type's overrides can't give, since they say which types there are.
    static let notOverridable = ["devices"]
}

/// One device type's video, as an edit cuts it.
public struct Edit: Equatable, Sendable {
    /// What this device type's video is there to show. Not read by the render.
    public var intent: String?
    public var music: Music?
    public var tapSound: Sound?
    /// The level of the take's own sound, where a clip plays it.
    public var takeAudioVolume: Double
    /// The colour of letterbox bands and of the corners a turn uncovers.
    public var background: Color
    public var turns: Turns
    public var turnBlur: TurnBlur?
    /// The colour touches are drawn in, unless a clip or a touch gives its own.
    public var touchColor: Color
    public var clips: [Clip]

    /// Every scene it plays or takes a still from, in the order it first does.
    public var scenes: [String] {
        clips.flatMap { [$0.take] + $0.stills.map(\.take) }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    public init(
        intent: String? = nil,
        music: Music? = nil,
        tapSound: Sound? = nil,
        takeAudioVolume: Double = 1,
        background: Color = .black,
        turns: Turns = .letterboxed,
        turnBlur: TurnBlur? = nil,
        touchColor: Color = .white,
        clips: [Clip],
    ) {
        self.intent = intent
        self.music = music
        self.tapSound = tapSound
        self.takeAudioVolume = takeAudioVolume
        self.background = background
        self.turns = turns
        self.turnBlur = turnBlur
        self.touchColor = touchColor
        self.clips = clips
    }

    public enum Turns: String, CaseIterable, Sendable {
        case letterboxed, device
    }

    public struct TurnBlur: Equatable, Sendable {
        public var duration: Double
    }

    public struct Music: Equatable, Sendable {
        public var file: String
        public var volume: Double
        public var fadeOut: Double
    }

    /// A sound file and its level: the tap sound, or the sound a clip's effect plays.
    public struct Sound: Equatable, Sendable {
        public var file: String
        public var volume: Double
    }

    public struct Clip: Equatable, Sendable {
        public var id: String?
        public var intent: String?
        /// The scene whose latest successful take the clip is cut from.
        public var take: String
        public var from: Anchor
        public var to: Anchor
        public var speed: Double
        /// Seconds the clip cross-fades in over the one before.
        public var crossfade: Double
        /// Seconds its sound fades in over, when longer than the picture's cross-fade.
        public var audioCrossfade: Double?
        public var touches: Bool
        /// The colour of this clip's touches; the edit's when nil.
        public var touchColor: Color? = nil
        /// Colours for single touches, by the step that made them, over the clip's or the edit's.
        public var touchColors: [TouchColor] = []
        public var takeAudio: Bool
        public var captions: [Caption]
        public var sounds: [Effect]
        public var spotlight: Spotlight?
        public var blurs: [Blur]
        public var stills: [Still]
        /// A colour filling the canvas behind the stills, over the clip's picture; none when nil.
        public var stillsBackground: Color? = nil
        /// When the stills pop out, one after another; they stay to the clip's end when nil.
        public var stillsOut: Anchor? = nil
        /// A colour covering the picture, for a card between clips; none when nil.
        public var card: Card? = nil
        /// The edit's when nil.
        public var turns: Turns?
        public var turnBlur: TurnBlur?
    }

    /// A colour covering the clip's picture, and what's drawn over it but its captions: a card,
    /// fading in and out with the cross-fades either side, or over its own stretch.
    public struct Card: Equatable, Sendable {
        public var color: Color
        /// The clip's `from` when nil.
        public var from: Anchor?
        /// The clip's `to` when nil.
        public var to: Anchor?
    }

    public struct TouchColor: Equatable, Sendable {
        public var step: Anchor.StepReference
        public var color: Color
    }

    public struct Caption: Equatable, Sendable {
        public var text: String
        /// The caption's centre, as a share of the video's height from the top.
        public var y: Double
        public var color: Color
        /// The clip's `from` when nil.
        public var from: Anchor?
        /// The clip's `to` when nil.
        public var to: CaptionEnd?
        public var symbol: Symbol?
    }

    /// Where a caption ends: an anchor in its own clip's take, or in a later clip's, or that later
    /// clip's end.
    public struct CaptionEnd: Equatable, Sendable {
        /// The later clip it runs on into; its own clip when nil.
        public var clip: String?
        /// The moment in that clip's take; the clip's own `to` when nil.
        public var anchor: Anchor?
    }

    public struct Symbol: Equatable, Sendable {
        public var name: String
        public var rotation: Rotation?

        public struct Rotation: Equatable, Sendable {
            /// Clockwise when positive.
            public var degrees: Double
            public var duration: Double
        }
    }

    /// A sound effect, played at normal speed however fast its clip plays.
    public struct Effect: Equatable, Sendable {
        public var file: String
        public var at: Anchor
        public var volume: Double
        /// Seconds it plays for before fading out, for an effect longer than its moment; all of it
        /// when nil.
        public var duration: Double?
    }

    /// Something on screen: an element the step log found, or a rectangle in screen points.
    public enum Region: Equatable, Sendable {
        /// An element, or the `part` of its frame given, in points from its corner or shares of it.
        case element(ElementTarget, part: Rect? = nil)
        /// In screen points, or shares of the screen as the device faced.
        case rect(Rect)
    }

    public struct Rect: Equatable, Sendable {
        public var x, y, width, height: Length

        public init(x: Length, y: Length, width: Length, height: Length) {
            (self.x, self.y, self.width, self.height) = (x, y, width, height)
        }

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.init(x: .points(x), y: .points(y), width: .points(width), height: .points(height))
        }

        /// In points, within `whole`: its shares of it, its points from its corner.
        func within(_ whole: CGRect) -> CGRect {
            CGRect(
                x: whole.minX + x.points(of: whole.width), y: whole.minY + y.points(of: whole.height),
                width: width.points(of: whole.width), height: height.points(of: whole.height),
            )
        }

        var hasShare: Bool { [x, y, width, height].contains(where: \.isShare) }
    }

    public struct Spotlight: Equatable, Sendable {
        public var region: Region
        public var padding: Double
        public var color: Color
        public var from: Anchor?
        public var to: Anchor?
    }

    public struct Blur: Equatable, Sendable {
        public var region: Region
        public var from: Anchor?
        public var to: Anchor?
        public var radius: Double
    }

    /// A frame of another take, popped in over the clip.
    public struct Still: Equatable, Sendable {
        /// The scene whose latest successful take it's from.
        public var take: String
        public var at: Anchor
    }
}

/// A colour, from `#RRGGBB` or `#RRGGBBAA`.
public struct Color: Equatable, Sendable, CustomStringConvertible {
    public var red, green, blue, alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = Color(red: 0, green: 0, blue: 0)
    public static let white = Color(red: 1, green: 1, blue: 1)

    public init?(hex: String) {
        guard hex.hasPrefix("#"), hex.count == 7 || hex.count == 9,
              let value = UInt64(hex.dropFirst(), radix: 16) else { return nil }
        let channels = hex.count == 9 ? value : value << 8 | 0xFF
        red = Double((channels >> 24) & 0xFF) / 255
        green = Double((channels >> 16) & 0xFF) / 255
        blue = Double((channels >> 8) & 0xFF) / 255
        alpha = Double(channels & 0xFF) / 255
    }

    public var description: String {
        let channels = [red, green, blue] + (alpha < 1 ? [alpha] : [])
        return "#" + channels.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }
}

/// A moment in a take: a step and where to go from it, or plain seconds from the take's start. See
/// README.md, "Anchors: times that follow the app".
public enum Anchor: Equatable, Sendable {
    case seconds(Double)
    case step(StepAnchor)

    public struct StepAnchor: Equatable, Sendable {
        public var step: StepReference
        public var offset: Double?
        public var fraction: Double?
        /// The edge the offset or fraction counts from; forward counts from the step's end and back
        /// from its start when nil.
        public var edge: Edge?

        public init(step: StepReference, offset: Double? = nil, fraction: Double? = nil, edge: Edge? = nil) {
            self.step = step
            self.offset = offset
            self.fraction = fraction
            self.edge = edge
        }
    }

    public enum StepReference: Equatable, Sendable {
        /// The take's first frame, lead-in included.
        case start
        /// The take's last frame, tail included.
        case end
        case id(String)
        /// From 1, or from the last when negative (`-1` is the last step).
        case number(Int)
    }

    public enum Edge: String, CaseIterable, Sendable {
        case start, end
    }
}
