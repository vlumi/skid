import SkidCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// **The whole track's own settings: its name, and what kind of road it is.**
///
/// Reached by tapping the name above the map. That chip used to open a bare rename
/// alert, which was both the last native-looking control in the editor and the wrong
/// shape for what was coming: a road style is not a piece property, so it had nowhere to
/// live. Rather than add a second button for it, the name chip became the door to
/// everything that belongs to the track rather than to a piece.
///
/// Deliberately not a piece inspector. Anything here applies to the track as a whole and
/// keeps applying to pieces added afterwards — which is exactly what distinguishes these
/// from decals, and why lane markings ended up as a road style rather than paint you
/// place. See `TrackLayout.RoadStyle`.
struct TrackPropertiesSheet: View {
    @ObservedObject var game: CouchGame
    /// Called after a successful paste, so the editor can re-fit its view to the track
    /// that just replaced the canvas.
    var onPasted: () -> Void = {}
    let close: () -> Void

    @State private var name: String = ""
    @State private var copied = false
    @State private var pasteFailed = false

    var body: some View {
        ZStack {
            Retro.ground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    RetroTitle(Text("Track", bundle: .module))
                    namePanel
                    roadPanel
                    sharePanel
                }
                .padding(16)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
        .onAppear { name = game.editedTrackName ?? "" }
    }

    private var namePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            RetroHeading(Text("NAME", bundle: .module))
            TextField(String(localized: "Name", bundle: .module), text: $name)
                .nameFieldStyle()
                .font(Retro.body)
                .foregroundStyle(Retro.ink)
                .onSubmit(save)
                .padding(.horizontal, 8)
                .frame(minHeight: 40)
                .background(Retro.panel.opacity(0.55))
                .overlay(RetroBevel(inset: true, thickness: 2))
            // A brand-new canvas has no library row yet — nothing is written until there
            // is more than a start piece — so a name given now is remembered and applied
            // when the row appears. Saying so beats a disabled field.
            Text("Kept with the track once it is worth saving.", bundle: .module)
                .font(Retro.caption)
                .foregroundStyle(Retro.inkSoft)
        }
        .retroPanel()
    }

    private var roadPanel: some View {
        VStack(spacing: 8) {
            RetroHeading(Text("ROAD", bundle: .module))
            RetroChoice(
                label: Text("Circuit", bundle: .module),
                detail: Text("Purpose-built: bare asphalt", bundle: .module),
                selected: style == .circuit
            ) { game.setEditedRoadStyle(.circuit) }
            RetroChoice(
                label: Text("Road", bundle: .module),
                detail: Text("A public road, with a dashed centre line", bundle: .module),
                selected: style == .road
            ) { game.setEditedRoadStyle(.road) }
        }
        .retroPanel()
    }

    /// **The track's share code** — copy it out, or paste one in to replace the canvas.
    ///
    /// Moved here from the top bar: these are track-level operations used rarely, and
    /// with the attribution seal they were most of a bar row. The sheet is where the
    /// track's own things live. Copy and paste stay SEPARATE buttons — one that did
    /// both could silently replace the track you are working on.
    private var sharePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            RetroHeading(Text("SHARE", bundle: .module))
            attributionRow
            HStack(spacing: 8) {
                shareButton(
                    copied ? Text("Copied", bundle: .module) : Text("Copy code", bundle: .module)
                ) {
                    copyCode(signed: true)
                }
                // The short code drops the ~135-character signature — for links that
                // are disposable. Its own button, not a hidden long-press.
                shareButton(Text("Copy short", bundle: .module)) {
                    copyCode(signed: false)
                }
            }
            shareButton(Text("Paste code", bundle: .module)) {
                pasteCode()
            }
            if pasteFailed {
                Text("The clipboard doesn't hold a readable track code.", bundle: .module)
                    .font(Retro.caption)
                    .foregroundStyle(Retro.danger)
            } else {
                Text("Pasting replaces this track with the pasted one.", bundle: .module)
                    .font(Retro.caption)
                    .foregroundStyle(Retro.inkSoft)
            }
        }
        .retroPanel()
    }

    /// Who signed the track that was pasted in. Absent for an unsigned one, which is
    /// the norm — every built-in is unsigned, and saying so on each would be noise. A
    /// signature that does not verify DOES show: it is the only sign that a track was
    /// edited after signing.
    @ViewBuilder private var attributionRow: some View {
        let attribution = game.pastedAttribution
        if attribution.isWorthShowing {
            let broken = attribution == .broken
            HStack(spacing: 6) {
                Image(systemName: broken ? "seal.slash" : "seal")
                    .font(Retro.caption)
                attributionLabel(attribution)
                    .font(Retro.caption)
            }
            .foregroundStyle(broken ? Retro.danger : Retro.inkSoft)
        }
    }

    private func attributionLabel(_ attribution: TrackAttribution) -> Text {
        switch attribution {
        case .mine: return Text("Signed by you", bundle: .module)
        case .other: return Text("Signed", bundle: .module)
        case .broken: return Text("Signature doesn't match", bundle: .module)
        case .unsigned: return Text("Not signed", bundle: .module)
        }
    }

    private func shareButton(_ label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(Retro.caption)
                .foregroundStyle(Retro.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(Retro.panel.opacity(0.55))
                .overlay(RetroBevel(thickness: 2))
        }
        .buttonStyle(.plain)
    }

    private func copyCode(signed: Bool) {
        guard let code = game.shareCode(signed: signed) else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = code
        #endif
        copied = true
    }

    /// Load a track from a share code on the clipboard. On success the sheet closes,
    /// so the result is on screen rather than behind the sheet that caused it.
    private func pasteCode() {
        #if canImport(UIKit)
        guard let pasted = UIPasteboard.general.string,
            game.loadCustomTrack(code: pasted)
        else {
            pasteFailed = true
            return
        }
        pasteFailed = false
        // No centering needed: a share code carries the NORMALIZED layout, so a
        // pasted track arrives centered. The editor still re-fits its viewport.
        onPasted()
        close()
        #endif
    }

    private var style: TrackLayout.RoadStyle {
        game.editorLayout?.roadStyle ?? .circuit
    }

    private var footer: some View {
        Button {
            save()
            close()
        } label: {
            Text("DONE", bundle: .module).retroButton(wide: true)
        }
        .buttonStyle(.plain)
        .padding(16)
        .background(Retro.ground.opacity(0.96))
    }

    /// The road style applies as it is tapped; only the name needs committing, and an
    /// empty field means "leave it alone" rather than "clear it".
    private func save() {
        game.renameEditedTrack(to: name)
    }
}
