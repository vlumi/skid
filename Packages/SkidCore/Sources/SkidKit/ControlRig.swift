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
        case oneTouch
    }

    @Published public private(set) var scheme: Scheme = .dpad

    public let dpad = VirtualDPadControlSource()
    public let slide = TouchPadControlSource()
    public let oneTouch = OneTouchControlSource()

    public init() {}

    public var active: TouchDrivenControlSource {
        switch scheme {
        case .dpad: return dpad
        case .slide: return slide
        case .oneTouch: return oneTouch
        }
    }

    public var label: LocalizedStringKey {
        switch scheme {
        case .dpad: return "D-pad"
        case .slide: return "Slide"
        case .oneTouch: return "One-touch"
        }
    }

    /// Switch to the next scheme, releasing any in-flight touch first.
    public func cycle() {
        active.touchEnded()
        let all = Scheme.allCases
        let index = all.firstIndex(of: scheme) ?? 0
        scheme = all[(index + 1) % all.count]
    }
}
