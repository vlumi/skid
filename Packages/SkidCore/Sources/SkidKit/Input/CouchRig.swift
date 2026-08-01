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
        pro.bounds = content
        pro.up = up
        casual.bounds = content
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
public final class CouchRig: ObservableObject {
    public private(set) var players: [PlayerControls]
    public let seating: SeatingConfig

    private var touchOwner: [TouchID: Int] = [:]
    private var lastSize: CGSize = .zero
    private var lastMapRect: CGRect = .zero
    private var lastInsets = EdgeInsets()

    public init(
        colorIndices: [Int], schemes: [ControlScheme] = [],
        seating: SeatingConfig = SeatingConfig()
    ) {
        self.players = colorIndices.enumerated().map { index, colorIndex in
            let controls = PlayerControls(player: PlayerID(index), colorIndex: colorIndex)
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
    public func layout(size: CGSize, mapRect: CGRect, safeInsets: EdgeInsets = EdgeInsets()) {
        guard size != lastSize || mapRect != lastMapRect || safeInsets != lastInsets else { return }
        lastSize = size
        lastMapRect = mapRect
        lastInsets = safeInsets
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

        let bands: [Band]
        switch players.count {
        case 1:
            bands = [band(top: false, half: .full)]
        case 2 where seating.faceToFace:
            bands = [band(top: false, half: .full), band(top: true, half: .full)]
        case 2:
            bands = [band(top: false, half: .left), band(top: false, half: .right)]
        case 3:
            let corners = ZoneCorner.allCases.filter { $0 != seating.openCorner }
            bands = corners.map { corner in
                band(top: corner.isTopRow, half: corner.isLeft ? .left : .right)
            }
        default:
            bands = ZoneCorner.allCases.map { corner in
                band(top: corner.isTopRow, half: corner.isLeft ? .left : .right)
            }
        }
        for (index, player) in players.enumerated() where index < bands.count {
            player.setZone(bands[index].box, content: bands[index].content, up: bands[index].up)
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
