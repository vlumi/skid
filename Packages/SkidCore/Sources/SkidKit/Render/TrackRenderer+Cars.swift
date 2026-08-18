import SkidCore
import SwiftUI

/// Car and deck-rail drawing, split out of TrackRenderer to keep each file
/// within the length budget. Everything here draws in world space, inside the
/// aspect-fit transform set up by `TrackRenderer.draw`.
extension TrackRenderer {
    /// Collect the cars as layers: each one at the storey it occupies, so the
    /// z-order puts it above its own road and under any road a level above.
    ///
    /// No pass-picking. A car on ASPHALT is at the storey of the piece under
    /// it — the ribbon paints whole at the level of its highest end, so the car
    /// must stack by the same rule, or mid-climb it is a storey below its own
    /// road and vanishes beneath the ramp's upper half. A car on GRASS has no
    /// piece; its raw height decides (which is what hides it under a bridge,
    /// where the bubble takes over). The long-running "is this car on a ramp /
    /// over ground-height road?" promotion logic is still gone — this is a
    /// lookup of stored piece data, not a guess from nearby slopes.
    static func addCars(
        scene: WorldScene, gateChrome: GateChrome, colorAt: @escaping (Int) -> Color,
        to order: inout RenderOrder.Builder
    ) {
        let race = scene.race
        let track = race.track

        // The PB ghost drives under the real cars, translucent and colorless —
        // present, never in the way.
        for ghost in scene.ghosts where !ghost.isAirborne {
            order.add(storey: carStorey(of: ghost, on: track), kind: .car) { context in
                draw(car: ghost, color: .white, opacity: 0.38, into: &context)
            }
        }

        for (index, car) in race.cars.enumerated() where !car.state.isAirborne {
            let state = car.state
            let storey = carStorey(of: state, on: track)
            order.add(storey: storey, kind: .car) { context in
                // Scaled by the continuous height at its position (the same
                // Elevation.scale the road width uses), so a car grows as it
                // climbs — no discrete pop at a level boundary.
                draw(
                    car: state, color: colorAt(index),
                    scale: Elevation.scale(atHeight: state.height), into: &context)
            }
            // The headlight fan, in the car's own color — the facing cue that
            // replaced the nose lamps. Registered with the airborne pass's storey so
            // it paints above every road band (see `RenderOrder.Kind.beam`); ghosts
            // carry none, being colorless and translucent by design.
            order.add(storey: Track.highestLevel + 1, kind: .beam) { context in
                drawHeadlight(
                    car: state, color: colorAt(index), track: track,
                    scale: Elevation.scale(atHeight: state.height), into: &context)
            }
            // Never-invisible rule: a car with road a full level above it is
            // hidden by that road, so the deck gets a WINDOW — a dimmed hole
            // at the car's position with the car itself visible through it.
            // Drawn at the covering storey, above that road (and above its
            // marks and gates, which the dimming swallows inside the hole).
            // A bridge's footprint is its asphalt PLUS the rails standing on
            // its edges — that whole band hides what is under it, so that whole
            // band is where the hole may be cut. The TRIGGER then reaches one
            // hole-radius further out, because the hole is centered on the car:
            // stopping the trigger at the footprint edge made the window vanish
            // the moment the car's center cleared the bridge, cutting off a
            // window whose disc still overlapped it. Reaching further lets the
            // clip do the trimming, which is its job.
            //
            // These two used to disagree the other way, too: the trigger
            // reached the rail's outer edge (87 on the eight) while the hole was
            // cut only in the asphalt (72), so a car under the wall triggered a
            // window with nowhere to draw and stayed invisible.
            // **Every storey above the car, not just the next one.** With one deck
            // `storey + 1` was the only candidate; with three, a ground car under a
            // level-3 bridge asked about storey 1, found no road overhead there, and
            // got no window — hidden with nothing to see it through. Measured on a
            // three-storey track: under a storey-2 deck with no storey-1 road above,
            // the window was missing at every sampled point.
            //
            // A window per covering storey is correct rather than merely tolerable:
            // each is drawn in its own layer, so a car under two stacked decks shows
            // through both, and where only one covers it only one is drawn.
            // **Which ROAD covers this car, not which storey.**
            //
            // Storeys are the wrong granularity here. A ramp climbing from 2.0 to
            // 2.65 is road above a car at 2.01, but it belongs to no whole storey —
            // so a scan that asked "is there road at storey 3?" found nothing 132
            // units away and left the car hidden. Reported from a ramp at h=2.11:
            // "still hidden on the ramp under this other ramp".
            //
            // Two earlier shapes were both wrong for the same reason. `storey + 1`
            // asked one level up from the car's PAINT storey, which `carStorey` had
            // already set to the deck above it. Flooring the car's own height fixed
            // the off-by-one at 2.60 but still only ever looked at whole levels.
            //
            // So: ask the road. Any segment a level or more above the car, whose
            // footprint reaches it, covers it — and each such segment's own storey
            // is the layer its window belongs in, so a car under two stacked decks
            // still shows through both.
            //
            // **The gap must be a whole level, not half a storey.** This used
            // `levelSeparation`, which is 0.5 and documented for solidity-interval
            // gaps — a different question. Half a level is less than a curved ramp
            // climbs while it bends back over its own footprint, so a car mid-climb
            // was "covered" by the stretch it was about to drive onto. Reported from
            // device on the clover at h 0.41, and absent on the eight, whose ramps
            // are straight and never pass over themselves.
            //
            // Measured on the built-ins: a ramp's self-overlap never exceeds a 0.565
            // height gap (0.299 on the eight), while every genuine deck clears
            // exactly 1.0 or more — decks sit on whole levels by construction. A full
            // `levelHeight` therefore separates the two cases with room on both
            // sides, which is why this needs no tuning.
            let deckClearance = Track.levelHeight - 0.001  // float-sum tolerance
            var coveringStoreys: Set<Int> = []
            for index in track.centerline.indices {
                let roadHeight = track.height(ofSegment: index)
                guard roadHeight > state.height + deckClearance else { continue }
                let reach = track.footprintHalfWidth(atHeight: roadHeight) + holeRadius
                let a = track.centerline[index]
                let b = track.centerline[(index + 1) % track.centerline.count]
                guard state.position.distance(toSegment: a, b) < reach else { continue }
                coveringStoreys.insert(Track.level(of: roadHeight))
            }
            for coveringStorey in coveringStoreys.sorted() {
                let deck = coveringDeck(track: track, storey: coveringStorey)
                guard !deck.isEmpty else { continue }
                order.add(storey: coveringStorey, kind: .window) { context in
                    drawWindow(
                        around: state, color: colorAt(index), deck: deck, into: &context)
                }
            }
        }

        // Airborne cars fly over everything: bigger, with a drop shadow.
        for (index, car) in race.cars.enumerated() where car.state.isAirborne {
            let state = car.state
            order.add(storey: Track.highestLevel + 1, kind: .airborne) { context in
                draw(
                    car: state, color: colorAt(index), scale: 1.22, shadow: true,
                    into: &context)
            }
        }
    }

    /// The storey a car paints in: **the highest storey of any road its BODY
    /// touches at its own height**; on grass (touching none), its own level.
    ///
    /// Body, not center: ribbons paint whole, so where a descent hands over to
    /// a flat run the neighboring ribbon is binned a storey up, and a car
    /// straddling that seam had its tail painted over by road at its own
    /// height. "At its own height" is the other half of the rule: without it,
    /// a car entering an underpass would inherit the BRIDGE's storey from the
    /// deck overhead and paint on top of the thing it is sliding under.
    static func carStorey(of state: CarState, on track: Track) -> Int {
        var highest: Int?
        for point in [state.position] + state.bodyCorners {
            guard
                track.distanceToCenterline(point, height: state.height)
                    <= track.halfWidth(atHeight: state.height)
            else { continue }
            let touched = storey(ofTop: track.deckTop(at: point, preferHeight: state.height))
            highest = max(highest ?? touched, touched)
        }
        // On road, the storeys the body touches decide — see above.
        if let highest { return highest }
        // **Off the road, ask what is BENEATH the car** rather than rounding its own
        // height. Rounding flips the storey at every half level — 0.5, and now 1.5
        // and 2.5 as well — so a car on the grass beside a ramp's low end jumped
        // from painting under the wall to over it partway up. Reported from device:
        // "the car (and the window) are hidden under the wall, but at some point
        // they clip above the wall". `deckTop` answers for any point, on road or
        // not, which is the same question the on-road branch asks.
        return storey(ofTop: track.deckTop(at: state.position, preferHeight: state.height))
    }

    /// A car hidden under the bridge shows THROUGH it: a dark circular hole
    /// in the deck with the car itself drawn inside, slightly small for depth.
    /// (Replaces a solid dot in the car's color — a placeholder that told you
    /// a car was there but not which way it pointed.)
    ///
    /// Two deliberate simplifications, both the maintainer's calls:
    /// - The hole is a hole IN THE DECK: everything, rim included, is clipped
    ///   to the covering asphalt, so the window never eats the deck rail or
    ///   spills onto the grass — the wall stands solid across the hole's edge.
    /// - The hole doesn't try to show what is really down there (grass,
    ///   decals): the car sits in plain heavy shadow, which reads as "under
    ///   the bridge" without re-rendering the world below.
    private static func drawWindow(
        around state: CarState, color: Color, deck: Path,
        into context: inout GraphicsContext
    ) {
        let hole = CGRect(
            x: state.position.x - holeRadius, y: state.position.y - holeRadius,
            width: holeRadius * 2, height: holeRadius * 2)
        let rim = Path(ellipseIn: hole)
        var window = context
        window.clip(to: deck)
        var inside = window
        inside.clip(to: rim)
        inside.fill(rim, with: .color(.black.opacity(0.62)))
        draw(car: state, color: color, opacity: 0.95, scale: 0.8, into: &inside)
        // A dark rim so the edge reads as a cut, not a smudge.
        window.stroke(rim, with: .color(.black.opacity(0.5)), lineWidth: 2.5)
    }

    /// The covering deck's asphalt as a region: the centerline segments at
    /// the covering height, stroked to the road width — what the window is
    /// allowed to cut a hole in.
    /// Every stretch of road belonging to `storey`, as a stroked band — the shape a
    /// window is clipped to, so a hole never spills past the road that casts it.
    ///
    /// Keyed by STOREY rather than an exact height: a ramp climbing through a level
    /// has no segment at any whole height, so matching `isAt:` left the very road
    /// that hides the car out of its own deck. Each segment is stroked at its own
    /// footprint, which also stops a ramp's narrow foot borrowing the deck's width.
    private static func coveringDeck(track: Track, storey: Int) -> Path {
        var path = Path()
        let n = track.centerline.count
        for i in 0..<n where Track.level(of: track.height(ofSegment: i)) == storey {
            let a = track.centerline[i]
            let b = track.centerline[(i + 1) % n]
            var line = Path()
            line.move(to: CGPoint(x: a.x, y: a.y))
            line.addLine(to: CGPoint(x: b.x, y: b.y))
            // Stroked to the road's whole FOOTPRINT — asphalt plus rails — since
            // the rails hide the ground under them just as the asphalt does.
            path.addPath(
                line.strokedPath(
                    StrokeStyle(
                        lineWidth: track.footprintHalfWidth(
                            atHeight: track.height(ofSegment: i)) * 2,
                        lineCap: .round, lineJoin: .round)))
        }
        return path
    }

    /// Radius of the window's disc, centered on the car. Also how far past the
    /// bridge's footprint the window keeps being drawn, since a disc centered
    /// just outside the bridge still overlaps it.
    static let holeRadius: Double = 20

    private static func draw(
        car: CarState, color: Color, opacity: Double = 1, scale: Double = 1,
        shadow: Bool = false, into context: inout GraphicsContext
    ) {
        if shadow {
            // A soft blob on the ground below a flying car.
            let rect = CGRect(
                x: car.position.x - 16 + 9, y: car.position.y - 11 + 15, width: 32, height: 22)
            context.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.25)))
        }
        var car2D = context
        car2D.opacity = opacity
        car2D.translateBy(x: car.position.x, y: car.position.y)
        car2D.rotate(by: Angle(radians: car.heading))
        car2D.scaleBy(x: scale, y: scale)

        let length = CarGeometry.length
        let width = CarGeometry.width
        // Tires first, so the body sits on top; open-wheel means they stick
        // out past the body sides.
        for offset in CarGeometry.tireOffsets {
            let tire = CGRect(x: offset.x - 4.5, y: offset.y - 3, width: 9, height: 6)
            car2D.fill(Path(tire), with: .color(rubber))
        }
        // Narrow open-wheeler body: a capsule nose-to-tail. The look is a bold
        // dark rim (the cartoony edge that reads well on grass/asphalt). A soft
        // light GLOW sits just outside that edge — subtler and closer than the
        // headlight — barely there on light surfaces, but enough to keep a dark
        // car legible on dark ground (the mud pit), where a dark-only edge
        // would vanish. Background-independent, and carries onto map themes.
        // **Chunky and square-cornered**, to match the menus' pixel look — and because
        // the car is small on screen, where a thin capsule reads as a smudge.
        //
        // Rendering only: `CarGeometry` is the SIM's car (collision runs off `radius`),
        // and widening that would move every wall contact and invalidate every stored
        // ghost. So the drawn body is deliberately its own number — 0.62 of the nominal
        // width rather than the old 0.5 — and the corners are square.
        let bodyHeight = width * 0.62
        let body = CGRect(x: -length / 2, y: -bodyHeight / 2, width: length, height: bodyHeight)
        let bodyPath = Path(body)
        // The glow: the dark rim drawn into a layer with TWO stacked white
        // shadow filters, so a soft light aura bleeds out around the whole
        // silhouette. Stacking compounds the light so it stays visible even at
        // the tiny on-device car size (a single pass all but vanished).
        car2D.drawLayer { glow in
            glow.addFilter(.shadow(color: .white.opacity(0.9), radius: 4))
            glow.addFilter(.shadow(color: .white.opacity(0.9), radius: 4))
            glow.stroke(bodyPath, with: .color(.black.opacity(0.7)), lineWidth: 2)
        }
        car2D.fill(bodyPath, with: .color(color))
        // **One tone per car, and that is a measured constraint rather than a
        // preference.**
        //
        // A white sheen over the front half used to carry facing, and it was
        // expensive: a gradient to opacity 0.55 collapsed the palette's worst pair
        // from ΔE 24.7 to **9.1** across the four vision types, because every car
        // washing toward the same white is a shared destination.
        //
        // Replacing it with a *derived* second tone (a lightness shift per car) was
        // tried and is worse than it looks. Judged by the question a player actually
        // asks — can I tell car A from car B — a two-tone car presents two patches,
        // and confusion is any patch of one resembling any patch of another. Measured
        // that way: single-tone **24.7**, two-tone **4.6**, the old sheen 3.7. So the
        // derived livery fixed the sheen's mechanism and kept its effect.
        //
        // The budget is TONES, not cars: nine mutually-distinct tones is already the
        // edge of what color-blind-safe lightness spread allows, so eighteen do not
        // exist. Two distinct hues per car measures fine at **four** cars (26.3) and
        // is impossible at nine — which makes it a job for the color picker, where
        // the field size can bound the choices, not for arithmetic here.
        //
        // So facing rests on the nose lamps and the tucked-back cockpit until the
        // projected cone returns — and the cone is the *right* answer precisely
        // because a beam adds no color to the body, spending nothing from the
        // palette's budget. It stays parked pending an occlusion query: an extended
        // beam binned at its origin's storey gets sliced at ramp feet, and it must
        // not shine through walls.
        var livery = car2D
        livery.clip(to: bodyPath)
        paintReverseLamps(car: car, length: length, into: &livery)
        car2D.stroke(bodyPath, with: .color(.black.opacity(0.7)), lineWidth: 2)
        // The driver sits near the back, like the classic single-seaters.
        let cockpit = CGRect(x: -9.5, y: -3.2, width: 6.4, height: 6.4)
        car2D.fill(Path(ellipseIn: cockpit), with: .color(.black.opacity(0.65)))
    }
}

#if DEBUG
extension TrackRenderer {
    /// Test-only window into the private car drawing, for look probes.
    static func probeDrawCar(
        _ state: CarState, color: Color, into context: inout GraphicsContext
    ) {
        draw(car: state, color: color, into: &context)
    }

    /// Test-only window into the covering-deck clip region.
    static func probeCoveringDeck(track: Track, storey: Int) -> Path {
        coveringDeck(track: track, storey: storey)
    }

    /// Test-only window into the under-deck window drawing.
    static func probeDrawWindow(
        around state: CarState, color: Color, deck: Path,
        into context: inout GraphicsContext
    ) {
        drawWindow(around: state, color: color, deck: deck, into: &context)
    }
}
#endif
