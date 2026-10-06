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
    /// so the system does not beep at it; an unused one passes through.
    ///
    /// **Two meanings for the same keys.** While a race is being DRIVEN —
    /// waiting at the ready gate included — the keys drive: arrows and WASD
    /// steer, Space starts, Escape pauses. Everywhere else, a paused or
    /// finished race included, they are the menus' (see `menuKey`). A key-UP
    /// always reaches the driving keys, so a key let go on the results card is
    /// not held into the rematch.
    @discardableResult
    public func handle(_ event: KeyEvent) -> Bool {
        if case .drive(let key, false) = event { keyboard.release(key) }
        guard let session, phase == .racing, !session.paused, session.race.phase != .finished
        else { return menuKey(event) }
        switch event {
        case .drive(let key, let down):
            if down { keyboard.press(key) }
            return true
        // During a race these keys are the game's even when they change
        // nothing (Space after the start): passed through, the system would
        // answer each one with its error beep.
        case .start:
            if !session.started { session.startOrPause() }
            return true
        case .pause:
            session.togglePause()
            return true
        }
    }

    /// **Keys in a menu**: arrows (or WASD) move the highlight, Enter or Space
    /// presses it, Escape takes the surface's way out — and resumes a paused
    /// race, which is what Escape opened. Nothing is used when no surface is
    /// listening, so the system keeps the key.
    private func menuKey(_ event: KeyEvent) -> Bool {
        // Escape closes the pause menu it opened, whether or not that menu's
        // buttons are listening yet.
        if case .pause = event, let session, phase == .racing, session.paused {
            session.togglePause()
            return true
        }
        guard let scope = menus.active else { return false }
        switch event {
        case .drive(let key, let down):
            guard down else { return false }
            scope.move(key.focusDirection)
        case .start:
            scope.activate()
        case .pause:
            scope.cancel()
        }
        return true
    }

    /// The input tap's view of the keyboard: a seat's input — at the
    /// keyboard's own turn rate — when this device drives with keys, nil when
    /// it drives with touch. Built once per race, so the per-tick closure
    /// never reaches back into the game.
    func keyboardSource(humans: Int) -> ((Int, PlayerID, Race) -> CarInput)? {
        guard keyboardDriving else { return nil }
        let keys = keyboard
        keys.humans = humans
        // A fresh race starts with nothing held: a key-up that went to a
        // menu (or to another app) must not leave a car driving itself.
        keys.releaseAll()
        return { seat, player, race in
            guard let source = keys.source(forSeat: seat),
                let car = race.cars.first(where: { $0.id == player })
            else { return .coast }
            return KeyboardSteering.scaled(
                source.input(for: player, at: race.tick), car: car.state,
                tuning: race.tuning, keyTurnRate: keys.turnRate)
        }
    }
}

extension KeyboardKey {
    /// The menu direction a driving key means: arrows as themselves, WASD as
    /// the same four under the left hand.
    var focusDirection: FocusDirection {
        switch drive {
        case .gas: return .up
        case .brake: return .down
        case .left: return .left
        case .right: return .right
        }
    }
}
