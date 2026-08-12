---
name: tic80
description: TRIGGER — read BEFORE writing or editing any TIC-80 cart code, and before answering questions about the TIC-80 API. Fires on: a `.tic` file; a `.js`/`.lua` file with a `// title:`/`// script:` metadata header or `<TILES>`/`<MAP>`/`<PALETTE>` asset blocks; a `TIC()`, `BOOT()`, or `BDR()` function; calls to `spr`, `btn`, `btnp`, `map`, `mget`, `mset`, `pmem`, `ttri`, `vbank`, `peek`/`poke`, `sfx`, `music`, `trace`; mentions of TIC-80, fantasy console, 240×136, or a "cart"/"cartridge". Carries the headless verification harness (carts can be run and error-checked without a display), source-labelled API signatures, JS-specific return shapes, and the 4bpp/FFI performance rules. Do not answer TIC-80 API questions from memory — argument orders and return shapes are easy to misremember, and this skill shows how to dump them from the installed binary with `help`.
---

# TIC-80

Fantasy console. 240×136 px, 16-color palette, 60 fps, 4 sound channels.
A cart is a **single source file** that contains both code and assets.

## Verify, don't guess — the harness

TIC-80 carts can be run and error-checked **headlessly, with no display**.
Use this instead of eyeballing code and hoping:

```bash
~/.claude/skills/tic80/scripts/check-cart.sh path/to/cart.js [seconds]
```

Exit 0 = loaded and ran clean. Exit 1 = engine error, with the engine's own
message. Syntax errors carry a line number (`at index.js:4`); runtime errors
usually name only the callback (`at TIC (index.js)`). Run it after any
non-trivial edit.

Three facts that make this work, all verified on TIC-80 1.2.3007 — they are
counter-intuitive and you will get this wrong if you improvise:

1. **`tic80` exits 0 even on syntax and runtime errors.** `$?` is useless as
   a pass/fail signal. Errors go to *stdout* as
   `SyntaxError: ... at index.js:4` / `ReferenceError: 'foo' is not defined
   at TIC (index.js)`. You must grep the output. The script does.
2. **`tic80` ignores SIGTERM.** A plain `timeout N tic80 ...` hangs forever.
   You must use `timeout -s KILL N`.
3. **A cart with no `exit()` runs until killed.** That is fine — running N
   seconds with no error output is a valid smoke test, and it needs no edit
   to the cart. Only add `exit()` to throwaway probe carts.

Raw form, if you need to drive it yourself:

```bash
cd <cart-dir> && timeout -s KILL 6 tic80 --fs=. --cli --skip --cmd 'load cart.js & run'
```

`trace()` output appears on stdout in `--cli` mode, so you can probe real
runtime values (see "Probing" below).

Both `.js` and binary `.tic` carts work. If the harness itself ever looks
wrong (new TIC-80 version, changed error text), run
`~/.claude/skills/tic80/scripts/self-test.sh` — it regenerates fixtures for
every outcome and checks the classification.

`PASS (WEAK)` means tic80 quit in under a second with no error text — either
the cart called `exit()` immediately (expected for probe carts) or it never
started. If you did not expect an immediate exit, confirm execution with a
gated probe before believing it.

**What the harness does NOT prove:** anything visual. A cart that draws
nothing, draws off-screen, or draws in the wrong colors passes cleanly. It
verifies "does not throw", never "looks right". For that, take a screenshot.

## Seeing the cart — headless screenshots

```bash
~/.claude/skills/tic80/scripts/shot-cart.sh cart.js out.png --frames=90 --scale=2
```

Then **Read the PNG** — the Read tool renders images, so you can actually look
at the frame you produced.

It works by running the cart for N frames, then reading the 240×136 screen
straight out of VRAM with `peek()` and converting the 4bpp data to PNG. No
display server, no window, no screen-capture timing races — the pixels are
exact. Your cart is never modified; the dumper goes into a copy.

- `--frames=N` picks the moment: raise it to get past a title screen or to
  land on a particular animation frame.
- Carts with no `<PALETTE>` block render with SWEETIE-16, TIC-80's default.
- Text carts (`.js`) only — it needs to inject code, so binary `.tic` is out.

Use this whenever a change is meant to alter what appears on screen. "It
loads" is not evidence that a layout, sprite, or color change is right.

**Driving the game:** to capture a state that needs input, poke the gamepad
register before the frame runs — `poke(0x0FF80, 1 << id)` sets button `id`
as held (see the button table in `references/api.md`).

## The commented blocks at the bottom are DATA — never delete them

```
// <TILES>
// 001:5555555555555555555555555555555555555555555555555555555555555555
// </TILES>
```

That is not commented-out code. **That is the cart's sprite sheet.** The same
goes for `<PALETTE>`, `<MAP>`, `<SPRITES>`, `<FLAGS>`, `<WAVES>`, `<SFX>`,
`<TRACKS>`, `<SCREEN>`. In this repo they are 26–71% of a cart file, and they
look exactly like dead commented-out junk, which is why they get deleted.

**Deleting them does not produce an error.** The cart still loads, still runs,
still passes the harness — it just renders with no graphics and a default
palette. The loss is silent, and if it is not caught before a commit the
artwork is gone.

Rules:

1. **Never remove or "tidy" a `// <TAG>` block**, no matter how much it looks
   like dead weight, and never as part of a cleanup, reformat, or size trim.
2. **Prefer `Edit` over `Write` on cart files.** A whole-file rewrite is the
   single most common way these blocks vanish — it is easy to reproduce the
   code faithfully and drop the 400 lines of hex at the bottom.
3. **If you must rewrite a whole cart, copy the blocks through byte for byte**,
   then verify.

Verify after any non-trivial edit:

```bash
~/.claude/skills/tic80/scripts/check-assets.sh cart.js
```

It inventories every block and compares against git `HEAD`, failing with the
exact restore command if any block lost data. `check-cart.sh` also prints a
block count so a sudden drop is visible.

Recovering after the fact, if the loss is not yet committed:

```bash
git show HEAD:path/to/cart.js > path/to/cart.js     # restore the whole file
git diff -- path/to/cart.js                          # or inspect what went
```

A missing `<PALETTE>` is also visible in a screenshot — `vram2png.py` prints
`note: cart has no <PALETTE>` and colors come out as SWEETIE-16 defaults.

## Never build a cart file with a shell heredoc

This shell aliases `cat` to a colorizing wrapper (ccat). Writing a cart with
`cat > cart.js <<'EOF'` **silently injects ANSI escape codes into the file**.
The cart then reports `binary string: not a precompiled chunk` — an error
that points nowhere near the real cause, and which cost real debugging time
to trace back.

Use the **Write tool**, or `printf '%s\n'`. Never a `cat` heredoc.
The harness pre-flights for this and fails loudly. To check by hand:

```bash
grep -c $'\033' cart.js      # must be 0
```

The same alias corrupts heredoc-built git commit messages — see the
`git-commit-safety` skill.

## Cart anatomy

A `.js` cart is a complete cartridge. Metadata header first, code, then
asset blocks as trailing comments:

```js
// title:  my game
// author: name
// desc:   short description
// script: js
// input:  gamepad          <-- omit unless you need mouse/keyboard

function TIC() { ... }

// <TILES>
// 001:5555555555555555555555555555555555555555555555555555555555555555
// </TILES>
// <PALETTE>
// 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
// </PALETTE>
```

- **`// script: js` is mandatory.** Verified: drop that line and TIC-80 parses
  the file as **Lua**, failing with `unexpected symbol near '//'`. An
  ANSI-corrupted cart fails differently, as `not a precompiled chunk`. Both
  errors point away from the real cause, so check the header first.
- **Code must come BEFORE the first asset block.** Verified: TIC-80 stops
  treating the file as code at the first `// <TILES>`-style marker, and
  anything after it is silently ignored — no error, the code simply never
  runs. Appending a function to the end of a cart file is a no-op. Asset
  blocks are often in the *middle* of the file, not at the end, so always
  check where they start before inserting code.
- **Asset blocks are parsed on `load`** — verified. A `.js` file alone is a
  fully self-contained cart, sprites and palette included. You can read and
  hand-edit these blocks; you do not need the binary `.tic`.
- Block tags seen in real carts: `<TILES>` `<SPRITES>` `<MAP>` `<PALETTE>`
  `<FLAGS>` `<WAVES>` `<SFX>` `<TRACKS>` `<SCREEN>`. Bank variants append a
  digit: `<TILES1>`, `<MAP1>`, `<PALETTE1>`.
- `// input:` accepts `gamepad`, `mouse`, `keyboard`, or combinations.
  `mouse()` does not report real values unless mouse input is declared.
- `.tic` is the binary export. **Edit the `.js`**; the `.tic` is regenerated
  by TIC-80. Never hand-edit a `.tic`.

## Write ES5 — this is a deployment constraint, not a style preference

**Write ES5 in every cart in this repo.** These games are run on an **R36S
handheld**, whose built-in TIC-80 is an older build using **Duktape (ES5.1)**.
Code that works on the desktop will fail on the device.

Forbidden, even though the desktop build accepts them:

- `let` / `const` → use `var`
- arrow functions (`=>`) → use `function`
- template literals (`` `${x}` ``) → use `"a" + x`
- classes → use factory functions or prototypes
- shorthand methods (`{ m() {} }`) → use `{ m: function () {} }`
- destructuring, spread/rest, default parameters, `for...of`

For `mouse()`, which returns an array, that means:

```js
var m = mouse();
var mx = m[0], my = m[1], left = m[2];   // not: const [mx,my,left] = mouse()
```

**The desktop TIC-80 will not catch these mistakes for you.** The installed
1.2.3007 embeds QuickJS and happily runs ES2020 — verified. So a cart using
arrow functions passes every local check and then breaks on the R36S. The
harness cannot catch it either. Reviewing for ES5 is a manual step.

Quick grep for the common offenders:

```bash
grep -nE '=>|`|\blet\b|\bconst\b|\.\.\.|\bclass\b|for *\([^;]*\bof\b' cart.js
```

(Expect false positives inside strings and comments — read the hits.)

Other supported languages: Lua (default), MoonScript, Fennel, Wren,
Squirrel, Ruby, Janet, Scheme, Python, WASM.

## Things that are easy to get wrong

**`mouse()` returns an array in JS, not an object:**

```js
const [mx, my, left, mid, right, sx, sy] = mouse();
```

**`time()` is float milliseconds** since cart start (not frames, not
seconds). For a frame counter, keep your own `var tick = 0; tick++`.

**`colorkey` defaults to `-1` = opaque.** `spr(id, x, y)` draws color 0 as
solid black. You almost always want `spr(id, x, y, 0)`.

**`print()` returns the drawn width in pixels** — measure with it rather
than estimating character widths:

```js
const w = print(msg, 0, -10);
print(msg, (240 - w) / 2, 60, 12);
```

**`spr()`'s `w`/`h` are in tiles, not pixels.** A 16×16 sprite is
`spr(id, x, y, 0, 1, 0, 0, 2, 2)`.

**Positional args only.** To set `scale` you must also pass `colorkey`.

**`pmem` values are unsigned 32-bit** (0–4294967295), 256 slots. Persistence
keys off the **cartridge MD5 by default — editing the code loses saved
data.** Set `// saveid:` in the header to keep saves across updates.

Signatures, button-id table, RAM/VRAM maps: `references/api.md`, with each
claim labelled by source. Read it rather than recalling argument order.

## TIC-80 documents itself — use it

The installed binary carries its own docs. This beats web lookups: it matches
the exact version you are running, needs no network, and is the fastest way to
settle an argument-order question.

```bash
tic80 --fs=. --cli --skip --cmd 'help spr'      # one function's full docs
tic80 --fs=. --cli --skip --cmd 'help buttons'  # button id table
tic80 --fs=. --cli --skip --cmd 'help keys'     # keyboard key codes
tic80 --fs=. --cli --skip --cmd 'help ram'      # memory map
```

Topics: `version welcome spec ram vram commands api keys buttons startup
hotkeys terms license`, plus any API function name. `help api` lists every
function the running build supports.

Output is ANSI-colored; strip it with `sed 's/\x1b\[[0-9;]*m//g'`.

## Performance

The console is 60 fps with no JIT. Two rules dominate, both drawn from a
performance post-mortem on a scrolling-world cart that degraded over a play
session:

**Native calls (`spr`, `pix`, `mget`, `Math.random`) cross an FFI boundary
and are expensive.** Hundreds per frame is the budget, not thousands. A
full-screen `pix()` loop is 32640 calls — never do it; poke VRAM or use
`map()`/`spr()`.

**Never let per-frame work outpace consumption.** The classic bug: generating
one world row per *frame* while the player consumes rows 5–6× slower, so the
data structure grows without bound. Gate generation on a position-derived
target, not a frame counter:

```js
const want = Math.floor(player.y / 8) + VIEWPORT_ROWS + MARGIN;
while (lastGenerated < want) { lastGenerated++; generate(lastGenerated); }
```

Also: prefer an object keyed by index over a sparse array with `delete`d
holes; iterate only populated entries rather than scanning all 30 columns;
batch or precompute `Math.random()` calls; remove genuinely dead *code*
(carts have a 64KB code limit).

When trimming for size, note that the `// <TILES>`-style blocks are **not**
code and do not count against you the way dead functions do — they are the
cart's assets. Never delete them to save space. See the section above.

`map()` draws a whole screen of tiles in one native call — far cheaper than
a `spr()` per tile.

## Probing runtime values

To answer "what does this actually return", write a throwaway cart and read
`trace()` from stdout:

```js
// title: probe
// script: js
function TIC() {
  trace("mouse=" + JSON.stringify(mouse()));
  trace("time=" + time());
  exit();
}
```

```bash
timeout -s KILL 15 tic80 --fs=. --cli --skip --cmd 'load probe.js & run'
```

This settled every empirical claim in this skill. Use it before asserting
anything the docs are vague about.

## Minimal working cart

Verified to load and run clean under the harness:

```js
// title:  minimal
// author: -
// desc:   minimal starting cart
// script: js

var t = 0;
var x = 96;
var y = 64;

function TIC() {
  if (btn(2)) x--;
  if (btn(3)) x++;
  if (btn(0)) y--;
  if (btn(1)) y++;

  cls(13);
  spr(1 + ((t / 8) % 4 | 0) * 2, x, y, 0, 3, 0, 0, 2, 2);
  print("hello world!", 84, 84);
  t++;
}
```

## Why the ES5 rule looks wrong but isn't

A project may state "ES5 only — do not use ES6+, the target runtime does not
support it." A probe on the desktop build appears to disprove this: QuickJS
runs ES2020 fine.

**Do not "correct" such a rule.** The target runtime is the deployment
device — here an R36S handheld — not the desktop. The rule is a portability
constraint about where the game ships, and the desktop build is simply a more
permissive environment than the deployment one. Treat local evidence that
"ES6 works" as evidence about the dev machine only.

The general lesson outlives this example: when a project constraint looks
contradicted by a local experiment, check whether you tested the same
environment the constraint is about before declaring the rule obsolete.
