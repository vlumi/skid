#if os(macOS)
import AppKit
import SwiftUI
import XCTest

@testable import SkidCore
@testable import SkidKit

/// **A tournament line-up is drawn on ARRIVAL, not only on a switch.** The
/// setup screen draws it with `onChange(of: mode, initial: true)`, which must
/// fire when the screen appears already in tournament mode (a restored setup,
/// a launch argument) — or the line-up shows empty and the mode looks broken.
/// Only a real, hosted screen runs that modifier.
@MainActor
final class SetupLineupHostedTests: XCTestCase {
    func testArrivingInTournamentModeDrawsTheLineUp() {
        let couch = CouchGame(
            signingKeys: NoSigningKey(),
            libraryFilename: "lineup-\(UUID().uuidString).json",
            profileFilename: "lineup-\(UUID().uuidString).json",
            setupFilename: "lineup-\(UUID().uuidString).json")
        couch.mode = .tournament
        couch.pendingTournamentTracks = []
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 900), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SetupView(game: couch))
        window.contentView?.layoutSubtreeIfNeeded()
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(
            couch.pendingTournamentTracks.isEmpty, "arriving in tournament mode drew no line-up")
    }
}
#endif
