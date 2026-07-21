import SkidCore
import SwiftUI

/// The whole v0.1 screen: the track fitted to the view, the car, the marks,
/// and one full-screen touch surface feeding the arcade touch-pad.
public struct GameView: View {
    @StateObject private var session: GameSession
    private let touchPad: TouchPadControlSource

    public init() {
        let pad = TouchPadControlSource()
        touchPad = pad
        _session = StateObject(wrappedValue: GameSession(controlSource: pad))
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            TimelineView(.animation) { timeline in
                // Step the sim on the main actor, then hand the Canvas plain
                // value copies — its renderer closure is not MainActor.
                // (`let _ =` is the ViewBuilder side-effect idiom; a bare
                // `_ =` isn't a valid result-builder statement.)
                // swiftlint:disable:next redundant_discardable_let
                let _ = session.advance(to: timeline.date.timeIntervalSinceReferenceDate)
                let race = session.race
                let marks = session.marks
                Canvas { context, size in
                    TrackRenderer.draw(race: race, marks: marks, into: &context, size: size)
                }
            }
            .ignoresSafeArea()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        touchPad.touchMoved(x: value.location.x)
                    }
                    .onEnded { _ in
                        touchPad.touchEnded()
                    }
            )

            Button {
                session.reset()
            } label: {
                Text("Reset", bundle: .module)
                    .font(.callout.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.35), in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding()
        }
        .statusBarHiddenIfAvailable()
        .persistentSystemOverlays(.hidden)
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
