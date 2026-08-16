import SkidCore
import SwiftUI

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
    let close: () -> Void

    @State private var name: String = ""

    var body: some View {
        ZStack {
            Retro.ground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    RetroTitle(Text("Track", bundle: .module))
                    namePanel
                    roadPanel
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
