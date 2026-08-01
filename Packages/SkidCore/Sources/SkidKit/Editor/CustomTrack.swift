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
        let code = TrackCode.encode(layout)
        guard !library.contains(code: code) else { return }
        var book = library
        let previous = editedEntryID.flatMap { book.entry(id: $0) }
        if let previous { book.remove(id: previous.id) }
        book.put(
            TrackLibraryBook.Entry(
                name: previous?.name ?? String(localized: "My track", bundle: .module),
                code: code,
                isRaceable: (try? PieceCompiler.compile(layout)) != nil,
                createdAt: previous?.createdAt ?? Date(),
                importedAt: previous?.importedAt,
                updatedAt: Date()))
        editedEntryID = TrackCode.contentCode(of: code)
        library = book
        saveLibrary()
    }
}
