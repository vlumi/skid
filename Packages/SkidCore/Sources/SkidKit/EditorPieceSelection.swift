import SkidCore
import SwiftUI

/// Selecting a piece on the map: hit-testing a tap to a piece, and the chrome that
/// hangs off the selection (the arrows that pick a build end, and delete).
extension EditorView {
    /// The piece a tap means: the one whose centerline passes nearest the point,
    /// within half a road width. Nil if the tap missed the road.
    ///
    /// Nearest-CENTERLINE rather than a bounding box, because pieces overlap at
    /// crossings and a box would claim taps on the road running under it.
    func piece(near point: CGPoint, walk: WalkResult, transform: EditorRenderer.Transform)
        -> Int?
    {
        let reach = Double(PieceCatalog.width) / 2 * transform.scale
        var best: (index: Int, distance: Double)?
        for (index, placed) in walk.placed.enumerated() {
            let samples = placed.centerlineSamples(degreesPerSample: 12)
            guard samples.count > 1 else { continue }
            for step in 1..<samples.count {
                let a = transform.screen(samples[step - 1])
                let b = transform.screen(samples[step])
                let d = distance(from: point, toSegment: a, b)
                guard d <= reach else { continue }
                if best == nil || d < best!.distance { best = (index, d) }
            }
        }
        return best?.index
    }

    private func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        return hypot(point.x - (a.x + dx * t), point.y - (a.y + dy * t))
    }

    /// Delete, anchored ON the selected piece rather than at a fixed spot.
    ///
    /// No build-end arrows: a piece has at most one free end (head at index 0, tail
    /// at the last), and selecting it already chooses that end — so the arrow was
    /// always the already-active one and tapping it did nothing. The construction
    /// marker shows which end is live.
    @ViewBuilder
    func selectionChrome(walk: WalkResult, transform: EditorRenderer.Transform) -> some View {
        if let index = game.editorSelectedPiece, walk.placed.indices.contains(index) {
            let placed = walk.placed[index]
            let anchor = transform.screen(placed.centerlineSamples().midpointSample)
            if game.editorCanDeleteSelected {
                mapAction("trash", tint: .white, label: "Delete piece") {
                    game.editorDeleteSelected()
                }
                .position(x: anchor.x, y: anchor.y - 34)
            }
        }
    }
}

extension Array where Element == Vec2 {
    /// The sample nearest the middle of the run — where chrome for a whole piece
    /// belongs, rather than at an end it might share with a neighbour.
    var midpointSample: Vec2 {
        isEmpty ? Vec2(0, 0) : self[count / 2]
    }
}
