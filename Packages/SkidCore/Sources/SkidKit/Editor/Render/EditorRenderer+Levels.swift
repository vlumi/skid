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
    /// What the badge pass is asked to show — the mode, the focus, the warnings.
    struct BadgeQuery {
        var blockedPieces: Set<Int>
        var showLevels: Bool
        var onlyLevel: Int?
    }

    /// One badge on the plan (see `levelBadges`), with the drawing split by kind.
    static func drawLevelBadges(
        walk: WalkResult, query: BadgeQuery, transform t: Transform,
        into context: inout GraphicsContext
    ) {
        for badge in levelBadges(walk: walk, query: query, transform: t) {
            if badge.blocked {
                drawBlockedBadge(at: badge.at, level: badge.level, t: t, into: &context)
            } else {
                drawLevelBadge(at: badge.at, level: badge.level, t: t, into: &context)
            }
        }
    }

    /// One planned badge — split from the drawing so the plan is testable.
    struct LevelBadge: Equatable {
        var at: CGPoint
        var level: Int
        var blocked: Bool
    }

    /// **Which pieces get a badge, and where** — a warning on any piece a car could
    /// not drive through, plus (in Levels mode) a level number on EVERY piece.
    ///
    /// Level 0 is badged too. It used to be skipped as noise, but the mode is
    /// something you keep on while building a multi-level track — reported: turn it
    /// on from the start, before the first climb exists, and it showed nothing.
    ///
    /// With a single storey chosen (`onlyLevel`), the other storeys' numbers are
    /// dropped so the chosen one can be read alone; the blocked warnings stay, since
    /// they show even with the mode off.
    ///
    /// **A badge covered by a higher badge is dropped.** Where pieces stack (a deck
    /// over a road), both badges landed on the same spot and read as neither
    /// (reported from device); the top-most piece's number is the one you can act
    /// on. Warnings are never dropped and cover anything under them.
    static func levelBadges(
        walk: WalkResult, query: BadgeQuery, transform t: Transform
    ) -> [LevelBadge] {
        var badges: [LevelBadge] = []
        for (index, placed) in walk.placed.enumerated() {
            let level = Track.level(of: max(placed.entryHeight, placed.exitHeight))
            let blocked = query.blockedPieces.contains(index)
            guard blocked || query.showLevels else { continue }
            if !blocked, let onlyLevel = query.onlyLevel, level != onlyLevel { continue }
            guard let at = badgeAnchor(placed, t: t) else { continue }
            badges.append(LevelBadge(at: at, level: level, blocked: blocked))
        }
        return dropCovered(badges, minDistance: max(7, 11 * t.scale) * 2.1)
    }

    /// The greedy cover pass: warnings first, then higher levels; anything landing
    /// within `minDistance` of an already-kept badge is dropped (warnings never are).
    static func dropCovered(_ badges: [LevelBadge], minDistance: Double) -> [LevelBadge] {
        let ordered = badges.enumerated().sorted { a, b in
            if a.element.blocked != b.element.blocked { return a.element.blocked }
            if a.element.level != b.element.level { return a.element.level > b.element.level }
            return a.offset < b.offset
        }.map(\.element)
        var kept: [LevelBadge] = []
        for badge in ordered {
            let covered = kept.contains { keep in
                hypot(keep.at.x - badge.at.x, keep.at.y - badge.at.y) < minDistance
            }
            if badge.blocked || !covered {
                kept.append(badge)
            }
        }
        return kept
    }

    /// The middle of the piece's own road, in screen space — so a badge sits on the
    /// piece it describes rather than at a seam it shares with a neighbor.
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

    /// A blocked piece gets the same badge in warning colors, with its level still
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
