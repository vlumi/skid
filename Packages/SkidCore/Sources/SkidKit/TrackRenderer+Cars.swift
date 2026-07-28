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
        let translucent = ghostOverlaps(race: race)

        // The PB ghost drives under the real cars, translucent and colorless —
        // present, never in the way.
        for ghost in scene.ghosts where !ghost.isAirborne {
            order.add(storey: carStorey(of: ghost, on: track), kind: .car) { context in
                draw(car: ghost, color: .white, opacity: 0.38, into: &context)
            }
        }

        for (index, car) in race.cars.enumerated() where !car.state.isAirborne {
            let state = car.state
            let opacity = translucent.contains(index) ? 0.55 : 1
            let storey = carStorey(of: state, on: track)
            order.add(storey: storey, kind: .car) { context in
                // Scaled by the continuous height at its position (the same
                // Elevation.scale the road width uses), so a car grows as it
                // climbs — no discrete pop at a level boundary.
                draw(
                    car: state, color: colorAt(index), opacity: opacity,
                    scale: Elevation.scale(atHeight: state.height), into: &context)
            }
            // Never-invisible rule: a car with road a full level above it is
            // hidden by that road, so the deck gets a WINDOW — a dimmed hole
            // at the car's position with the car itself visible through it.
            // Drawn at the covering storey, above that road (and above its
            // marks and gates, which the dimming swallows inside the hole).
            // WHETHER a window is due is asked of the deck's REGION, not of
            // the distance to its centerline. Distance-to-centerline reads the
            // nearest SAMPLE POINT, and the samples along a straight are a
            // whole road-width apart, so one step off a crossing the distance
            // jumped from 0 to 120 and the window only appeared within a hair
            // of dead centre — the reported wide margin, worse on the flat
            // side where the samples are coarsest (the ramp side, densely
            // sampled by its climb, was nearly right).
            //
            // The region is the same clip the hole is cut in, grown by the
            // rail band so the window appears just before the car slides under
            // the deck's edge rather than after.
            let coveringStorey = storey + 1
            if windowIsDue(for: state, on: track, storey: coveringStorey) {
                let deck = coveringDeck(track: track, storey: coveringStorey)
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
    /// a flat run the neighbouring ribbon is binned a storey up, and a car
    /// straddling that seam had its tail painted over by road at its own
    /// height. "At its own height" is the other half of the rule: without it,
    /// a car entering an underpass would inherit the BRIDGE's storey from the
    /// deck overhead and paint on top of the thing it is sliding under.
    static func carStorey(of state: CarState, on track: Track) -> Int {
        var highest: Int?
        for point in [state.position] + state.bodyCorners {
            guard
                track.distanceToCenterline(point, height: state.height)
                    <= track.width / 2
            else { continue }
            let touched = storey(ofTop: track.deckTop(at: point, preferHeight: state.height))
            highest = max(highest ?? touched, touched)
        }
        return highest ?? Track.level(of: state.height)
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
            x: state.position.x - 20, y: state.position.y - 20, width: 40, height: 40)
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

    /// Whether a car needs a window in the road at `storey` above it.
    ///
    /// Asked of the deck's REGION, never of distance to its centerline:
    /// distance-to-centerline reads the nearest sample POINT, and samples
    /// along a straight sit a full road-width apart, so one step off a
    /// crossing the distance jumped from 0 to 120 and the window only appeared
    /// within a hair of dead centre. The region is sample-density-independent,
    /// which is what makes the margin the same on a densely-sampled ramp and
    /// a sparsely-sampled straight.
    ///
    /// Grown by the rail band, and asked of the BODY, so the window is up from
    /// the moment any part of the car reaches the deck's barrier rather than
    /// once its centre is already hidden.
    static func windowIsDue(for state: CarState, on track: Track, storey: Int) -> Bool {
        guard track.heights.contains(where: { Track.level(of: $0) == storey })
        else { return false }
        let deck = coveringDeck(track: track, storey: storey)
        let approach = deck.strokedPath(StrokeStyle(lineWidth: railBand * 2))
        return state.bodyCorners.contains {
            let point = CGPoint(x: $0.x, y: $0.y)
            return deck.contains(point) || approach.contains(point)
        }
    }

    /// How far the deck's barrier stands outboard of its asphalt — the band the
    /// window has to reach so it appears as the car meets the rail.
    private static let railBand: Double = 16

    /// The covering storey's asphalt as a region — what the window is allowed
    /// to cut a hole in.
    ///
    /// Selected by the STOREY each segment's piece is binned into, exactly as
    /// the ribbon layers are, NOT by a height test on the segment itself. A
    /// height test cut the region short at every deck end: a ramp shoulder
    /// sits below `deckHeight - surfaceTolerance` while still painting in the
    /// deck's storey, so the clip ended before the ribbon did and a window
    /// near the bridge's edge fell outside it and vanished entirely.
    private static func coveringDeck(track: Track, storey: Int) -> Path {
        var line = Path()
        let n = track.centerline.count
        for i in 0..<n where self.storey(ofTop: track.deckTops[i]) == storey {
            let a = track.centerline[i]
            let b = track.centerline[(i + 1) % n]
            line.move(to: CGPoint(x: a.x, y: a.y))
            line.addLine(to: CGPoint(x: b.x, y: b.y))
        }
        // Round joins/caps: the ribbon's own ends are square, but a round cap
        // only ever reaches HALF a road-width past the last sample, which is
        // covered by the piece beyond it wherever one exists.
        return line.strokedPath(
            StrokeStyle(lineWidth: track.width, lineCap: .round, lineJoin: .round))
    }

    /// Ghost mode: overlapping pass-through cars go translucent so pileups
    /// on the racing line stay readable.
    private static func ghostOverlaps(race: Race) -> Set<Int> {
        var translucent: Set<Int> = []
        guard !race.config.carContact else { return translucent }
        for i in 0..<race.cars.count {
            for j in (i + 1)..<race.cars.count {
                let gap = race.cars[i].state.position.distance(
                    to: race.cars[j].state.position)
                if gap < CarGeometry.radius * 2.6 {
                    translucent.insert(i)
                    translucent.insert(j)
                }
            }
        }
        return translucent
    }

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
            car2D.fill(Path(roundedRect: tire, cornerRadius: 2), with: .color(rubber))
        }
        // Narrow open-wheeler body: a capsule nose-to-tail. The look is a bold
        // dark rim (the cartoony edge that reads well on grass/asphalt). A soft
        // light GLOW sits just outside that edge — subtler and closer than the
        // headlight — barely there on light surfaces, but enough to keep a dark
        // car legible on dark ground (the mud pit), where a dark-only edge
        // would vanish. Background-independent, and carries onto map themes.
        let body = CGRect(x: -length / 2, y: -width / 4, width: length, height: width / 2)
        let bodyPath = Path(roundedRect: body, cornerRadius: width / 4)
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
        // FACING is told by the body itself, not a thrown headlight beam — a
        // projected cone fought the storey binning (sliced off at ramp feet
        // by the higher-binned ribbon, painted onto a deck from a descent
        // that shares its storey), and no shape change fixes a decal that
        // leaves the car. Classic single-seater proportions carry the cue
        // instead: a LIT NOSE and the driver tucked back at the rear axle.
        // Bright end = front, dark dot = back — silhouette-scale marks that
        // survive the tiny on-SE car where any detail line vanishes.
        var sheen = car2D
        sheen.clip(to: bodyPath)
        sheen.fill(
            Path(CGRect(x: 0, y: -width / 4, width: length / 2, height: width / 2)),
            with: .linearGradient(
                Gradient(colors: [.white.opacity(0), .white.opacity(0.55)]),
                startPoint: .zero, endPoint: CGPoint(x: length / 2, y: 0)))
        // Lamp dots hugging the nose tip (the body clip rounds them into the
        // corners): flavor at editor zoom, they melt into the sheen at race
        // scale.
        for side in [-1.0, 1.0] {
            let lamp = CGRect(
                x: length / 2 - 6, y: side * 3.4 - 1.9, width: 3.8, height: 3.8)
            sheen.fill(
                Path(ellipseIn: lamp),
                with: .color(Color(red: 1, green: 0.98, blue: 0.82)))
        }
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

    /// Test-only window into the window-due predicate.
    static func probeWindowIsDue(for state: CarState, on track: Track, storey: Int) -> Bool {
        windowIsDue(for: state, on: track, storey: storey)
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
