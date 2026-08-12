#!/usr/bin/env bash
# self-test.sh — verify check-cart.sh still behaves on this machine/version.
#
# Generates throwaway carts covering each outcome and checks the harness
# classifies them correctly. Run this if check-cart.sh ever looks wrong, or
# after a TIC-80 upgrade.
#
# Usage: self-test.sh

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHECK="$HERE/check-cart.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# printf, never a `cat` heredoc — cat is aliased to ccat and would inject
# ANSI codes into these fixtures (which is itself one of the cases below).
printf '%s\n' '// title: good' '// script: js' \
  'var n=0;' 'function TIC(){ n++; if(n===2){ trace("RAN"); exit(); } }' > "$TMP/good.js"

printf '%s\n' '// title: syn' '// script: js' 'function TIC({' > "$TMP/syntax.js"

printf '%s\n' '// title: rt' '// script: js' \
  'function TIC(){ nosuchfunc(); }' > "$TMP/runtime.js"

printf '%s\n' '// title: loop' '// script: js' \
  'function TIC(){ cls(0); }' > "$TMP/loop.js"

# ANSI-corrupted source, as produced by a ccat heredoc.
printf '\033[38;2;255;70;137m//\033[39m title: ansi\n// script: js\nfunction TIC(){}\n' \
  > "$TMP/ansi.js"

pass=0; fail=0
expect() { # expect <label> <file> <want_rc> <want_pattern>
  local label=$1 file=$2 want_rc=$3 want_pat=$4
  local out rc
  out=$("$CHECK" "$file" 4 2>&1); rc=$?
  if [ "$rc" -eq "$want_rc" ] && printf '%s' "$out" | grep -q "$want_pat"; then
    printf 'ok    %-22s (rc=%s)\n' "$label" "$rc"; pass=$((pass+1))
  else
    printf 'FAIL  %-22s (rc=%s, wanted %s + /%s/)\n' "$label" "$rc" "$want_rc" "$want_pat"
    printf '%s\n' "$out" | sed 's/^/        /'; fail=$((fail+1))
  fi
}

expect "good cart"        "$TMP/good.js"    0 "PASS"
expect "syntax error"     "$TMP/syntax.js"  1 "FAIL"
expect "runtime error"    "$TMP/runtime.js" 1 "FAIL"
expect "no exit() -> kill" "$TMP/loop.js"   0 "killed on timeout"
expect "ANSI-corrupted"   "$TMP/ansi.js"    1 "ANSI escape codes"

"$CHECK" "$TMP/does-not-exist.js" >/dev/null 2>&1
if [ $? -eq 2 ]; then printf 'ok    %-22s (rc=2)\n' "missing file"; pass=$((pass+1))
else printf 'FAIL  %-22s\n' "missing file"; fail=$((fail+1)); fi

# --- asset-block protection ---
ASSETS="$HERE/check-assets.sh"
G="$TMP/repo"; mkdir -p "$G"
(cd "$G" && git init -q . && git config user.email t@t && git config user.name t) >/dev/null 2>&1
{ printf '%s\n' '// title: a' '// script: js' 'function TIC(){}' \
    '// <PALETTE>' '// 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57' '// </PALETTE>' \
    '// <TILES>' '// 001:5555555555555555555555555555555555555555555555555555555555555555' '// </TILES>'
} > "$G/cart.js"
(cd "$G" && git add cart.js && git commit -qm base) >/dev/null 2>&1

if "$ASSETS" "$G/cart.js" >/dev/null 2>&1; then
  printf 'ok    %-22s (rc=0)\n' "assets intact"; pass=$((pass+1))
else printf 'FAIL  %-22s\n' "assets intact"; fail=$((fail+1)); fi

grep -v '^// <PALETTE>\|^// 000:\|^// </PALETTE>' "$G/cart.js" > "$G/t" && mv "$G/t" "$G/cart.js"
if "$ASSETS" "$G/cart.js" >/dev/null 2>&1; then
  printf 'FAIL  %-22s (missed deleted palette)\n' "assets lost"; fail=$((fail+1))
else printf 'ok    %-22s (rc=1)\n' "assets lost"; pass=$((pass+1)); fi

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
