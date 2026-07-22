import Foundation
import SkidCore
import SwiftUI

/// Impact taps and a finish flourish, from the same deterministic
/// `RaceEvent` stream the audio uses. iOS only; a no-op elsewhere.
@MainActor
public final class Haptics {
    #if os(iOS)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notice = UINotificationFeedbackGenerator()
    #endif

    public init() {}

    public func play(events: [RaceEvent], humanCount: Int) {
        #if os(iOS)
        for event in events {
            switch event {
            case .wallImpact(let id, let speed) where id.rawValue < humanCount:
                if speed > 200 {
                    heavy.impactOccurred()
                } else {
                    light.impactOccurred()
                }
            case .carImpact(let a, let b, _)
            where a.rawValue < humanCount || b.rawValue < humanCount:
                heavy.impactOccurred(intensity: 0.8)
            case .finished(let id) where id.rawValue < humanCount:
                notice.notificationOccurred(.success)
            default:
                break
            }
        }
        #endif
    }
}

/// Player-facing toggles, persisted across launches. Small on purpose —
/// only what a couch session needs.
@MainActor
public final class GameSettings: ObservableObject {
    @AppStorage("skid.sound") public var soundOn = true
    @AppStorage("skid.haptics") public var hapticsOn = true

    public init() {}
}
