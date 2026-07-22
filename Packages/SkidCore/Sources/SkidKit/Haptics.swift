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

/// Player-facing toggles + the control-tuning playground, persisted across
/// launches. The tuning dials exist to be A/B-ed on device before the
/// scheme verdict — they may shrink once the feel is settled.
@MainActor
public final class GameSettings: ObservableObject {
    @AppStorage("skid.sound") public var soundOn = true
    @AppStorage("skid.haptics") public var hapticsOn = true

    // D-pad feel (applied live, every frame).
    @AppStorage("skid.dpad.deadzone") public var dpadDeadzone = 10.0
    @AppStorage("skid.dpad.travel") public var dpadTravel = 48.0
    /// Steps per axis; 0 = fully analog.
    @AppStorage("skid.dpad.steps") public var dpadSteps = 3
    /// Response curve; 1 = linear, higher = softer near center.
    @AppStorage("skid.dpad.expo") public var dpadExpo = 1.0

    /// Game pace for learning: scales acceleration + speed caps (agility
    /// stays). Applies on the next race (Reset). Hiscores only record at
    /// full pace.
    @AppStorage("skid.pace") public var pace = 1.0

    public init() {}
}
