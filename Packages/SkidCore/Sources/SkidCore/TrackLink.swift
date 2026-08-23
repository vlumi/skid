import Foundation

/// **A track as a link** — the whole road in the URL, so there is no backend and
/// a link cannot rot.
///
/// ```text
/// https://skid.misaki.fi/t/<code>      ← canonical, emitted
/// https://skid.misaki.fi/t/#<code>     ← also accepted
/// ```
///
/// **Accept both, emit the path form.** The parser takes the code from the
/// fragment when there is one and from the path otherwise, which costs one
/// branch and keeps a link working whichever way it was written — including
/// anything already shared. The path form is canonical because the site can
/// *read* it, leaving room for a server-rendered preview later without changing
/// the URL shape.
///
/// **Any host.** The design privileges no domain: a code is the whole track, so a
/// link from somebody else's site is as valid as one from ours, and refusing
/// them would be enforcing a landlord nobody needs. The host is not checked on
/// the way in — only the shape of the path and the readability of the code.
///
/// **The name rides as a query parameter**, unsigned and optional. It cannot live
/// in the code itself: a signed code attests to exact bytes, so a name inside one
/// could not be renamed on import, and duplicate imported names would be
/// guaranteed. See `docs/track-pieces.md`.
public enum TrackLink {
    /// Where this app's own links point. Only used for *emitting* — nothing on
    /// the way in cares which host a link came from.
    public static let host = "skid.misaki.fi"
    /// The path prefix, matching the deployed `apple-app-site-association`.
    public static let pathPrefix = "/t/"
    /// The query parameter carrying an optional display name.
    public static let nameParameter = "n"

    /// Build a shareable link for a code, optionally naming the track.
    ///
    /// Nil for an empty code, since a link to nothing is not worth showing.
    public static func url(code: String, name: String? = nil) -> URL? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = pathPrefix + trimmed
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            components.queryItems = [URLQueryItem(name: nameParameter, value: name)]
        }
        return components.url
    }

    /// What a link carries: the code, and the name it suggests (if any).
    public struct Contents: Equatable, Sendable {
        public var code: String
        public var name: String?

        public init(code: String, name: String? = nil) {
            self.code = code
            self.name = name
        }
    }

    /// Read a link. Nil when it is not a track link at all — the caller can then
    /// treat the text as a bare code, or say it is not a track.
    ///
    /// Deliberately tolerant of what a human paste contains: surrounding
    /// whitespace, and a missing scheme (`skid.misaki.fi/t/…` typed or copied out
    /// of a message). A pasted link that "looks right" should work.
    public static func contents(of text: String) -> Contents? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // A scheme-less paste is still a URL to a person, so give it one before
        // parsing rather than refusing what obviously reads as a link.
        let candidate =
            trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: candidate),
            let path = components.path.isEmpty ? nil : components.path,
            path.hasPrefix(pathPrefix)
        else { return nil }

        // The fragment form puts the code after the path prefix's `#`; the path
        // form puts it in the path itself.
        let fromPath = String(path.dropFirst(pathPrefix.count))
        let code = (components.fragment?.isEmpty == false ? components.fragment! : fromPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        let name = components.queryItems?
            .first { $0.name == nameParameter }?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Contents(code: code, name: (name?.isEmpty == false) ? name : nil)
    }

    /// **The code out of whatever was pasted** — a link, or a bare code.
    ///
    /// One entry point, because every paste path wants the same tolerance: a
    /// player copying "a track" may have copied either, and telling them which
    /// one the app wanted would be the app's problem leaking out.
    public static func code(fromPasted text: String) -> Contents? {
        if let link = contents(of: text) { return link }
        let bare = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return bare.isEmpty ? nil : Contents(code: bare)
    }
}
