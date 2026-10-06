#if os(macOS)
import AppKit
import SkidCore
import SwiftUI

extension KeyboardKey {
    /// The Mac's virtual key codes — PHYSICAL keys, independent of the layout,
    /// so the left-hand cluster stays under the left hand on AZERTY or Dvorak
    /// too, where "WASD" are not the letters printed on those caps.
    init?(macKeyCode code: UInt16) {
        switch code {
        case 0x0D: self = .w
        case 0x00: self = .a
        case 0x01: self = .s
        case 0x02: self = .d
        case 0x7E: self = .up
        case 0x7D: self = .down
        case 0x7B: self = .left
        case 0x7C: self = .right
        default: return nil
        }
    }
}

extension KeyEvent {
    /// What a Mac key event means to the game, if anything. A key held with
    /// ⌘ is a menu shortcut (⌘Q, ⌘T), never driving.
    init?(macKeyCode code: UInt16, down: Bool, command: Bool) {
        guard !command else { return nil }
        if let key = KeyboardKey(macKeyCode: code) {
            self = .drive(key, down: down)
            return
        }
        guard down else { return nil }
        switch code {
        case 0x31, 0x24: self = .start  // Space, Return
        case 0x35: self = .pause  // Escape
        default: return nil
        }
    }
}

extension View {
    /// **Drive with the keyboard.** Installs one app-wide key monitor for as
    /// long as the game's root view lives, and lets go of every key when the
    /// app stops being frontmost — a key-up that goes to another app never
    /// arrives here, and the car would drive on by itself.
    public func keyboardDriving(_ game: CouchGame) -> some View {
        modifier(KeyboardDrivingModifier(game: game))
    }
}

private struct KeyboardDrivingModifier: ViewModifier {
    let game: CouchGame
    @State private var monitor: Any?

    /// One key event: the game's if it means something during a race, the
    /// system's otherwise. Local monitors run on the main thread.
    private func route(_ event: NSEvent) -> NSEvent? {
        // A text field being edited (a track or player name) keeps every key:
        // its arrows move the caret and its Return commits.
        if event.window?.firstResponder is NSText { return event }
        let meaning = KeyEvent(
            macKeyCode: event.keyCode, down: event.type == .keyDown,
            command: event.modifierFlags.contains(.command))
        guard let meaning else { return event }
        let used = MainActor.assumeIsolated { game.handle(meaning) }
        return used ? nil : event
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                game.keyboardDriving = true
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.keyDown, .keyUp], handler: route)
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didResignActiveNotification)
            ) { _ in
                game.keyboard.releaseAll()
            }
    }
}

/// **The Mac's menu commands.** The tuning panel opens with ⌘T where a phone
/// would shake — the same notification, so the panel cannot tell the
/// difference, and like the shake it is absent from a build without the dials.
public struct SkidMacCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandMenu(Text("Game", bundle: .module)) {
            #if SKID_TUNING
            Button {
                NotificationCenter.default.post(name: ShakeToTune.shaken, object: nil)
            } label: {
                Text("Tuning Panel", bundle: .module)
            }
            .keyboardShortcut("t")
            #endif
        }
    }
}
#endif
