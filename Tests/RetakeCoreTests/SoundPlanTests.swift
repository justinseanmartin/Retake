import AVFoundation
import Foundation
@testable import RetakeCore
import Testing

/// A video's sound, placed on its clock and laid into the composition.
struct SoundPlanTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "retake-sound-\(UUID().uuidString)", directoryHint: .isDirectory)
    let timelines = ["walk": TakeTimelineTests.timeline()]

    func video(_ json: String) throws -> Edit {
        let reader = JSONReader(file: "edits/video.json")
        return try #require(EditFile.read(#"{"devices": ["ipad"], \#(json)}"#, with: reader)?.videos[.ipad], "\(reader.problems)")
    }

    /// A tone `seconds` long, as a sound file in the project.
    func tone(_ name: String, seconds: Double) throws {
        try FileManager.default.createDirectory(at: root.appending(path: "audio"), withIntermediateDirectories: true)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let file = try AVAudioFile(forWriting: root.appending(path: "audio/\(name).caf"), settings: format.settings)
        let frames = AVAudioFrameCount(seconds * 48000)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<2 {
            for frame in 0..<Int(frames) { buffer.floatChannelData![channel][frame] = 0.2 * sin(Float(frame) * 0.06) }
        }
        try file.write(from: buffer)
    }

    @Test func effectsAndTapsLandWhereTheirMomentsPlayAndATakesSoundFadesWithItsClips() throws {
        let video = try video(#"""
            "music": {"file": "audio/theme.caf", "volume": 0.6, "fadeOut": 1.5},
            "tapSound": {"file": "audio/tap.caf", "volume": 0.5},
            "clips": [
              {"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}, "speed": 2, "takeAudio": true,
               "sounds": [{"file": "audio/pop.caf", "at": {"step": "b"}, "volume": 0.8, "duration": 0.3}]},
              {"take": "walk", "from": {"step": "start"}, "to": {"step": "a"}, "crossfade": 0.25, "takeAudio": true}
            ]
            """#)
        let plan = try CutPlan.make(video, timelines: timelines)
        var overlays = Overlays()
        overlays.touches = [.init(from: .zero, to: nil, start: 1.25, duration: 0)]
        let sound = try SoundPlan.make(video, plan: plan, overlays: overlays, timelines: timelines, root: root)
        #expect(sound.music == .init(file: root.appending(path: "audio/theme.caf"), volume: 0.6, fadeOut: 1.5))
        // The first clip plays 1–6 s of the take at twice its speed, so step b, at 2 s, is at 0.5 s.
        #expect(sound.cues.map(\.at) == [0.5, 1.25])
        #expect(sound.cues.map(\.file.lastPathComponent) == ["pop.caf", "tap.caf"])
        #expect(sound.cues[0].duration == 0.3 && sound.cues[1].volume == 0.5)
        #expect(sound.takeSounds == [.init(clip: 0, fadeIn: 0, fadeOut: 0.25), .init(clip: 1, fadeIn: 0.25, fadeOut: 0)])
    }

    @Test func anAudioCrossfadeFadesBothSidesTheIncomingSoundStartingAheadOfItsPicture() throws {
        let video = try video(#"""
            "clips": [
              {"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}, "takeAudio": true},
              {"take": "walk", "from": {"step": "b"}, "to": {"step": "end"}, "speed": 2, "crossfade": 0.25, "audioCrossfade": 0.75},
              {"take": "walk", "from": {"step": "b"}, "to": {"step": "end"}, "speed": 2, "crossfade": 0.25, "audioCrossfade": 0.75, "takeAudio": true},
              {"take": "walk", "from": {"step": "start"}, "to": {"step": "a"}, "crossfade": 0.25, "audioCrossfade": 0.5, "takeAudio": true}
            ]
            """#)
        let plan = try CutPlan.make(video, timelines: timelines)
        let sound = try SoundPlan.make(video, plan: plan, overlays: Overlays(), timelines: timelines, root: root)
        // 0–5 s; 4.75–6.75 s; 6.5–8.5 s, its sound from 6 s, 1 s into the take at twice its speed, a
        // second before its from; 8.25–9.25 s, from the take's start, so nothing ahead of it.
        #expect(sound.takeSounds == [
            .init(clip: 0, fadeIn: 0, fadeOut: 0.75),
            .init(clip: 2, fadeIn: 0.75, fadeOut: 0.25, lead: 0.5),
            .init(clip: 3, fadeIn: 0.25, fadeOut: 0),
        ], "each side fades over the audioCrossfade, though clip 1 plays no take sound")
        let incoming = plan.placements[2]
        #expect(incoming.start - 0.5 == plan.placements[1].end - 0.75 && incoming.from - 0.5 * incoming.speed == 1, "as the fade before it starts")
    }

    @Test func anEffectOutsideItsClipFails() throws {
        let video = try video(#""clips": [{"take": "walk", "from": {"step": "a"}, "to": {"step": "b"}, "sounds": [{"file": "audio/pop.caf", "at": {"step": "end"}}]}]"#)
        do {
            _ = try SoundPlan.make(video, plan: try CutPlan.make(video, timelines: timelines), overlays: Overlays(), timelines: timelines, root: root)
            Issue.record("placed it")
        } catch {
            #expect((error as? RetakeError)?.message == "clips[0].sounds[0].at: 6 s into the take is outside what the clip plays.")
        }
    }

    @Test func theSoundIsLaidIntoTheCompositionWithEachEffectOnAFreeTrack() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try tone("theme", seconds: 3)
        try tone("pop", seconds: 0.5)
        let red = try await EditCompositionTests().movie("red", red: 255, green: 0, blue: 0)
        let plan = CutPlan(placements: [.init(take: "red", from: 0, to: 2, speed: 1, start: 0, duration: 2, crossfade: 0)])
        let composition = try await EditComposition.make(plan, movies: ["red": red], logs: EditCompositionTests().logs("red"), spec: PreviewSpec(width: 64, height: 96, framesPerSecond: 30), background: .black)
        var sound = SoundPlan()
        sound.music = .init(file: root.appending(path: "audio/theme.caf"), volume: 0.6, fadeOut: 0.5)
        let pop = root.appending(path: "audio/pop.caf")
        sound.cues = [.init(file: pop, at: 0.2, volume: 1, duration: nil), .init(file: pop, at: 0.4, volume: 1, duration: nil), .init(file: pop, at: 1, volume: 1, duration: nil)]
        let mix = try await composition.add(sound, movies: ["red": red])
        let tracks = composition.composition.tracks(withMediaType: .audio)
        // The music, then two tracks for effects: the second pop overlaps the first, the third doesn't.
        #expect(tracks.count == 3 && mix.inputParameters.count == 3)
        #expect(tracks[2].segments.filter { !$0.isEmpty }.map { $0.timeMapping.target.start.seconds } == [0.4])

        sound.music = .init(file: pop, volume: 1, fadeOut: 0)
        await #expect(throws: RetakeError.self, "music shorter than the video") { try await composition.add(sound, movies: [:]) }
    }
}
