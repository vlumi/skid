import CoreGraphics
import Foundation
import SkidCore
import SwiftUI

/// One player's control kit: the two schemes (Casual + Pro), bound to that
/// player's zone (rect + `up` orientation) and color.
@MainActor
public final class PlayerControls {
    public let player: PlayerID
    public var colorIndex: Int
    /// This player's own control scheme (Casual/Pro) — each seat picks its own
    /// in setup, so one couch can mix aim and d-pad players.
    public var scheme: ControlScheme = .casual
    /// The full band box — reaches the physical screen edge, so the tinted
    /// fill + outline bleed past the safe area. Drives chrome + touch routing.
    public private(set) var zone = CGRect.zero
    /// The band's content region, clamped inside the safe area. The floating
    /// stick lives here and the lap/time chip sits on its map-side edge, so
    /// nothing the player must see or reach hides under the notch / home bar.
    public private(set) var content = CGRect.zero
    public private(set) var up = Vec2(0, -1)

    /// Pro: the direct steer/throttle d-pad (with flip-assist).
    public let pro = VirtualDPadControlSource()
    /// Casual: aim-to-drive.
    public let casual = AimControlSource()

    public init(player: PlayerID, colorIndex: Int) {
        self.player = player
        self.colorIndex = colorIndex
    }

    public func source(for scheme: ControlScheme) -> TouchDrivenControlSource {
        switch scheme {
        case .casual: return casual
        case .pro: return pro
        }
    }

    public func setZone(_ rect: CGRect, content: CGRect, up: Vec2) {
        zone = rect
        self.content = content
        self.up = up
        // The stick clamps to the content rect (inside the safe area), not the
        // full box — so full deflection is always reachable, never off-screen.
        pro.bounds = content.asRect
        pro.up = up
        casual.bounds = content.asRect
    }

    public func releaseAll() {
        for scheme in ControlScheme.allCases {
            source(for: scheme).releaseAll()
        }
    }
}

/// A quadrant of the shared screen. Bottom corners face up; top corners
/// face down (sitting across a tabletop device) — controls are
/// car-relative, so the zone's `up` is all that flips.
public enum ZoneCorner: CaseIterable, Sendable {
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight

    var isTopRow: Bool { self == .topLeft || self == .topRight }
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }

    func rect(in size: CGSize) -> CGRect {
        let w = size.width / 2
        let h = size.height / 2
        switch self {
        case .bottomLeft: return CGRect(x: 0, y: h, width: w, height: h)
        case .bottomRight: return CGRect(x: w, y: h, width: w, height: h)
        case .topLeft: return CGRect(x: 0, y: 0, width: w, height: h)
        case .topRight: return CGRect(x: w, y: 0, width: w, height: h)
        }
    }
}

/// How the players actually sit around the device — a setup choice, not a
/// guess: 2P picks side-by-side vs face-to-face, 3P picks which quadrant
/// stays open.
public struct SeatingConfig: Equatable, Sendable {
    /// 2P: false = side-by-side halves (couch), true = top/bottom halves
    /// facing each other (tabletop).
    public var faceToFace: Bool
    /// 3P: the quadrant left empty.
    public var openCorner: ZoneCorner

    public init(faceToFace: Bool = false, openCorner: ZoneCorner = .topLeft) {
        self.faceToFace = faceToFace
        self.openCorner = openCorner
    }
}

/// The shared-screen control rig: per-player zones, and multitouch routing —
/// a touch belongs to the zone it started in, for its whole life. Each player
/// drives their own scheme (Casual or Pro), chosen in setup.
@MainActor
public final class CouchRig {
    public private(set) var players: [PlayerControls]
    public let seating: SeatingConfig

    private var touchOwner: [TouchID: Int] = [:]
    private var lastSize: CGSize = .zero
    private var lastMapRect: CGRect = .zero
    private var lastInsets = EdgeInsets()
    private var lastDock = false

    /// `seats` names the cars these bands drive, defaulting to `0..<n` for a couch
    /// race where the local players ARE the whole field.
    ///
    /// **A networked device must pass its own seats.** Global seat numbers are
    /// assigned by the host, so the guest drives (say) 2 and 3 — and hardcoding
    /// `PlayerID(index)` meant every device built players 0 and 1. Both phones then
    /// steered the host's two cars, nobody published seats 2 and 3, and the clock
    /// waited for input that could never come: "waiting for iPhone", forever.
    /// Reported from device.
    public init(
        colorIndices: [Int], schemes: [ControlScheme] = [],
        seating: SeatingConfig = SeatingConfig(), seats: [PlayerID]? = nil
    ) {
        self.players = colorIndices.enumerated().map { index, colorIndex in
            let seat = seats?.indices.contains(index) == true ? seats![index] : PlayerID(index)
            let controls = PlayerControls(player: seat, colorIndex: colorIndex)
            controls.scheme = index < schemes.count ? schemes[index] : .casual
            return controls
        }
        self.seating = seating
    }

    /// Lay out control zones as **bands in the grass beside the map**, so
    /// the track (and everyone's fingers off it) stays clear. Each player's
    /// band sits "below the map from their point of view": the bottom gap
    /// for near-side players (up), the top gap for players across the table
    /// (down, rotated). `mapRect` is where the track sits on screen.
    /// The keyboard's bottom strip, in points: the HUD's height, no thumb room.
    public static let keyboardBand: CGFloat = 120

    /// `dockAtBottom`: everyone sits on ONE side — the keyboard's — so every
    /// band goes along the bottom edge, side by side, whatever the screen's
    /// shape. (Pair it with `fittedMapRect(bottomBand:)`, which leaves the
    /// strip.)
    public func layout(
        size: CGSize, mapRect: CGRect, safeInsets: EdgeInsets = EdgeInsets(),
        dockAtBottom: Bool = false
    ) {
        guard
            size != lastSize || mapRect != lastMapRect || safeInsets != lastInsets
                || dockAtBottom != lastDock
        else { return }
        lastDock = dockAtBottom
        lastSize = size
        lastMapRect = mapRect
        lastInsets = safeInsets
        // **Landscape puts the spare space at the SIDES** — a Mac window, an
        // iPad turned sideways — and `fittedMapRect` reserves it there. Bands
        // above and below a map that fills the height would be zero pixels
        // tall, so the zones (and the HUD in them) simply vanished.
        let bands =
            dockAtBottom
            ? bottomBands(size: size, mapRect: mapRect, safeInsets: safeInsets)
            : mapRect.minX > mapRect.minY
                ? sideBands(size: size, mapRect: mapRect, safeInsets: safeInsets)
                : portraitBands(size: size, mapRect: mapRect, safeInsets: safeInsets)
        for (index, player) in players.enumerated() where index < bands.count {
            player.setZone(bands[index].box, content: bands[index].content, up: bands[index].up)
        }
    }

    /// Bands above and below a map that fills the width (portrait).
    private func portraitBands(size: CGSize, mapRect: CGRect, safeInsets: EdgeInsets) -> [Band] {
        let w = size.width

        // Band that fills the bottom gap (near players) or top gap (far),
        // optionally just the left or right half for a same-side pair.
        // Returns the full box (to the physical edge) AND its content rect
        // (clamped inside the safe area): only the box bleeds past the notch.
        func band(top: Bool, half: Half) -> Band {
            // Fill the WHOLE gap between the screen edge and the map — max
            // touch area (the empty space between was wasted). The band runs
            // flush to the map edge; the seam pause sits on that boundary.
            let y = top ? 0 : mapRect.maxY
            let height = top ? mapRect.minY : size.height - mapRect.maxY
            let x: CGFloat
            let width: CGFloat
            switch half {
            case .full: x = 0; width = w
            case .left: x = 0; width = w / 2
            case .right: x = w / 2; width = w / 2
            }
            let box = CGRect(x: x, y: y, width: width, height: height)
            // The content rect pulls the box's edges in by the safe insets on
            // the sides that touch the physical screen edge (never the map-side
            // edge — that's already clear of any inset).
            let content = CGRect(
                x: box.minX + (x <= 0 ? safeInsets.leading : 0),
                y: box.minY + (top ? safeInsets.top : 0),
                width: box.width
                    - (x <= 0 ? safeInsets.leading : 0)
                    - (x + width >= w ? safeInsets.trailing : 0),
                height: box.height - (top ? safeInsets.top : safeInsets.bottom))
            return Band(box: box, content: content, up: top ? down : up)
        }

        switch players.count {
        case 1:
            return [band(top: false, half: .full)]
        case 2 where seating.faceToFace:
            return [band(top: false, half: .full), band(top: true, half: .full)]
        case 2:
            return [band(top: false, half: .left), band(top: false, half: .right)]
        case 3:
            let corners = ZoneCorner.allCases.filter { $0 != seating.openCorner }
            return corners.map { corner in
                band(top: corner.isTopRow, half: corner.isLeft ? .left : .right)
            }
        default:
            return ZoneCorner.allCases.map { corner in
                band(top: corner.isTopRow, half: corner.isLeft ? .left : .right)
            }
        }
    }

    /// Every band below the map, side by side in seat order (P1 on the left,
    /// where WASD sits), the whole strip from the map down to the screen edge.
    private func bottomBands(size: CGSize, mapRect: CGRect, safeInsets: EdgeInsets) -> [Band] {
        let count = max(1, players.count)
        let width = size.width / Double(count)
        return (0..<count).map { index in
            let box = CGRect(
                x: Double(index) * width, y: mapRect.maxY,
                width: width, height: size.height - mapRect.maxY)
            let first = index == 0, last = index == count - 1
            let content = CGRect(
                x: box.minX + (first ? safeInsets.leading : 0), y: box.minY,
                width: box.width - (first ? safeInsets.leading : 0)
                    - (last ? safeInsets.trailing : 0),
                height: box.height - safeInsets.bottom)
            return Band(box: box, content: content, up: up)
        }
    }

    /// Bands left and right of a map that fills the height. Everyone faces
    /// screen-up: the long edge is where people sit. One player takes the
    /// left; two split left/right (WASD under the left hand is P1, so P1's
    /// box is on the left too); three or four stack two to a side, in the
    /// same corner order the portrait layout uses.
    private func sideBands(size: CGSize, mapRect: CGRect, safeInsets: EdgeInsets) -> [Band] {
        func band(left: Bool, rows: ClosedRange<Int> = 0...1) -> Band {
            let x = left ? 0 : mapRect.maxX
            let width = left ? mapRect.minX : size.width - mapRect.maxX
            let y = rows.lowerBound == 0 ? 0 : size.height / 2
            let height = size.height / 2 * Double(rows.count)
            let box = CGRect(x: x, y: y, width: width, height: height)
            let topEdge = rows.lowerBound == 0, bottomEdge = rows.upperBound == 1
            let content = CGRect(
                x: box.minX + (left ? safeInsets.leading : 0),
                y: box.minY + (topEdge ? safeInsets.top : 0),
                width: box.width - (left ? safeInsets.leading : safeInsets.trailing),
                height: box.height - (topEdge ? safeInsets.top : 0)
                    - (bottomEdge ? safeInsets.bottom : 0))
            return Band(box: box, content: content, up: up)
        }
        switch players.count {
        case 1:
            return [band(left: true)]
        case 2:
            return [band(left: true), band(left: false)]
        default:
            let corners =
                players.count == 3
                ? ZoneCorner.allCases.filter { $0 != seating.openCorner } : ZoneCorner.allCases
            return corners.map { corner in
                band(left: corner.isLeft, rows: corner.isTopRow ? 0...0 : 1...1)
            }
        }
    }

    private let up = Vec2(0, -1)
    private let down = Vec2(0, 1)

    private enum Half { case full, left, right }

    /// One player's band: the full box (to the physical edge, so its fill
    /// bleeds past the notch) and the content rect (inside the safe area).
    private struct Band {
        var box: CGRect
        var content: CGRect
        var up: Vec2
    }

    public func touchBegan(id: TouchID, at location: Vec2) {
        let point = CGPoint(x: location.x, y: location.y)
        guard let index = players.firstIndex(where: { $0.zone.contains(point) }) else { return }
        touchOwner[id] = index
        let player = players[index]
        player.source(for: player.scheme).touchBegan(id: id, at: location)
    }

    public func touchMoved(id: TouchID, at location: Vec2) {
        guard let index = touchOwner[id] else { return }
        let player = players[index]
        player.source(for: player.scheme).touchMoved(id: id, at: location)
    }

    public func touchEnded(id: TouchID) {
        guard let index = touchOwner.removeValue(forKey: id) else { return }
        let player = players[index]
        player.source(for: player.scheme).touchEnded(id: id)
    }
}
