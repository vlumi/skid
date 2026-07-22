#!/usr/bin/env bash
# Release step 1 (pure): refuse to start unless we're on a clean release base
# (main, or a release/X.Y.x maintenance branch — see release_base) that matches
# origin, with gh available — so the commit we eventually tag and build is
# exactly what reviewers see and what lands on the base. Mutates nothing; safe
# to run anytime.
set -euo pipefail
cd "$(dirname "$0")/.."
. Scripts/release-lib.sh

command -v gh >/dev/null || die "gh CLI not found (needed to open + auto-merge the PR)."
command -v xcodegen >/dev/null || die "xcodegen not found (brew install xcodegen)."
[ -z "$(git status --porcelain)" ] || die "working tree not clean — commit or stash first."

# The App Store icon must have NO alpha channel — App Store Connect silently
# refuses a transparent icon (it just never shows up). `make icon` flattens
# to opaque, but guard the release anyway so a hand-edited or regenerated
# icon can never ship transparent. sips reports "hasAlpha: yes/no".
icon="Sources/Shared/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
if [ -f "$icon" ]; then
    if sips -g hasAlpha "$icon" 2>/dev/null | grep -q "hasAlpha: yes"; then
        die "app icon has an alpha channel — ASC will reject it. Rerun \`make icon\` (it flattens to opaque)."
    fi
else
    die "app icon not found at $icon."
fi

base="$(release_base)"
say "Fetching origin…"
git fetch --quiet origin "$base"
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$base")" ] \
    || die "local ${base} differs from origin/${base} — pull/push to sync first."
echo "✓ preflight: on a clean ${base} matching origin."
