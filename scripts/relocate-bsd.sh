#!/usr/bin/env bash
# relocate-bsd.sh — keep the FreeBSD base tools that NextBSD's wrappers exec
# (pw, chpass) under /usr/libexec/bsd, per scripts/relocated. The wrappers in
# nextbsd-userland own the original paths; they run these for root, the
# system users and /etc/group.
#
# Runs after strip-superseded.sh and BEFORE strip-collisions.sh: once moved,
# the originals no longer share a path with the wrappers, so nothing here
# needs the collision allowlist. Modes are applied explicitly because the
# unprivileged installworld cannot set setuid and the METALOG fix-up at pack
# time no longer finds the moved paths.
#
# Every `move` source and `drop` path must exist; a stale entry fails the
# build so the list gets pruned.
set -euo pipefail

STAGE="${STAGE:-/stage}"
SELFDIR="$(cd "$(dirname "$0")" && pwd)"
LIST="${LIST:-$SELFDIR/relocated}"

[ -d "$STAGE" ] || { echo "FATAL: stage dir $STAGE missing" >&2; exit 2; }
[ -f "$LIST" ]  || { echo "FATAL: relocation list $LIST missing" >&2; exit 2; }

stale=0; n=0
while IFS= read -r raw; do
    line="${raw%%#*}"
    set -- $line
    [ $# -gt 0 ] || continue
    op=$1
    case "$op" in
        move)
            [ $# -eq 4 ] || { echo "::error::bad move line: $raw" >&2; exit 2; }
            src="$STAGE/${2#/}"; dst="$STAGE/${3#/}"; mode=$4
            if [ ! -e "$src" ] && [ ! -L "$src" ]; then
                echo "::error::stale relocation entry (not present in base): $2" >&2
                stale=1; continue
            fi
            mkdir -p "$(dirname "$dst")"
            mv -f "$src" "$dst"
            chmod "$mode" "$dst"
            echo "moved $2 -> $3 ($mode)"
            ;;
        link)
            [ $# -eq 3 ] || { echo "::error::bad link line: $raw" >&2; exit 2; }
            dst="$STAGE/${2#/}"
            mkdir -p "$(dirname "$dst")"
            ln -sfn "$3" "$dst"
            echo "linked $2 -> $3"
            ;;
        drop)
            [ $# -eq 2 ] || { echo "::error::bad drop line: $raw" >&2; exit 2; }
            path="$STAGE/${2#/}"
            if [ ! -e "$path" ] && [ ! -L "$path" ]; then
                echo "::error::stale drop entry (not present in base): $2" >&2
                stale=1; continue
            fi
            rm -f "$path"
            echo "dropped $2"
            ;;
        *)
            echo "::error::unknown directive in $LIST: $raw" >&2; exit 2 ;;
    esac
    n=$((n+1))
done < "$LIST"

if [ "$stale" -ne 0 ]; then
    echo "Prune the stale entries from $LIST, then re-run." >&2
    exit 1
fi

# The wrappers depend on exactly these; assert them so a future list edit
# cannot silently leave the system side of pw and chpass without a backend.
for must in usr/libexec/bsd/pw usr/libexec/bsd/chpass; do
    [ -x "$STAGE/$must" ] || { echo "::error::$must missing after relocation" >&2; exit 1; }
done
[ -u "$STAGE/usr/libexec/bsd/chpass" ] || { echo "::error::usr/libexec/bsd/chpass is not setuid" >&2; exit 1; }
echo "Applied $n relocation directive(s) in $STAGE."
