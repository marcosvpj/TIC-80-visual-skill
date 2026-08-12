#!/usr/bin/env bash
# shot-cart.sh — render a TIC-80 cart to a PNG, headlessly.
#
# Runs the cart for N frames, then reads the 240x136 screen straight out of
# VRAM with peek() and converts it to a PNG you can actually look at.
# No display server, no window, no timing races — the pixels are exact.
#
# Usage:  shot-cart.sh <cart.js> [out.png] [--frames N] [--scale N]
#
#   --frames N   capture after N frames (default 2). Use a larger number to
#                get past intros, or to see animation at a chosen moment.
#   --scale N    integer upscale of the PNG (default 2). Does not change
#                what is rendered, only the image size.
#
# Only works on TEXT carts (.js). It appends a dumper to a COPY — your file
# is never modified.

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CART=""; OUT=""; FRAMES=2; SCALE=2

for a in "$@"; do
  case "$a" in
    --frames=*) FRAMES="${a#*=}" ;;
    --scale=*)  SCALE="${a#*=}" ;;
    --*)        echo "unknown option: $a" >&2; exit 2 ;;
    *)          if [ -z "$CART" ]; then CART="$a"; elif [ -z "$OUT" ]; then OUT="$a"; fi ;;
  esac
done

[ -n "$CART" ] && [ -f "$CART" ] || { echo "usage: shot-cart.sh <cart.js> [out.png] [--frames=N] [--scale=N]" >&2; exit 2; }
grep -Iq . "$CART" 2>/dev/null || { echo "shot-cart.sh needs a text cart (.js); got a binary" >&2; exit 2; }
[ -n "$OUT" ] || OUT="${CART%.*}-shot.png"

command -v tic80 >/dev/null 2>&1 || { echo "tic80 not on PATH" >&2; exit 2; }

# Same ANSI pre-flight as check-cart.sh: a ccat heredoc silently corrupts the
# source, and without this the failure surfaces as a confusing "no palette".
if grep -Iq . "$CART" 2>/dev/null && LC_ALL=C grep -q $'\033' "$CART" 2>/dev/null; then
  echo "FAIL — $CART contains ANSI escape codes (source is corrupted)."
  echo "       Caused by writing the file with \`cat > f <<EOF\` while cat is"
  echo "       aliased to ccat. Rewrite it with the Write tool or printf."
  exit 1
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
BASE="shot_$(basename "${CART%.*}").js"

# The dumper, written to a fragment first. ES5 only, so it is safe to inject
# into carts written for older TIC-80 builds. It wraps the cart's own TIC(),
# lets it draw, then reads VRAM on the chosen frame.
FRAG="$TMP/frag.js"
{
  printf '\n// ---- injected by shot-cart.sh ----\n'
  printf 'var __shotOrig = TIC;\n'
  printf 'var __shotN = 0;\n'
  printf 'TIC = function () {\n'
  printf '  __shotOrig();\n'
  printf '  __shotN++;\n'
  printf '  if (__shotN === %s) {\n' "$FRAMES"
  printf '    var h = "0123456789abcdef", s = "", i, b;\n'
  printf '    for (i = 0; i < 16320; i++) {\n'
  printf '      b = peek(i);\n'
  printf '      s += h[(b >> 4) & 15] + h[b & 15];\n'
  printf '      if (s.length >= 4096) { trace("S:" + s); s = ""; }\n'
  printf '    }\n'
  printf '    if (s.length) { trace("S:" + s); }\n'
  printf '    var p = "", j, v;\n'
  printf '    for (j = 0; j < 48; j++) {\n'
  printf '      v = peek(0x3FC0 + j);\n'
  printf '      p += h[(v >> 4) & 15] + h[v & 15];\n'
  printf '    }\n'
  printf '    trace("P:" + p);\n'
  printf '    exit();\n'
  printf '  }\n'
  printf '};\n'
} > "$FRAG"

# TIC-80 stops treating the file as code at the FIRST asset block, so the
# dumper must be inserted before it. Appending to the end of the file looks
# fine and silently never runs.
if grep -qE '^// <[A-Z]+[0-9]*>' "$CART"; then
  awk -v frag="$FRAG" '
    BEGIN { done = 0 }
    /^\/\/ <[A-Z]+[0-9]*>/ && !done {
      while ((getline line < frag) > 0) print line
      done = 1
    }
    { print }
  ' "$CART" > "$TMP/$BASE"
else
  cp "$CART" "$TMP/$BASE"
  awk '{ print }' "$FRAG" >> "$TMP/$BASE"
fi

RAW="$TMP/raw.txt"
(cd "$TMP" && env -u DISPLAY -u WAYLAND_DISPLAY \
   timeout -s KILL 60 tic80 --fs=. --cli --skip --cmd "load $BASE & run" 2>&1) \
  | sed 's/\x1b\[[0-9;]*m//g' > "$RAW"

if grep -qE 'SyntaxError|ReferenceError|TypeError|precompiled chunk|unexpected symbol' "$RAW"; then
  echo "FAIL — cart errored before it could be captured:"
  grep -E 'SyntaxError|ReferenceError|TypeError|precompiled chunk|unexpected symbol' "$RAW"
  exit 1
fi

python3 "$HERE/vram2png.py" "$RAW" "$OUT" "--scale=$SCALE" || exit 1
echo "frame $FRAMES of $CART"
