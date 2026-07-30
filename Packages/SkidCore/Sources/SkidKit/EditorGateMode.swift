import SkidCore
import SwiftUI

/// **Gating as a mode.** One map tap used to mean two things — select a loose end
/// or toggle a checkpoint — so a stray seam hit was a silent real edit. The mode
/// decides which meaning applies, and the toggle says which one is live.
extension EditorView {
    /// The mode switch. Gating is a MODE, not a tool, because it changes what a
    /// map tap means — so it is labelled, not just an icon.
    var modeToggle: some View {
        let gating = game.editorMode == .gate
        return Button {
            game.editorMode = gating ? .build : .gate
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "flag.checkered")
                Text(gating ? "Done" : "Gates", bundle: .module)
            }
            .font(.footnote.bold())
            .foregroundStyle(gating ? .black : .white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(gating ? Color.cyan : .black.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
            .contentShape(Capsule())
        }
        .accessibilityLabel(Text(gating ? "Leave gate mode" : "Edit gates", bundle: .module))
    }

    /// What gate mode is for, plus the count — a track needs the start line and at
    /// least one more gate to be saveable.
    @ViewBuilder
    func gateModeHint(_ walk: WalkResult) -> some View {
        let count = game.editorLayout?.gateSeams.count ?? 0
        Text(
            count < 2
                ? "Tap a seam to add a checkpoint — a track needs at least one"
                : "Tap seams to add or remove checkpoints",
            bundle: .module
        )
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(.black.opacity(0.35), in: Capsule())
    }

    /// The seam a tap means, if any is close enough to count.
    ///
    /// **Measured to the drawn gate LINE, not the seam's centre point.** A gate
    /// is a bar across the road, and that bar is what the author aims at — so a
    /// tap near either end of it counts, exactly as it looks. Measuring to the
    /// centre point made gates on a zoomed-out track nearly untappable: the
    /// canvas is 1600 units wide, so a whole track on a small phone draws at
    /// ~0.47 points per unit, putting adjacent seams 56 points apart with a
    /// 26-point hit circle each — narrower than a fingertip, and a tap that
    /// looked spot-on landed in a neighbour's circle instead.
    ///
    /// **Existing gates win ties**, because removing one is the harder gesture:
    /// a track carrying several gates has many seams to hit, and the one you
    /// can see is the one you meant.
    func seam(
        near point: CGPoint, walk: WalkResult, transform: EditorRenderer.Transform
    ) -> Int? {
        // Seam N is piece N's EXIT, so that exit is where the tap must land —
        // matching entries made every gate tap one piece early (the same
        // off-by-one the gate markers had). Piece 0's exit is the start line,
        // which is always a gate and not toggleable.
        var best: SeamHit?
        for (index, placed) in walk.placed.enumerated() where index != 0 {
            let distance = distanceToGateBar(of: placed, from: point, transform: transform)
            guard distance < EditorRenderer.endHitRadius else { continue }
            let candidate = SeamHit(
                seam: index, distance: distance, height: placed.exitHeight,
                isGate: game.editorIsGate(seam: index))
            guard let current = best else {
                best = candidate
                continue
            }
            best = preferred(candidate, over: current)
        }
        return best?.seam
    }

    /// Screen distance from `point` to the gate bar drawn across this piece's
    /// exit — the segment spanning the road, not its midpoint.
    private func distanceToGateBar(
        of placed: PlacedPiece, from point: CGPoint, transform: EditorRenderer.Transform
    ) -> CGFloat {
        let pose = placed.exits[0]
        let across = Vec2(angle: pose.heading.radians).perpendicular
        let half = across * (Double(PieceCatalog.width) / 2)
        let a = transform.screen(pose.position.vec2 - half)
        let b = transform.screen(pose.position.vec2 + half)
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > 0 else { return hypot(a.x - point.x, a.y - point.y) }
        // Project onto the bar, clamped to its ends.
        let t = max(
            0, min(1, ((point.x - a.x) * ab.x + (point.y - a.y) * ab.y) / lengthSquared))
        let closest = CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
        return hypot(closest.x - point.x, closest.y - point.y)
    }

    /// Which of two candidate seams a tap meant.
    private func preferred(_ candidate: SeamHit, over current: SeamHit) -> SeamHit {
        // A gate you can see beats an empty seam at a comparable distance —
        // removing a gate is the gesture that was impossible otherwise.
        if candidate.isGate != current.isGate {
            let gate = candidate.isGate ? candidate : current
            let empty = candidate.isGate ? current : candidate
            return gate.distance < empty.distance + EditorRenderer.endHitRadius / 2
                ? gate : empty
        }
        // Otherwise nearest wins, except between bars at the SAME SPOT, where
        // distance can't choose and height does: the one drawn on top is the
        // one being pointed at. "Same spot" is literal — a float-noise window,
        // since any two seams you can aim between are a piece apart.
        let coincident = abs(candidate.distance - current.distance) < 1
        if coincident {
            return candidate.height > current.height + 0.001 ? candidate : current
        }
        return candidate.distance < current.distance ? candidate : current
    }
}

/// A seam a tap could have meant: which one, how far off, and how high — the
/// height breaks ties where a bridge crosses a road.
private struct SeamHit {
    var seam: Int
    var distance: CGFloat
    var height: Double
    /// Whether this seam already carries a gate — a visible target, so it wins
    /// near-ties against empty seams.
    var isGate: Bool
}
