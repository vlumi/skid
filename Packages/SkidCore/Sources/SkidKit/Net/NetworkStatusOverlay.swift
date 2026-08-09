import SkidCore
import SwiftUI

/// **What the network is doing, on screen, while you race.**
///
/// The spike's instrument panel. Not a nicety: a lockstep race that stops moving
/// is indistinguishable from a crash unless something says *why*, and a desync is
/// invisible unless something says it happened. Both are the outcomes worth
/// knowing about, and both are otherwise silent.
///
/// Stays quiet when everything is fine — a permanent readout would just be noise
/// once the design is trusted.
struct NetworkStatusOverlay: View {
    /// Plain values, not an `@ObservedObject`. These are updated on every simulated
    /// tick, so observing them would publish from inside the render pass — which
    /// froze the app solid. `RaceScreen` redraws every frame via `TimelineView`
    /// anyway, so reading them as values is both correct and sufficient.
    let divergenceNote: String?
    let stallNote: String?

    var body: some View {
        VStack(spacing: 8) {
            // A desync means the whole design does not work. Loud, and sticky:
            // it does not clear, because everything after it is fiction.
            if let note = divergenceNote {
                banner(note, tint: .red)
            }
            // A stall names who it is waiting for, so "frozen" becomes "Ville's
            // phone went away" — actionable rather than mysterious.
            if let note = stallNote {
                banner(note, tint: .orange)
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private func banner(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(tint.opacity(0.85), in: Capsule())
            .shadow(radius: 4)
    }
}
