#!/usr/bin/env bash
# Release step 2 (the stateful one): bump the build number (and the
# marketing version when VERSION=x.y.z is given), verify the CHANGELOG's
# version/build heading was written BY HAND, land it all on main via an
# auto-merged PR (main is protected), then tag the merge.
#
# The changelog is editorial: rename "### Unreleased (next build)" to
# "### vX.Y.Z build N — YYYY-MM-DD" yourself (and open a fresh pending
# section above it) before running this; the edit may sit uncommitted —
# it rides in the release PR. The script only checks it exists.
#
# State crosses to the next step via the tagged commit on main, not through
# the shell — so `release-distribute` can run standalone later.
set -euo pipefail
cd "$(dirname "$0")/.."
. Scripts/release-lib.sh

version="$(read_unique MARKETING_VERSION)"
build="$(read_unique CURRENT_PROJECT_VERSION)"

new_version="${VERSION:-$version}"
if [ "$new_version" != "$version" ]; then
    new_build=1
else
    new_build=$((build + 1))
fi
tag="$(tag_name "$new_version" "$new_build")"
say "Cutting ${tag} (was v${version} build ${build})…"

# The changelog heading is hand-written — refuse to cut without it.
heading="### v${new_version} build ${new_build}"
grep -qF "$heading" CHANGELOG.md || die "CHANGELOG.md is missing \"${heading} — <date>\".
Rename the pending \"### Unreleased (next build)\" section to it by hand
(and open a fresh empty pending section above it), then rerun."
grep -qF "### Unreleased (next build)" CHANGELOG.md \
    || die "CHANGELOG.md has no fresh \"### Unreleased (next build)\" section — open one above the new heading."

write_setting MARKETING_VERSION "$new_version"
write_setting CURRENT_PROJECT_VERSION "$new_build"

branch="release/${tag}"
git switch -c "$branch"
git add project.yml CHANGELOG.md
git commit -m "Release ${tag}

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push -u origin "$branch"

say "Opening auto-merging PR…"
gh pr create --title "Release ${tag}" --body "Version/build bump + changelog cut for ${tag}." >/dev/null
gh pr merge --auto --merge "$branch" \
    || die "couldn't enable auto-merge — enable 'Allow auto-merge' in the repo settings, or merge the PR by hand and rerun."

say "Waiting for CI + merge…"
for _ in $(seq 1 60); do
    state="$(gh pr view "$branch" --json state -q .state)"
    [ "$state" = "MERGED" ] && break
    [ "$state" = "CLOSED" ] && die "release PR was closed without merging."
    sleep 20
done
[ "$(gh pr view "$branch" --json state -q .state)" = "MERGED" ] \
    || die "release PR not merged after 20 min — investigate, then rerun (it will no-op the bump)."

git switch main
git pull --quiet
git branch -D "$branch" >/dev/null
git push origin --delete "$branch" >/dev/null 2>&1 || true

say "Tagging ${tag} on main…"
git tag "$tag"
git push --quiet origin "$tag"
echo "✓ published: ${tag} on main, tagged."
