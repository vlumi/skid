# Sharing tracks: links, QR, and a curated site library

## Why this changes the library plan

[game-shape-plan.md](game-shape-plan.md) has "grow the built-in library to 8–12"
as authorship: sit in the editor, design tracks, paste codes into
`TrackLibrary.builtins`. That is still the floor, but it is the wrong ceiling —
every track costs a design session and an app release.

**Make the library a channel instead.** A track that can travel as a link or a QR
code can come from the site, from a friend, or from a player who built something
good, and none of those need an app update. The built-ins become the *starting*
set rather than the whole set.

So this is partly a replacement for step 4 and partly an enabler of it: fewer
hand-authored built-ins are needed if tracks arrive from outside.

**Built-ins still matter, and here is the floor:** a tournament needs a pool that
is present on first launch, before anyone has scanned anything. Six to eight
built-in tracks, with links raising the ceiling from there.

## What already exists

More than expected, on both sides.

**The app:**

- Share codes work and round-trip, **32–72 chars** unsigned for the current
  built-ins, ~160–190 signed. Comfortably inside QR V8/V9.
- Import works by clipboard, so decode → validate → name → store is proven.
- Ed25519 signing and attribution shipped in v0.6.0, so a shared track can say
  who made it.
- `EditorRenderer.drawTrack` already takes a `Transform`, so drawing a layout
  thumbnail at any scale is a call rather than a feature.

**The site** (`skid-site`, Hugo, `skid.misaki.fi`):

- An `apple-app-site-association` is **already deployed**, claiming `/t/*` for
  `U84DT7P75P.fi.misaki.skid`. Nothing on the site needs changing for links to
  work — see the URL shape below.

- Hugo has a built-in `images.QR`, so build-time QR codes need no dependency.

**Missing in the app:** the `associatedDomains` entitlement, `onOpenURL`
handling, a QR encoder, a camera scanner, and the URL shape itself.

## The URL shape

**Self-contained, payload in the fragment.** The whole track rides in the URL:

```text
https://skid.misaki.fi/t/#<base64url share code>
```

**Note the trailing slash**, and it is load-bearing: the deployed AASA claims
`/t/*`, which matches path `/t/` but **not** `/t`. Writing the link with the slash
means the already-deployed file is correct as it stands — see below.

Three properties earn this over a server-hosted short link:

- **No backend.** Nothing to run, nothing to pay for, nothing to keep alive.
- **A link cannot rot.** A track whose site went away is a bad thing to have
  handed to a friend.
- **The payload never reaches the server.** A fragment is not sent in an HTTP
  request, so sharing a track does not publish it to whoever hosts the page.

This is the same shape `nitpitch-site` uses for tuning presets, and the app side
should read the same way.

**Server-hosted short links stay possible later** for curated collections, where
both ends are controlled. Limited server logic for an online library is a
post-1.0 thought, not part of this.

### The deployed AASA is fine — match it rather than change it

Skid already serves:

```json
{ "applinks": { "apps": [], "details": [
  { "appID": "U84DT7P75P.fi.misaki.skid", "paths": ["/t/*"] } ] } }
```

`/t/*` matches `/t/#code` and **not** `/t#code`, so the URL carries the trailing
slash and nothing needs redeploying. Worth being deliberate about because AASA is
fetched and cached by Apple's CDN, so a wrong file is slow to correct — and because
the sibling app made the opposite choice (no slash, and claims both forms), which
would be an easy thing to copy by mistake.

The older `paths` spelling is legacy in favor of `components`, but it still works
and there is no reason to touch the file until something else needs changing there.

## The site library

Static content, following the nitpitch tunings pattern: **one data file, links and
QR codes computed at build time, no JavaScript and no runtime dependency.**

**But a track is not a tuning, and the difference decides the design.** A tuning is
`[57, 64, 69, 76]` — the data file *is* the readable form, and the page computes note
names straight from it. A track code is opaque base64. So:

- **`tracks.yaml` cannot describe its own content.** Name, author and blurb are
  hand-written prose; nothing about the track's shape can be derived from the entry.
- **The preview is not a convenience, it is the only view of the content.** For a
  tuning, the QR sits beside text a reader can already understand. For a track,
  without a picture the page is a name and an opaque blob.
- **Hugo cannot validate the data.** The nitpitch layout rejects out-of-range MIDI
  numbers with `errorf` because they are numbers. Deciding whether a track code is
  valid needs the *compiler* — which is Swift, in this repo.

Both of those push the same way: the preview generator belongs **here**, not in the
site repo, and it validates as a side effect of rendering.

- `data/tracks.yaml` — the collection. Per entry: `name`, `author`, `code`, and a
  `blurb`; grouped into categories the same way tunings are.
- A layout that renders, per track: the **preview image**, the **QR code**, the
  **link**, the name, and the author.
- QR via Hugo's built-in `images.QR` — build-time, no library.
- **Validate at build time.** The nitpitch layout calls `errorf` on out-of-range
  data, and the same applies here: a code that does not decode should fail the
  build rather than ship a QR nobody can scan.

### The preview generator

**A tool in this repo** that takes a share code and writes a PNG, with the
committed images consumed by the site. The compiler and `EditorRenderer.drawTrack`
already exist, so this is a thin wrapper around them — and it is the only option
that can *validate*, since validation means compiling.

Two properties worth designing in:

- **A code that does not compile fails the tool**, which is the build-time check
  Hugo cannot perform. A curated collection should not be able to ship a track
  nobody can race.
- **Deterministic output**, so a regenerated preview is byte-identical when the
  track has not changed and a diff means something.

Rejected: **rendering client-side in the browser**, which needs the compiler ported
to JS or WASM. The in-app share sheet wants a preview too, and that is the same
renderer called from the app — worth doing, but it is a separate surface from
curated site content, where deterministic committed images are better than
whatever a phone produced.

## Submissions

Deliberately unsolved. Options range from "email me a code" through a pull
request against `tracks.yaml` to a form. All of them are process rather than code,
and the answer will be clearer once there are tracks worth submitting.

**Explicitly welcome: someone else hosting their own collection.** Nothing in this
design privileges `skid.misaki.fi` — a link is self-contained, so any page
anywhere can host codes, QR codes and previews, and the app will open them the
same way. Only *universal link* handling is domain-bound (AASA lists the domains
that may open the app directly); a third-party page's links still work by
copy-paste, and a QR still scans. Worth stating so it is a property of the design
rather than an accident.

## Sequence

1. **Universal links in.** `associatedDomains` entitlement, `onOpenURL`, decode
   and offer to add — with a **paste-a-URL fallback** so the flow is testable
   without the domain or a camera.
2. **QR out, with a preview.** In-app: show a track as a QR beside a thumbnail of
   its layout, using the renderer that already exists.
3. **QR in.** Camera scanning. Bigger than it looks — permission prompt, a
   scanner UI, and the "what am I looking at" moment — hence last of the app
   work.
4. **Site pages.** `data/tracks.yaml`, a layout, previews generated by a tool in
   this repo.

Steps 1 and 2 are the high-value half and can ship together.

**Budget a device session for step 1.** Universal links cannot be exercised
properly in the simulator against a real domain, and a link tapped in Safari on
the device that owns the app sometimes needs long-press → Open. That is why the
paste fallback is in the same step rather than deferred.

## What this does not decide

- **How submissions work** — see above.
- **Whether the app can browse the site's collection** in-app. That is a network
  fetch and a list UI, and it wants the site content to exist first.
- **Server-hosted short links**, and any online library with server logic. Both
  are post-1.0.
- **Whether shared tracks are separated from built-ins** in the picker, or mixed
  with a badge. A UI question for the front-end work.
