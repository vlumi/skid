import SkidCore
import SwiftUI

/// The whole screen: the track fitted to the view, the race HUD, one
/// full-screen touch surface feeding the active control scheme, and the
/// in-run scheme switcher for on-device A/B.
public struct GameView: View {
    @StateObject private var session: GameSession
    @StateObject private var rig: ControlRig

    public init() {
        let rig = ControlRig()
        _rig = StateObject(wrappedValue: rig)
        _session = StateObject(wrappedValue: GameSession(controlSource: rig.active))
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
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
                    let marks = session.marks
                    let pad = padOverlay()
                    ZStack {
                        Canvas { context, size in
                            var world = context
                            TrackRenderer.draw(race: race, marks: marks, into: &world, size: size)
                            if let pad {
                                TrackRenderer.drawDPad(pad, into: &context)
                            }
                        }
                        RaceHUD(race: race)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            rig.active.touchChanged(
                                at: Vec2(value.location.x, value.location.y))
                        }
                        .onEnded { _ in
                            rig.active.touchEnded()
                        }
                )
            }
            .ignoresSafeArea()

            HStack(spacing: 10) {
                Button {
                    rig.cycle()
                    session.controlSource = rig.active
                } label: {
                    pill(Text(rig.label, bundle: .module))
                }
                Button {
                    session.reset()
                } label: {
                    pill(Text("Reset", bundle: .module))
                }
            }
            .padding()
        }
        .statusBarHiddenIfAvailable()
        .persistentSystemOverlays(.hidden)
    }

    private func step(size: CGSize, time: TimeInterval) {
        rig.updateBounds(CGRect(origin: .zero, size: size))
        session.advance(to: time)
    }

    /// The floating d-pad, when it's the active scheme and a thumb is down.
    private func padOverlay() -> DPadOverlay? {
        guard rig.scheme == .dpad, let origin = rig.dpad.origin else { return nil }
        return DPadOverlay(
            origin: origin,
            up: rig.dpad.up,
            radius: rig.dpad.radius,
            input: rig.dpad.input(for: session.player, at: session.race.tick),
            color: TrackRenderer.playerColor(0)
        )
    }

    private func pill(_ text: Text) -> some View {
        text
            .font(.callout.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.35), in: Capsule())
            .foregroundStyle(.white)
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

/// Countdown, lap counter, and timing — minimal, in the classics' spirit.
struct RaceHUD: View {
    let race: Race

    var body: some View {
        ZStack {
            if case .countdown(let remaining) = race.phase {
                Text(verbatim: "\((remaining + Race.tickRate - 1) / Race.tickRate)")
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            } else if race.raceTicks < Race.tickRate * 3 / 4 {
                Text("GO!", bundle: .module)
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let progress = race.cars.first?.progress, let laps = race.config.laps {
                    Text("Lap \(min(progress.lap + 1, laps))/\(laps)", bundle: .module)
                        .font(.headline.monospacedDigit())
                    Text(verbatim: formatTicks(currentTicks(progress)))
                        .font(.title3.monospacedDigit().bold())
                    if let best = progress.bestLapTicks {
                        Text("Best \(formatTicks(best))", bundle: .module)
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
            .foregroundStyle(.white)
            .shadow(radius: 2)
            .padding(.leading, 16)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }

    private func currentTicks(_ progress: CarProgress) -> Tick {
        if let finished = progress.finishedAt {
            return finished - race.config.countdownTicks
        }
        return race.raceTicks
    }
}

extension View {
    fileprivate func statusBarHiddenIfAvailable() -> some View {
        #if os(iOS)
        return statusBarHidden(true)
        #else
        return self
        #endif
    }
}
