"""Contact sheets of runtime poses, silhouette cameras and head crops."""

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

from preview_sourced_mesh import render


def sheet(paths, out, columns):
    snapshots = []
    for path in paths:
        snapshots.extend(json.loads(path.read_text())["snapshots"])
    if not snapshots:
        raise ValueError("No review snapshots found")
    tile, caption = 260, 38
    rows = math.ceil(len(snapshots) / columns)
    image = Image.new("RGB", (columns * tile, rows * (tile + caption)), "#f6f6f6")
    draw = ImageDraw.Draw(image)
    for index, snapshot in enumerate(snapshots):
        x, y = index % columns * tile, index // columns * (tile + caption)
        image.paste(render(snapshot, size=tile), (x, y))
        name = snapshot["model"].replace("ultimate_", "").replace("daydaze_", "")
        draw.text((x + 8, y + tile + 1), name, fill="#273a45")
        draw.text((x + 8, y + tile + 17), str(snapshot["phase"]), fill="#273a45")
    image.save(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    for category, columns in [("poses", 5), ("views", 5), ("heads", 3)]:
        sheet(sorted(args.input.glob(f"*_{category}.json")), args.out / f"{category}.png", columns)


if __name__ == "__main__":
    main()
