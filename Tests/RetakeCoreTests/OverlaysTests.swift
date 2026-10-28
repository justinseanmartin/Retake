import CoreGraphics
import Foundation
@testable import RetakeCore
import Testing

/// What's drawn over the picture, placed in time and on the canvas.
struct OverlaysTests {
    let spec = PreviewSpec.of(.ipad)
    /// Points to pixels: the iPad's 834 points across its 1200-pixel capture, the 3:4 window filling
    /// the 1200×1600 canvas.
    let scale = 1200.0 / 834

    /// The `TakeTimelineTests` take, its screen recorded, step `a` a tap at (100, 200).
    func timeline(screen: CGSize? = CGSize(width: 834, height: 1194)) -> TakeTimeline {
        var log = TakeTimelineTests.timeline().log
        log.screen = screen
        log.steps[0].touch = Point(x: 100, y: 200)
        log.width = 1200
        log.height = 1718
        return TakeTimeline(log)
    }

    func overlays(_ clips: String, screen: CGSize? = CGSize(width: 834, height: 1194)) throws -> Overlays {
        let reader = JSONReader(file: "edits/video.json")
        let video = try #require(EditFile.read(#"{"devices": ["ipad"], "clips": [\#(clips)]}"#, with: reader)?.videos[.ipad], "\(reader.problems)")
        let timelines = ["walk": timeline(screen: screen)]
        let plan = try CutPlan.make(video, timelines: timelines)
        let framing = ClipFraming.framing(spec.size, stored: CGSize(width: 1200, height: 1718), turned: 0, aspect: .init(portrait: .init(width: 3, height: 4)), turns: .letterboxed, screen: screen)
        return try Overlays.make(video, plan: plan, framings: plan.placements.map { [($0.start, framing)] }, timelines: timelines)
    }

    func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01 && abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
    }

    @Test func captionsAreUpFromTheirFromToTheirToOrOnIntoALaterClip() throws {
        let placed = try overlays(#"""
            {"take": "walk", "from": {"step": "a"}, "to": {"step": "b"}, "captions": [
              {"text": "Whole clip", "y": 0.1, "color": "#000000"},
              {"text": "Runs on", "y": 0.9, "color": "#1F6FEB", "from": {"step": "a", "offset": 0.25}, "to": {"clip": "later", "step": "end", "offset": -1}}
            ]},
            {"id": "later", "take": "walk", "from": {"step": "b"}, "to": {"step": "end"}, "crossfade": 0.5}
            """#)
        // The first clip plays 1–2 s of the take as 0–1 s; the later one 2–6 s from 0.5 s.
        #expect(placed.captions.map(\.start) == [0, 0.75])
        #expect(placed.captions.map(\.end) == [1, 3.5])
        #expect(placed.captions[1].y == 0.9 && placed.captions[1].color == Color(hex: "#1F6FEB"))
    }

    @Test func aTouchIsDrawnWhereItLandedAndASpotlightAroundItsElement() throws {
        let placed = try overlays(#"""
            {"take": "walk", "from": {"step": "start"}, "to": {"step": "end"}, "touches": true,
             "spotlight": {"element": {"label": "Share"}, "from": {"step": "b", "offset": 0.1}},
             "blurs": [{"rect": {"x": 0, "y": 834, "width": 834, "height": 100}, "from": {"step": "a"}, "to": {"step": "b"}}]}
            """#)
        #expect(placed.touches.count == 1)
        #expect(abs(placed.touches[0].from.x - 100 * scale) < 0.01 && abs(placed.touches[0].from.y - 200 * scale) < 0.01)
        #expect(placed.touches[0].start == 1 && placed.touches[0].to == nil)
        // The Share button, 44 points square at (10, 20), padded 8 points all round.
        #expect(close(placed.spotlights[0].rect, CGRect(x: 2 * scale, y: 12 * scale, width: 60 * scale, height: 60 * scale)))
        #expect(abs(placed.spotlights[0].start - 3.1) < 1e-9 && placed.spotlights[0].end == 6)
        #expect(close(placed.blurs[0].rect, CGRect(x: 0, y: 834 * scale, width: 1200, height: 100 * scale)))
        #expect(placed.blurs[0].start == 1 && placed.blurs[0].end == 2)
    }

    @Test(arguments: [
        (#"{"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}, "touches": true}"#, "clips[0]: the take of walk doesn't record its screen's size, so its touches can't be drawn; record it again."),
        (#"{"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}, "spotlight": {"rect": {"x": 0, "y": 0, "width": 1, "height": 1}}}"#, "clips[0].spotlight: the take of walk doesn't record its screen's size; record it again."),
    ])
    func whatCantBePlacedWithoutTheScreensSizeSaysSo(_ clip: String, _ message: String) throws {
        do {
            _ = try overlays(clip, screen: nil)
            Issue.record("placed it")
        } catch {
            let error = error as? RetakeError
            #expect(error?.status == .failed && error?.message == message)
        }
    }

    @Test func aSpotlightOnAnElementNotOnScreenSaysWhy() throws {
        do {
            _ = try overlays(#"{"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}, "spotlight": {"element": {"label": "Send"}, "from": {"step": "b", "offset": 0.1}}}"#)
            Issue.record("placed it")
        } catch {
            #expect((error as? RetakeError)?.message == #"clips[0].spotlight.element: "Send" isn't on screen after step 2, at 3 s."#)
        }
    }

    @Test func eachIsALayerOverThePicture() {
        var overlays = Overlays()
        overlays.captions = [.init(text: "Hi", color: .black, y: 0.25, symbol: Edit.Symbol(name: "rotate.right", rotation: .init(degrees: 90, duration: 0.4)), start: 0, end: 1)]
        overlays.touches = [.init(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 50), start: 0.5, duration: 0.4)]
        overlays.spotlights = [.init(rect: CGRect(x: 10, y: 10, width: 20, height: 20), color: .white, start: 0, end: 1)]
        let layers = OverlayLayers(overlays, spec: spec)
        // The picture, a touch, a spotlight's dimming and ring, and a caption, in that order.
        #expect(layers.parent.sublayers?.count == 5)
        let caption = layers.parent.sublayers!.last!
        #expect(caption.position == CGPoint(x: 600, y: 400) && caption.sublayers?.count == 2, "its text and its symbol")
    }
}
