# Releasing

How Skid Jam versions, builds, and ships. Mechanical steps only. The lane mirrors
its sibling project's — iOS-only for now, with the macOS scope reserved for
when a Mac target lands.

## Branching

Trunk-based: `main` is the single trunk. Every change is a short-lived branch →
PR → merge to `main`. Releases are **tags**, not long-lived branches (see
Cutting a release). No `develop` branch.

**Version-line release branches are cut ON DEMAND, not routinely.** The only
reason to want one is patching an already-shipped version *after* trunk has
moved on. Branch from that version's last release tag then:

- Cut `release/<minor>.x` (e.g. `release/0.5.x`) **from that version's last
  release tag** (`git switch -c release/0.5.x ios/v0.5.0-3`). Forward work
  stays on `main`. (Any name but a `v` prefix — `release/v…` is reserved for
  the lane's own PR branches.)
- **Fixes land on the release branch** (branch off it → PR into it), NOT on
  `main`. Cut the patch build with the normal lane from the branch: the build
  number continues past every existing tag (trains never collide). Auto-merge
  falls back to a direct merge after green CI (the branch has no protection).
- **Every release-branch fix must also reach `main`** — cherry-pick it over,
  or the next version silently regresses it.
- **Delete it once that patched version ships.**

(Distinct from the transient `release/vX.Y.Z-N` branch `make release` creates
to carry a bump PR — that's lane machinery, auto-merged and deleted per build.)

## Versioning

Two numbers, both in [project.yml](project.yml) (the source of truth — the
`.xcodeproj` is generated, never hand-edited):

| Setting | Info.plist key | Meaning | Rule |
| --- | --- | --- | --- |
| `MARKETING_VERSION` | `CFBundleShortVersionString` | User-facing version, e.g. `0.5.0` | SemVer. Bump on a meaningful milestone. |
| `CURRENT_PROJECT_VERSION` | `CFBundleVersion` | Build number, e.g. `3` | **Unique & strictly increasing per upload — globally, regardless of the marketing version.** |

**The build-number rule is load-bearing.** App Store Connect rejects any
upload whose build number isn't higher than every build already uploaded, and
this counter does **not** reset when the marketing version changes. If ASC has
seen build 2, the next accepted upload is build 3 — even across a `0.1.0 →
0.5.0` bump. The lane enforces this: the next build is always one past the
highest existing tag (`highest_tagged_build` in
[Scripts/release-lib.sh](Scripts/release-lib.sh)), never reset by a version
bump.

### When to bump what

- **New build of the same version** (`0.5.0 (3)` → `0.5.0 (4)`): bump only
  `CURRENT_PROJECT_VERSION`. No TestFlight Beta App Review.
- **New version** (`0.5.0` → `0.6.0`): bump `MARKETING_VERSION`. **The first
  external build of a new version triggers a one-time Beta App Review**
  (~hours), keyed on the version *string*, not the change size.

**Version-bump policy (pre-1.0 beta).** Bump `MARKETING_VERSION` only when a
**roadmap milestone** lands (see [ROADMAP.md](ROADMAP.md)) — never for routine
iteration; climb build numbers freely within a milestone. Keeps the version
string meaningful (version = milestone = tags / GitHub releases / changelog)
and spreads each version's one-time Beta App Review across the project.

> Xcode's Organizer auto-increments the build number past an existing one at
> distribution time. If that happens, resync `project.yml`'s
> `CURRENT_PROJECT_VERSION` so the repo doesn't drift from the upload.

## Cutting a release

One command from a clean, up-to-date release base — `main`, or a version-line
`release/<minor>.x` branch when patching a shipped version:

```sh
make release                 # iOS → App Store Connect (PLATFORM defaults to ios)
make release UPLOAD=0        # everything through export, no ASC upload
make release-build           # alias for UPLOAD=0
# make release PLATFORM=macos / all  — reserved for when a Mac target exists
```

`make release` runs a four-step chain (each step its own
[`Scripts/release-*.sh`](Scripts/); the Makefile wires the order). The pure
steps re-derive their inputs from git + `project.yml`, so the only state passed
between them is the merged commit on the base — no state file:

1. **preflight** — refuse unless on a clean release base matching its origin,
   with `gh`/`xcodegen` available and an **opaque app icon** (ASC silently
   rejects a transparent icon; `make icon` flattens it).
2. **publish** — the interactive, stateful step. Prompts to bump
   `MARKETING_VERSION` on an all-platform release (blank = keep, `p` = patch,
   or type `X.Y.Z`); always bumps the build number to one past the highest
   tag. Stamps the changelog's *Unreleased (next build)* into `### build N`,
   commits on a `release/vX.Y.Z-N` branch, opens a PR, sets **auto-merge**,
   and **blocks until CI passes and it merges**. Red CI stops here — PR left
   open, nothing tagged or built.
3. **tag** — tags the merge commit and publishes a GitHub release with a
   version/build/commit table and the commits since the previous tag.
4. **distribute** — regenerates the project, archives, exports, and (unless
   `UPLOAD=0`) uploads to App Store Connect via
   [Scripts/distribute.sh](Scripts/distribute.sh).

### Tags

Every tag MUST be exactly `<prefix>/vMAJOR.MINOR.PATCH-BUILD` — platform
`<prefix>` is `ios` (or `mac` later); version is plain SemVer; the suffix is
the **build number**, not a beta/rc label:

```sh
ios/v0.5.0-3    # iOS, version 0.5.0, build 3
```

This format is **load-bearing**:

- **Platform prefix required** — keeps the scheme stable for a future Mac
  target sharing the bundle id.
- **The suffix is a plain integer build number.** No `-beta.N` / `-rc.N`: the
  lane orders tags with `--sort=-v:refname` and parses `(version, build)` to
  pick the previous release for a changelog (`previous_tag` in
  [Scripts/release-lib.sh](Scripts/release-lib.sh)); a pre-release suffix
  would mis-sort and corrupt that choice.

The **git tags are the source of truth** — immutable pointers to the exact
commit each build shipped from. GitHub releases are a presentation layer.

> **Never delete an immutable GitHub release.** GitHub permanently reserves the
> tag name — you cannot re-create a release on it. *Edit* to revise notes.

`make release` creates these; never tag by hand in the normal flow.

### By hand (fallback)

If you must bypass the lane (e.g. an Xcode-Organizer archive while debugging
signing), archive from a clean `main`, Distribute → App Store Connect, then
create the tag + GitHub release matching the scheme above. Prefer re-running
the lane; this is the escape hatch.

## Recovering from a failed release

The steps are **idempotent against the real artifacts** (tags, merge state) —
no progress file to go stale. Re-enter the chain at the right point:

| Where it died | What happened | Recovery |
| --- | --- | --- |
| preflight / publish, **before** the PR merged | nothing irreversible; PR (if any) left open | `make release` again — a clean restart |
| **after** the PR merged, before tagging | the base has the bumped build but no tag | `make release` — **publish self-skips** (its build is already ahead of every tag) and the chain tags + distributes |
| **partway through tagging** | tag or release missing | `make release-tag` — skips a done one, creates a missing release for an existing tag |
| **upload only** (export ok, ASC upload flaked) | the `.ipa` is already in `dist/` | `make release-upload` — uploads the existing package, no rebuild |
| **archive/export** | release is tagged; the build failed | `make release-distribute-retry` — verifies the tag exists, then re-archives/exports/uploads **without** touching git/PR/tags |

## One-time setup

- **App Store Connect app record** for `fi.misaki.skid`.
- **ASC API key**: App Store Connect → Users and Access → Integrations →
  App Store Connect API → generate (App Manager role). Put the `.p8` at
  `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`, then copy
  `Scripts/.asc-config.example` → `Scripts/.asc-config` (gitignored) and fill
  in the Key ID + Issuer ID.
- **Signing** is automatic (`-allowProvisioningUpdates`); no manual certs.
- **Repo setting**: "Allow auto-merge" enabled (the release PR self-merges on
  green CI).
