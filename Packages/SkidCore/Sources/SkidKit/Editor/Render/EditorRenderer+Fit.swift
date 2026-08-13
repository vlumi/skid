import SkidCore
import SwiftUI

/// **Fitting a track's footprint into a box.**
///
/// Extracted from `EditorView` so the thumbnail and the editor size a track the same
/// way. They differ only in what they do afterwards — the editor multiplies in zoom and
/// adds pan; a thumbnail takes the fit as-is — so the shared part is the *bounds* and the
/// scale that lands them in the box.
///
/// Worth sharing rather than reimplementing: a preview that framed a track differently
/// from the editor would show the author something other than what they built, and the
/// half-width padding below is the kind of detail that silently goes missing in a second
/// copy.
extension EditorRenderer {
    /// The world-space box a laid-out track occupies, padded by the road's half-width so
    /// the edges are not clipped to the centerline.
    static func footprint(of walk: WalkResult) -> CGRect {
        let points = walk.placed.flatMap { placed in
            placed.piece.paths.indices.flatMap { placed.centerlineSamples(path: $0) }
        }
        let half = Double(PieceCatalog.width) / 2
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = (xs.min() ?? 0) - half
        let maxX = (xs.max() ?? 100) + half
        let minY = (ys.min() ?? 0) - half
        let maxY = (ys.max() ?? 100) + half
        return CGRect(
            x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    /// A transform that centers `walk` in `view`, scaled to fit inside `margin`.
    ///
    /// `zoom` and `pan` are the editor's; a thumbnail passes neither.
    static func fit(
        walk: WalkResult, in view: CGSize, margin: CGFloat = 40,
        zoom: CGFloat = 1, pan: CGSize = .zero
    ) -> Transform {
        let box = footprint(of: walk)
        let usable = CGSize(
            width: max(1, view.width - 2 * margin), height: max(1, view.height - 2 * margin))
        let scale = min(usable.width / box.width, usable.height / box.height) * zoom
        return Transform(
            scale: scale,
            offset: CGSize(
                width: view.width / 2 - box.midX * scale + pan.width,
                height: view.height / 2 - box.midY * scale + pan.height))
    }
}
