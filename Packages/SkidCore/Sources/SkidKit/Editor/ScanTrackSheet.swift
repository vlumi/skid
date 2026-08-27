import SkidCore
import SwiftUI

/// **Pointing your phone at somebody else's screen.**
///
/// The camera half of sharing: they show the QR (`TrackShareSheet`), you scan it,
/// and the same offer sheet asks whether you want the track. No network on
/// either side — the whole road is in the code.
///
/// **The scan is the easy part; knowing when to stop is not.** A camera reports
/// the same code many times a second, so this takes the FIRST readable track and
/// then ignores everything, rather than re-offering the same track sixty times
/// while somebody holds the phone still.
struct ScanTrackSheet: View {
    @ObservedObject var game: CouchGame
    let dismiss: () -> Void

    /// Set once a track has been taken, so the stream of repeats is ignored.
    @State private var handled = false
    @State private var failure: String?
    /// A code that scanned cleanly but is not a track — worth saying, since the
    /// alternative is a camera that appears to ignore a perfectly good QR.
    @State private var notATrack = false

    var body: some View {
        ZStack {
            Retro.ground.ignoresSafeArea()
            VStack(spacing: 14) {
                retroLeaveRow(retroClose(dismiss)).padding(.horizontal, -16)
                RetroTitle(Text("Scan a track", bundle: .module))
                camera
                note
            }
            .padding(16)
            .frame(maxWidth: 460)
        }
    }

    @ViewBuilder private var camera: some View {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        if let failure {
            Text(verbatim: failure)
                .font(Retro.body)
                .foregroundStyle(Retro.danger)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 260)
                .retroPanel()
        } else {
            QRScannerView(onCode: scanned, onFailure: { failure = $0 })
                .frame(height: 300)
                .overlay(RetroBevel(thickness: 2))
        }
        #else
        // The Mac target has no capture session; the paste path covers importing
        // there, and pretending otherwise would be a dead camera view.
        Text("Scanning needs a camera.", bundle: .module)
            .font(Retro.body)
            .foregroundStyle(Retro.inkSoft)
            .frame(maxWidth: .infinity, minHeight: 260)
            .retroPanel()
        #endif
    }

    @ViewBuilder private var note: some View {
        if notATrack {
            Text("That code isn't a Skid Jam track.", bundle: .module)
                .font(Retro.caption)
                .foregroundStyle(Retro.danger)
        } else {
            Text("Point the camera at a track's QR code.", bundle: .module)
                .font(Retro.caption)
                .foregroundStyle(Retro.inkSoft)
        }
    }

    /// One code from the camera. Takes the first readable track and stops; a
    /// code that is not a track leaves the scanner running, since the next thing
    /// in frame may well be one.
    private func scanned(_ text: String) {
        guard !handled else { return }
        guard game.receive(scanned: text) else {
            notATrack = true
            return
        }
        handled = true
        dismiss()
    }
}
