# Shared helpers for the release scripts. Sourced, not executed.

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

# Read a build setting that must have ONE distinct value across project.yml.
read_unique() {
    local key="$1" values
    values="$(grep -E "^[[:space:]]+${key}:" project.yml | sed -E 's/.*: *"?([^"]*)"?/\1/' | sort -u)"
    [ "$(printf '%s\n' "$values" | wc -l | tr -d ' ')" = 1 ] \
        || die "${key} has multiple values in project.yml: $values"
    printf '%s' "$values"
}

# Rewrite a build setting everywhere it appears in project.yml.
write_setting() {
    local key="$1" value="$2"
    sed -i '' -E "s/^([[:space:]]+${key}:).*/\1 \"${value}\"/" project.yml
}

tag_name() { printf 'v%s-b%s' "$1" "$2"; }

CHANGELOG_FILE="CHANGELOG.md"

# Stamp the changelog's "Unreleased (next build)" section at release time: the
# bullets a cycle's PRs accumulated there get promoted to a mechanical
# "### vX.Y.Z build N — <today>" heading, and a fresh empty Unreleased takes
# its place. Bullets stay editorial (PRs write them); the "## vX.Y.Z" marketing
# heading stays hand-written above. This only does the mechanical rename —
# closing the gap where a build could ship without a heading.
# No-op (exit 0, nothing staged) if Unreleased has no real content yet, so a
# build with only doc/internal changes doesn't get an empty heading.
promote_changelog_build() {
    local version="$1" build="$2"
    local unreleased="### Unreleased (next build)"
    [ -f "$CHANGELOG_FILE" ] || { say "no $CHANGELOG_FILE — skipping changelog stamp."; return 0; }

    # Refuse if this build's heading already exists (a rerun after the bump
    # merged, or a stray hand-edit) — promoting again would duplicate it.
    local heading="### v${version} build ${build}"
    if grep -qF "$heading" "$CHANGELOG_FILE"; then
        echo "  ($heading already present — nothing to promote)"
        return 0
    fi

    # Unreleased is immediately followed by its list items (see the CHANGELOG
    # preamble). "Anything to promote?" = a list item before the next "### "
    # heading. No-op otherwise, so a doc/internal-only build gets no heading.
    awk '
        f && /^#/ { exit 1 }
        f && /^[[:space:]]*-[[:space:]]/ { exit 0 }
        $0 == h { f = 1 }
    ' h="$unreleased" "$CHANGELOG_FILE" || {
        echo "  (Unreleased has no entries — nothing to promote)"
        return 0
    }

    local today; today="$(date +%Y-%m-%d)"
    local tmp; tmp="$(mktemp)"
    awk -v heading="$heading" -v today="$today" '
        $0 == h && !done {
            print h "\n\n" heading " — " today
            done = 1
            next
        }
        { print }
    ' h="$unreleased" "$CHANGELOG_FILE" > "$tmp"
    mv "$tmp" "$CHANGELOG_FILE"
    git add "$CHANGELOG_FILE"
    echo "  promoted Unreleased → v${version} build ${build}"
}
