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
    let stallNote: String?
    /// The client's measured link quality, small and dim — spike instrumentation,
    /// not product chrome.
    let linkNote: String?
    /// The real top safe-area inset, from the layout that still knows it.
    let topInset: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            // A stall names who it is waiting for, so "frozen" becomes "Ville's
            // phone went away" — actionable rather than mysterious.
            if let note = stallNote {
                banner(note, tint: .orange)
            }
            if let note = linkNote {
                Text(note)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        // **Below the notch.** `RaceScreen` works in full-screen coordinates and
        // ignores the safe area, so a top-aligned banner sits UNDER the Dynamic
        // Island — a desync WAS reported from device as "no banner" when it had in
        // fact fired and was hidden there. The inset is passed in rather than read
        // from the environment, because this view is inside a full-bleed stack that
        // has already discarded it (and `safeAreaPadding` is iOS 17+, while the
        // deployment target is 16).
        .padding(.top, topInset + 8)
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
