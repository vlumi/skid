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
        // the remaining box, then centre it — the surplus falls to the bands.
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

        drawRibbon(track: track, layer: 0, into: &context)
        drawPatches(track: track, into: &context)
        drawRampMarkers(track: track, into: &context)
        // Which players are waiting on which gate, in car colors.
        var nextByGate: [Int: [Color]] = [:]
        for (index, car) in race.cars.enumerated() where car.progress.finishedAt == nil {
            nextByGate[car.progress.nextGate, default: []].append(color(index))
        }
        let gateChrome = GateChrome(
            spans: gateSpans,
            nextByGate: nextByGate,
            worldCenter: Vec2(track.size.x / 2, track.size.y / 2),
            layers: track.gates.map(\.layer)
        )
        drawGates(gateChrome, layerFilter: 0, into: &context)
        drawMarks(marks, into: &context)
        drawCars(scene: scene, gateChrome: gateChrome, colorAt: color, into: &context)
    }

    /// The ribbon of one layer, as contiguous runs of that layer's
    /// centerline segments (a flat track's layer 0 is one full loop).
    private static func ribbonPath(_ track: Track, layer: Int) -> Path {
        var path = Path()
        var penDown = false
        for i in track.centerline.indices {
            let a = track.centerline[i]
            let b = track.centerline[(i + 1) % track.centerline.count]
            if track.segmentLayer(i) == layer {
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

    static func drawRibbon(track: Track, layer: Int, into context: inout GraphicsContext) {
        let path = ribbonPath(track, layer: layer)
        // Ground loops close on themselves, so round caps never show; the
        // bridge deck is an open span and must end FLUSH where the ramp
        // wedges meet it — butt caps, or a half-circle bulges over the ramp.
        let cap: CGLineCap = layer > 0 ? .butt : .round
        if layer > 0 {
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
            with: .color(layer > 0 ? Color(white: 0.68) : asphalt),
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
        var layers: [Int]
    }

    static func drawGates(
        _ chrome: GateChrome, layerFilter: Int, into context: inout GraphicsContext
    ) {
        for (index, span) in chrome.spans.enumerated() {
            guard let span else { continue }
            guard index < chrome.layers.count, chrome.layers[index] == layerFilter else {
                continue
            }
            let isStartFinish = index == chrome.spans.count - 1
            if isStartFinish {
                drawCheckers(span: span, into: &context)
            } else {
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
        for end in [span.a, span.b] {
            let post = CGRect(x: end.x - 6, y: end.y - 6, width: 12, height: 12)
            context.fill(Path(ellipseIn: post), with: .color(kerbWhite))
            context.stroke(
                Path(ellipseIn: post), with: .color(.black.opacity(0.55)), lineWidth: 2)
        }
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

    private static func drawCheckers(
        span: (a: Vec2, b: Vec2), into context: inout GraphicsContext
    ) {
        let start = span
        // Two rows of checkers across the ribbon.
        let along = (start.b - start.a).normalized
        let across = along.perpendicular
        let squares = max(6, Int((start.b - start.a).length / 13))
        let side = (start.b - start.a).length / Double(squares)
        for row in 0..<2 {
            for i in 0..<squares where (i + row) % 2 == 0 {
                let corner = start.a + along * (Double(i) * side) + across * (Double(row) * side)
                var path = Path()
                let points = [
                    corner,
                    corner + along * side,
                    corner + along * side + across * side,
                    corner + across * side,
                ]
                path.move(to: CGPoint(x: points[0].x, y: points[0].y))
                for p in points.dropFirst() {
                    path.addLine(to: CGPoint(x: p.x, y: p.y))
                }
                path.closeSubpath()
                context.fill(path, with: .color(.black.opacity(0.8)))
            }
        }
    }
}

extension TrackRenderer {
    static func drawMarks(_ marks: MarkStore, into context: inout GraphicsContext) {
        // Marks arrive pre-batched into chunked paths — a few dozen stroke
        // calls total, whatever the segment count.
        let style = StrokeStyle(lineWidth: 4, lineCap: .round)
        for bucket in MarkStore.Bucket.allCases {
            guard let chunkList = marks.chunks[bucket] else { continue }
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

    /// Sloped bridge approaches: a wedge that widens toward the deck and
    /// shades from road-gray to deck-gray, with up-slope chevrons — the
    /// road visibly climbs; the car never warps.
    static func drawRampMarkers(track: Track, into context: inout GraphicsContext) {
        for index in track.rampSegments.sorted() {
            let count = track.centerline.count
            let a = track.centerline[index]
            let b = track.centerline[(index + 1) % count]
            // The end that meets the deck is the one whose neighboring
            // segment is elevated.
            let previous = (index + count - 1) % count
            let deckFirst = track.segmentLayer(previous) == 1
            let ground = deckFirst ? b : a
            let deck = deckFirst ? a : b
            let up = (deck - ground).normalized
            let side = up.perpendicular
            let groundHalf = side * (track.width / 2)
            let deckHalf = side * (track.width / 2 + 8)

            var wedge = Path()
            wedge.move(to: CGPoint(x: (ground - groundHalf).x, y: (ground - groundHalf).y))
            wedge.addLine(to: CGPoint(x: (deck - deckHalf).x, y: (deck - deckHalf).y))
            wedge.addLine(to: CGPoint(x: (deck + deckHalf).x, y: (deck + deckHalf).y))
            wedge.addLine(to: CGPoint(x: (ground + groundHalf).x, y: (ground + groundHalf).y))
            wedge.closeSubpath()
            context.fill(
                wedge,
                with: .linearGradient(
                    Gradient(colors: [asphalt, Color(white: 0.68)]),
                    startPoint: CGPoint(x: ground.x, y: ground.y),
                    endPoint: CGPoint(x: deck.x, y: deck.y)
                )
            )
            // White edges so the slope reads against both road and grass.
            for sign in [-1.0, 1.0] {
                var edge = Path()
                let g = ground + groundHalf * sign
                let d = deck + deckHalf * sign
                edge.move(to: CGPoint(x: g.x, y: g.y))
                edge.addLine(to: CGPoint(x: d.x, y: d.y))
                context.stroke(edge, with: .color(kerbWhite), lineWidth: 5)
            }
            // Chevrons along the DRIVING direction (centerline order) —
            // on the descent that's down-slope; arrows pointing at the
            // driver read as a wrong-way sign.
            drawChevrons(
                from: ground, to: deck, drive: (b - a).normalized,
                wing: side * (track.width * 0.28), into: &context)
        }
    }

    private static func drawChevrons(
        from ground: Vec2, to deck: Vec2, drive: Vec2, wing: Vec2,
        into context: inout GraphicsContext
    ) {
        let up = (deck - ground).normalized
        let length = ground.distance(to: deck)
        for t in [0.3, 0.55, 0.8] {
            let base = ground + up * (length * t) - drive * 8
            let tip = base + drive * 16
            var chevron = Path()
            chevron.move(to: CGPoint(x: (base - wing).x, y: (base - wing).y))
            chevron.addLine(to: CGPoint(x: tip.x, y: tip.y))
            chevron.addLine(to: CGPoint(x: (base + wing).x, y: (base + wing).y))
            context.stroke(
                chevron,
                with: .color(.white.opacity(0.55)),
                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
