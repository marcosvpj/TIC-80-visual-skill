# TIC-80 skill for Claude Code

A [Claude Code](https://claude.ai/code) skill that makes an agent productive and
accurate on [TIC-80](https://tic80.com) carts — including **headless
verification and screenshots**, so the agent can check its own work instead of
guessing.

Everything here was verified empirically against TIC-80 **1.2.3007** rather than
recalled from memory. API signatures are labelled by source.

## What it gives you

**Run and error-check a cart with no display:**

```bash
scripts/check-cart.sh cart.js [seconds]
```

Exit 0 = loaded and ran clean, 1 = engine error. This is less obvious than it
looks: `tic80` **exits 0 even on syntax and runtime errors**, and **ignores
SIGTERM** (so a plain `timeout` hangs forever). The script handles both.

**Actually see a frame:**

```bash
scripts/shot-cart.sh cart.js out.png --frames=90 --scale=2
```

Runs the cart N frames, reads the 240×136 screen straight out of VRAM with
`peek()`, and writes a PNG — which Claude Code's Read tool can display. No
display server, no window, no screen-capture timing races. Your cart is never
modified; the dumper is injected into a copy.

**Protect the cart's assets:**

```bash
scripts/check-assets.sh cart.js [git-ref]
```

The `// <TILES>` / `// <PALETTE>` / `// <MAP>` comment blocks are the cart's
sprites, palette, map and music — not dead code. Deleting them raises **no
error**; the cart still runs, just with no graphics. This checker inventories
every block, diffs against git, and fails with the exact restore command.

**Verify the tooling itself:**

```bash
scripts/self-test.sh      # 8 cases, incl. both asset-loss shapes
```

## Install

```bash
git clone git@github.com:marcosvpj/TIC-80-visual-skill.git ~/.claude/skills/tic80
```

Claude Code picks the skill up automatically from `~/.claude/skills/`. The
scripts need `tic80` on `PATH` and `python3` (standard library only — no pip
install, the PNG encoder is hand-rolled with `zlib` and `struct`).

## Layout

| Path | What |
|---|---|
| `SKILL.md` | The skill: rules, gotchas, cart anatomy, performance |
| `references/api.md` | API signatures, button table, RAM/VRAM maps, source-labelled |
| `scripts/check-cart.sh` | Headless run + error check |
| `scripts/shot-cart.sh` | Headless screenshot to PNG |
| `scripts/vram2png.py` | VRAM dump to PNG converter |
| `scripts/check-assets.sh` | Asset-block integrity vs git |
| `scripts/self-test.sh` | Validates the harness |

## Notable findings baked in

- **Code after the first asset block is silently ignored.** Blocks are often
  mid-file, so appending code at end-of-file is a no-op.
- **Asset blocks are parsed on `load`**, so a `.js` file is a complete
  self-contained cart, sprites and palette included.
- **`mouse()` returns an array in JS**, not an object. `time()` is float
  milliseconds. `print()` returns the drawn width in pixels.
- **TIC-80 documents itself**: `tic80 --cli --cmd 'help spr'` (also `ram`,
  `vram`, `buttons`, `keys`, `api`) beats the web docs and matches your build.
- `poke(0x0FF80, 1 << id)` simulates a held button, to screenshot input-gated
  states.

## Local assumptions worth adapting

Two sections encode the author's setup — adjust them for yours:

- **ES5-only** is enforced because these carts are deployed to an **R36S
  handheld**, whose bundled TIC-80 is an older Duktape (ES5.1) build. The
  desktop TIC-80 runs ES2020 fine and will *not* catch violations. If you only
  target desktop, drop that section.
- A note about a shell where `cat` is aliased to a colorizing wrapper, which
  silently injects ANSI escapes into files built with `cat > f <<EOF`. Harmless
  to keep; the scripts pre-flight for it either way.
