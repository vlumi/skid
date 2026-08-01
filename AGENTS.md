# Skid — agent & contributor guide

A top-down drift racer for Apple platforms; local multiplayer (2–4 on one
device), one thumb per player, static single-screen track. This file is how to
*work on* the repo — for humans and AI agents alike.

The driving is proven and the game is in beta (TestFlight since v0.1). Feel is
still the thing that matters most, and it can't be settled from a spec: game
feel needs device iteration, and every tuning knob belongs in the Tuning panel
where it can be tried.

The repo is fully independent and self-contained: it shares no code or
packages with any other project.

## Where things are documented

One place per concern — don't duplicate, link:

| | |
|---|---|
| **What the system is** | [ARCHITECTURE.md](ARCHITECTURE.md) — the sim, the track model, the piece model, the share code, and a fenced *Planned* chapter |
| **How to work on it** | this file — conventions, toolchain, PR process |
| **What's next, and when** | [ROADMAP.md](ROADMAP.md) |
| **Why a design was chosen** | `docs/*-plan.md`, linked from ARCHITECTURE.md |
| **What shipped** | [CHANGELOG.md](CHANGELOG.md) |

When something ships, move it out of ARCHITECTURE.md's *Planned* chapter and
into the prose above it. That chapter exists because the architecture notes
previously blurred built and intended, and drifted into describing a model
that had already been replaced.

## Conventions

- **Toolchain:** Xcode + Swift 6, **XcodeGen** (`.xcodeproj` generated,
  gitignored, never committed). The team ID IS committed in `project.yml`
  (it's not a secret, and the release lane's headless automatic signing
  needs it); certs/profiles are fetched by `-allowProvisioningUpdates`.
- **Bundle id:** `fi.misaki.skid` (working). **Universal Purchase** from the
  start if it ships to both platforms. MIT, no monetization.
- **Localization:** English-only for now, but String Catalog + `Text(_,
  bundle:)` / `String(localized:)` from day one — never hardcoded literals.
- **Comments minimal**; determinism for tests (injected RNG, fixed timestep).
- **Lint/format/CI:** pinned SwiftLint + swift-format both
  `--strict`; CI runs lint + core tests (with coverage) + builds. Coverage-
  ignore the view layer; keep testable logic in `SkidCore`.
- **PRs:** branch off `main`, one focused change; `Co-Authored-By: <model>
  <noreply@anthropic.com>` trailer; a user-facing PR writes its own CHANGELOG
  bullet; wait for Codecov before merging.

## Deliberately out of scope

See [ARCHITECTURE.md](ARCHITECTURE.md#deliberately-out-of-scope) — no ads, IAP,
accounts, server, global leaderboards, or third-party runtime dependencies, and
no performance upgrades ever.
