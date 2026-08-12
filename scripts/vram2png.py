#!/usr/bin/env python3
"""Convert a TIC-80 VRAM dump (from shot-cart.sh) into a PNG.

Reads the raw trace stream on stdin or from a file, extracts the screen
nibbles and the 16-color palette, and writes a 240x136 PNG.

TIC-80's trace() emits no newlines under --cli, so the stream is one long
line and must be parsed by marker, not by line.

Screen is 4bpp: one byte holds two horizontally adjacent pixels, LOW NIBBLE
FIRST (left pixel in the low nibble).

Usage: vram2png.py <raw.txt> <out.png> [--scale N]
"""
import re
import sys
import struct
import zlib

W, H = 240, 136
SCREEN_BYTES = W * H // 2  # 16320


def parse(raw):
    screen = "".join(re.findall(r"S:([0-9a-f]+)", raw))
    pal_m = re.search(r"P:([0-9a-f]{96})", raw)
    if not pal_m:
        sys.exit("no palette (P:) found — did the cart finish dumping?")
    if len(screen) < SCREEN_BYTES * 2:
        sys.exit(f"short screen dump: {len(screen)//2} of {SCREEN_BYTES} bytes")
    pal_hex = pal_m.group(1)
    # A cart with no <PALETTE> block leaves the VRAM palette zeroed, which
    # would render every color as black. Fall back to SWEETIE-16, TIC-80's
    # default palette, which is what such a cart actually displays.
    if set(pal_hex) == {"0"}:
        pal_hex = (
            "1a1c2c5d275db13e53ef7d57ffcd75a7f07038b764257179"
            "29366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57"
        )
        print("note: cart has no <PALETTE>; using default SWEETIE-16",
              file=sys.stderr)
    palette = [
        tuple(int(pal_hex[i * 6 + c * 2 : i * 6 + c * 2 + 2], 16) for c in range(3))
        for i in range(16)
    ]
    return screen[: SCREEN_BYTES * 2], palette


def to_rows(screen_hex, palette, scale):
    rows = []
    for y in range(H):
        row = bytearray()
        base = y * (W // 2) * 2
        for x in range(W // 2):
            byte = int(screen_hex[base + x * 2 : base + x * 2 + 2], 16)
            for nib in (byte & 0x0F, (byte >> 4) & 0x0F):  # low nibble = left
                row += bytes(palette[nib]) * scale
        rows.extend([bytes(row)] * scale)
    return rows


def write_png(path, rows, width, height):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    raw = b"".join(b"\x00" + r for r in rows)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as f:
        f.write(png)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    scale = 1
    for a in sys.argv[1:]:
        if a.startswith("--scale"):
            scale = int(a.split("=")[1]) if "=" in a else 1
    if len(args) < 2:
        sys.exit(__doc__)
    raw = open(args[0], "r", errors="replace").read()
    screen_hex, palette = parse(raw)
    rows = to_rows(screen_hex, palette, scale)
    write_png(args[1], rows, W * scale, H * scale)
    print(f"wrote {args[1]} ({W*scale}x{H*scale})")


if __name__ == "__main__":
    main()
