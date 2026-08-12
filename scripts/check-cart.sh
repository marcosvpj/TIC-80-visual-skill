#!/usr/bin/env bash
# check-cart.sh — headless smoke test for a TIC-80 cart.
#
# Loads and runs the cart in TIC-80's CLI mode, then scans stdout for engine
# errors. Works without a display server.
#
# Usage:  check-cart.sh <cart.js|cart.tic> [seconds]
#   seconds — how long to let the cart run before killing it (default 6).
#             Ignored if the cart calls exit() on its own.
#
# Exit status: 0 = no errors seen, 1 = error detected, 2 = bad invocation.
#
# WHY THIS SCRIPT EXISTS: `tic80` exits 0 even on syntax and runtime errors,
# so $? is worthless as a pass/fail signal. The only reliable signal is the
# error text printed to stdout.

set -uo pipefail

CART="${1:-}"
SECS="${2:-6}"

if [ -z "$CART" ] || [ ! -f "$CART" ]; then
  echo "usage: check-cart.sh <cart.js|cart.tic> [seconds]" >&2
  exit 2
fi

command -v tic80 >/dev/null 2>&1 || { echo "tic80 not on PATH" >&2; exit 2; }

# Pre-flight: ANSI escapes in the source. This shell aliases `cat` to a
# colorizing wrapper, so building a cart with `cat > f <<EOF` silently
# injects escape codes. TIC-80 then fails to parse the cart in a way that
# looks nothing like the real cause. Catch it here.
# grep -Iq . skips binary carts (.tic), where a 0x1B byte is legitimate data.
if grep -Iq . "$CART" 2>/dev/null && LC_ALL=C grep -q $'\033' "$CART" 2>/dev/null; then
  echo "FAIL — $CART contains ANSI escape codes (source is corrupted)."
  echo "       Almost always caused by writing the file with a heredoc"
  echo "       (\`cat > f <<EOF\`) while \`cat\` is aliased to ccat."
  echo "       Rewrite the file with the Write tool or printf."
  exit 1
fi

DIR=$(cd "$(dirname "$CART")" && pwd)
BASE=$(basename "$CART")

# -s KILL is REQUIRED: tic80 ignores SIGTERM, so a plain `timeout` hangs
# forever waiting on the command substitution.
START=$(date +%s)
OUT=$(cd "$DIR" && env -u DISPLAY -u WAYLAND_DISPLAY \
      timeout -s KILL "$SECS" tic80 --fs=. --cli --skip \
      --cmd "load $BASE & run" 2>&1)
RC=$?
ELAPSED=$(( $(date +%s) - START ))

# Engine errors are printed to stdout; the process still exits 0.
ERRS=$(printf '%s\n' "$OUT" \
  | grep -E 'SyntaxError|ReferenceError|TypeError|RangeError|InternalError|Error:|is not defined|is not a function|unexpected symbol|unexpected token|error:|precompiled chunk|attempt to|stack traceback' \
  || true)

printf '%s\n' "$OUT" | grep -v '^[[:space:]]*$'

echo "---"
if [ -n "$ERRS" ]; then
  echo "FAIL — engine reported an error:"
  printf '%s\n' "$ERRS"
  exit 1
fi

if ! printf '%s\n' "$OUT" | grep -q 'loaded!'; then
  echo "FAIL — cart never loaded (check the metadata header and file path)"
  exit 1
fi

if [ "$RC" -eq 137 ] || [ "$RC" -eq 124 ]; then
  echo "PASS — ran ${SECS}s with no engine error (cart never called exit(), so it was killed on timeout)"
elif [ "$ELAPSED" -lt 1 ]; then
  echo "PASS (WEAK) — tic80 quit in under a second with no error text."
  echo "  Either the cart called exit() immediately, or it never started."
  echo "  If you did not expect an immediate exit, confirm the cart really"
  echo "  executes by adding a gated probe and looking for its output:"
  echo "      var n=0; function TIC(){ n++; if(n===2){ trace(\"RAN\"); exit(); } }"
else
  echo "PASS — ran to completion with no engine error"
fi
# Surface the asset blocks. Deleting them is silent — the cart still runs,
# just with no graphics — so show the inventory on every run.
if grep -Iq . "$CART" 2>/dev/null; then
  BLOCKS=$(grep -cE '^// <[A-Z]+[0-9]*>' "$CART" 2>/dev/null || echo 0)
  DATA=$(grep -cE '^// [0-9a-f]{3}:' "$CART" 2>/dev/null || echo 0)
  echo "assets: $BLOCKS blocks, $DATA data lines" \
       "(run check-assets.sh to compare against git)"
fi

echo
echo "NOTE: this proves the cart LOADS and RUNS without throwing."
echo "      It does NOT verify anything visual. Nothing here checks that"
echo "      sprites, layout, colors, or gameplay look or behave correctly."
echo "      Use shot-cart.sh to actually look at a frame."
exit 0
