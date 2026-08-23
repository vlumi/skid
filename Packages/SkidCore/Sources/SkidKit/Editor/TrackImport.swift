import SkidCore
import SwiftUI

/// **Taking a track in** — from a pasted link, a pasted code, or (later) a
/// scanned QR.
///
/// Separate from the editor's paste, which REPLACES what is on the canvas. This
/// adds to the library and changes nothing you were working on: importing is
/// collecting, not editing, and a player who taps Add expects a new row rather
/// than to lose their unsaved track.
extension CouchGame {
    /// What came of an import, so the UI can say something useful rather than
    /// just failing silently.
    public enum ImportOutcome: Equatable {
        /// Filed, with the name it will appear under.
        case added(name: String)
        /// The library already had this exact track. Not an error — the same
        /// code twice is the same road, and saying so beats a duplicate row.
        case alreadyHave(name: String)
        /// Not a track: unreadable code, or text that is not one at all.
        case unreadable
    }

    /// Add a track from pasted text — a share link or a bare code.
    ///
    /// The name comes from the link when it carries one, since that is what the
    /// sender called it; otherwise it is named for being imported, and can be
    /// renamed in the library like anything else.
    @discardableResult
    public func importTrack(fromPasted text: String) -> ImportOutcome {
        guard let contents = TrackLink.code(fromPasted: text),
            let layout = try? TrackCode.decode(contents.code)
        else { return .unreadable }
        return add(code: contents.code, layout: layout, suggestedName: contents.name)
    }

    /// File a decoded track, or report that it is already here.
    func add(code: String, layout: TrackLayout, suggestedName: String?) -> ImportOutcome {
        // **Identity is the CONTENT**, so the same road arriving twice — as a
        // link, then as a scan, or signed and unsigned — is one row rather than
        // a pile of near-duplicates the player has to tell apart.
        let id = TrackCode.contentCode(of: code)
        if let existing = library.entry(id: id) {
            return .alreadyHave(name: existing.name)
        }
        let cleaned = suggestedName.flatMap(PlayerProfile.cleaned(name:))
        let name = cleaned ?? String(localized: "Imported track", bundle: .module)
        let signature = TrackCode.signature(of: code)
        var book = library
        book.put(
            TrackLibraryBook.Entry(
                name: name,
                code: code,
                authorKey: signature?.publicKey,
                signatureIsValid: signature?.isValid ?? false,
                isRaceable: (try? PieceCompiler.compile(layout)) != nil,
                createdAt: Date(), importedAt: Date(), updatedAt: Date()))
        library = book
        saveLibrary()
        return .added(name: name)
    }
}
