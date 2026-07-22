# Releasing

Cutting a TestFlight build is two steps from a clean, up-to-date `main`:

1. **Edit CHANGELOG.md by hand** (version numbers are editorial, never
   scripted): rename the pending section

   ```md
   ### Unreleased (next build)        →  ### v0.5.0 build 1 — 2026-07-23
   ```

   and open a fresh empty `### Unreleased (next build)` above it. Leaving
   this edit uncommitted is fine — it rides in the release PR.

2. Run the lane:

```sh
make release              # bump build → PR → tag → archive → upload
make release VERSION=0.6.0  # also bump the marketing version (build resets to 1)
make release-build        # same, but stop after export (no upload)
```

The publish step refuses to cut if the CHANGELOG heading for the new
version+build is missing.

The lane is three scripts chained by the Makefile, each standalone:

1. **`release-preflight`** — refuses unless you're on a clean `main`
   matching `origin`, with `gh` and `xcodegen` available. Pure; run anytime.
2. **`release-publish`** — bumps `CURRENT_PROJECT_VERSION` (and
   `MARKETING_VERSION` when `VERSION=` is given), **verifies the
   hand-written CHANGELOG heading**, lands it all on `main` via an
   **auto-merged PR** (main is protected), and tags the merge
   `vX.Y.Z-bN`. State crosses to the next step via that tagged commit,
   not the shell.
3. **`release-distribute`** — regenerates the project, archives
   `Skid-iOS`, exports the `.ipa` (`Scripts/ExportOptions.plist`,
   automatic signing), and uploads it to App Store Connect.

## Retry paths

Distribute is the likeliest step to fail and is safe to repeat:

```sh
make release-distribute-retry  # re-archive + upload an already-tagged release
make release-upload            # upload the existing dist/ package, no rebuild
```

Neither touches git, PRs, or tags.

## One-time setup

- **App Store Connect app record** for `fi.misaki.skid` (create it in ASC
  before the first upload).
- **ASC API key**: App Store Connect → Users and Access → Integrations →
  App Store Connect API → generate (App Manager role). Put the `.p8` at
  `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`, then copy
  `Scripts/.asc-config.example` → `Scripts/.asc-config` (gitignored) and
  fill in the Key ID + Issuer ID.
- **Signing** is automatic: the team ID is committed in `project.yml`, and
  `-allowProvisioningUpdates` fetches certs/profiles as needed. No manual
  cert or profile installs.
- **Repo settings**: "Allow auto-merge" must be enabled (the release PR
  merges itself once CI is green).

## Versioning

- `MARKETING_VERSION` tracks the roadmap milestone (`0.5.0`, …); bump it
  with `VERSION=` when a milestone ships. The build number
  (`CURRENT_PROJECT_VERSION`) climbs by one per TestFlight upload and
  resets to 1 on a version bump.
- Tags are `vX.Y.Z-bN` on the release's merge commit on `main`.
- The CHANGELOG convention: each user-facing PR writes bullets under
  *Unreleased (next build)*; at cut time YOU rename that section to the
  build's heading and open a fresh one — version numbers in the changelog
  are set by hand, the lane only verifies them (see AGENTS.md).
