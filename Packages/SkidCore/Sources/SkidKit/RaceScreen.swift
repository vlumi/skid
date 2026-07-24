import SkidCore
import SwiftUI

/// The race itself: world canvas, per-player d-pad overlays, zone chrome,
/// zone-aware HUD, the multitouch input surface, pause menu, results card.
struct RaceScreen: View {
    @ObservedObject var game: CouchGame
    @ObservedObject var session: GameSession
    @ObservedObject var rig: CouchRig

    var body: some View {
        // The GeometryReader must NOT ignore the safe area, or its
        // `safeAreaInsets` read as zero — the layout needs the real insets
        // (notch, Dynamic Island, home indicator) to reserve control room.
        // Only the world Canvas ignores them, so the grass still draws
        // full-bleed under the notch.
        GeometryReader { geo in
            // The GeometryReader respects the safe area, so `geo.size` is the
            // safe-area size and `geo.safeAreaInsets` are the real insets. But
            // every layer below ignores the safe area (grass full-bleed, band
            // boxes to the physical edge), so we work in FULL-SCREEN coords:
            // reconstruct the physical size and pass the insets down. One
            // coordinate space for the Canvas, the input surface, and the HUD —
            // so nothing is shifted by the notch.
            let insets = geo.safeAreaInsets
            let fullSize = CGSize(
                width: geo.size.width + insets.leading + insets.trailing,
                height: geo.size.height + insets.top + insets.bottom)
            let mapRect = TrackRenderer.fittedMapRect(
                trackSize: session.race.track.size, in: fullSize,
                safeInsets: insets)
            TimelineView(.animation) { timeline in
                // Step the sim on the main actor, then hand the Canvas
                // plain value copies — its renderer closure is not
                // MainActor. (`let _ =` is the ViewBuilder side-effect
                // idiom; a bare `_ =` isn't a valid builder statement.)
                // swiftlint:disable:next redundant_discardable_let
                let _ = step(
                    size: fullSize, mapRect: mapRect, safeInsets: insets,
                    time: timeline.date.timeIntervalSinceReferenceDate
                )
                let race = session.race
                let colors = game.carColors
                let scene = WorldScene(
                    race: race, marks: session.marks, gateSpans: session.gateSpans,
                    colors: colors, mapRect: mapRect, ghosts: session.ghost?.cars ?? []
                )
                let pads = padOverlays()
                let aims = aimOverlays()
                let zones = zoneChrome(safeInsets: insets)
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
                    RaceHUD(
                        race: race, colors: colors, rig: rig, size: fullSize,
                        started: session.started)

                    // The map centre is meta-control space (no car races there,
                    // and map-area touches are otherwise inert). A tap on it
                    // starts the race off the ready gate, and after that opens
                    // the pause menu — one learned "tap the map" gesture. Sized
                    // to the map so it never steals a control-band touch.
                    if race.phase != .finished, !session.paused {
                        mapTapTarget(mapRect: mapRect)
                    }
                    if !session.started, race.phase != .finished {
                        readyOverlay(at: CGPoint(x: mapRect.midX, y: mapRect.midY))
                    }
                    if session.paused {
                        PauseMenu(
                            game: game, session: session, rig: rig, settings: game.settings)
                    }
                    if race.phase == .finished {
                        ResultsCard(game: game, race: race, colors: colors)
                    }
                }
                .ignoresSafeArea()
            }
        }
        .defersEdgeSwipes(!session.paused && !session.raceOver)
    }

    /// An invisible tap target over the map: it starts the race off the ready
    /// gate (first tap), then opens the pause menu (later taps). Sized and
    /// positioned to the map rect so it never overlaps a control band. Once
    /// learned via the Play overlay, the same gesture pauses — no on-track
    /// button needed.
    private func mapTapTarget(mapRect: CGRect) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: mapRect.width, height: mapRect.height)
            .position(x: mapRect.midX, y: mapRect.midY)
            .onTapGesture {
                if !session.started {
                    session.started = true
                } else {
                    session.paused = true
                }
            }
    }

    /// The ready gate: a big Play button on the map centre while the race is
    /// frozen before the start, so everyone can get their thumbs in place.
    /// Tapping the map (see `mapTapTarget`) starts the countdown; this is just
    /// the visible affordance that also teaches the "tap the map" gesture.
    private func readyOverlay(at point: CGPoint) -> some View {
        Image(systemName: "play.fill")
            .font(.system(size: 44))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 96, height: 96)
            .background(.black.opacity(0.45), in: Circle())
            .shadow(radius: 6)
            .position(point)
            .allowsHitTesting(false)
    }

    private func step(size: CGSize, mapRect: CGRect, safeInsets: EdgeInsets, time: TimeInterval) {
        rig.layout(size: size, mapRect: mapRect, safeInsets: safeInsets)
        game.applyControlTuning()
        session.advance(to: time)
        game.noteProgress()
        game.audioFrame()
    }

    /// Every active floating d-pad (Pro players), in its owner's color.
    private func padOverlays() -> [DPadOverlay] {
        rig.players.compactMap { controls in
            guard controls.scheme == .pro, let origin = controls.pro.origin else { return nil }
            return DPadOverlay(
                origin: origin,
                up: controls.pro.up,
                radius: controls.pro.radius,
                input: controls.pro.input(for: controls.player, at: session.race.tick),
                color: CouchGame.palette[controls.colorIndex]
            )
        }
    }

    /// Every active floating aim stick (Casual players), in its owner's color.
    private func aimOverlays() -> [AimOverlay] {
        rig.players.compactMap { controls in
            guard controls.scheme == .casual, let origin = controls.casual.origin else {
                return nil
            }
            return AimOverlay(
                origin: origin,
                knob: controls.casual.knob,
                radius: controls.casual.radius,
                color: CouchGame.palette[controls.colorIndex]
            )
        }
    }

    /// Zone outlines + corner tabs, only when the screen is shared.
    private func zoneChrome(safeInsets: EdgeInsets) -> [ZoneChrome] {
        rig.players.map { controls in
            ZoneChrome(
                rect: controls.zone,
                up: controls.up,
                color: CouchGame.palette[controls.colorIndex],
                safeInsets: safeInsets
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
    /// Screen safe-area insets, so the color tab can dodge the notch / home
    /// indicator even though the band itself is drawn full-bleed.
    var safeInsets: EdgeInsets
}
