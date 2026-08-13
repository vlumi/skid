# Sharing tracks: links, QR, previews

## Why

Hand-authored built-ins cost a design session *and an app release*. A track that
travels as a link or a QR code can come from the site, a friend, or a player, with
no app update — so the library becomes a channel and the built-ins become the
starting set rather than the whole set.

Built-ins stay as the floor: a tournament needs a pool present on first launch,
before anyone has scanned anything. Six to eight is enough for that.

## The link

```text
https://skid.misaki.fi/t/<base64url share code>
```

The whole track is in the URL, so there is no backend and a link cannot rot.

**Path, not fragment.** A `#fragment` would keep the code out of server logs and
referrer headers, which is worth nothing here — a track is not a secret, and the
curated ones are published on the site anyway. A path is a cleaner link, and the
site can *read* it, which leaves the door open to a server-rendered preview page
later without changing the URL shape.

This matches the `apple-app-site-association` already deployed on the site
(`/t/*`), so nothing there needs changing.

## What already exists

- Codes are **32–72 chars** unsigned, ~160–190 signed. Comfortably inside QR
  V8/V9.
- Clipboard import works, so decode → validate → name → store is proven.
- Signing shipped in v0.6.0, so a shared track can say who made it.
- `EditorRenderer.drawTrack` takes a `Transform`, so it already draws a layout at
  any scale.
- Hugo has a built-in `images.QR` for the site side.

Missing: the `associatedDomains` entitlement, `onOpenURL`, a QR encoder, a camera
scanner.

## The work

1. **Preview rendering in the app.** Needed regardless of sharing: the track
   library wants thumbnails in its list, and the share screen wants a picture of
   what you are sharing. `EditorRenderer.drawTrack` does the drawing.
2. **Share screen** — the QR code, the link, and the preview together.
3. **Link handling** — entitlement, `onOpenURL`, decode and offer to add. Include a
   **paste-a-URL** path so this is testable without the domain resolving or a
   camera. Wants a device session: universal links do not exercise properly in the
   simulator against a real domain.
4. **QR scanning** — camera permission, a scanner, and the "what am I looking at"
   moment. Last, because it is the biggest and the paste path already covers
   importing.

## The site

Static content in the sibling site repo, in the shape it already uses for its
presets: one data file, build-time QR codes, no JavaScript. Per track: preview
image, QR, link, name, author.

Preview images are **static files, produced by whatever is convenient** — most
likely by running the app's own renderer once that exists. Not a pipeline, and
nothing needs to be live.

One asymmetry worth knowing: a track code is opaque, so unlike a tuning preset's
data file, an entry cannot describe its own content and the site build cannot check
it. The preview is therefore the only view of what a track *is*, and a bad code
shows up as a broken preview rather than a build error.

## Open

- **Submissions.** Email a code, a pull request against the data file, or a form.
  Process rather than code, and clearer once there are tracks worth submitting.
- **Third-party collections** need nothing built: a link is self-contained, so any
  page can host codes, QR codes and previews. Only universal-link handling is
  domain-bound.
- **Server-hosted short links** and an online library with server logic — post-1.0.
- **Whether shared tracks sit apart from built-ins** in the picker, or mixed with a
  badge.
