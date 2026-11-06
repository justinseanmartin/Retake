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
    func timeline(screen: CGSize = CGSize(width: 834, height: 1194)) -> TakeTimeline {
        var log = TakeTimelineTests.timeline().log
        log.screen = screen
        log.steps[0].touch = Point(x: 100, y: 200)
        log.width = 1200
        log.height = 1718
        return TakeTimeline(log)
    }

    func overlays(_ clips: String, edit: String = "", screen: CGSize = CGSize(width: 834, height: 1194)) throws -> Overlays {
        let reader = JSONReader(file: "edits/video.json")
        let video = try #require(EditFile.read(#"{"devices": ["ipad"], \#(edit)"clips": [\#(clips)]}"#, with: reader)?.videos[.ipad], "\(reader.problems)")
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
              {"text": "Runs on", "y": 0.9, "color": "#1F6FEB", "from": {"step": "a", "offset": 0.25, "edge": "end"}, "to": {"clip": "later", "step": "end", "offset": -1}}
            ]},
            {"id": "later", "take": "walk", "from": {"step": "b"}, "to": {"step": "end"}, "crossfade": 0.5}
            """#)
        // The first clip plays 1–2 s of the take as 0–1 s; the later one 2–6 s from 0.5 s, fading in
        // over it until 1 s. The whole clip's caption goes as the later one starts to fade in.
        #expect(placed.captions.map(\.start) == [0, 0.75])
        #expect(placed.captions.map(\.end) == [0.5, 3.5])
        #expect(placed.captions[1].y == 0.9 && placed.captions[1].color == Color(hex: "#1F6FEB"))
    }

    @Test func aCaptionThatDoesntSayWhenKeepsClearOfTheCrossfades() throws {
        let placed = try overlays(#"""
            {"take": "walk", "from": {"step": "a"}, "to": {"step": "b"}},
            {"id": "middle", "take": "walk", "from": {"step": "b"}, "to": {"step": "end"}, "crossfade": 0.5, "captions": [
              {"text": "This clip", "y": 0.8, "color": "#000000"},
              {"text": "Runs on", "y": 0.8, "color": "#000000", "to": {"clip": "last"}}
            ]},
            {"id": "last", "take": "walk", "from": {"step": "a"}, "to": {"step": "b"}, "crossfade": 0.25},
            {"take": "walk", "from": {"step": "a"}, "to": {"step": "b"}, "crossfade": 0.25}
            """#)
        // The middle clip fades in over 0.5–1 s and plays to 4.5 s; the last fades in from 4.25 s,
        // plays to 5.25 s, and the one after it fades in from 5 s.
        #expect(placed.captions.map(\.start) == [1, 1])
        #expect(placed.captions.map(\.end) == [4.25, 5])
    }

    @Test func aTouchIsDrawnWhereItLandedAndASpotlightAroundItsElement() throws {
        let placed = try overlays(#"""
            {"take": "walk", "from": {"step": "start"}, "to": {"step": "end"}, "touches": true,
             "spotlight": {"element": {"label": "Share"}, "from": {"step": "b", "offset": 0.1, "edge": "end"}},
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

    @Test func aRegionCanBePartOfAnElementOrSharesOfTheScreen() throws {
        let placed = try overlays(#"""
            {"take": "walk", "from": {"step": "b"}, "to": {"step": "end"},
             "spotlight": {"rect": {"x": "10%", "y": "50%", "width": "50%", "height": 100}, "padding": 0},
             "blurs": [{"element": {"label": "Share"}, "part": {"x": "50%", "width": "50%", "y": 4, "height": 10}, "from": {"step": "b", "offset": 0.1, "edge": "end"}}]}
            """#)
        // A tenth of the 834-point screen across, half its 1194 down; and the right half of the
        // Share button, 44 points square at (10, 20), from 4 points down its side for 10.
        #expect(close(placed.spotlights[0].rect, CGRect(x: 83.4 * scale, y: 597 * scale, width: 417 * scale, height: 100 * scale)))
        #expect(close(placed.blurs[0].rect, CGRect(x: 32 * scale, y: 24 * scale, width: 22 * scale, height: 10 * scale)))
    }

    @Test func touchesAreDrawnUnlessAClipTurnsThemOff() throws {
        let drawn = try overlays(#"{"take": "walk", "from": {"step": "start"}, "to": {"step": "end"}}"#)
        let hidden = try overlays(#"{"take": "walk", "from": {"step": "start"}, "to": {"step": "end"}, "touches": false}"#)
        #expect(drawn.touches.count == 1)
        #expect(hidden.touches.isEmpty)
    }

    @Test func aTouchsColourIsItsStepsOverItsClipsOverTheEdits() throws {
        let walk = #""take": "walk", "from": {"step": "start"}, "to": {"step": "end"}"#
        let red = Color(hex: "#FF0000")!, green = Color(hex: "#00FF00")!, blue = Color(hex: "#0000FF80")!
        #expect(try overlays("{\(walk)}").touches.map(\.color) == [.white])
        #expect(try overlays("{\(walk)}", edit: ##""touchColor": "#FF0000", "##).touches.map(\.color) == [red])
        let clipColour = try overlays(##"{\##(walk), "touchColor": "#00FF00"}"##, edit: ##""touchColor": "#FF0000", "##)
        #expect(clipColour.touches.map(\.color) == [green])
        let stepColour = try overlays(##"{\##(walk), "touchColor": "#00FF00", "touchColors": [{"step": "a", "color": "#0000FF80"}]}"##)
        #expect(stepColour.touches.map(\.color) == [blue])
    }

    @Test func aTouchColourForAStepThatDoesntTouchSaysSo() {
        let error = #expect(throws: RetakeError.self) {
            try overlays(##"{"take": "walk", "from": {"step": "start"}, "to": {"step": "end"}, "touchColors": [{"step": "b", "color": "#000000"}]}"##)
        }
        #expect(error?.message == "clips[0].touchColors[0].step: it doesn't touch the screen within the clip.")
    }

    @Test func aSpotlightOnAnElementNotOnScreenSaysWhy() throws {
        do {
            _ = try overlays(#"{"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}, "spotlight": {"element": {"label": "Send"}, "from": {"step": "b", "offset": 0.1, "edge": "end"}}}"#)
            Issue.record("placed it")
        } catch {
            #expect((error as? RetakeError)?.message == #"clips[0].spotlight.element: "Send" isn't on screen after step 2, at 3 s."#)
        }
    }

    @Test func aStillsBackgroundHasFadedInAsTheFirstStillPopsInAndStaysToTheClipsEnd() throws {
        let placed = try overlays(#"""
            {"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}, "stillsBackground": "#F4F1EA",
             "stills": [{"take": "walk", "at": 1}, {"take": "walk", "at": 2}]}
            """#)
        // The clip plays 1–6 s of the take as 0–5 s.
        let background = try #require(placed.stillsBackgrounds.first)
        #expect(placed.stillsBackgrounds.count == 1 && background.color == Color(hex: "#F4F1EA"))
        #expect(abs(background.start + OverlayLayers.stillsBackgroundFade - placed.stills[0].start) < 1e-9 && background.end == 5)
        let layers = OverlayLayers(placed, spec: spec, stills: [Self.pixel, Self.pixel])
        #expect(layers.parent.sublayers?[1].backgroundColor != nil, "over the picture, under the stills")
    }

    @Test func aCardFadesWithTheCrossFadesEitherSideOrQuicklyOverAStretchOfItsOwn() throws {
        let placed = try overlays(#"""
            {"take": "walk", "from": {"step": "a"}, "to": {"step": "b"}},
            {"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}, "crossfade": 0.5, "card": {"color": "#FFD43B"},
             "captions": [{"text": "On the card", "y": 0.5, "color": "#1B2A4E"}]},
            {"take": "walk", "from": {"step": "b"}, "to": {"step": "end"}, "crossfade": 0.4, "card": {"color": "#000000", "from": {"step": "b", "offset": 1, "edge": "end"}}}
            """#)
        // 1–2 s of the take as 0–1 s; 1–6 s as 0.5–5.5 s; 2–6 s as 5.1–9.1 s, b ending at 3 s.
        let whole = placed.cards[0], own = placed.cards[1]
        #expect(whole.start == 0.5 && whole.end == 5.5 && whole.fadeIn == 0.5 && abs(whole.fadeOut - 0.4) < 1e-9)
        #expect(abs(own.start - 7.1) < 1e-9 && abs(own.end - 9.1) < 1e-9 && own.fadeIn == Overlays.cardFade && own.fadeOut == 0, "to the video's end: \(own)")
        let layers = OverlayLayers(placed, spec: spec)
        #expect(layers.parent.sublayers?.last?.cornerRadius ?? 0 > 0, "the caption, a pill, over the cards")
    }

    @Test func stillsPopOutOneAfterAnotherInTheOrderTheyPoppedIn() throws {
        let placed = try overlays(#"""
            {"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}, "stillsOut": {"step": "b", "offset": 0.5, "edge": "end"},
             "stills": [{"take": "walk", "at": 1}, {"take": "walk", "at": 2}, {"take": "walk", "at": 3}]}
            """#)
        // The clip plays 1–6 s of the take as 0–5 s; b ends at 3 s in the take, 2 s in the video.
        let ends = placed.stills.map { ($0.end * 1000).rounded() / 1000 }
        #expect(ends == [2.5, 2.72, 2.94] && placed.stills.allSatisfy(\.popsOut))
        #expect(throws: RetakeError.self, "before they've popped in") {
            try overlays(#"{"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}, "stillsOut": {"step": "a"}, "stills": [{"take": "walk", "at": 1}]}"#)
        }
    }

    @Test func aBlursRadiusIsInScreenPointsScaledToTheCanvasAsItsRectangleIs() throws {
        let reader = JSONReader(file: "edits/video.json")
        let edit = try #require(EditFile.read(#"""
            {"devices": ["iphone", "ipad"], "clips": [{"take": "walk", "from": {"step": "a"}, "to": {"step": "end"},
              "blurs": [{"rect": {"x": 10, "y": 20, "width": 100, "height": 50}}, {"rect": {"x": 0, "y": 0, "width": 10, "height": 10}, "radius": 4}]}]}
            """#, with: reader), "\(reader.problems)")
        let timelines = ["walk": timeline()]
        func blurs(_ type: DeviceType, stored: CGSize, screen: CGSize) throws -> [Overlays.Blur] {
            let video = try #require(edit.videos[type])
            let plan = try CutPlan.make(video, timelines: timelines)
            let framing = ClipFraming.framing(PreviewSpec.of(type).size, stored: stored, turned: 0, aspect: nil, turns: .letterboxed, screen: screen)
            return try Overlays.make(video, plan: plan, framings: plan.placements.map { [($0.start, framing)] }, timelines: timelines).blurs
        }
        // A 6.1-inch iPhone's 393 points across its 1179-pixel capture, filling the 886-pixel-wide
        // canvas; the iPad's 834 across 1200, filling 1200.
        let iphone = try blurs(.iphone, stored: CGSize(width: 1179, height: 2556), screen: CGSize(width: 393, height: 852))
        let ipad = try blurs(.ipad, stored: CGSize(width: 1200, height: 1718), screen: CGSize(width: 834, height: 1194))
        let iphoneScale = 886.0 / 393
        #expect(abs(iphone[0].sigma - Edit.Blur.defaultRadius * iphoneScale) < 1e-9 && abs(iphone[0].rect.width - 100 * iphoneScale) < 1e-9)
        #expect(abs(iphone[0].sigma - 20) < 0.5, "the default looks as 20 canvas pixels did")
        #expect(abs(ipad[0].sigma - Edit.Blur.defaultRadius * scale) < 1e-9 && abs(ipad[1].sigma - 4 * scale) < 1e-9)
    }

    @Test func stillsInMovesWhenTheStillsPopInAndTheirBackgroundWithThem() throws {
        let placed = try overlays(#"""
            {"take": "walk", "from": {"step": "a"}, "to": {"step": "end"}, "stillsIn": {"step": "b", "offset": 0.5, "edge": "end"},
             "stillsBackground": "#F4F1EA", "stills": [{"take": "walk", "at": 1}, {"take": "walk", "at": 2}, {"take": "walk", "at": 3}]}
            """#)
        // The clip plays 1–6 s of the take as 0–5 s; 0.5 s after b ends is 3.5 s in the take.
        let starts = placed.stills.map { ($0.start * 1000).rounded() / 1000 }
        #expect(starts == [2.5, 2.72, 2.94] && placed.stills.allSatisfy { $0.end == 5 })
        #expect(abs(placed.stillsBackgrounds[0].start - (2.5 - OverlayLayers.stillsBackgroundFade)) < 1e-9)
    }

    @Test func stillsFitTheCanvasWithTheSameSpaceAboveBetweenAndBelow() {
        let canvas = CGSize(width: 1200, height: 1600)
        let grid = OverlayLayers.stillsGrid(count: 4, aspect: 4.0 / 3, canvas: canvas)
        let above = grid[0].minY, between = grid[2].minY - grid[0].maxY, below = canvas.height - grid[2].maxY
        #expect(abs(above - between) < 1e-9 && abs(between - below) < 1e-9 && above >= OverlayLayers.stillsSpacing)
        let left = grid[0].minX, across = grid[1].minX - grid[0].maxX, right = canvas.width - grid[1].maxX
        #expect(abs(left - across) < 1e-9 && abs(across - right) < 1e-9)
        let short = OverlayLayers.stillsGrid(count: 3, aspect: 4.0 / 3, canvas: canvas)
        #expect(abs(short[2].midX - canvas.width / 2) < 1e-9, "a short last row is centred")
        let wide = OverlayLayers.stillsGrid(count: 2, aspect: 2, canvas: CGSize(width: 1600, height: 900))
        #expect(wide.allSatisfy { $0.minY >= OverlayLayers.stillsSpacing && $0.maxY <= 900 - OverlayLayers.stillsSpacing }, "fits a short canvas by its height")
    }

    @Test func aCaptionTooWideForTheCanvasIsSetSmallerToFit() {
        let short = OverlayLayers.caption(.init(text: "Hi", color: .black, y: 0.5, symbol: nil, start: 0, end: 1), canvas: spec.size)
        let long = OverlayLayers.caption(
            .init(text: "https://github.com/justinseanmartin/Retake", color: .black, y: 0.5, symbol: Edit.Symbol(name: "link"), start: 0, end: 1), canvas: spec.size,
        )
        #expect(long.bounds.width <= spec.size.width - OverlayLayers.captionMargin * 2 + 1 && long.bounds.width > spec.size.width * 0.8)
        #expect(long.bounds.height < short.bounds.height, "its text smaller")
    }

    /// A one-pixel image, standing in for a still's frame.
    static let pixel: CGImage = {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()

    @Test func eachIsALayerOverThePicture() {
        var overlays = Overlays()
        overlays.captions = [.init(text: "Hi", color: .black, y: 0.25, symbol: Edit.Symbol(name: "rotate.right", rotation: .init(degrees: 90, duration: 0.4)), start: 0, end: 1)]
        overlays.touches = [.init(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 50), start: 0.5, duration: 0.4)]
        overlays.spotlights = [.init(rect: CGRect(x: 10, y: 10, width: 20, height: 20), color: .white, start: 0, end: 1)]
        let layers = OverlayLayers(overlays, spec: spec)
        // The picture; the drag's tail, a circle every thirtieth of a second it moves bar the first,
        // and its own circle; a spotlight's dimming and ring; and a caption, in that order.
        let expected = 1 + 11 + 1 + 2 + 1
        #expect(layers.parent.sublayers?.count == expected)
        let caption = layers.parent.sublayers!.last!
        #expect(caption.position == CGPoint(x: 600, y: 400) && caption.sublayers?.count == 2, "its text and its symbol")
    }
}
