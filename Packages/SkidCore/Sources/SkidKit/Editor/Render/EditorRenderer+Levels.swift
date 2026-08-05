import SkidCore
import SwiftUI

/// **Which storey each piece sits on, and where the road is walled off.**
///
/// Both are author aids rather than part of the track: badges say "you are on level
/// 2 here" while building tall, and a blockage marker says "a car cannot get through
/// this piece". Neither gates anything — a blocked track still races, because the
/// only thing validation gates is whether a track appears in the picker, and making
/// it vanish with no explanation is worse than driving into the wall and seeing it.
extension EditorRenderer {
    /// A level badge on every piece that is off the ground, plus a warning on any
    /// piece a car could not drive through.
    ///
    /// Drawn in its own pass ABOVE all road: per-piece, a deck crossing over a lower
    /// piece would paint out that piece's badge — the same fault the decals and the
    /// start line both had.
    ///
    /// Only off-ground pieces are badged. Labelling every piece "0" on a flat track
    /// is noise, and the ground is the case you can already see.
    static func drawLevelBadges(
        walk: WalkResult, blockedPieces: Set<Int>, transform t: Transform,
        into context: inout GraphicsContext
    ) {
        for (index, placed) in walk.placed.enumerated() {
            let level = Track.level(of: max(placed.entryHeight, placed.exitHeight))
            let blocked = blockedPieces.contains(index)
            guard level != 0 || blocked else { continue }
            guard let at = badgeAnchor(placed, t: t) else { continue }
            if blocked {
                drawBlockedBadge(at: at, level: level, t: t, into: &context)
            } else {
                drawLevelBadge(at: at, level: level, t: t, into: &context)
            }
        }
    }

    /// The middle of the piece's own road, in screen space — so a badge sits on the
    /// piece it describes rather than at a seam it shares with a neighbour.
    private static func badgeAnchor(_ placed: PlacedPiece, t: Transform) -> CGPoint? {
        let samples = placed.centerlineSamples(degreesPerSample: 20)
        guard !samples.isEmpty else { return nil }
        return t.screen(samples[samples.count / 2])
    }

    private static func drawLevelBadge(
        at: CGPoint, level: Int, t: Transform, into context: inout GraphicsContext
    ) {
        let radius = max(7, 11 * t.scale)
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: at.x - radius, y: at.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(.black.opacity(0.45)))
        context.draw(
            Text(verbatim: "\(level)")
                .font(.system(size: max(9, 13 * t.scale), weight: .heavy))
                .foregroundColor(.white),
            at: at, anchor: .center)
    }

    /// A blocked piece gets the same badge in warning colours, with its level still
    /// legible — the level is usually *why* it is blocked.
    private static func drawBlockedBadge(
        at: CGPoint, level: Int, t: Transform, into context: inout GraphicsContext
    ) {
        let radius = max(9, 13 * t.scale)
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: at.x - radius, y: at.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(blockedTint))
        context.stroke(
            Path(
                ellipseIn: CGRect(
                    x: at.x - radius, y: at.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(.white.opacity(0.9)), lineWidth: max(1.5, 2 * t.scale))
        context.draw(
            Text(verbatim: level == 0 ? "!" : "\(level)")
                .font(.system(size: max(10, 14 * t.scale), weight: .heavy))
                .foregroundColor(.white),
            at: at, anchor: .center)
    }

    /// Warning amber: reads as "look at this" without the finality of red, which the
    /// editor uses for nothing else yet.
    static let blockedTint = Color(red: 0.85, green: 0.42, blue: 0.05)
}

extension EditorRenderer {
    /// A veil over every storey but one, for when the editor is working on a single
    /// level.
    ///
    /// Veiled rather than hidden: the other storeys are still where the track is, and
    /// a map that omits them would misrepresent the road. Dimming says "not this one"
    /// while keeping the shape readable.
    static func drawOtherStoreyVeil(
        walk: WalkResult, keeping storey: Int, t: Transform,
        into context: inout GraphicsContext
    ) {
        var veil = Path()
        for placed in walk.placed {
            let top = max(placed.entryHeight, placed.exitHeight)
            guard Track.level(of: top) != storey else { continue }
            let samples = placed.centerlineSamples(degreesPerSample: 12)
            guard samples.count > 1 else { continue }
            var line = Path()
            line.move(to: t.screen(samples[0]))
            samples.dropFirst().forEach { line.addLine(to: t.screen($0)) }
            // The road's own drawn width, so the veil covers the asphalt and its kerb
            // rather than a nominal stripe down the middle.
            let width =
                Double(PieceCatalog.width) * Elevation.scale(atHeight: top) * t.scale
            veil.addPath(
                line.strokedPath(
                    StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)))
        }
        context.fill(veil, with: .color(.black.opacity(0.42)))
    }
}
