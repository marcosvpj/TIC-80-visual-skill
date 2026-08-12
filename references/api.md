# TIC-80 API Reference (JavaScript)

**Sources, and how much to trust each line:**

- **[binary]** — dumped from the installed TIC-80 itself via `help <name>`.
  Authoritative for the version you are running. Regenerate any time:
  ```bash
  tic80 --fs=. --cli --skip --cmd 'help spr'     # or ram, vram, spec, keys, buttons, api
  ```
- **[probed]** — observed by running a cart and reading `trace()` output.
  Verified on TIC-80 1.2.3007.
- **[unverified]** — plausible but not confirmed here. Probe before relying on it.

Tables below were taken from TIC-80 **1.2.3007**. If `tic80 --version` differs,
re-dump rather than trusting this file.

`=value` marks a default. Arguments are positional — JS has no named args, so
to set a later argument you must supply every earlier one.

---

## Callbacks [binary]

| Callback | When |
|---|---|
| `BOOT()` | once, at cart start |
| `TIC()` | every frame, 60 fps — the main loop |
| `MENU(index)` | when a custom menu item is chosen |
| `BDR(row)` | per scanline, for palette/offset raster tricks |
| `SCN(row)` | older name for `BDR`; prefer `BDR` |

Only `TIC()` is required.

## Drawing [binary]

```
cls(color=0)
pix(x y color)                    pix(x y) -> color
line(x0 y0 x1 y1 color)
rect(x y w h color)               rectb(x y w h color)
circ(x y radius color)            circb(x y radius color)
elli(x y a b color)               ellib(x y a b color)
tri(x1 y1 x2 y2 x3 y3 color)      trib(x1 y1 x2 y2 x3 y3 color)
ttri(x1 y1 x2 y2 x3 y3 u1 v1 u2 v2 u3 v3 texsrc=0 chromakey=-1 z1=0 z2=0 z3=0)
clip(x y width height)            clip()          // no args = reset
paint(x y color bordercolor=-1)                   // flood fill
```

`ttri` is the textured triangle used for pseudo-3D. `u`/`v` address the sprite
sheet **as one large image in pixels**, not by sprite id — the top-left of
sprite #2 is `u=16, v=0` [binary]. `texsrc` selects image ram / map ram /
vbank, in that order [binary], which implies `0`/`1`/`2` respectively —
**[unverified]**, probe it before depending on the numbering.

## Sprites and map [binary]

```
spr(id x y colorkey=-1 scale=1 flip=0 rotate=0 w=1 h=1)
map(x=0 y=0 w=30 h=17 sx=0 sy=0 colorkey=-1 scale=1 remap=nil)
mget(x y) -> tile_id
mset(x y tile_id)
fget(sprite_id flag) -> bool
fset(sprite_id flag bool)
```

- `colorkey=-1` means **opaque** — color 0 draws as solid black. Pass `0` for
  the usual transparency. Most common sprite bug.
- `flip`: 0 none, 1 horizontal, 2 vertical, 3 both [binary].
- `rotate`: clockwise in 90° steps — 0, 1=90°, 2=180°, 3=270° [binary].
- `w`/`h` are in **tiles**: a 16×16 sprite is `spr(id,x,y,0,1,0,0,2,2)`.
- `map` defaults draw exactly one screenful (30×17 tiles).

## Text [binary]

```
print(text x=0 y=0 color=15 fixed=false scale=1 smallfont=false) -> width
font(text x y chromakey char_width char_height fixed=false scale=1 alt=false) -> width
```

`print` **returns the rendered width in pixels** [probed] — use it to center
or right-align rather than guessing character widths:

```js
const w = print(msg, 0, -10);          // measure off-screen
print(msg, (240 - w) / 2, 60, 12);     // then draw centered
```

`fixed=true` puts every character in an equal-width box; when false there is a
single space between characters [binary]. `font()` uses the foreground sprites.

## Input [binary]

```
btn(id) -> pressed
btnp(id hold=-1 period=-1) -> pressed
key(code=-1) -> pressed
keyp(code=-1 hold=-1 period=-1) -> pressed
mouse() -> x y left middle right scrollx scrolly
```

Button ids, from `help buttons` [binary]:

| Action | P1 | P2 | P3 | P4 |
|---|---|---|---|---|
| UP | 0 | 8 | 16 | 24 |
| DOWN | 1 | 9 | 17 | 25 |
| LEFT | 2 | 10 | 18 | 26 |
| RIGHT | 3 | 11 | 19 | 27 |
| A | 4 | 12 | 20 | 28 |
| B | 5 | 13 | 21 | 29 |
| X | 6 | 14 | 22 | 30 |
| Y | 7 | 15 | 23 | 31 |

Default keyboard binding is A=Z, B=X, X=A, Y=S **[unverified]** — it is
user-remappable via BUTTONS MAPPING, so treat any keyboard label in a comment
as a convention, not a guarantee. Carts in this repo consistently use 4 for
confirm and 5 for cancel.

`btn()` returns a real boolean in JS [probed].

**`mouse()` returns an ARRAY in JavaScript**, not an object [probed]:

```js
const [mx, my, ml, mm, mr, sx, sy] = mouse();
```

Mouse values are only meaningful when the cart declares `// input: mouse`
(or `gamepad+mouse`). Key codes: `tic80 --cli --cmd 'help keys'` [binary].

## Audio [binary]

```
sfx(id note=-1 duration=-1 channel=0 volume=15 speed=0)
music(track=-1 frame=-1 row=-1 loop=true sustain=false tempo=-1 speed=-1)
```

- `sfx(-1)` stops the channel [binary].
- `note`: integer 0–95 (8 octaves × 12), or a string — two chars for the note
  (`C-`, `C#`, `D-` … no flats) plus an octave digit 0–8, e.g. `"D-2"` [binary].
- `duration` is in ticks at 60 fps, so 30 = half a second; `-1` = continuous.
- `channel` 0–3.

## Memory [binary]

```
peek(addr bits=8) -> value      poke(addr value bits=8)
peek1/peek2/peek4(addr)         poke1/poke2/poke4(addr value)
memcpy(dest source size)        memset(dest value size)
pmem(index) -> value            pmem(index value)
sync(mask=0 bank=0 tocart=false)
vbank(bank) -> prev             vbank() -> prev
```

`pmem`: 256 slots of **unsigned** 32-bit ints (0–4294967295) [binary]. Store
negatives with an offset. Persistence keys off the **cartridge MD5 hash**, so
editing the code loses saved data — set `// saveid:` in the metadata header to
override that and survive updates [binary].

`vbank(1)` switches to the overlay bank; restore with `vbank(0)` before the
frame ends. `sync` moves data between banks (8 banks, Pro only) [binary].

## System [binary]

```
time() -> ms                 // float milliseconds since start [probed]
tstamp() -> seconds          // unix timestamp
trace(message color=15)
exit()   reset()
fft(start_freq end_freq=-1)  ffts(...)   // only with --fft
```

`trace()` goes to the console and to **stdout under `--cli`**, which is what
makes headless testing possible.

---

## Console spec [binary]

```
DISPLAY 240x136 pixels, 16 colors palette
INPUT   4 gamepads with 8 buttons / mouse / keyboard
SPRITES 256 8x8 tiles and 256 8x8 sprites
MAP     240x136 cells, 1920x1088 pixels
SOUND   4 channels with configurable waveforms
CODE    64KB of lua or js
```

## 96KB RAM layout [binary]

| Addr | Region | Bytes |
|---|---|---|
| `0x00000` | VRAM | 16384 |
| `0x04000` | TILES (sprites #0–255) | 8192 |
| `0x06000` | SPRITES (#256–511) | 8192 |
| `0x08000` | MAP | 32640 |
| `0x0FF80` | GAMEPADS | 4 |
| `0x0FF84` | MOUSE | 4 |
| `0x0FF88` | KEYBOARD | 4 |
| `0x0FF8C` | SFX STATE | 16 |
| `0x0FF9C` | SOUND REGISTERS | 72 |
| `0x0FFE4` | WAVEFORMS | 256 |
| `0x100E4` | SFX | 4224 |
| `0x11164` | MUSIC PATTERNS | 11520 |
| `0x13E64` | MUSIC TRACKS | 408 |
| `0x13FFC` | MUSIC STATE | 4 |
| `0x14000` | STEREO VOLUME | 4 |
| `0x14004` | PERSISTENT MEMORY (`pmem`) | 1024 |
| `0x14404` | SPRITE FLAGS | 512 |
| `0x14604` | FONT | 1016 |
| `0x149FC` | FONT PARAMS | 8 |
| `0x14A04` | ALT FONT | 1016 |
| `0x14DFC` | ALT FONT PARAMS | 8 |
| `0x14E04` | BUTTONS MAPPING | 32 |
| `0x14E24` | PCM SAMPLES | 128 |

## 16KB VRAM layout [binary]

| Addr | Region | Bytes |
|---|---|---|
| `0x00000` | SCREEN | 16320 |
| `0x03FC0` | PALETTE | 48 |
| `0x03FF0` | PALETTE MAP | 8 |
| `0x03FF8` | BORDER COLOR | 1 |
| `0x03FF9` | SCREEN OFFSET | 2 |
| `0x03FFB` | MOUSE CURSOR | 1 |
| `0x03FFC` | BLIT SEGMENT | 1 |

Common pokes:

```js
poke(0x3FF9, dx); poke(0x3FFA, dy);   // screen shake — moves border too
poke(0x3FF8, c);                       // border color
```

Screen shake via SCREEN OFFSET is far cheaper than redrawing at an offset.

## Sprite / tile data format

Tiles are 4 bits per pixel: one byte holds two horizontally adjacent pixels,
**low nibble first** [probed — palette and tile bytes read back via `peek`].
One 8×8 tile = 32 bytes, so tile `id` starts at `0x4000 + id*32`. In `.js`
source each tile is one line of 64 hex chars under `// <TILES>`.
