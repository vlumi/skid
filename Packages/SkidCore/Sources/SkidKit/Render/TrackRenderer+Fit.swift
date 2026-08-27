import SkidCore
import SwiftUI

/// **Where the map goes on the screen, and how much paint reaches past it.**
/// Split out of `TrackRenderer` on the file-length limit; a coherent seam,
/// since everything here is layout arithmetic and nothing draws.
extension TrackRenderer {
    /// Where the track sits on screen — the one primitive the renderer, the
    /// pause button, and the control-band layout all key off.
    ///
    /// Allocation rule: **controls get a guaranteed minimum first, the map
    /// fills what's left, and any space the map's aspect can't use goes back
    /// to the controls** (so bands are never below `minBand`, the map is as
    /// big as it can be in the leftover, and there's never dead grass between
    /// map and bands). Works off the **safe-area** usable rect, so the notch
    /// and home indicator never eat into the reserved minimum.
    /// `screenPadding` reserves room, PER SIDE, for paint that reaches past
    /// the track's world bounds (see `drawnOverhang`) — a raised road is drawn
    /// wider than its nominal width and casts an offset shadow, and both once
    /// leaked into the control bands. The returned rect is still the world
    /// mapping; the padding only guarantees the overflow stays out of the
    /// bands and on screen.
    static func fittedMapRect(
        trackSize: Vec2, in screen: CGSize, safeInsets: EdgeInsets = EdgeInsets(),
        minBand: CGFloat = 150, screenPadding: EdgeInsets = EdgeInsets()
    ) -> CGRect {
        // Usable region: the screen minus the safe-area insets.
        let usable = CGRect(
            x: safeInsets.leading, y: safeInsets.top,
            width: screen.width - safeInsets.leading - safeInsets.trailing,
            height: screen.height - safeInsets.top - safeInsets.bottom)
        // Tracks are wide, so on portrait the bands are top/bottom and the
        // map is height-constrained by the leftover between them; on a wide
        // (landscape) usable area the map may instead be width-constrained.
        // Reserve minBand on the two sides the bands occupy, fit the map in
        // the remaining box, then center it — the surplus falls to the bands.
        let portrait = usable.height >= usable.width
        // The padding is PER SIDE, so the map is centred inside the box the
        // padding leaves — not inside the usable rect — or an edge that needs
        // shadow room would shove the whole world off-centre.
        let horizontal = screenPadding.leading + screenPadding.trailing
        let vertical = screenPadding.top + screenPadding.bottom
        let box =
            portrait
            ? CGRect(
                x: usable.minX + screenPadding.leading,
                y: usable.minY + minBand + screenPadding.top,
                width: max(1, usable.width - horizontal),
                height: max(1, usable.height - 2 * minBand - vertical))
            : CGRect(
                x: usable.minX + minBand + screenPadding.leading,
                y: usable.minY + screenPadding.top,
                width: max(1, usable.width - 2 * minBand - horizontal),
                height: max(1, usable.height - vertical))
        let scale = min(box.width / trackSize.x, box.height / trackSize.y)
        let fitted = CGSize(width: trackSize.x * scale, height: trackSize.y * scale)
        return CGRect(
            x: box.minX + (box.width - fitted.width) / 2,
            y: box.minY + (box.height - fitted.height) / 2,
            width: fitted.width, height: fitted.height)
    }

    /// **How far the DRAWN track reaches past its world bounds, per side**, in
    /// screen points at `scale`.
    ///
    /// A raised deck is drawn wider than its nominal width (the height
    /// perspective) with its rail outside that, and casts a shadow offset
    /// right and down (see `drawPieceShadow`: 6·h across, 11·h down). Each
    /// edge is padded by what actually overflows IT: every centerline point
    /// above ground contributes its drawn extent minus its distance to that
    /// edge, and the shadow only ever reaches the trailing and bottom edges.
    /// A flat track pads nothing; a raised road hugging one edge pads that
    /// edge alone.
    ///
    /// Was one uniform number on all four sides, sized for the highest deck as
    /// if it hugged every edge. Invisible while grass ran to the screen edge,
    /// it became a navy frame around every elevated track the moment grass
    /// stopped at the world — a tall figure-eight with nothing raised near its
    /// top or bottom wore padding there for no reason.
    static func drawnOverhang(track: Track, scale: Double) -> EdgeInsets {
        guard track.deckTops.count == track.centerline.count else { return EdgeInsets() }
        let nominal = Double(track.width) / 2
        let rail = Double(PieceCatalog.kerbBand)
        var leading = 0.0, trailing = 0.0, top = 0.0, bottom = 0.0
        for (point, height) in zip(track.centerline, track.deckTops) where height > 0 {
            // World-unit reach of the drawn road at this height, past the
            // centerline, then how much of it lies outside each edge.
            let extent = nominal * Elevation.scale(atHeight: height) + rail
            let paint = extent * scale
            let shadowAcross = 6.0 * height, shadowDown = 11.0 * height
            leading = max(leading, paint - point.x * scale)
            top = max(top, paint - point.y * scale)
            trailing = max(trailing, paint + shadowAcross - (track.size.x - point.x) * scale)
            bottom = max(bottom, paint + shadowDown - (track.size.y - point.y) * scale)
        }
        // A hair of slack on any side that overflows at all, rounded UP to a
        // whole point: the layer cache renders the grown rect into an image of
        // whole pixels and blits it back at the rect, and a fractional rect
        // resampled that image — measured as a vertical drift growing toward
        // the padded edge, 77 of 83 mismatched samples in the bottom half.
        func pad(_ v: Double) -> CGFloat { v > 0 ? ceil(CGFloat(v) + 2) : 0 }
        return EdgeInsets(
            top: pad(top), leading: pad(leading), bottom: pad(bottom), trailing: pad(trailing))
    }
}

extension CGRect {
    /// This rect plus per-side padding — the map plus the paint that reaches
    /// past it, which is the rect the control bands must stay clear of.
    func grown(by insets: EdgeInsets) -> CGRect {
        CGRect(
            x: minX - insets.leading, y: minY - insets.top,
            width: width + insets.leading + insets.trailing,
            height: height + insets.top + insets.bottom)
    }
}
