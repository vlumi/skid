import Foundation
import SkidCore

/// Arcade touch-pad, the first scheme: thumb down = gas, horizontal offset
/// from touch-start = steer, release = coast. One touch, car-relative.
/// A reference type so the gesture layer can mutate it while the game loop
/// reads it; the sim only ever sees the `CarInput` values.
public final class TouchPadControlSource: ControlSource, ObservableObject {
    /// Horizontal thumb travel (points) for full steer.
    public var steerTravel: Double = 70

    private var touchStartX: Double?
    private var currentX: Double = 0
    private var touching = false

    public init() {}

    public func touchBegan(x: Double) {
        touchStartX = x
        currentX = x
        touching = true
    }

    public func touchMoved(x: Double) {
        if touchStartX == nil { touchStartX = x }
        currentX = x
        touching = true
    }

    public func touchEnded() {
        touchStartX = nil
        touching = false
    }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        guard touching, let startX = touchStartX else { return .coast }
        return CarInput(steer: (currentX - startX) / steerTravel, throttle: 1)
    }
}

/// One-touch scheme, stubbed to exercise the swap seam early: permanent gas,
/// touch = turn left. Radically simple; promoted or cut by the A/B milestone.
public final class OneTouchControlSource: ControlSource {
    private var touching = false

    public init() {}

    public func touchBegan(x: Double) { touching = true }
    public func touchMoved(x: Double) { touching = true }
    public func touchEnded() { touching = false }

    public func input(for player: PlayerID, at tick: Tick) -> CarInput {
        CarInput(steer: touching ? -1 : 0, throttle: 1)
    }
}
