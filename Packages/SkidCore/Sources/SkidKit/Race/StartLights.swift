import SkidCore
import SwiftUI

/// **The start gantry: five lights that fill up, then go out.**
///
/// Replaces a big "3 · 2 · 1 · GO!". Numbers were the obvious thing and the wrong one on
/// a shared screen: a **3** upside down is not a 3, so the countdown had to be drawn
/// twice, mirrored, once for each side of the table. Lights have no such problem — the
/// row is symmetric, so one set reads the same from every seat, and a four-way game
/// needs no fourth copy for the players sitting sideways.
///
/// The sequence is the circuit-racing one: lights come **on** as the seconds pass, and
/// the start is all of them going **out** at once. Nothing turns green, because nothing
/// needs to: "the lights went out" is the most legible event on the screen, and it is a
/// change of everything at once rather than a small color swap somebody could miss.
///
/// ```text
///   3s   ● ○ ○ ○ ●     (the outer pair)
///   2s   ● ● ○ ● ●     (and the inner pair)
///   1s   ● ● ● ● ●     (and the middle)
///   GO   ○ ○ ○ ○ ○     — drive
/// ```
///
/// **Filled in mirrored pairs, outside in**, so every state is left–right symmetric.
/// Filling from one end would read forwards from one side of the table and backwards
/// from the other — the exact problem the numbers had.
struct StartLights: View {
    /// Seconds left, 3…1. Zero or less is the start itself: every light dark.
    let secondsRemaining: Int
    /// Briefly true right after the start, so the gantry stays on screen with its lights
    /// out — the "out" state is the signal, and a gantry that vanished at the same
    /// instant would leave nothing to have gone out.
    let started: Bool

    /// Five, like a real gantry, and odd so there is a middle to fill last.
    static let count = 5

    /// **Which lamps are lit with `seconds` left** — the pattern, without the view, so
    /// the suite can hold the property the whole design rests on: every state reads the
    /// same upside down.
    static func pattern(secondsRemaining seconds: Int) -> [Bool] {
        (0..<count).map { index in
            guard seconds > 0 else { return false }
            let ring = abs(index - count / 2)
            return ring >= seconds - 1
        }
    }

    var body: some View {
        // **Sized to be noticed, not to blanket the track.** The first pass used 26pt
        // lamps in a 14pt frame, which on the SE spanned the start line and both cars —
        // a countdown you have to see past. Smaller lamps and a tighter frame keep it
        // unmissable while leaving the grid visible underneath.
        HStack(spacing: 6) {
            ForEach(0..<Self.count, id: \.self) { index in
                lamp(lit: isLit(index))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Retro.ground.opacity(0.8))
        .overlay(RetroBevel(thickness: 2))
    }

    /// A lamp's "ring" is its distance from the middle: 2 for the outermost pair, 1 for
    /// their neighbours, 0 for the center. Outer rings light first, and because a ring is
    /// a mirrored PAIR, every state is symmetric — which is the whole point.
    private func isLit(_ index: Int) -> Bool {
        Self.pattern(secondsRemaining: secondsRemaining)[index]
    }

    private func lamp(lit: Bool) -> some View {
        Rectangle()
            .fill(lit ? Retro.danger : Retro.ink.opacity(0.55))
            .frame(width: 16, height: 16)
            .overlay(RetroBevel(inset: !lit, thickness: 2))
    }
}
