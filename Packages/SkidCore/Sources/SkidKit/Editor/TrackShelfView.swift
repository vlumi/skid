import SkidCore
import SwiftUI

/// **Your tracks: open one, copy one, or start something new.**
///
/// The editor's front door, and the thing that was missing: the library has stored many
/// tracks since v0.6.0, but the editor had one buffer restored from one slot — so every
/// track was raceable and exactly one was editable. Edits flowed *to* the library and
/// nothing flowed back.
///
/// Two distinctions this screen makes that the model already supported:
///
/// - **Unfinished tracks belong here and nowhere else.** An entry that does not compile is
///   kept by the library and withheld from the race picker; this is where you get back to
///   it. That is what "scratchpads" turned out to be — no new storage kind, just rows the
///   racing side declines to offer.
/// - **Open versus start-a-copy.** Editing *moves* a track: an entry's id is a hash of its
///   own content, so an edit writes a new row and drops the old one, carrying the name
///   over. Starting a copy claims no row, so the first edit writes a fresh entry and the
///   original is untouched — which is also the only way to open a **built-in**, since those
///   ship in the binary and have no row to claim. A copy you never edit leaves no trace,
///   which is the honest outcome: there is nothing yet to distinguish it from its source.
struct TrackShelfView: View {
    @ObservedObject var game: CouchGame
    let dismiss: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ZStack {
            Color(red: 0.28, green: 0.55, blue: 0.23).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    newTrackButton

                    if !game.library.tracks.isEmpty {
                        section(Text("Yours", bundle: .module)) {
                            // Every entry, finished or not — unlike the race picker.
                            ForEach(game.library.byRecency) { entry in
                                tile(entry: entry)
                            }
                        }
                    }

                    section(Text("Start from a built-in", bundle: .module)) {
                        ForEach(TrackLibrary.builtins, id: \.id) { builtin in
                            builtinTile(builtin)
                        }
                    }
                }
                .padding(16)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                dismiss()
            } label: {
                Text("Back", bundle: .module)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white.opacity(0.92), in: Capsule())
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    private var newTrackButton: some View {
        Button {
            game.newTrackForEditing()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").font(.title3)
                Text("New track", bundle: .module).font(.headline)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white.opacity(0.92), in: Capsule())
        }
    }

    private func section(
        _ title: Text, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            title
                .font(.subheadline.bold())
                .foregroundStyle(.white.opacity(0.8))
            LazyVGrid(columns: columns, spacing: 12) { content() }
        }
    }

    private func tile(entry: TrackLibraryBook.Entry) -> some View {
        let layout = try? TrackCode.decode(entry.code)
        return Menu {
            Button {
                game.openForEditing(entryID: entry.id)
                dismiss()
            } label: {
                Label {
                    Text("Edit", bundle: .module)
                } icon: {
                    Image(systemName: "pencil")
                }
            }
            Button {
                game.startFrom(code: entry.code, name: entry.name)
                dismiss()
            } label: {
                Label {
                    Text("Start a copy", bundle: .module)
                } icon: {
                    Image(systemName: "plus.square.on.square")
                }
            }
            Button(role: .destructive) {
                game.deleteTrack(id: entry.id)
            } label: {
                Label {
                    Text("Delete", bundle: .module)
                } icon: {
                    Image(systemName: "trash")
                }
            }
        } label: {
            card(
                layout: layout, name: entry.name,
                // The one thing a picture cannot say: whether this ring closes. An
                // unfinished track is not a fault, it is where you left off.
                note: entry.isRaceable ? nil : Text("Unfinished", bundle: .module))
        }
    }

    private func builtinTile(_ builtin: TrackLibrary.Builtin) -> some View {
        Button {
            game.startFrom(
                code: builtin.code, name: TrackLibrary.displayName(id: builtin.id))
            dismiss()
        } label: {
            card(
                layout: try? TrackCode.decode(builtin.code),
                name: TrackLibrary.displayName(id: builtin.id),
                note: Text("Copy", bundle: .module))
        }
    }

    private func card(layout: TrackLayout?, name: String, note: Text?) -> some View {
        VStack(spacing: 6) {
            if let layout {
                TrackThumbnail(layout: layout)
                    .frame(height: 96)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.25))
                    .frame(height: 96)
            }
            Text(verbatim: name)
                .font(.footnote.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
            if let note {
                note
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(6)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    }
}
