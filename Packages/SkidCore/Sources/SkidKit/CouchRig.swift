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

    public func layout(size: CGSize) {
        guard size != lastSize else { return }
        lastSize = size
        let up = Vec2(0, -1)
        let down = Vec2(0, 1)
        let w = size.width
        let h = size.height
        let rects: [(CGRect, Vec2)]
        switch players.count {
        case 1:
            rects = [(CGRect(x: 0, y: 0, width: w, height: h), up)]
        case 2 where seating.faceToFace:
            rects = [
                (CGRect(x: 0, y: h / 2, width: w, height: h / 2), up),
                (CGRect(x: 0, y: 0, width: w, height: h / 2), down),
            ]
        case 2:
            rects = [
                (CGRect(x: 0, y: 0, width: w / 2, height: h), up),
                (CGRect(x: w / 2, y: 0, width: w / 2, height: h), up),
            ]
        case 3:
            let corners = ZoneCorner.allCases.filter { $0 != seating.openCorner }
            rects = corners.map { corner in
                (corner.rect(in: size), corner.isTopRow ? down : up)
            }
        default:
            rects = ZoneCorner.allCases.map { corner in
                (corner.rect(in: size), corner.isTopRow ? down : up)
            }
        }
        for (index, player) in players.enumerated() where index < rects.count {
            player.setZone(rects[index].0, up: rects[index].1)
        }
    }

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
