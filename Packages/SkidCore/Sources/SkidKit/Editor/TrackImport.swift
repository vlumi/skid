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

    /// **A track arrived from outside** — a tapped link, or a scanned code.
    ///
    /// Offered rather than filed: the app is being handed something by a third
    /// party, and one that silently writes to your library on a tap is one you
    /// stop trusting. The library shows what it is and asks. Nil when the link
    /// is not a track at all, so a mis-tapped URL says nothing rather than
    /// popping an error nobody caused.
    @discardableResult
    public func receive(url: URL) -> Bool {
        guard let contents = TrackLink.contents(of: url.absoluteString),
            let layout = try? TrackCode.decode(contents.code)
        else { return false }
        incomingTrack = IncomingTrack(
            code: contents.code, name: contents.name, layout: layout,
            alreadyHave: library.entry(id: TrackCode.contentCode(of: contents.code)) != nil)
        // Straight to the library, which is where it would land — arriving into
        // whatever screen happened to be open (a race, the editor) and asking a
        // question there would be an interruption rather than an offer.
        phase = .tracks
        return true
    }

    /// **A scanned code** — the camera's half of `receive(url:)`.
    ///
    /// A QR holds whatever the sharer's app put in it, which is a link; but a
    /// code pasted into a QR generator by hand is just as valid a way to share a
    /// track, so both are accepted. Returns whether it was a track at all, so
    /// the scanner can keep looking rather than stopping on a shop's wifi code.
    @discardableResult
    public func receive(scanned text: String) -> Bool {
        guard let contents = TrackLink.code(fromPasted: text),
            let layout = try? TrackCode.decode(contents.code)
        else { return false }
        incomingTrack = IncomingTrack(
            code: contents.code, name: contents.name, layout: layout,
            alreadyHave: library.entry(id: TrackCode.contentCode(of: contents.code)) != nil)
        phase = .tracks
        return true
    }

    /// Accept the offered track, filing it under the name it suggested.
    @discardableResult
    public func acceptIncomingTrack() -> ImportOutcome {
        guard let incoming = incomingTrack else { return .unreadable }
        incomingTrack = nil
        return add(code: incoming.code, layout: incoming.layout, suggestedName: incoming.name)
    }

    /// Decline it. Nothing is written, which is the point of asking.
    public func declineIncomingTrack() {
        incomingTrack = nil
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

/// A track offered by a link or a scan, pending the player's answer.
public struct IncomingTrack: Equatable {
    public var code: String
    /// What the sender called it, if the link said.
    public var name: String?
    /// Decoded up front, so the offer can show a preview and cannot fail later.
    public var layout: TrackLayout
    /// Whether this exact road is already in the library — worth saying before
    /// somebody accepts a second copy of something they have.
    public var alreadyHave: Bool
}
