import SkidCore
import SwiftUI

/// **A small picture of a track**, drawn by the game's own renderer.
///
/// The thing a list of track *names* cannot tell you: whether it is a tight circuit or a
/// long sweeper, whether it climbs, whether you have driven it before. A library of a
/// dozen tracks called "My track 3" is unusable without this.
///
/// No image assets and nothing cached to disk: `EditorRenderer.drawTrack` already draws a
/// layout at any scale, so a thumbnail is that call in a smaller box. Which also means a
/// preview can never disagree with the track — it *is* the track, drawn by the same code
/// the editor and the race use.
struct TrackThumbnail: View {
    let layout: TrackLayout
    /// Drawn without gate markers or level badges: at this size they are noise, and the
    /// question a thumbnail answers is "what shape is this".
    var showsGates = false

    var body: some View {
        GeometryReader { geo in
            let walk = layout.walk()
            // A smaller margin than the editor's: a thumbnail wants the track to fill it,
            // and there is no chrome around the edges to leave room for.
            let transform = EditorRenderer.fit(walk: walk, in: geo.size, margin: 4)
            Canvas { context, _ in
                EditorRenderer.drawTrack(
                    walk: walk, width: Double(PieceCatalog.width),
                    gateSeams: showsGates ? layout.gateSeams : [],
                    decals: layout.decals, railed: layout.railed,
                    roadStyle: layout.roadStyle,
                    transform: transform, into: &context)
            }
        }
        .background(Color(red: 0.24, green: 0.47, blue: 0.20))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension TrackThumbnail {
    /// The layout behind a picker row, whichever kind of track it is.
    ///
    /// Built-ins live as share codes in `TrackLibrary`; a player's tracks live as codes in
    /// the library book. Both decode to a layout, so the thumbnail needs no idea which it
    /// is looking at. Nil when a code will not decode, which a caller shows as a blank
    /// rather than as an error: a corrupt row is not worth a dialog.
    static func layout(forTrackID id: String, library: TrackLibraryBook) -> TrackLayout? {
        if let builtin = TrackLibrary.builtins.first(where: { $0.id == id }) {
            return try? TrackCode.decode(builtin.code)
        }
        guard let entry = library.entry(id: id) else { return nil }
        return try? TrackCode.decode(entry.code)
    }
}
