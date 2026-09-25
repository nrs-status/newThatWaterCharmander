#!/usr/bin/env python3
"""Generate a console (PSF2) bitmap font that extends Terminus ter-128n
(14x28) with three status glyphs usable from the virtual console (e.g. in
the tmux status bar):

  U+E100  CPU    (chip with pins)
  U+E101  RAM    (memory stick)
  U+E102  battery

The 256 original glyphs (and their unicode table entries) are preserved, so
the font looks exactly like ter-128n; the three icons are appended as glyph
slots 256..258 (PSF fonts may hold up to 512 glyphs) and the unicode map is
extended so the kernel console in UTF-8 mode resolves those codepoints to
the new glyphs.

Usage: mkstatusfont <terminus-psf.gz> <out.psf>
"""

import gzip
import struct
import sys

W = 14  # font width  (matches ter-128n)
H = 28  # font height (matches ter-128n)

PSF2_MAGIC = b"\x72\xb5\x4a\x86"


# --------------------------------------------------------------------------
# glyph bitmaps: a list of H strings of W chars, '#' = lit pixel
# --------------------------------------------------------------------------

def render(art):
    lines = art.strip("\n").split("\n")
    assert len(lines) == H, f"expected {H} rows, got {len(lines)}"
    for l in lines:
        assert len(l) == W, f"expected {W} cols, got {len(l)} in {l!r}"
    return lines


CPU = render(
    """
..............
..............
..#........#..
..#........#..
..#........#..
..............
.############.
.############.
.##........##.
.##........##.
.##..####..##.
.##..#..#..##.
.##..#..#..##.
.##..#..#..##.
.##..#..#..##.
.##..#..#..##.
.##..####..##.
.##........##.
.##........##.
.############.
.############.
..............
..#........#..
..#........#..
..#........#..
..............
..............
..............
"""
)

RAM = render(
    """
..............
...########...
...#......#...
...#......#...
...#.####.#...
...#.####.#...
...#.####.#...
...#......#...
...#.####.#...
...#.####.#...
...#.####.#...
...#......#...
...#.####.#...
...#.####.#...
...#.####.#...
...#......#...
...#......#...
...#......#...
...#......#...
...#......#...
...#......#...
...#......#...
...#......#...
...########...
...###..###...
...########...
..............
..............
"""
)

BATTERY = render(
    """
..............
..............
..............
..............
..............
..............
..............
..............
.##########...
.#........#...
.#.##..##.#...
.#.##..##.#...
.#.##..##.###.
.#.##..##.###.
.#.##..##.###.
.#.##..##.###.
.#.##..##.#...
.#.##..##.#...
.#........#...
.##########...
..............
..............
..............
..............
..............
..............
..............
..............
"""
)

GLYPHS = [CPU, RAM, BATTERY]

# codepoints the kernel console will map onto the appended glyph slots
CODEPOINTS = [0xE100, 0xE101, 0xE102]


# --------------------------------------------------------------------------
# PSF2 parsing
# --------------------------------------------------------------------------

def parse_psf2(data):
    magic, ver, hsize, flags, length, charsize, height, width = struct.unpack(
        "<4s7I", data[:32]
    )
    assert magic == PSF2_MAGIC, "not a PSF2 font"
    glyphs = data[hsize : hsize + length * charsize]
    rest = data[hsize + length * charsize :]
    if flags & 1:  # has unicode table
        table_raw = rest
    else:
        table_raw = None
    return {
        "ver": ver,
        "hsize": hsize,
        "flags": flags,
        "length": length,
        "charsize": charsize,
        "height": height,
        "width": width,
        "glyphs": glyphs,
        "table_raw": table_raw,
    }


def split_table(table_raw):
    """Split the raw unicode table into per-glyph byte blobs (PSF2 format:
    utf-8 encoded codepoints, 0xFF terminates a glyph, 0xFE starts a
    combining sequence that still belongs to the same glyph)."""
    entries = []
    cur = b""
    seq = False
    for b in table_raw:
        if b == 0xFF:
            entries.append(cur)
            cur = b""
            seq = False
        elif b == 0xFE:
            cur += bytes([b])
            seq = True
        else:
            cur += bytes([b])
    # trailing data should not exist; last glyph was terminated
    return entries


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def glyph_bytes(art):
    rows = []
    for line in art:
        bits = [1 if c == "#" else 0 for c in line]
        row = 0
        for i, b in enumerate(bits):
            row = (row << 1) | b
        # W = 14 -> 2 bytes per row, MSB first, padded in the low 2 bits
        row <<= (8 - W % 8) if W % 8 else 0
        nbytes = (W + 7) // 8
        rows.append(row.to_bytes(nbytes, "big"))
    return b"".join(rows)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    with gzip.open(src, "rb") as f:
        font = parse_psf2(f.read())

    assert font["width"] == W and font["height"] == H, (
        f"unexpected font geometry {font['width']}x{font['height']}"
    )

    length = 512  # kernel consoles support up to 512 glyph slots
    charsize = font["charsize"]

    glyphs = bytearray(b"\x00" * length * charsize)
    glyphs[: len(font["glyphs"])] = font["glyphs"]
    for i, art in enumerate(GLYPHS):
        gb = glyph_bytes(art)
        assert len(gb) == charsize, (len(gb), charsize)
        glyphs[(256 + i) * charsize : (257 + i) * charsize] = gb

    table = b""
    if font["table_raw"]:
        for entry in split_table(font["table_raw"]):
            table += entry + b"\xff"
    for cp in CODEPOINTS:
        table += chr(cp).encode("utf-8") + b"\xff"
    # the table must hold one (possibly empty) entry per glyph slot, so pad
    # the unused slots with bare terminators
    defined = font["length"] + len(CODEPOINTS)
    table += b"\xff" * (length - defined)

    hdr = struct.pack("<4s7I", PSF2_MAGIC, 0, 32, 1, length, charsize, H, W)
    out = hdr + bytes(glyphs) + table
    with open(dst, "wb") as f:
        f.write(out)
    print(f"wrote {dst}: {length} glyphs, {W}x{H}, charsize {charsize}")


if __name__ == "__main__":
    main()
