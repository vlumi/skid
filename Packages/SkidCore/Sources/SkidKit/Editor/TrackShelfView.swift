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
    /// **Leaving without choosing** — back to wherever the shelf was opened from.
    let back: () -> Void
    /// **A track was chosen**, so the canvas opens regardless of how we got here.
    ///
    /// Separate from `back` on purpose: the two were one closure, and making Back
    /// context-aware silently turned every "open this track" into "return to the menu"
    /// as well. Picking a track and backing out are opposite intents and now say so.
    let openCanvas: () -> Void

    /// The track being renamed, and the name being typed. Held together so the field cannot
    /// outlive the row it belongs to.
    @State private var renaming: TrackLibraryBook.Entry?
    @State private var newName = ""
    /// What the last "add from clipboard" did, shown until the next one.
    @State private var importOutcome: CouchGame.ImportOutcome?
    /// Whether the camera scanner is open.
    @State private var scanning = false
    /// The track being shared, if any — its QR, link and code.
    ///
    /// Opens on the first track under `-skid-share`, for the same reason the
    /// other screenshot arguments exist: `simctl` cannot tap a context menu, so
    /// this sheet is otherwise unreachable for a screenshot.
    @State private var sharing: TrackLibraryBook.Entry?
    private let shareOnAppear = LaunchFlag.consume("-skid-share")

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ZStack {
            Retro.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // **Titled, because this is a destination now** rather than a
                    // step inside the editor: it is reached from the front door
                    // (top → tracks → editor) and needs to say where you are.
                    // Back rides the same corner as every other screen.
                    retroBack(back)
                    RetroTitle(Text("Tracks", bundle: .module))
                    HStack(spacing: 10) {
                        newTrackButton
                        addTrackButton
                    }
                    scanButton
                    if let outcome = importOutcome {
                        importNote(outcome)
                    }

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
        // An alert rather than a sheet: one field and two buttons, and a sheet would cover
        // the tile whose name is being changed.
        .alert(
            Text("Rename track", bundle: .module),
            isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } })
        ) {
            TextField(String(localized: "Name", bundle: .module), text: $newName)
                .nameFieldStyle()
            Button {
                if let entry = renaming { game.renameTrack(id: entry.id, to: newName) }
                renaming = nil
            } label: {
                Text("Rename", bundle: .module)
            }
            Button(role: .cancel) {
                renaming = nil
            } label: {
                Text("Cancel", bundle: .module)
            }
        }
        .onAppear {
            if shareOnAppear, sharing == nil { sharing = game.library.tracks.first }
        }
        .sheet(isPresented: $scanning) {
            ScanTrackSheet(game: game) { scanning = false }
        }
        .sheet(
            isPresented: Binding(
                get: { sharing != nil },
                set: { if !$0 { sharing = nil } })
        ) {
            if let entry = sharing {
                TrackShareSheet(name: entry.name, code: entry.code) { sharing = nil }
            }
        }
    }

    private var newTrackButton: some View {
        Button {
            game.newTrackForEditing()
            openCanvas()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").font(.title3)
                Text("New track", bundle: .module).font(Retro.body)
            }
            .foregroundStyle(Retro.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Retro.panel)
            .overlay(RetroBevel(thickness: 2))
        }
    }

    /// **Taking a track IN**, beside making one — the two ways the library
    /// grows, so they sit together rather than one being hidden in a menu.
    private var addTrackButton: some View {
        Button {
            importOutcome = game.importTrack(fromPasted: Clipboard.paste() ?? "")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down").font(.title3)
                Text("Add from clipboard", bundle: .module).font(Retro.caption)
            }
            .foregroundStyle(Retro.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Retro.panel)
            .overlay(RetroBevel(thickness: 2))
        }
    }

    /// **The camera path.** Its own row rather than crowded in beside the other
    /// two: it is the one somebody uses standing next to the person sharing, and
    /// the other two are for a link that arrived some other way.
    private var scanButton: some View {
        Button {
            scanning = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "qrcode.viewfinder").font(.title3)
                Text("Scan a QR code", bundle: .module).font(Retro.caption)
            }
            .foregroundStyle(Retro.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Retro.panel)
            .overlay(RetroBevel(thickness: 2))
        }
    }

    /// What the last import did. Named rather than silent: a paste that appears
    /// to do nothing is the same to a player as a broken button.
    @ViewBuilder private func importNote(_ outcome: CouchGame.ImportOutcome) -> some View {
        switch outcome {
        case .added(let name):
            note(Text("Added \(name).", bundle: .module), bad: false)
        case .alreadyHave(let name):
            // Not a failure: the same code twice is the same road.
            note(Text("You already have this one — \(name).", bundle: .module), bad: false)
        case .unreadable:
            note(
                Text("The clipboard doesn't hold a track link or code.", bundle: .module),
                bad: true)
        }
    }

    private func note(_ text: Text, bad: Bool) -> some View {
        text
            .font(Retro.caption)
            .foregroundStyle(bad ? Retro.danger : Retro.onGround)
    }

    private func section(
        _ title: Text, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            title
                .font(Retro.body)
                .foregroundStyle(Retro.onGround)
            LazyVGrid(columns: columns, spacing: 12) { content() }
        }
    }

    /// **A tap opens the track; the rest is a long press.**
    ///
    /// The tile was a `Menu`, so choosing your track cost two taps and the primary action —
    /// edit this one — was buried among three others. Worse, a tile that only opens a menu
    /// reads as unresponsive: the obvious gesture appears to do nothing.
    ///
    /// A plain button with a `contextMenu` puts the common case on the tap and keeps copy,
    /// rename and delete one press away.
    private func tile(entry: TrackLibraryBook.Entry) -> some View {
        Button {
            game.openForEditing(entryID: entry.id)
            openCanvas()
        } label: {
            card(
                layout: try? TrackCode.decode(entry.code), name: entry.name,
                // The one thing a picture cannot say: whether this ring closes. An
                // unfinished track is not a fault, it is where you left off.
                note: entry.isRaceable ? nil : Text("Unfinished", bundle: .module))
        }
        // **Both**, deliberately. A long press is the iOS idiom and stays; a visible
        // kebab is how somebody finds out it exists — "ah, long tap" is not a discovery a
        // player should have to make. Same menu behind each, defined once.
        .overlay(alignment: .topTrailing) {
            Menu {
                actions(for: entry)
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Retro.ink)
                    .padding(6)
            }
        }
        .contextMenu { actions(for: entry) }
    }

    /// Copy, rename, delete — the things that are not "open this".
    @ViewBuilder private func actions(for entry: TrackLibraryBook.Entry) -> some View {
        // **First, because it is the point of a library.** A track you cannot
        // hand to anyone is a track only you will ever drive.
        Button {
            sharing = entry
        } label: {
            Label {
                Text("Share", bundle: .module)
            } icon: {
                Image(systemName: "qrcode")
            }
        }
        Button {
            game.startFrom(code: entry.code, name: entry.name)
            openCanvas()
        } label: {
            Label {
                Text("Start a copy", bundle: .module)
            } icon: {
                Image(systemName: "plus.square.on.square")
            }
        }
        Button {
            newName = entry.name
            renaming = entry
        } label: {
            Label {
                Text("Rename", bundle: .module)
            } icon: {
                Image(systemName: "pencil.line")
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
    }

    private func builtinTile(_ builtin: TrackLibrary.Builtin) -> some View {
        Button {
            game.startFrom(
                code: builtin.code, name: TrackLibrary.displayName(id: builtin.id))
            openCanvas()
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
                .font(Retro.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Retro.ink)
            if let note {
                note
                    .font(Retro.caption)
                    .foregroundStyle(Retro.inkSoft)
            }
        }
        .padding(6)
        .background(Retro.panel)
        .overlay(RetroBevel(thickness: 2))
    }
}
