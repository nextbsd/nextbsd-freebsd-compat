#!/usr/bin/env bash
# strip-superseded.sh — delete FreeBSD base files NextBSD deliberately replaces
# with its own implementation (launchd, kextd/IOKit, nextbsd-installer, pkg),
# listed explicitly in scripts/superseded. These are NOT path collisions — they
# are distinct FreeBSD tools that would just be dead/conflicting weight.
#
# Every listed path MUST exist in the stage; a missing one means the list is
# stale (base stopped shipping it / renamed it) and the build FAILS so the list
# gets pruned. Reports ALL stale entries before failing.
set -euo pipefail

STAGE="${STAGE:-/stage}"
SELFDIR="$(cd "$(dirname "$0")" && pwd)"
LIST="${LIST:-$SELFDIR/superseded}"

[ -d "$STAGE" ] || { echo "FATAL: stage dir $STAGE missing" >&2; exit 2; }
[ -f "$LIST" ]  || { echo "FATAL: superseded list $LIST missing" >&2; exit 2; }

stale=0; n=0
while IFS= read -r raw; do
    path="${raw%%#*}"                                              # strip inline comment
    path="$(printf '%s' "$path" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$path" ] || continue                                    # skip blank / comment-only
    rel="${path#/}"                                               # tolerate leading slash
    target="$STAGE/$rel"
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then             # -L catches dangling symlinks
        echo "::error::stale superseded entry (not present in base): $path" >&2
        stale=1; continue
    fi
    rm -rf "$target"; n=$((n+1))
done < "$LIST"

if [ "$stale" -ne 0 ]; then
    echo "Prune the stale entries from $LIST, then re-run." >&2
    exit 1
fi
echo "Stripped $n superseded path(s) from $STAGE."
