import SkidCore
import SwiftUI

/// The race itself: world canvas, per-player d-pad overlays, zone chrome,
/// zone-aware HUD, the multitouch input surface, pause menu, results card.
struct RaceScreen: View {
    @ObservedObject var game: CouchGame
    @ObservedObject var session: GameSession
    @ObservedObject var rig: CouchRig

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                // Step the sim on the main actor, then hand the Canvas
                // plain value copies — its renderer closure is not
                // MainActor. (`let _ =` is the ViewBuilder side-effect
                // idiom; a bare `_ =` isn't a valid builder statement.)
                // swiftlint:disable:next redundant_discardable_let
                let _ = step(
                    size: geo.size,
                    time: timeline.date.timeIntervalSinceReferenceDate
                )
                let race = session.race
                let colors = game.carColors
                let scene = WorldScene(
                    race: race, marks: session.marks, gateSpans: session.gateSpans,
                    colors: colors, ghosts: session.ghost?.cars ?? []
                )
                let pads = padOverlays()
                let aims = aimOverlays()
                let zones = zoneChrome()
                ZStack {
                    Canvas { context, size in
                        var world = context
                        TrackRenderer.draw(scene: scene, into: &world, size: size)
                        for zone in zones {
                            OverlayRenderer.drawZone(zone, into: &context)
                        }
                        for pad in pads {
                            OverlayRenderer.drawDPad(pad, into: &context)
                        }
                        for aim in aims {
                            OverlayRenderer.drawAim(aim, into: &context)
                        }
                    }
                    InputSurface(rig: rig)
                    RaceHUD(race: race, colors: colors, rig: rig, size: geo.size)

                    // Meta controls live OUT of everyone's way: one small
                    // pause toggle parked on genuine infield/grass (never on
                    // the racing line, which the old fixed screen-center did
                    // on tracks whose ribbon runs through the middle) — never
                    // a Reset under someone's racing thumb.
                    if race.phase != .finished, !session.paused {
                        pauseButton(at: pausePoint(track: race.track, screen: geo.size))
                    }
                    if session.paused {
                        PauseMenu(
                            game: game, session: session, rig: rig, settings: game.settings)
                    }
                    if race.phase == .finished {
                        ResultsCard(game: game, race: race, colors: colors)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .defersEdgeSwipes(!session.paused && !session.raceOver)
    }

    /// The shared pause button's screen point: the seam between the map and
    /// the near-side control band — the map rect's bottom-centre. Off the
    /// track, out of every thumb's way; not tapped much (one shared button).
    private func pausePoint(track: Track, screen: CGSize) -> CGPoint {
        let map = TrackRenderer.fittedMapRect(trackSize: track.size, in: screen)
        return CGPoint(x: map.midX, y: map.maxY)
    }

    private func pauseButton(at point: CGPoint) -> some View {
        Button {
            session.paused = true
        } label: {
            Image(systemName: "pause.fill")
                .font(.callout.bold())
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.3), in: Circle())
        }
        .position(point)
    }

    private func step(size: CGSize, time: TimeInterval) {
        let mapRect = TrackRenderer.fittedMapRect(trackSize: session.race.track.size, in: size)
        rig.layout(size: size, mapRect: mapRect)
        game.applyControlTuning()
        session.advance(to: time)
        game.noteProgress()
        game.audioFrame()
    }

    /// Every active floating d-pad (Pro scheme), in its owner's color.
    private func padOverlays() -> [DPadOverlay] {
        guard rig.scheme == .pro else { return [] }
        return rig.players.compactMap { controls in
            guard let origin = controls.pro.origin else { return nil }
            return DPadOverlay(
                origin: origin,
                up: controls.pro.up,
                radius: controls.pro.radius,
                input: controls.pro.input(for: controls.player, at: session.race.tick),
                color: CouchGame.palette[controls.colorIndex]
            )
        }
    }

    /// Every active floating aim stick (Casual scheme), in its owner's color.
    private func aimOverlays() -> [AimOverlay] {
        guard rig.scheme == .casual else { return [] }
        return rig.players.compactMap { controls in
            guard let origin = controls.casual.origin else { return nil }
            return AimOverlay(
                origin: origin,
                knob: controls.casual.knob,
                radius: controls.casual.radius,
                color: CouchGame.palette[controls.colorIndex]
            )
        }
    }

    /// Zone outlines + corner tabs, only when the screen is shared.
    private func zoneChrome() -> [ZoneChrome] {
        guard rig.players.count > 1 else { return [] }
        return rig.players.map { controls in
            ZoneChrome(
                rect: controls.zone,
                up: controls.up,
                color: CouchGame.palette[controls.colorIndex]
            )
        }
    }
}

/// The frozen-race menu: every meta action lives here, where it can't be
/// fat-thumbed mid-corner.
struct PauseMenu: View {
    let game: CouchGame
    let session: GameSession
    @ObservedObject var rig: CouchRig
    @ObservedObject var settings: GameSettings
    @State private var showTuning = false

    var body: some View {
        if showTuning {
            TuningPanel(settings: settings) {
                showTuning = false
            }
        } else {
            menu
        }
    }

    private var menu: some View {
        VStack(spacing: 12) {
            Button {
                session.paused = false
            } label: {
                Text("Resume", bundle: .module).pillStyle()
            }
            Button {
                rig.cycleScheme()
            } label: {
                Text(rig.schemeLabel, bundle: .module).pillStyle()
            }
            HStack(spacing: 10) {
                Button {
                    settings.soundOn.toggle()
                } label: {
                    Text("Sound", bundle: .module).pillStyle()
                        .opacity(settings.soundOn ? 1 : 0.45)
                }
                Button {
                    settings.hapticsOn.toggle()
                } label: {
                    Text("Haptics", bundle: .module).pillStyle()
                        .opacity(settings.hapticsOn ? 1 : 0.45)
                }
            }
            Button {
                showTuning = true
            } label: {
                Text("Tuning", bundle: .module).pillStyle()
            }
            Button {
                game.raceAgain()
            } label: {
                Text("Reset", bundle: .module).pillStyle()
            }
            Button {
                game.backToSetup()
            } label: {
                Text("Setup", bundle: .module).pillStyle()
            }
        }
        .padding(22)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Everything the renderer needs to draw the floating d-pad, colored by the
/// owning player's car color.
struct DPadOverlay {
    var origin: Vec2
    var up: Vec2
    var radius: Double
    var input: CarInput
    var color: Color
}

/// The floating aim stick's screen state: where it landed, the current
/// thumb offset (the aimed direction), and the player's color.
struct AimOverlay {
    var origin: Vec2
    var knob: Vec2
    var radius: Double
    var color: Color
}

/// A player's control zone, drawn as faint chrome so everyone knows whose
/// corner is whose.
struct ZoneChrome {
    var rect: CGRect
    var up: Vec2
    var color: Color
}

/// Zone-aware HUD: each player's chip sits in their own zone's home corner,
/// rotated to face them; the countdown mirrors for flipped players. Solo
/// keeps the classic top-left block (with AI opponents listed).
struct RaceHUD: View {
    let race: Race
    let colors: [Color]
    @ObservedObject var rig: CouchRig
    let size: CGSize

    private var hasFlippedZone: Bool {
        rig.players.contains { $0.up.y > 0 }
    }

    var body: some View {
        ZStack {
            countdown
            if rig.players.count == 1 {
                soloBlock
            } else {
                ForEach(Array(rig.players.enumerated()), id: \.offset) { index, controls in
                    playerChip(index: index, controls: controls)
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private var countdown: some View {
        let label: Text? = {
            if case .countdown(let remaining) = race.phase {
                return Text(verbatim: "\((remaining + Race.tickRate - 1) / Race.tickRate)")
            }
            if race.phase == .running, race.raceTicks < Race.tickRate * 3 / 4 {
                return Text("GO!", bundle: .module)
            }
            return nil
        }()
        if let label {
            if hasFlippedZone {
                // One for each side of the table.
                bigLabel(label)
                    .position(x: size.width / 2, y: size.height * 0.7)
                bigLabel(label)
                    .rotationEffect(.degrees(180))
                    .position(x: size.width / 2, y: size.height * 0.3)
            } else {
                bigLabel(label)
                    .position(x: size.width / 2, y: size.height / 2)
            }
        }
    }

    private func bigLabel(_ text: Text) -> some View {
        text
            .font(.system(size: 84, weight: .black, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .shadow(radius: 4)
    }

    /// Solo: the classic corner block, every car listed.
    private var soloBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let laps = race.config.laps {
                ForEach(Array(race.cars.enumerated()), id: \.offset) { index, car in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(index < colors.count ? colors[index] : .white)
                            .frame(width: 12, height: 12)
                        chipLine(car: car, laps: laps)
                    }
                }
                Text(verbatim: formatTicks(race.raceTicks))
                    .font(.headline.monospacedDigit())
                    .padding(.top, 2)
            } else if let car = race.cars.first {
                timeTrialLines(car: car)
            }
        }
        .foregroundStyle(.white)
        .shadow(radius: 2)
        .padding(.leading, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Shared screens: one chip per player, along the OUTER (screen) edge of
    /// their control band — clear of the map and the thumb — facing them.
    @ViewBuilder private func playerChip(index: Int, controls: PlayerControls) -> some View {
        if race.cars.indices.contains(index) {
            let car = race.cars[index]
            let flipped = controls.up.y > 0
            let zone = controls.zone
            // Outer edge = the screen edge the band hugs: top for a flipped
            // (far-side) band, bottom for a near-side band. A full-width band
            // shifts the chip off dead-centre so it clears the top notch /
            // Dynamic Island (which straddles the screen middle); half-width
            // bands are already off-centre, so they keep their midpoint.
            let fullWidth = zone.width > size.width * 0.75
            let x = fullWidth ? zone.minX + zone.width * 0.25 : zone.midX
            let y = flipped ? zone.minY + 30 : zone.maxY - 30
            HStack(spacing: 6) {
                Circle()
                    .fill(index < colors.count ? colors[index] : .white)
                    .frame(width: 11, height: 11)
                if let laps = race.config.laps {
                    chipLine(car: car, laps: laps)
                }
            }
            .foregroundStyle(.white)
            .shadow(radius: 2)
            .rotationEffect(flipped ? .degrees(180) : .zero)
            .position(x: x, y: y)
        }
    }

    @ViewBuilder private func chipLine(car: Car, laps: Int) -> some View {
        if let finished = car.progress.finishedAt {
            Text(verbatim: formatTicks(finished - race.config.countdownTicks))
                .font(.subheadline.monospacedDigit().bold())
        } else {
            Text("Lap \(min(car.progress.lap + 1, laps))/\(laps)", bundle: .module)
                .font(.subheadline.monospacedDigit())
        }
    }

    @ViewBuilder private func timeTrialLines(car: Car) -> some View {
        let lapTicks = max(
            0, race.tick - max(car.progress.lapStartTick, race.config.countdownTicks))
        Text(verbatim: formatTicks(lapTicks))
            .font(.title3.monospacedDigit().bold())
        if let best = car.progress.bestLapTicks {
            Text("Best \(formatTicks(best))", bundle: .module)
                .font(.subheadline.monospacedDigit())
        }
    }
}

/// Final standings once every car has taken the flag.
struct ResultsCard: View {
    let game: CouchGame
    let race: Race
    let colors: [Color]

    var body: some View {
        let standings = race.cars.enumerated().sorted { a, b in
            (a.element.progress.finishedAt ?? .max) < (b.element.progress.finishedAt ?? .max)
        }
        VStack(spacing: 14) {
            ForEach(Array(standings.enumerated()), id: \.offset) { place, entry in
                let (carIndex, car) = entry
                HStack(spacing: 10) {
                    Text(verbatim: "\(place + 1).")
                        .font(.title3.monospacedDigit().bold())
                    Circle()
                        .fill(carIndex < colors.count ? colors[carIndex] : .white)
                        .frame(width: 16, height: 16)
                    if let finished = car.progress.finishedAt {
                        Text(verbatim: formatTicks(finished - race.config.countdownTicks))
                            .font(.title3.monospacedDigit())
                    }
                    if let best = car.progress.bestLapTicks {
                        Text("Best \(formatTicks(best))", bundle: .module)
                            .font(.footnote.monospacedDigit())
                            .opacity(0.75)
                    }
                }
            }
            HStack(spacing: 12) {
                Button {
                    game.raceAgain()
                } label: {
                    Text("Race again", bundle: .module).pillStyle()
                }
                Button {
                    game.backToSetup()
                } label: {
                    Text("Setup", bundle: .module).pillStyle()
                }
            }
        }
        .padding(24)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.white)
    }
}
