import Foundation
import Testing

@testable import SkidCore

/// **A track as a link.** The whole road rides in the URL, so these pin the two
/// accepted shapes, the tolerance a pasted link needs, and the rule that no host
/// is privileged.
struct TrackLinkTests {
    private let code = "AUwBCB8SDAkBCgwaAgMABAwDBQNIAlgA"

    @Test func aLinkCarriesTheWholeTrack() throws {
        let url = try #require(TrackLink.url(code: code))
        #expect(url.absoluteString == "https://skid.misaki.fi/t/\(code)")
        // And it round-trips.
        let back = try #require(TrackLink.contents(of: url.absoluteString))
        #expect(back.code == code)
        #expect(back.name == nil)
    }

    /// **The name rides as a query parameter**, not inside the code: a signed code
    /// attests to exact bytes, so a name inside one could not be renamed on
    /// import.
    @Test func aNameRidesAlongsideTheCode() throws {
        let url = try #require(TrackLink.url(code: code, name: "Hairpin Alley"))
        let back = try #require(TrackLink.contents(of: url.absoluteString))
        #expect(back.code == code)
        #expect(back.name == "Hairpin Alley")
        // The code itself is untouched by the name — the same track either way.
        #expect(TrackLink.contents(of: "https://skid.misaki.fi/t/\(code)")?.code == back.code)
    }

    @Test func aNameIsOmittedWhenThereIsNone() throws {
        #expect(try #require(TrackLink.url(code: code)).query == nil)
        #expect(try #require(TrackLink.url(code: code, name: "   ")).query == nil)
    }

    /// **Both forms are accepted**, because a link should keep working whichever
    /// way it was written — including anything already shared.
    @Test func theFragmentFormIsAcceptedToo() throws {
        let fragment = try #require(
            TrackLink.contents(of: "https://skid.misaki.fi/t/#\(code)"))
        #expect(fragment.code == code)
        let path = try #require(TrackLink.contents(of: "https://skid.misaki.fi/t/\(code)"))
        #expect(path.code == fragment.code, "the two forms named different tracks")
    }

    /// **No host is privileged.** A code is the whole track, so a link from
    /// somebody else's site is as valid as one from ours.
    @Test func anyHostIsAccepted() throws {
        let elsewhere = try #require(
            TrackLink.contents(of: "https://tracks.example.com/t/\(code)"))
        #expect(elsewhere.code == code)
    }

    /// A pasted link is whatever a human copied: it may have lost its scheme, or
    /// picked up whitespace. Both should still work rather than being refused on
    /// a technicality.
    @Test func aPastedLinkIsReadTolerantly() throws {
        #expect(TrackLink.contents(of: "  https://skid.misaki.fi/t/\(code)  ")?.code == code)
        #expect(TrackLink.contents(of: "skid.misaki.fi/t/\(code)")?.code == code)
    }

    @Test func whatIsNotATrackLinkIsRefused() {
        #expect(TrackLink.contents(of: "") == nil)
        #expect(TrackLink.contents(of: "https://skid.misaki.fi/") == nil)
        #expect(TrackLink.contents(of: "https://skid.misaki.fi/about") == nil)
        // The right path but no code is not a track either.
        #expect(TrackLink.contents(of: "https://skid.misaki.fi/t/") == nil)
        #expect(TrackLink.url(code: "") == nil)
        #expect(TrackLink.url(code: "   ") == nil)
    }

    /// **One entry point for a paste**, because a player copying "a track" may
    /// have copied a link or a bare code, and which one the app wanted is the
    /// app's problem rather than theirs.
    @Test func aPasteMayBeEitherALinkOrABareCode() throws {
        #expect(TrackLink.code(fromPasted: code)?.code == code)
        #expect(TrackLink.code(fromPasted: "https://skid.misaki.fi/t/\(code)")?.code == code)
        #expect(
            TrackLink.code(fromPasted: "https://skid.misaki.fi/t/\(code)?n=Mine")?.name
                == "Mine")
        #expect(TrackLink.code(fromPasted: "  \n ") == nil)
    }

    /// A link built from a real track decodes back into that track — the round
    /// trip that matters, rather than string equality alone.
    @Test func aRealTrackSurvivesTheRoundTrip() throws {
        for builtin in TrackLibrary.builtins {
            let url = try #require(TrackLink.url(code: builtin.code, name: builtin.name))
            let back = try #require(TrackLink.contents(of: url.absoluteString))
            let layout = try TrackCode.decode(back.code)
            let original = try TrackCode.decode(builtin.code)
            #expect(layout == original, "\(builtin.name) did not survive the link")
            #expect(back.name == builtin.name)
        }
    }
}
