#!/usr/bin/env python3
"""Stitch contact sheets into one comparison image, a row per input.

    stitch.py --out cmp.png --cell 512 [--take collage|lines|both] [--width 2000] SHEET ...

SHEET is a PNG from tests/plant_sheet.gd (each plant is two cells side by
side: painted line art, then the collage), or any other image (taken whole,
as one cell). --take picks which half of each plant to keep. Every input
becomes one row. Writes --out at full size and, when it is wider than
--width, a copy scaled to that width next to it ("_small"), which is the one
to look at with the Read tool.
"""
import argparse
from pathlib import Path

from PIL import Image


def cells(path: Path, cell: int, take: str) -> list:
    im = Image.open(path).convert("RGB")
    if im.width % (cell * 2) or im.height % cell:
        return [im]
    out = []
    for y in range(0, im.height, cell):
        for x in range(0, im.width, cell * 2):
            pair = im.crop((x, y, x + cell * 2, y + cell))
            # An empty slot at the end of a short last row is all one color.
            if pair.getextrema() and all(lo == hi for lo, hi in pair.getextrema()):
                continue
            if take == "both":
                out.append(pair)
            else:
                left = 0 if take == "lines" else cell
                out.append(pair.crop((left, 0, left + cell, cell)))
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("sheets", nargs="+", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--cell", type=int, default=512)
    ap.add_argument("--take", choices=["collage", "lines", "both"], default="collage")
    ap.add_argument("--width", type=int, default=2000)
    args = ap.parse_args()
    rows = [cells(p, args.cell, args.take) for p in args.sheets]
    w = max(sum(c.width for c in row) for row in rows)
    h = sum(max(c.height for c in row) for row in rows)
    sheet = Image.new("RGB", (w, h), (90, 90, 96))
    y = 0
    for row in rows:
        x = 0
        for c in row:
            sheet.paste(c, (x, y))
            x += c.width
        y += max(c.height for c in row)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.out)
    print(f"wrote {args.out} ({w}x{h})")
    if w > args.width:
        small = args.out.with_name(args.out.stem + "_small" + args.out.suffix)
        sheet.resize((args.width, round(h * args.width / w)), Image.LANCZOS).save(small)
        print(f"wrote {small} ({args.width}x{round(h * args.width / w)})")


if __name__ == "__main__":
    main()
