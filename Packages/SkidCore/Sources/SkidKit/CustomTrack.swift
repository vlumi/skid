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
        guard trackID == Self.customTrackID else { return TrackLibrary.track(id: trackID) }
        return customTrack() ?? TrackLibrary.all[0]
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
    /// permanent, and what the slot is persisted as.
    public func customTrackCode() -> String? {
        editorLayout.map { TrackCode.encode($0) }
    }

    /// Replace the custom slot from a share code. Returns false if the code is
    /// unreadable, so the editor can say so rather than silently doing nothing.
    @discardableResult
    public func loadCustomTrack(code: String) -> Bool {
        guard
            let layout = try? TrackCode.decode(code.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        // Canonical in memory, matching its code — see `finishIfClosed`.
        editorLayout = layout.normalized()
        // A different track arrives with no history — undoing back into the
        // previous one would be a surprise, not a convenience.
        clearUndoHistory()
        return true
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
        guard let code = UserDefaults.standard.string(forKey: customTrackKey) else { return nil }
        return try? TrackCode.decode(code)
    }
}
