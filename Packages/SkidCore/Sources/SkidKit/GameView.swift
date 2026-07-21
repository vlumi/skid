import SkidCore
import SwiftUI

/// The whole v0.1 screen: the track fitted to the view, the car, the marks,
/// one full-screen touch surface feeding the active control scheme, and the
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
                    Canvas { context, size in
                        var world = context
                        TrackRenderer.draw(race: race, marks: marks, into: &world, size: size)
                        if let pad {
                            TrackRenderer.drawDPad(pad, into: &context)
                        }
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
        rig.dpad.bounds = CGRect(origin: .zero, size: size)
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

extension View {
    fileprivate func statusBarHiddenIfAvailable() -> some View {
        #if os(iOS)
        return statusBarHidden(true)
        #else
        return self
        #endif
    }
}
