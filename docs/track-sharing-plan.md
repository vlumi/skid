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
https://skid.misaki.fi/t/<base64url share code>     ← canonical
https://skid.misaki.fi/t/#<base64url share code>    ← also accepted
```

The whole track is in the URL, so there is no backend and a link cannot rot.

**Accept both, emit the path form.** The parser takes the code from the fragment if
there is one and from the path otherwise, which costs one branch and means a link
keeps working whichever way it was written — including anything already shared. The
path form is canonical because the site can *read* it, leaving room for a
server-rendered preview page later without changing the URL shape; the fragment form
keeps the code out of server logs, which is not a concern worth optimizing for but
is free to support.

Both match the `apple-app-site-association` already deployed (`/t/*`), so nothing on
the site needs changing.

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

Preview images are **static files, produced by whatever is convenient**. Nothing
needs to be live.

**A way to make one from a code or URL is wanted, but not yet** — after things have
stabilized, since a tool pinned to the renderer is churn while the renderer is still
moving. The one firm constraint: it **must use the production rendering code** rather
than a copy, or the site ends up advertising tracks that do not look like they do in
the app.

Already feasible, so this is scheduling rather than a question: `SkidKit` declares
`.macOS(.v14)` and neither renderer imports UIKit, so the real drawing code can run
on a Mac and go through `ImageRenderer`.

**Two shapes, and the Mac client changes which is better.** A Mac version is wanted
anyway, and it links the renderer regardless — so:

- **A render mode in the Mac app**, driven by arguments. One target, nothing extra to
  maintain. An app binary can be invoked directly and read `argv`, so it can render
  and exit without showing a window — but headless invocation of a bundled GUI app is
  fiddlier than it sounds, since `ImageRenderer` wants a run-loop turn and the app
  may still take an activation cycle.
- **A small executable target** in the same package: a few lines importing SkidKit,
  trivially driven from `make` or CI. Costs one target in `Package.swift`.

Neither risks drift, since both link the same code. Decide when the Mac client
exists — that is what makes the first option nearly free.

Settled details for when it is built:

- **Name the file after the code** — `<code>.png`. The code is already base64url and
  unpadded, so its alphabet is `[A-Za-z0-9_-]`: URL-safe *and* filename-safe, no
  escaping. Verified against all four built-ins. Watch one edge: a signed code is
  ~160–190 chars against a 255-byte filename limit, so it fits with room but not
  endlessly — fall back to a truncated hash if that is ever reached.
- **PNG, not JPEG.** A track preview is flat color with hard edges — thin white
  lines, kerb stripes, a dark rim — which is what JPEG chroma subsampling smears,
  giving ringing on every road edge. PNG is smaller *and* sharper for this content;
  JPEG only wins on photographs.

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
