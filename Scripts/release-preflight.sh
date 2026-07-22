#!/usr/bin/env bash
# Release step 1 (pure): refuse to start unless we're on a clean main that
# matches origin, with gh available — so the commit we eventually tag and
# build is exactly what lands on main. Mutates nothing; safe to run anytime.
set -euo pipefail
cd "$(dirname "$0")/.."
. Scripts/release-lib.sh

command -v gh >/dev/null || die "gh CLI not found (needed to open + auto-merge the release PR)."
command -v xcodegen >/dev/null || die "xcodegen not found (brew install xcodegen)."
# The publish step stamps the CHANGELOG itself, so the tree must be fully
# clean — nothing rides into the release PR but the lane's own bump + stamp.
dirty="$(git status --porcelain || true)"
[ -z "$dirty" ] || die "working tree not clean:
$dirty"
[ "$(git branch --show-current)" = "main" ] || die "not on main."
say "Fetching origin…"
git fetch --quiet origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
    || die "local main differs from origin/main — pull/push to sync first."
echo "✓ preflight: on a clean main matching origin."
