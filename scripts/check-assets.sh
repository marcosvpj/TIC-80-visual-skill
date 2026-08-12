#!/usr/bin/env bash
# check-assets.sh — make sure a cart's asset blocks are still intact.
#
# The `// <TILES>` / `// <PALETTE>` / `// <MAP>` … comment blocks at the end
# of a cart are NOT dead code — they ARE the sprites, palette, map and music.
# They look exactly like commented-out junk, which makes them easy to delete
# by accident during a refactor or a whole-file rewrite. Deleting them does
# not break the build: the cart still loads and runs, just with no graphics.
#
# Usage:
#   check-assets.sh <cart.js>            # inventory + compare against git HEAD
#   check-assets.sh <cart.js> <ref>      # compare against another git ref
#   check-assets.sh <cart.js> --list     # inventory only, no comparison
#
# Exit: 0 = no loss detected, 1 = asset data lost, 2 = bad invocation.

set -uo pipefail

CART="${1:-}"
REF="${2:-HEAD}"

[ -n "$CART" ] && [ -f "$CART" ] || {
  echo "usage: check-assets.sh <cart.js> [git-ref|--list]" >&2; exit 2; }

# tag -> number of data lines, emitted as "TAG count"
inventory() {
  awk '
    /^\/\/ <\/[A-Z]+[0-9]*>/ { intag = 0; next }
    /^\/\/ <[A-Z]+[0-9]*>/ {
      tag = $0; sub(/^\/\/ </, "", tag); sub(/>.*$/, "", tag)
      intag = 1; seen[tag] = seen[tag] + 0; order[++n] = tag; next
    }
    intag && /^\/\// { seen[tag]++ }
    END { for (i = 1; i <= n; i++) if (!printed[order[i]]++)
            printf "%s %d\n", order[i], seen[order[i]] }
  ' "$1"
}

CUR=$(inventory "$CART")

echo "asset blocks in $CART:"
if [ -z "$CUR" ]; then
  echo "  (none)"
else
  printf '%s\n' "$CUR" | while read -r tag n; do printf '  %-12s %4s data lines\n' "$tag" "$n"; done
fi

[ "$REF" = "--list" ] && exit 0

# Compare against the version in git, if we can get one.
DIR=$(cd "$(dirname "$CART")" && pwd)
git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "---"; echo "not a git repo — inventory only, nothing to compare against"; exit 0; }

ROOT=$(git -C "$DIR" rev-parse --show-toplevel)
REL="${DIR#$ROOT/}/$(basename "$CART")"
[ "$DIR" = "$ROOT" ] && REL=$(basename "$CART")

OLD_FILE=$(mktemp); trap 'rm -f "$OLD_FILE"' EXIT
if ! git -C "$ROOT" show "$REF:$REL" > "$OLD_FILE" 2>/dev/null; then
  echo "---"; echo "no $REF version of $REL (new file?) — nothing to compare"; exit 0
fi

OLD=$(inventory "$OLD_FILE")
echo "---"

lost=0
while read -r tag n; do
  [ -z "$tag" ] && continue
  now=$(printf '%s\n' "$CUR" | awk -v t="$tag" '$1==t {print $2}')
  now=${now:-0}
  if [ "$now" -lt "$n" ]; then
    echo "LOST  <$tag>: $n data lines in $REF, $now now"
    lost=1
  fi
done <<< "$OLD"

if [ "$lost" -eq 1 ]; then
  echo
  echo "FAIL — asset data was removed relative to $REF."
  echo "  These blocks are the cart's sprites/palette/map/music, not comments."
  echo "  Restore them:  git -C $ROOT show $REF:$REL > $CART"
  echo "  Or recover just the blocks and re-append them below your code."
  exit 1
fi

echo "OK — no asset block lost data relative to $REF"
exit 0
