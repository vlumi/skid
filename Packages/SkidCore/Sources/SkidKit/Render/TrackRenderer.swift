import SkidCore
import SwiftUI

/// Everything one frame of the world needs, as plain values (the Canvas
/// renderer closure is not MainActor, so it gets copies, not the session).
struct WorldScene {
    var race: Race
    var marks: MarkStore
    var gateSpans: [(a: Vec2, b: Vec2)?]
    var colors: [Color]
    /// Where the map is placed on screen (the allocator's result). The
    /// bands + pause key off the same rect, so the map is drawn exactly
    /// where the layout expects it.
    var mapRect: CGRect
    /// PB-ghost cars to draw translucently (time trial), if any.
    var ghosts: [CarState] = []
    /// Draw the sim's own view of the world on top (see `DebugOverlay`).
    var debug = false
}

extension Track {
    /// The transform that puts layout-space drawing where the compiled geometry
    /// actually is. The race context is already scaled to world units, so this is
    /// a pure translation by `layoutOffset`.
    var layoutTransform: EditorRenderer.Transform {
        EditorRenderer.Transform(
            scale: 1, offset: CGSize(width: layoutOffset.x, height: layoutOffset.y))
    }
}

/// Draws the whole world procedurally into a `Canvas` context — grass,
/// kerbed asphalt ribbon, start line, marks, cars. No image assets anywhere.
enum TrackRenderer {
    /// Where the track sits on screen — the one primitive the renderer, the
    /// pause button, and the control-band layout all key off.
    ///
    /// Allocation rule: **controls get a guaranteed minimum first, the map
    /// fills what's left, and any space the map's aspect can't use goes back
    /// to the controls** (so bands are never below `minBand`, the map is as
    /// big as it can be in the leftover, and there's never dead grass between
    /// map and bands). Works off the **safe-area** usable rect, so the notch
    /// and home indicator never eat into the reserved minimum. The grass is
    /// still drawn full-bleed; only this positioning respects the insets.
    static func fittedMapRect(
        trackSize: Vec2, in screen: CGSize, safeInsets: EdgeInsets = EdgeInsets(),
        minBand: CGFloat = 150
    ) -> CGRect {
        // Usable region: the screen minus the safe-area insets.
        let usable = CGRect(
            x: safeInsets.leading, y: safeInsets.top,
            width: screen.width - safeInsets.leading - safeInsets.trailing,
            height: screen.height - safeInsets.top - safeInsets.bottom)
        // Tracks are wide, so on portrait the bands are top/bottom and the
        // map is height-constrained by the leftover between them; on a wide
        // (landscape) usable area the map may instead be width-constrained.
        // Reserve minBand on the two sides the bands occupy, fit the map in
        // the remaining box, then center it — the surplus falls to the bands.
        let portrait = usable.height >= usable.width
        let box =
            portrait
            ? CGSize(width: usable.width, height: max(1, usable.height - 2 * minBand))
            : CGSize(width: max(1, usable.width - 2 * minBand), height: usable.height)
        let scale = min(box.width / trackSize.x, box.height / trackSize.y)
        let fitted = CGSize(width: trackSize.x * scale, height: trackSize.y * scale)
        return CGRect(
            x: usable.minX + (usable.width - fitted.width) / 2,
            y: usable.minY + (usable.height - fitted.height) / 2,
            width: fitted.width, height: fitted.height)
    }

    // The palette. Deliberately close to the classic top-down look.
    private static let grass = Color(red: 0.28, green: 0.55, blue: 0.23)
    private static let asphalt = Color(white: 0.62)
    private static let kerbRed = Color(red: 0.82, green: 0.16, blue: 0.14)
    private static let kerbWhite = Color(white: 0.95)
    static let rubber = Color(white: 0.15)
    private static let scuff = Color(red: 0.32, green: 0.26, blue: 0.16)

    /// The car colors players pick from. Deliberately loud, classic-arcade.
    static let carPalette: [Color] = [
        .red, .yellow, .cyan, .purple,
        Color(red: 0.3, green: 0.85, blue: 0.3), .orange, .pink, .white,
    ]

    static func draw(scene: WorldScene, into context: inout GraphicsContext, size: CGSize) {
        let race = scene.race
        let marks = scene.marks
        let gateSpans = scene.gateSpans
        let colors = scene.colors
        let track = race.track
        let mapRect = scene.mapRect
        let scale = mapRect.width / track.size.x
        // Grass fills the whole surface (full-bleed, under the safe areas);
        // the map is drawn at the allocated rect the bands leave clear.
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(grass))
        context.translateBy(x: mapRect.minX, y: mapRect.minY)
        context.scaleBy(x: scale, y: scale)

        func color(_ index: Int) -> Color {
            index < colors.count ? colors[index] : carPalette[index % carPalette.count]
        }

        // **The track is drawn by the EDITOR's renderer**, off the same placed
        // pieces the editor draws, so what you build is exactly what you drive.
        // Two separate renderers drifted apart in kerbs, rails and ramp
        // markings, and every fix had to be made twice. The context is already
        // in world space here, so the shared drawing takes an identity
        // transform.
        //
        // Everything below is COLLECTED, not painted: each drawable declares
        // the storey it occupies and what kind of thing it is, and
        // `RenderOrder` paints them sorted. See RenderOrder.swift for why —
        // briefly, "the bridge covers the car under it" and "the car sits on
        // its own road" are then the same comparison instead of two hand-tuned
        // height passes that disagreed at the edges.
        var order = RenderOrder.Builder()

        let gateChrome = chrome(race: race, spans: gateSpans, colorAt: color)

        // Road, one layer per storey the track actually uses. A piece belongs
        // to the storey of its highest end, so a ramp paints whole, with the
        // level it climbs to.
        let storeys = trackStoreys(track)
        for storey in storeys {
            let band = storeyBand(storey)
            order.add(storey: storey, kind: .road) { context in
                if let layout = track.layout {
                    // The race context scales world → screen AFTER the
                    // transform; the transform must know, so true-screen-point
                    // quantities (the seam overlap) hold on screen.
                    var t = track.layoutTransform
                    t.contextScale = scale
                    EditorRenderer.drawTrack(
                        walk: layout.walk(), width: track.width, gateSeams: [],
                        decals: layout.decals, transform: t, heightRange: band,
                        into: &context)
                } else {
                    // No layout (ad-hoc tracks built directly in tests): fall
                    // back to the centerline stroke, which needs no piece model.
                    drawRibbon(track: track, elevated: storey > 0, into: &context)
                }
            }
            order.add(storey: storey, kind: .gate) { context in
                drawGates(gateChrome, elevated: storey > 0, into: &context)
            }
            order.add(storey: storey, kind: .mark) { context in
                drawMarks(marks, elevated: storey > 0, into: &context)
            }
        }
        // Surface patches are ground paint.
        order.add(storey: 0, kind: .ground) { context in
            drawPatches(track: track, into: &context)
        }

        addCars(scene: scene, gateChrome: gateChrome, colorAt: color, to: &order)
        order.paint(into: &context)

        // Last, so it sits over everything it's describing.
        if scene.debug {
            DebugOverlay.draw(scene: scene, into: &context)
        }
    }

    /// Gate chrome for this frame: the spans, plus which players are waiting on
    /// which gate, in their car colors.
    private static func chrome(
        race: Race, spans: [(a: Vec2, b: Vec2)?], colorAt: (Int) -> Color
    ) -> GateChrome {
        var nextByGate: [Int: [Color]] = [:]
        for (index, car) in race.cars.enumerated() where car.progress.finishedAt == nil {
            nextByGate[car.progress.nextGate, default: []].append(colorAt(index))
        }
        return GateChrome(
            spans: spans,
            nextByGate: nextByGate,
            worldCenter: Vec2(race.track.size.x / 2, race.track.size.y / 2),
            heights: race.track.gates.map(\.height)
        )
    }

    /// The storeys a track's road occupies, ascending. Always includes the
    /// ground, so a flat track still gets its single road layer.
    static func trackStoreys(_ track: Track) -> [Int] {
        var found: Set<Int> = [0]
        for height in track.heights { found.insert(Track.level(of: height)) }
        return found.sorted()
    }

    /// The height range whose pieces belong to `storey` — a piece counts as
    /// belonging to the storey of its HIGHEST end, so a climb paints whole
    /// rather than splitting across levels at its midpoint.
    static func storeyBand(_ storey: Int) -> ClosedRange<Double> {
        let top = Double(storey) * Track.levelHeight
        let below = top - Track.levelHeight
        return (below + Track.levelHeight / 4)...(top + Track.levelHeight / 4)
    }

    /// The inverse of `storeyBand`: the storey whose band a piece top falls in.
    /// Cars on asphalt stack by THIS of the piece under them, so a car and its
    /// own ribbon can never land in different storeys.
    static func storey(ofTop top: Double) -> Int {
        Int((top / Track.levelHeight - 0.25).rounded(.up))
    }

    /// The ribbon at one height band, as contiguous runs of centerline segments
    /// (a flat track is one full loop at height 0).
    ///
    /// Only a FALLBACK for tracks with no piece layout (ad-hoc test tracks).
    /// Every real track is drawn by `EditorRenderer.drawTrack`, which renders the
    /// placed pieces as width-varying ribbons and shades ramps across their climb.
    private static func ribbonPath(_ track: Track, elevated: Bool) -> Path {
        var path = Path()
        var penDown = false
        for i in track.centerline.indices {
            let a = track.centerline[i]
            let b = track.centerline[(i + 1) % track.centerline.count]
            let high = track.height(ofSegment: i) > 0.5
            if high == elevated {
                if !penDown {
                    path.move(to: CGPoint(x: a.x, y: a.y))
                    penDown = true
                }
                path.addLine(to: CGPoint(x: b.x, y: b.y))
            } else {
                penDown = false
            }
        }
        return path
    }

    static func drawRibbon(track: Track, elevated: Bool, into context: inout GraphicsContext) {
        let path = ribbonPath(track, elevated: elevated)
        // Ground loops close on themselves, so round caps never show; the
        // bridge deck is an open span and must end FLUSH where the ramp
        // wedges meet it — butt caps, or a half-circle bulges over the ramp.
        let cap: CGLineCap = elevated ? .butt : .round
        if elevated {
            // The bridge floats: a soft drop shadow under its span —
            // trimmed at both ends so no dark band falls across the ramp
            // mouths where the deck meets its slopes.
            var shadow = context
            shadow.translateBy(x: 7, y: 12)
            shadow.stroke(
                path.trimmedPath(from: 0.06, to: 0.94),
                with: .color(.black.opacity(0.25)),
                style: StrokeStyle(lineWidth: track.width + 18, lineCap: cap, lineJoin: .round)
            )
        }
        // Striped kerb: a white band just wider than the asphalt, with red
        // dashes on top, then the asphalt covers all but the protruding edge.
        let kerbStyle = StrokeStyle(lineWidth: track.width + 16, lineCap: cap, lineJoin: .round)
        context.stroke(path, with: .color(kerbWhite), style: kerbStyle)
        context.stroke(
            path,
            with: .color(kerbRed),
            style: StrokeStyle(
                lineWidth: track.width + 16, lineCap: .butt, lineJoin: .round, dash: [24, 24])
        )
        context.stroke(
            path,
            with: .color(elevated ? Color(white: 0.68) : asphalt),
            style: StrokeStyle(lineWidth: track.width, lineCap: cap, lineJoin: .round)
        )
    }

    private static func drawPatches(track: Track, into context: inout GraphicsContext) {
        for patch in track.patches {
            let rect = CGRect(
                x: patch.center.x - patch.radius, y: patch.center.y - patch.radius,
                width: patch.radius * 2, height: patch.radius * 2
            )
            let color: Color
            switch patch.surface {
            case .mud: color = Color(red: 0.42, green: 0.30, blue: 0.16)
            case .water: color = Color(red: 0.23, green: 0.46, blue: 0.77).opacity(0.9)
            case .oil: color = Color(white: 0.1).opacity(0.55)
            case .asphalt, .grass: color = .clear
            }
            context.fill(Path(ellipseIn: rect), with: .color(color))
            // A darker rim so patches read against both asphalt and grass.
            context.stroke(
                Path(ellipseIn: rect.insetBy(dx: 1.5, dy: 1.5)),
                with: .color(color.opacity(0.8)),
                lineWidth: 3
            )
        }
    }

    /// Checkpoints drawn like physical gates on a real course: a faint line
    /// across the road with a **post** at each ribbon edge. Beside the
    /// posts, a dot lights up in each car's color whose NEXT gate this is —
    /// per-player guidance that stays honest with 2–4 players on screen.
    /// The last gate is the start/finish and keeps its checkers.
    /// Everything the gate pass needs, bundled once per frame.
    struct GateChrome {
        var spans: [(a: Vec2, b: Vec2)?]
        var nextByGate: [Int: [Color]]
        var worldCenter: Vec2
        var heights: [Double]
    }

    static func drawGates(
        _ chrome: GateChrome, elevated: Bool, into context: inout GraphicsContext
    ) {
        for (index, span) in chrome.spans.enumerated() {
            guard let span else { continue }
            guard index < chrome.heights.count, (chrome.heights[index] > 0.5) == elevated
            else {
                continue
            }
            // The start/finish's checkerboard comes from the shared renderer —
            // it's paint on the start piece, drawn with the road — so only the
            // CHECKPOINT lines are chrome here.
            let isStartFinish = index == chrome.spans.count - 1
            if !isStartFinish {
                var path = Path()
                path.move(to: CGPoint(x: span.a.x, y: span.a.y))
                path.addLine(to: CGPoint(x: span.b.x, y: span.b.y))
                context.stroke(
                    path,
                    with: .color(.white.opacity(0.3)),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
            }
            drawPosts(
                span: span, colors: chrome.nextByGate[index] ?? [],
                worldCenter: chrome.worldCenter, into: &context)
        }
    }

    /// The two gate posts, plus one dot per waiting player in that player's
    /// color — clustered past the infield-side post (the infield always has
    /// room by track design; the outer post may sit against the wall).
    private static func drawPosts(
        span: (a: Vec2, b: Vec2), colors: [Color], worldCenter: Vec2,
        into context: inout GraphicsContext
    ) {
        // No neutral posts: the thin white line is the gate; the only dots
        // drawn are car-colored "waiting on this gate" markers, anchored off
        // the infield end.
        let infield =
            span.a.distance(to: worldCenter) <= span.b.distance(to: worldCenter)
            ? (post: span.a, other: span.b) : (post: span.b, other: span.a)
        let direction = (infield.post - infield.other).normalized
        for (slot, color) in colors.enumerated() {
            let center = infield.post + direction * (22 + Double(slot) * 22)
            let dot = CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)
            context.fill(Path(ellipseIn: dot), with: .color(color))
            context.stroke(
                Path(ellipseIn: dot), with: .color(.white.opacity(0.9)), lineWidth: 2.5)
        }
    }

    static func drawMarks(
        _ marks: MarkStore, elevated: Bool = false, into context: inout GraphicsContext
    ) {
        // Marks arrive pre-batched into chunked paths — a few dozen stroke
        // calls total, whatever the segment count.
        let style = StrokeStyle(lineWidth: 4, lineCap: .round)
        for bucket in MarkStore.Bucket.allCases {
            guard let chunkList = (elevated ? marks.elevatedChunks : marks.chunks)[bucket]
            else { continue }
            let color: Color
            switch bucket {
            case .rubberLight: color = rubber.opacity(0.25)
            case .rubberHeavy: color = rubber.opacity(0.5)
            case .scuff: color = scuff.opacity(0.55)
            case .mudTrail: color = Color(red: 0.42, green: 0.30, blue: 0.16).opacity(0.5)
            case .wetTrail: color = Color(red: 0.35, green: 0.5, blue: 0.7).opacity(0.35)
            }
            for chunk in chunkList {
                context.stroke(chunk.path, with: .color(color), style: style)
            }
        }
    }

}
