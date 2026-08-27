import SkidCore
import SwiftUI

/// **Handing a track to somebody standing next to you.**
///
/// The QR is the point: two phones, one screen pointed at the other, no typing
/// and no network. The link and the code are the same track in the forms that
/// travel through a message or a clipboard — one sheet, three ways out, because
/// which one a player wants depends on who they are giving it to rather than on
/// anything the app knows.
///
/// The whole track rides in the code, so nothing here talks to a server and none
/// of it can rot.
struct TrackShareSheet: View {
    let name: String
    let code: String
    let dismiss: () -> Void

    @State private var copied: Copied?

    private enum Copied { case link, code }

    /// The link this track travels as. Nil only for an empty code, which the
    /// library cannot produce.
    private var url: URL? { TrackLink.url(code: code, name: name) }

    var body: some View {
        ZStack {
            Retro.ground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    retroLeaveRow(retroClose(dismiss)).padding(.horizontal, -16)
                    RetroTitle(Text(verbatim: name))
                    qrPanel
                    copyPanel
                }
                .padding(16)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var qrPanel: some View {
        VStack(spacing: 10) {
            RetroHeading(Text("POINT A PHONE AT THIS", bundle: .module))
            if let url {
                QRCodeView(text: url.absoluteString)
            }
            Text("The whole track is in the code — no internet needed.", bundle: .module)
                .font(Retro.caption)
                .foregroundStyle(Retro.inkSoft)
                .multilineTextAlignment(.center)
        }
        .retroPanel()
    }

    private var copyPanel: some View {
        VStack(spacing: 8) {
            RetroHeading(Text("OR SEND IT", bundle: .module))
            // The link first: it is the form that works for somebody who does not
            // have the app yet, since the site can show them the track.
            shareButton(
                copied == .link
                    ? Text("Copied", bundle: .module) : Text("Copy link", bundle: .module)
            ) {
                guard let url else { return }
                Clipboard.copy(url.absoluteString)
                copied = .link
            }
            // The bare code stays, because it is what the editor's paste box
            // takes and what a previous build's users already have.
            shareButton(
                copied == .code
                    ? Text("Copied", bundle: .module) : Text("Copy code", bundle: .module)
            ) {
                Clipboard.copy(code)
                copied = .code
            }
        }
        .retroPanel()
    }

    private func shareButton(_ label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label.retroButton(wide: true)
        }
        .buttonStyle(.plain)
    }
}
