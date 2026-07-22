import CoreGraphics
import Foundation
import SkidCore
import SwiftUI

/// Owns one instance of every prototyped control scheme and which one is
/// live — the in-run A/B switcher the find-the-fun milestone runs on.
@MainActor
public final class ControlRig: ObservableObject {
    public enum Scheme: CaseIterable {
        case dpad
        case slide
        case twoZone
        case oneTouch
    }

    @Published public private(set) var scheme: Scheme = .dpad

    public let dpad = VirtualDPadControlSource()
    public let slide = TouchPadControlSource()
    public let twoZone = TwoZoneControlSource()
    public let oneTouch = OneTouchControlSource()

    public init() {}

    public var active: TouchDrivenControlSource {
        switch scheme {
        case .dpad: return dpad
        case .slide: return slide
        case .twoZone: return twoZone
        case .oneTouch: return oneTouch
        }
    }

    public var label: LocalizedStringKey {
        switch scheme {
        case .dpad: return "D-pad"
        case .slide: return "Slide"
        case .twoZone: return "Two-zone"
        case .oneTouch: return "One-touch"
        }
    }

    /// The player's control zone, fed by the view's layout.
    public func updateBounds(_ rect: CGRect) {
        dpad.bounds = rect
        twoZone.bounds = rect
    }

    /// Switch to the next scheme, releasing any in-flight touch first.
    public func cycle() {
        active.touchEnded()
        let all = Scheme.allCases
        let index = all.firstIndex(of: scheme) ?? 0
        scheme = all[(index + 1) % all.count]
    }
}
