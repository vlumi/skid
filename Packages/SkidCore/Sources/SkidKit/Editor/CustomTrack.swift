import SkidCore
import SwiftUI

/// The **custom track slot**: one permanent place to build and race your own
/// design. It persists across launches as a share code, so a track survives
/// quitting — and the same code is what gets copied out to promote a design to
/// a built-in (see docs/track-pieces.md "A library of your own tracks" for
/// where this grows: UUID identity, many named tracks, import by link/QR).
extension CouchGame {
    /// The track to race: the custom slot when it's picked, else a built-in.
    /// A custom slot that isn't a valid track falls back rather than refusing
    /// to start (the setup picker already grays it out in that state).
    func selectedTrack() -> Track {
        if let builtin = TrackLibrary.builtin(id: trackID) { return builtin }
        if let mine = libraryTrack(id: trackID) { return mine }
        // The legacy slot, for a build that raced it before the library existed.
        if trackID == Self.customTrackID, let slot = customTrack() { return slot }
        return TrackLibrary.all[0]
    }

    /// Compile one of your own tracks. Nil if the entry is gone or no longer
    /// compiles — the caller falls back rather than refusing to start.
    func libraryTrack(id: String) -> Track? {
        guard let entry = library.entry(id: id),
            let layout = try? TrackCode.decode(entry.code)
        else { return nil }
        return try? PieceCompiler.compile(layout, id: entry.trackID)
    }

    /// The track id the custom slot races under.
    public static let customTrackID = "my-track"

    /// The custom slot compiled for racing, or nil if it isn't a valid track
    /// yet — which is what grays it out in the setup picker.
    public func customTrack() -> Track? {
        guard let editorLayout else { return nil }
        return try? PieceCompiler.compile(editorLayout, id: Self.customTrackID)
    }

    /// The share code for the custom slot — what you copy out to make a design
    /// permanent, and what the slot is persisted as. Unsigned: this is also the
    /// undo snapshot's encoding, and signing it would cost a key operation per
    /// edit.
    public func customTrackCode() -> String? {
        editorLayout.map { TrackCode.encode($0) }
    }

    /// The code to hand to someone else, **signed when a key is available**.
    ///
    /// Falls back to the unsigned code rather than failing: an unavailable
    /// Keychain (or a device that has never signed) should still let you share.
    /// `signed: false` asks for the short one on purpose — a signature costs
    /// ~135 characters, which is worth skipping when the link is disposable.
    public func shareCode(signed: Bool = true) -> String? {
        guard let layout = editorLayout else { return nil }
        guard signed, let signer = signingKeys.signer() else { return TrackCode.encode(layout) }
        return (try? TrackCode.encode(layout, signedBy: signer)) ?? TrackCode.encode(layout)
    }

    /// What the last pasted code claimed about its author.
    public var pastedAttribution: TrackAttribution { pastedAttributionRaw }

    /// Replace the custom slot from a share code. Returns false if the code is
    /// unreadable, so the editor can say so rather than silently doing nothing.
    @discardableResult
    public func loadCustomTrack(code: String) -> Bool {
        guard
            let layout = try? TrackCode.decode(code.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // Read once, here — never per render. Verification is cheap but not
        // free, and the setup picker's compile-per-frame is the cautionary tale.
        pastedAttributionRaw = TrackAttribution.of(
            trimmed, myPublicKey: signingKeys.signer()?.publicKey)
        // File it BEFORE assigning the layout. That assignment mirrors the
        // editor into the library, and it only has the plain re-encode to work
        // from — so importing after it would overwrite the signed code and its
        // author with an unsigned copy of the same road.
        importIntoLibrary(code: trimmed, layout: layout)
        // Canonical in memory, matching its code — see `finishIfClosed`.
        editorLayout = layout.normalized()
        // A different track arrives with no history — undoing back into the
        // previous one would be a surprise, not a convenience.
        clearUndoHistory()
        return true
    }

    /// File an arriving track under its own row, keeping the SIGNED code so it
    /// can be passed on intact, and recording who signed it.
    ///
    /// A track that is already in the library keeps the row it has — including
    /// the name you gave it. Arriving again is not a reason to rename it.
    private func importIntoLibrary(code: String, layout: TrackLayout) {
        guard !library.contains(code: code) else { return }
        let signature = TrackCode.signature(of: code)
        var book = library
        book.put(
            TrackLibraryBook.Entry(
                name: String(localized: "Imported track", bundle: .module),
                code: code,
                authorKey: signature?.publicKey,
                signatureIsValid: signature?.isValid ?? false,
                isRaceable: (try? PieceCompiler.compile(layout)) != nil,
                createdAt: Date(), importedAt: Date(), updatedAt: Date()))
        library = book
        // The editor now works on the imported row, so the first edit replaces
        // it rather than leaving the import behind as a stray.
        editedEntryID = TrackCode.contentCode(of: code)
        saveLibrary()
    }

    static let customTrackKey = "skid.editor.customTrack"

    func saveCustomTrack() {
        guard let code = customTrackCode() else {
            UserDefaults.standard.removeObject(forKey: Self.customTrackKey)
            return
        }
        UserDefaults.standard.set(code, forKey: Self.customTrackKey)
    }

    /// The persisted custom slot, if there is a readable one.
    static func restoredCustomTrack() -> TrackLayout? {
        guard let code = restoredCustomTrackCode() else { return nil }
        return try? TrackCode.decode(code)
    }

    /// The slot's raw stored code, for the library migration to fold in.
    /// Deliberately NOT removed once migrated: it costs a few dozen bytes and
    /// is the only way back if the library turns out to have eaten something.
    static func restoredCustomTrackCode() -> String? {
        UserDefaults.standard.string(forKey: customTrackKey)
    }

    /// The library after folding in the old slot, run on every launch.
    ///
    /// Idempotent through `TrackLibraryBook.migrating` — the guard is "the book
    /// is empty" — so this is a no-op from the second launch on, and cannot
    /// duplicate the track.
    static func migratedLibrary(_ book: TrackLibraryBook, slot: String?) -> TrackLibraryBook {
        TrackLibraryBook.migrating(
            legacyCode: slot, into: book, now: Date(),
            name: String(localized: "My track", bundle: .module))
    }
}

extension CouchGame {
    /// Mirror the edited track into the library as it changes.
    ///
    /// Identity is the CODE, so every edit is a new entry rather than an update
    /// in place — which would leave a trail of half-built rings. So the entry
    /// this edit replaces is dropped, keeping its name and dates: one row that
    /// follows the track being worked on.
    func syncEditedTrackToLibrary() {
        guard let layout = editorLayout else { return }
        // **An untouched canvas is not a track.** Opening the editor assigns a layout of
        // one start piece, which fires this observer — so a player who opened the editor
        // and left got a saved "My track" they never made, and every `newTrackForEditing`
        // added another. Nothing is written until there is something on the canvas.
        guard layout.pieces.count > 1 else { return }
        let code = TrackCode.encode(layout)
        guard !library.contains(code: code) else { return }
        // **Nor is a track you have only LOOKED at.** `startFrom` loads a track with no row
        // claimed, and this observer fires on that assignment too — so merely opening a
        // built-in to see how it was made filed a copy under your own tracks. `startedFrom`
        // holds the code it arrived as; while the canvas still matches, there is nothing to
        // save. That is what makes "start a copy" leave no trace until there is something
        // to distinguish the copy from its source.
        guard code != startedFrom else { return }
        var book = library
        let previous = editedEntryID.flatMap { book.entry(id: $0) }
        if let previous { book.remove(id: previous.id) }
        book.put(
            TrackLibraryBook.Entry(
                // A name chosen before the first edit — "Eight 2" when starting from a
                // built-in — outranks the default, and is consumed once used.
                name: previous?.name ?? pendingTrackName
                    ?? String(localized: "My track", bundle: .module),
                code: code,
                isRaceable: (try? PieceCompiler.compile(layout)) != nil,
                createdAt: previous?.createdAt ?? Date(),
                importedAt: previous?.importedAt,
                updatedAt: Date()))
        editedEntryID = TrackCode.contentCode(of: code)
        pendingTrackName = nil
        startedFrom = nil
        library = book
        saveLibrary()
    }
}

// MARK: - Opening a track to edit

/// **Which of your tracks the editor is working on.**
///
/// The editor had exactly one buffer restored from one slot, so a library that stored many
/// tracks could race all of them and edit only the newest. Edits flowed *to* the library;
/// nothing flowed back.
extension CouchGame {
    /// **Load an entry into the editor, and keep editing THAT entry.**
    ///
    /// Safe to do in place, and the reason is worth stating because it looks unsafe: an
    /// entry's id is a hash of its own content (`TrackCode.contentCode`), so an edit
    /// necessarily produces a *different* id. `syncEditedTrackToLibrary` then drops the
    /// row this edit came from and writes the new one, carrying the name and dates over —
    /// so one row follows the track being worked on rather than a trail accumulating.
    ///
    /// Editing therefore *moves* a track rather than overwriting a stranger's. What it
    /// cannot do is leave the original behind; that is `duplicate(entryID:)`.
    @discardableResult
    public func openForEditing(entryID: String) -> Bool {
        guard let entry = library.entry(id: entryID),
            let layout = try? TrackCode.decode(entry.code)
        else { return false }
        // Set before the layout, since assigning `editorLayout` fires the sync observer.
        // Not load-bearing here, and worth saying so rather than implying a hazard: the
        // code being loaded is already in the book, so the observer's own
        // `contains(code:)` guard returns before it can do anything either way. Verified
        // by swapping the two lines — nothing changes.
        editedEntryID = entry.id
        startedFrom = nil
        editorLayout = layout
        clearUndoHistory()
        editorMode = .build
        editorSelect(layout.pieces.count - 1)
        return true
    }

    /// **Start from an existing track, without claiming its row.**
    ///
    /// What "copy this and edit the copy" means here — and it needs no stored copy, which
    /// is worth explaining because the obvious implementation is impossible:
    ///
    /// **A library entry's id IS its content** (`TrackCode.contentCode`), so two rows
    /// holding the same track cannot coexist — `put` would replace the original rather
    /// than add a sibling. A "duplicate" written to the book therefore *is* the original.
    ///
    /// So this loads the layout and tracks **no row at all**. The first edit then writes a
    /// fresh entry (the content differs by then, so it gets its own id) and the original is
    /// untouched, because nothing pointed at it. The copy exists exactly when there is
    /// something to distinguish it — which is also why an unedited "copy" leaves no trace,
    /// and that is the honest outcome rather than a missing feature.
    ///
    /// The only way to open a **built-in**, since those ship in the binary under a slug and
    /// have no library row to claim.
    @discardableResult
    public func startFrom(code: String, name: String) -> Bool {
        guard let layout = try? TrackCode.decode(code) else { return false }
        editedEntryID = nil
        pendingTrackName = duplicateName(of: name)
        startedFrom = code
        editorLayout = layout
        clearUndoHistory()
        editorMode = .build
        editorSelect(layout.pieces.count - 1)
        return true
    }

    /// Start from nothing: one start-grid piece, built outward from its loose end.
    public func newTrackForEditing() {
        editedEntryID = nil
        pendingTrackName = nil
        startedFrom = nil
        editorLayout = TrackLayout(pieces: [PieceCatalog.startPieceID], gateSeams: [0])
        clearUndoHistory()
        editorMode = .build
        editorSelect(0)
    }

    /// `Name` → `Name 2`, `Name 2` → `Name 3`. Numbered rather than "copy of" so a third
    /// copy does not become "copy of copy of Name".
    func duplicateName(of name: String) -> String {
        let taken = Set(library.tracks.map(\.name))
        // A trailing number is a count to continue, not part of the name.
        let base: String
        var next = 2
        if let space = name.lastIndex(of: " "), let number = Int(name[name.index(after: space)...])
        {
            base = String(name[name.startIndex..<space])
            next = number + 1
        } else {
            base = name
        }
        while taken.contains("\(base) \(next)") { next += 1 }
        return "\(base) \(next)"
    }
}

extension CouchGame {
    /// Delete one of your tracks.
    ///
    /// **Two things follow it out.** If the deleted row is the one the editor is working
    /// on, `editedEntryID` is cleared — otherwise the next edit would try to "replace" a
    /// row that no longer exists and quietly resurrect it. And if it was the selected
    /// race track, the selection falls back to a built-in, since `selectedTrack()` would
    /// otherwise silently substitute one anyway and the picker would keep showing a name
    /// that is gone.
    public func deleteTrack(id: String) {
        guard library.entry(id: id) != nil else { return }
        var book = library
        book.remove(id: id)
        library = book
        saveLibrary()
        if editedEntryID == id { editedEntryID = nil }
        if trackID == id { trackID = TrackLibrary.builtins[0].id }
    }
}

extension CouchGame {
    /// **Rename one of your tracks.**
    ///
    /// A name is the only part of an entry that is *yours* rather than derived: the id is a
    /// hash of the track's content, the dates are events, and the code is the road. So this
    /// is the one edit that changes a row without changing the track — `put` replaces by
    /// id, and the id does not move.
    ///
    /// Returns false when the name is unusable, leaving the old one: a track called "" is
    /// worse than a track called "My track".
    @discardableResult
    public func renameTrack(id: String, to name: String) -> Bool {
        guard var entry = library.entry(id: id),
            let cleaned = TrackName.cleaned(name)
        else { return false }
        guard cleaned != entry.name else { return true }
        entry.name = cleaned
        // `updatedAt` deliberately untouched: it means "last edited here" and orders the
        // shelf, so renaming would push a track you have not touched to the front.
        var book = library
        book.put(entry)
        library = book
        saveLibrary()
        return true
    }
}

/// Cleaning a track name, kept beside the operation that needs it.
///
/// Deliberately its own type rather than a method on the book: the same rule applies to a
/// name typed in the shelf and a name arriving with an imported track, and neither of those
/// is a library concern.
public enum TrackName {
    /// Longest name worth storing — generous for a real one, short enough that a shelf tile
    /// can show it without the layout fighting back.
    public static let maxLength = 24

    /// Trimmed and capped, or nil when nothing usable is left. Nil rather than a
    /// placeholder for the same reason `PlayerProfile.cleaned` does it: "  " is not a name,
    /// and the caller's answer is to keep what it had.
    public static func cleaned(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }
}

extension CouchGame {
    /// **The name of the track being edited**, or nil when it has none yet.
    ///
    /// Nil is the honest answer for a canvas that has not been saved: nothing is written to
    /// the library until there is more than a start piece on it (see
    /// `syncEditedTrackToLibrary`), so until then there is no row to name. The editor shows
    /// a placeholder rather than inventing one.
    public var editedTrackName: String? {
        editedEntryID.flatMap { library.entry(id: $0)?.name } ?? pendingTrackName
    }

    /// Rename the track currently being edited. Convenience over `renameTrack(id:to:)` for
    /// the editor, which knows *what* it is editing but should not have to know how rows
    /// are keyed.
    ///
    /// **Works before the first save too**: with no row yet, the name is remembered and
    /// applied when one is written, which is what `pendingTrackName` already does for a
    /// track started from a copy. So naming a brand-new track works the moment you think
    /// of the name, rather than only after it has been saved.
    @discardableResult
    public func renameEditedTrack(to name: String) -> Bool {
        guard let cleaned = TrackName.cleaned(name) else { return false }
        if let id = editedEntryID, library.entry(id: id) != nil {
            return renameTrack(id: id, to: cleaned)
        }
        pendingTrackName = cleaned
        return true
    }
}
