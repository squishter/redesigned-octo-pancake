"""Assemble the study's real Godot renders into labelled review sheets.

Requires Pillow. Run after build_plants.py and check_plants.gd:
    python experiments/plant_3d/make_sheets.py --input=/tmp/plant-library-v2
"""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


PAPER = "#f8f5ee"
INK = "#283e36"
MUTED = "#65746a"
VIEWS = ("front", "three_quarter", "side", "back", "high")


def font(size):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                 "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf"):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def sheet(path, title, subtitle, cells, columns, image_size=240):
    margin, header, gutter, footer = 24, 105, 14, 46
    width = margin * 2 + columns * image_size + (columns - 1) * gutter
    rows = (len(cells) + columns - 1) // columns
    height = header + rows * (image_size + footer + gutter) + margin
    canvas = Image.new("RGB", (width, height), PAPER)
    draw = ImageDraw.Draw(canvas)
    draw.text((margin, 20), title, fill=INK, font=font(27))
    draw.text((margin, 62), subtitle, fill=MUTED, font=font(14))
    for index, (image_path, label, detail) in enumerate(cells):
        x = margin + index % columns * (image_size + gutter)
        y = header + index // columns * (image_size + footer + gutter)
        tile = Image.open(image_path).convert("RGB")
        tile = tile.resize((image_size, image_size), Image.Resampling.LANCZOS)
        canvas.paste(tile, (x, y))
        draw.text((x + 3, y + image_size + 6), label, fill=INK, font=font(14))
        draw.text((x + 3, y + image_size + 26), detail, fill=MUTED, font=font(11))
    canvas.save(path)
    print(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path("/tmp/plant-library-v2"))
    args = parser.parse_args()
    catalog = json.loads((args.input / "catalog.json").read_text())
    previews = args.input / "previews"
    for group in ("flowers", "leaves", "stems"):
        cells = []
        for entry in catalog[group]:
            cells.append((previews / f"component_{entry['id']}_lines.png",
                          entry["id"].replace("_", " ").title(),
                          f"{entry['triangles']:,} triangles · authored mesh"))
        sheet(previews / f"{group}_library.png", f"Modular plants / {group}",
              "Original geometry · four mutation recipes per family · independent component controls",
              cells, 4 if group != "stems" else 3)
        if group != "stems":
            added = cells[16:32] if group == "flowers" else cells[12:]
            sheet(previews / f"{group}_added.png", f"New {group} / expanded component library",
                  "New constructions and silhouettes · actual triangle meshes rendered in Godot",
                  added, 4)
    lookup = {}
    for entry in catalog["leaves"] + catalog["flowers"] + catalog["variants"]:
        lookup[(entry["family"], entry["variant"])] = entry
    for group, families in (
        ("flowers", ("rose", "iris", "daffodil", "calla", "hydrangea", "hibiscus")),
        ("leaves", ("monstera", "ginkgo", "fern", "maple", "heart", "succulent")),
    ):
        cells = []
        for family in families:
            for variant in catalog["mutation_variants"]:
                entry = lookup[(family, variant)]
                cells.append((previews / f"component_{entry['id']}_lines.png",
                              family.replace("_", " ").title() + " / " + variant,
                              "Seed 81 · geometry mutation"))
        sheet(previews / f"{group}_mutations.png", f"Mutatable {group} / four shapes per family",
              "Reference, slender, ruffled and cupped · proportions, contours and curvature change",
              cells, 4)
    selected = [catalog["plants"][i] for i in (0, 6, 15)]
    for suffix, label in (("model", "unlit surfaces"), ("lines", "visible contours")):
        cells = []
        for entry in selected:
            for view in VIEWS:
                cells.append((previews / f"{entry['id']}_{view}_{suffix}.png",
                              view.replace("_", " ").title(),
                              f"{entry['stem'].replace('_', ' ')} · {entry['flower']}"))
        sheet(previews / f"plant_{suffix}_views.png", f"Modular plants / {label}",
              "Each row is one fixed 3D assembly viewed from five cameras · no camera-facing billboards",
              cells, 5)
    cells = []
    for base in (0, 6, 15):
        for entry in catalog["plants"][base:base + 3]:
            cells.append((previews / f"{entry['id']}_three_quarter_lines.png",
                          entry["pose"].title(),
                          f"{entry['stem'].replace('_', ' ')} · {entry['flower']}"))
    sheet(previews / "plant_poses.png", "Modular plants / pose variations",
          "Upright, reaching and nodding · stems, attachment frames, leaf curl and bloom opening change together",
          cells, 3, image_size=280)
    cells = []
    for entry in catalog["plants"]:
        if entry["pose"] == "upright":
            cells.append((previews / f"{entry['id']}_game_colors.png",
                          entry["flower"].title(),
                          "Existing picture-to-kit pipeline · theme colors"))
    sheet(previews / "plant_game_colors.png", "Modular plants / puzzle color regions",
          "Twelve assemblies run through the existing collage and diamond-kit generators",
          cells, 3, image_size=280)


if __name__ == "__main__":
    main()
