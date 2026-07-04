#!/usr/bin/env bash
# strip-collisions.sh — remove from the staged base every path the NextBSD
# userland overlay (nextbsd-userland, Apple/Darwin) ALSO ships, so the overlay
# owns the canonical copy on the ISO (pkg refuses two packages owning one path).
#
# Self-policing: the collision set is DERIVED (intersect the staged base with the
# published userland file list), then checked against scripts/collisions. Any
# overlap NOT in that allowlist FAILS the build — so a future FreeBSD import or a
# new Apple daemon that starts sharing a path stops CI until a human records who
# wins, instead of silently clobbering.
set -euo pipefail

STAGE="${STAGE:-/stage}"
ARCH="${ARCH:?set ARCH (amd64|arm64)}"
SELFDIR="$(cd "$(dirname "$0")" && pwd)"
ALLOWLIST="${ALLOWLIST:-$SELFDIR/collisions}"
# NextBSD-userland publishes its file set as the continuous release tarball.
UL_URL="${UL_URL:-https://github.com/nextbsd-redux/nextbsd-userland/releases/download/continuous/nextbsd-userland-${ARCH}.tar.gz}"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
[ -d "$STAGE" ]     || { echo "FATAL: stage dir $STAGE missing" >&2; exit 2; }
[ -f "$ALLOWLIST" ] || { echo "FATAL: allowlist $ALLOWLIST missing" >&2; exit 2; }

# 1. Userland file list (STAGE-relative: drop leading ./, drop dir entries, blanks).
echo "Fetching userland file list: $UL_URL"
curl -fsSL "$UL_URL" -o "$tmp/ul.tgz"
tar tzf "$tmp/ul.tgz" | sed -e 's#^\./##' -e '/\/$/d' -e '/^$/d' | sort -u > "$tmp/overlay"

# 2. Staged base: every regular file / symlink, STAGE-relative.
( cd "$STAGE" && find . \( -type f -o -type l \) -print ) | sed 's#^\./##' | sort -u > "$tmp/staged"

# 3. Intersection = paths both ship.
comm -12 "$tmp/overlay" "$tmp/staged" > "$tmp/collide"
if [ ! -s "$tmp/collide" ]; then
    echo "No base/overlay collisions. Nothing to strip."
    exit 0
fi

# 4. Normalise the allowlist (drop comments/blanks/leading slash).
sed -E -e 's/#.*$//' -e 's/^[[:space:]]+//' -e 's/[[:space:]]+$//' -e '/^$/d' -e 's#^/##' \
    "$ALLOWLIST" | sort -u > "$tmp/allow"

# 5. Any collision NOT allow-listed is a policy violation -> FAIL.
comm -23 "$tmp/collide" "$tmp/allow" > "$tmp/violations"
if [ -s "$tmp/violations" ]; then
    echo "::error::Unapproved base<->userland collisions (not in $ALLOWLIST):" >&2
    sed 's/^/  /' "$tmp/violations" >&2
    echo "Add each to scripts/collisions (if the overlay should own it) or stop" >&2
    echo "base/overlay from shipping it, then re-run." >&2
    exit 1
fi

# 6. All approved -> strip.
n=0
while IFS= read -r rel; do rm -f "$STAGE/$rel"; n=$((n+1)); done < "$tmp/collide"
echo "Stripped $n approved base<->userland collision(s) from $STAGE."
