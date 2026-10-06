import SkidCore
import SwiftUI

/// **Driving from a keyboard.** The Mac shell turns key codes into these and
/// hands them over; everything about what a key MEANS lives here, where it is
/// testable, and the platform layer only translates.
public enum KeyEvent: Equatable, Sendable {
    /// A driving key went down or came up.
    case drive(KeyboardKey, down: Bool)
    /// Space or Return: off the ready gate.
    case start
    /// Escape: in and out of the pause menu.
    case pause
}

extension CouchGame {
    /// Apply a key, and say whether the game used it. A used key is swallowed
    /// so the system does not beep at it; an unused one passes through, so a
    /// text field in the editor still types.
    ///
    /// Keys only drive during a race. A key-UP always lands, though — let go of
    /// a key as the results card appears and it must not stay held into the
    /// rematch.
    @discardableResult
    public func handle(_ event: KeyEvent) -> Bool {
        let racing = phase == .racing && session != nil
        switch event {
        case .drive(let key, let down):
            if down {
                guard racing else { return false }
                keyboard.press(key)
            } else {
                keyboard.release(key)
                guard racing else { return false }
            }
            return true
        // During a race these keys are the game's even when they change
        // nothing (Space after the start, Escape before it): passed through,
        // the system would answer each one with its error beep.
        case .start:
            guard racing, let session else { return false }
            if !session.started { session.startOrPause() }
            return true
        case .pause:
            guard racing, let session else { return false }
            session.togglePause()
            return true
        }
    }

    /// The input tap's view of the keyboard: a seat-indexed lookup when this
    /// device drives with keys, nil when it drives with touch. Built once per
    /// race, so the per-tick closure never reaches back into the game.
    func keyboardSource(humans: Int) -> ((Int) -> KeyboardControlSource?)? {
        guard keyboardDriving else { return nil }
        let keys = keyboard
        keys.humans = humans
        // A fresh race starts with nothing held: a key-up that went to a
        // menu (or to another app) must not leave a car driving itself.
        keys.releaseAll()
        return { keys.source(forSeat: $0) }
    }
}
