import AVFoundation
import Foundation

/// A video's sound, placed on its clock: the music under all of it, each clip's effects and its
/// take's own sound, and the tap sound with each touch drawn. Worked out apart from AVFoundation,
/// so it can be tested. See README.md, "Sound".
public struct SoundPlan: Equatable, Sendable {
    /// A sound file played once, from `at` in the video, at its normal speed however fast the clip
    /// plays, cut short over `duration`, fading out, when given.
    public struct Cue: Equatable, Sendable {
        public var file: URL
        public var at: Double
        public var volume: Double
        public var duration: Double?
    }

    /// A clip's take's own sound, played with the clip at its speed, fading in and out over these.
    /// It starts `lead` seconds before the clip's picture, playing the take from as long before the
    /// clip's `from` at its speed, so it fades in over the same stretch as the clip before's fades out.
    public struct TakeSound: Equatable, Sendable {
        public var clip: Int
        public var fadeIn: Double
        public var fadeOut: Double
        public var lead: Double = 0
    }

    public struct Music: Equatable, Sendable {
        public var file: URL
        public var volume: Double
        public var fadeOut: Double
    }

    public var music: Music?
    public var cues: [Cue] = []
    public var takeSounds: [TakeSound] = []
    public var takeAudioVolume = 1.0

    /// The sound of `video`, its clips placed as `plan` says, its effects' anchors resolved in its
    /// clips' takes in `timelines`, the tap sound with each of `overlays`' touches, and its files
    /// relative to `root`, the project's folder. Fails (1) for an effect whose anchor doesn't
    /// resolve, or falls outside what its clip plays.
    public static func make(
        _ video: Edit, plan: CutPlan, overlays: Overlays, timelines: [String: TakeTimeline], root: URL,
    ) throws(RetakeError) -> SoundPlan {
        func file(_ path: String) -> URL { URL(filePath: path, relativeTo: root).standardizedFileURL }
        var sound = SoundPlan(takeAudioVolume: video.takeAudioVolume)
        // A clip's sound cross-fades over its audioCrossfade on both sides, the picture over its
        // crossfade: the clip before's sound fades out over the audioCrossfade before its end, and
        // this clip's starts as that fade does, ahead of its picture by the difference, fading in to
        // the clip before's end. Ahead by no more than the take has before the clip's `from`, the clip
        // before plays, or, when it plays its take's sound on the same track, the clip before that
        // leaves free.
        func lead(_ index: Int) -> Double {
            guard index > 0, let audio = video.clips[index].audioCrossfade else { return 0 }
            let placement = plan.placements[index], previous = plan.placements[index - 1]
            var lead = min(audio - placement.crossfade, placement.from / placement.speed, previous.duration - placement.crossfade)
            if index > 1, video.clips[index - 2].takeAudio { lead = min(lead, placement.start - plan.placements[index - 2].end) }
            return max(lead, 0)
        }
        sound.music = video.music.map { Music(file: file($0.file), volume: $0.volume, fadeOut: $0.fadeOut) }
        for (index, clip) in video.clips.enumerated() {
            let placement = plan.placements[index]
            for (soundIndex, effect) in clip.sounds.enumerated() {
                let name = "clips[\(index)].sounds[\(soundIndex)].at"
                let at: Double
                do throws(TakeTimeline.Unresolved) {
                    guard let timeline = timelines[clip.take] else { throw TakeTimeline.Unresolved("there's no take of \(clip.take)") }
                    at = try timeline.time(of: effect.at)
                } catch {
                    throw RetakeError(.failed, "\(name): \(error.message).")
                }
                guard at >= placement.from, at <= placement.to else {
                    throw RetakeError(.failed, "\(name): \(TakeTimeline.seconds(at)) into the take is outside what the clip plays.")
                }
                sound.cues.append(Cue(file: file(effect.file), at: placement.videoTime(at), volume: effect.volume, duration: effect.duration))
            }
            if clip.takeAudio {
                let next = plan.placements.indices.contains(index + 1) ? index + 1 : nil
                sound.takeSounds.append(TakeSound(
                    clip: index, fadeIn: placement.crossfade + lead(index), fadeOut: next.map { plan.placements[$0].crossfade + lead($0) } ?? 0, lead: lead(index),
                ))
            }
        }
        if let tap = video.tapSound {
            sound.cues += overlays.touches.map { Cue(file: file(tap.file), at: $0.start, volume: tap.volume, duration: nil) }
        }
        sound.cues.sort { $0.at < $1.at }
        return sound
    }
}

extension EditComposition {
    /// Adds `sound` to the composition, its takes' sound from `movies`, returning how to mix it.
    /// Fails (1) for a sound file that can't be read, or music shorter than the video.
    public func add(_ sound: SoundPlan, movies: [String: URL]) async throws(RetakeError) -> AVMutableAudioMix {
        let total = Self.time(plan.duration)
        var parameters: [AVMutableAudioMixInputParameters] = []
        // A track doesn't keep its asset alive, and inserting from one whose asset is gone fails.
        var assets: [AVURLAsset] = []
        func audio(of url: URL) async throws(RetakeError) -> (AVAssetTrack, CMTime) {
            let asset = AVURLAsset(url: url)
            assets.append(asset)
            do {
                guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                    throw RetakeError(.failed, "\(url.lastPathComponent) has no sound.")
                }
                // The track's own range: an MP3's duration can run past its last packet.
                return (track, try await track.load(.timeRange).duration)
            } catch let error as RetakeError {
                throw error
            } catch {
                throw RetakeError(.failed, "Couldn't read \(url.path): \(error.localizedDescription)")
            }
        }
        func track() throws(RetakeError) -> AVMutableCompositionTrack {
            guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw RetakeError(.failed, "Couldn't add a sound track to the composition.")
            }
            return track
        }

        do {
            if let music = sound.music {
                let (source, length) = try await audio(of: music.file)
                guard length >= total else {
                    throw RetakeError(.failed, "The music, \(music.file.lastPathComponent), is \(TakeTimeline.seconds(length.seconds)), shorter than the video's \(TakeTimeline.seconds(plan.duration)).")
                }
                let musicTrack = try track()
                try musicTrack.insertTimeRange(CMTimeRange(start: .zero, duration: total), of: source, at: .zero)
                let mix = AVMutableAudioMixInputParameters(track: musicTrack)
                mix.setVolume(Float(music.volume), at: .zero)
                let fade = min(music.fadeOut, plan.duration)
                mix.setVolumeRamp(fromStartVolume: Float(music.volume), toEndVolume: 0, timeRange: CMTimeRange(start: Self.time(plan.duration - fade), end: total))
                parameters.append(mix)
            }

            // Takes' sound alternates between two tracks, as their pictures do, to fade across.
            if !sound.takeSounds.isEmpty {
                let takeTracks = [try track(), try track()]
                let mixes = takeTracks.map { AVMutableAudioMixInputParameters(track: $0) }
                for take in sound.takeSounds {
                    let placement = plan.placements[take.clip]
                    guard let movie = movies[placement.take] else { continue }
                    let source = try await audio(of: movie).0
                    let lane = take.clip % 2
                    let range = CMTimeRange(start: Self.time(placement.from - take.lead * placement.speed), end: Self.time(placement.to))
                    let at = Self.time(placement.start - take.lead)
                    try takeTracks[lane].insertTimeRange(range, of: source, at: at)
                    takeTracks[lane].scaleTimeRange(CMTimeRange(start: at, duration: range.duration), toDuration: Self.time(placement.duration + take.lead))
                    let volume = Float(sound.takeAudioVolume)
                    let mix = mixes[lane]
                    mix.setVolume(take.fadeIn > 0 ? 0 : volume, at: at)
                    if take.fadeIn > 0 {
                        mix.setVolumeRamp(fromStartVolume: 0, toEndVolume: volume, timeRange: CMTimeRange(start: at, duration: Self.time(take.fadeIn)))
                    }
                    if take.fadeOut > 0 {
                        let fade = min(take.fadeOut, placement.duration)
                        mix.setVolumeRamp(fromStartVolume: volume, toEndVolume: 0, timeRange: CMTimeRange(start: Self.time(placement.end - fade), duration: Self.time(fade)))
                    }
                }
                for (lane, takeTrack) in takeTracks.enumerated() {
                    // An empty track fails the export.
                    if takeTrack.segments.isEmpty { composition.removeTrack(takeTrack) } else { parameters.append(mixes[lane]) }
                }
            }

            // Each effect on the first track free when it starts, adding tracks as they overlap.
            var lanes: [(track: AVMutableCompositionTrack, mix: AVMutableAudioMixInputParameters, free: CMTime)] = []
            var sources: [URL: (AVAssetTrack, CMTime)] = [:]
            for cue in sound.cues {
                if sources[cue.file] == nil { sources[cue.file] = try await audio(of: cue.file) }
                let (source, length) = sources[cue.file]!
                let start = Self.time(cue.at)
                guard start < total else { continue }
                let duration = min(length, total - start, cue.duration.map(Self.time) ?? length)
                // A track's volume changes are keyed by time, so a sound starting the moment another
                // ends goes on another track.
                let lane = try lanes.firstIndex { $0.free < start } ?? {
                    let effects = try track()
                    lanes.append((effects, AVMutableAudioMixInputParameters(track: effects), .zero))
                    return lanes.count - 1
                }()
                try lanes[lane].track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: start)
                let volume = Float(cue.volume)
                lanes[lane].mix.setVolume(volume, at: start)
                if cue.duration != nil {
                    let fade = min(Self.time(0.2), duration)
                    lanes[lane].mix.setVolumeRamp(fromStartVolume: volume, toEndVolume: 0, timeRange: CMTimeRange(start: start + duration - fade, duration: fade))
                }
                lanes[lane].free = start + duration
            }
            parameters += lanes.map(\.mix)
        } catch let error as RetakeError {
            throw error
        } catch {
            throw RetakeError(.failed, "Couldn't lay the sound out: \(error.localizedDescription)")
        }
        withExtendedLifetime(assets) {}
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        return mix
    }
}
