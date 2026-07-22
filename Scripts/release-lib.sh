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
