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
    public private(set) var zone = CGRect.zero
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

    public func setZone(_ rect: CGRect, up: Vec2) {
        zone = rect
        self.up = up
        pro.bounds = rect
        pro.up = up
        casual.bounds = rect
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
/// a touch belongs to the zone it started in, for its whole life. The scheme
/// is global — every player drives the same one (Casual or Pro).
@MainActor
public final class CouchRig: ObservableObject {
    @Published public private(set) var scheme: ControlScheme = .casual

    public private(set) var players: [PlayerControls]
    public let seating: SeatingConfig

    private var touchOwner: [TouchID: Int] = [:]
    private var lastSize: CGSize = .zero
    private var lastMapRect: CGRect = .zero

    public init(
        colorIndices: [Int], scheme: ControlScheme = .casual,
        seating: SeatingConfig = SeatingConfig()
    ) {
        self.players = colorIndices.enumerated().map { index, colorIndex in
            PlayerControls(player: PlayerID(index), colorIndex: colorIndex)
        }
        self.scheme = scheme
        self.seating = seating
    }

    /// Lay out control zones as **bands in the grass beside the map**, so
    /// the track (and everyone's fingers off it) stays clear. Each player's
    /// band sits "below the map from their point of view": the bottom gap
    /// for near-side players (up), the top gap for players across the table
    /// (down, rotated). `mapRect` is where the track sits on screen.
    public func layout(size: CGSize, mapRect: CGRect) {
        guard size != lastSize || mapRect != lastMapRect else { return }
        lastSize = size
        lastMapRect = mapRect
        let w = size.width

        // Band that fills the bottom gap (near players) or top gap (far),
        // optionally just the left or right half for a same-side pair.
        func band(top: Bool, half: Half) -> (CGRect, Vec2) {
            let gapTop = top ? 0 : mapRect.maxY
            let gapHeight = top ? mapRect.minY : size.height - mapRect.maxY
            let height = min(gapHeight, Self.maxBandHeight)
            // Sit against the screen edge (the player's near side).
            let y = top ? gapTop : gapTop + (gapHeight - height)
            let x: CGFloat
            let width: CGFloat
            switch half {
            case .full: x = 0; width = w
            case .left: x = 0; width = w / 2
            case .right: x = w / 2; width = w / 2
            }
            return (CGRect(x: x, y: y, width: width, height: height), top ? down : up)
        }

        let rects: [(CGRect, Vec2)]
        switch players.count {
        case 1:
            rects = [band(top: false, half: .full)]
        case 2 where seating.faceToFace:
            rects = [band(top: false, half: .full), band(top: true, half: .full)]
        case 2:
            rects = [band(top: false, half: .left), band(top: false, half: .right)]
        case 3:
            let corners = ZoneCorner.allCases.filter { $0 != seating.openCorner }
            rects = corners.map { corner in
                band(top: corner.isTopRow, half: corner.isLeft ? .left : .right)
            }
        default:
            rects = ZoneCorner.allCases.map { corner in
                band(top: corner.isTopRow, half: corner.isLeft ? .left : .right)
            }
        }
        for (index, player) in players.enumerated() where index < rects.count {
            player.setZone(rects[index].0, up: rects[index].1)
        }
    }

    private let up = Vec2(0, -1)
    private let down = Vec2(0, 1)
    /// Cap the band so a wide gap doesn't make a needlessly tall control
    /// strip; the floating stick needs ~132pt, this leaves comfortable room.
    private static let maxBandHeight: CGFloat = 200

    private enum Half { case full, left, right }

    public func touchBegan(id: TouchID, at location: Vec2) {
        let point = CGPoint(x: location.x, y: location.y)
        guard let index = players.firstIndex(where: { $0.zone.contains(point) }) else { return }
        touchOwner[id] = index
        players[index].source(for: scheme).touchBegan(id: id, at: location)
    }

    public func touchMoved(id: TouchID, at location: Vec2) {
        guard let index = touchOwner[id] else { return }
        players[index].source(for: scheme).touchMoved(id: id, at: location)
    }

    public func touchEnded(id: TouchID) {
        guard let index = touchOwner.removeValue(forKey: id) else { return }
        players[index].source(for: scheme).touchEnded(id: id)
    }

    /// Switch every player to the next scheme, releasing in-flight touches.
    public func cycleScheme() {
        for player in players {
            player.releaseAll()
        }
        touchOwner.removeAll()
        let all = ControlScheme.allCases
        let index = all.firstIndex(of: scheme) ?? 0
        scheme = all[(index + 1) % all.count]
    }

    public var schemeLabel: LocalizedStringKey {
        switch scheme {
        case .casual: return "Casual"
        case .pro: return "Pro"
        }
    }
}
