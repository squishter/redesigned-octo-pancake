"""Label the real Godot stem/bloom renders for direct visual comparisons."""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops

from make_sheets import sheet


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path("/tmp/plant-stems-v4"))
    parser.add_argument("--stems-only", action="store_true")
    args = parser.parse_args()
    catalog = json.loads((args.input / "catalog.json").read_text())
    out = args.input / "previews"
    cells = []
    for entry in catalog["stems"]:
        meta = entry["metadata"]
        count = dict(none=0, few=3, many=15)[meta["branching"]]
        cells.append((out / (entry["id"] + "_model.png"),
                      meta["curve"].title() + " / " + meta["branching"] + " branches",
                      f"{count} side branches · flower count is separate"))
    sheet(out / "stem_structures.png", "Stem mutations / shape and branching",
          "Rows: straight, gently curved, winding · seeded angle ranges and irregular branch intervals",
          cells, 3, image_size=300)
    if args.stems_only:
        return
    for entry in catalog["plants"]:
        for view in entry["views"]:
            stem = entry["id"] + "_" + view
            color = Image.open(out / (stem + "_model.png")).convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)
            lines = Image.open(out / (stem + "_lines.png")).convert("RGB")
            ImageChops.multiply(color, lines).save(out / (stem + "_render.png"))
    for curve in catalog["curve_presets"]:
        cells = []
        for entry in catalog["plants"]:
            if entry["group"] != "matrix" or entry["curve"] != curve:
                continue
            stats = entry["metadata"]["stats"]
            bloom_label = "bloom" if stats["flower_count"] == 1 else "blooms"
            cells.append((out / (entry["id"] + "_front_render.png"),
                          f"{entry['branching'].title()} branches / {stats['flower_count']} {bloom_label}",
                          f"{stats['structural_branches']} structural branches · no added buds"))
        sheet(out / ("rose_bloom_matrix_" + curve + ".png"), "Rose stems / " + curve.title(),
              "Stem-aligned rose blooms · rows vary branching · columns have 1, 5 and 15 blooms",
              cells, 3, image_size=300)
    selected = [("straight", "none", "one"), ("gentle", "few", "few"), ("winding", "many", "many")]
    cells = []
    for curve, branching, flowers in selected:
        name = "rose_" + curve + "_" + branching + "_" + flowers
        for view in ("front", "three_quarter", "side", "back", "high"):
            cells.append((out / (name + "_" + view + "_render.png"), view.replace("_", " ").title(),
                          f"{curve} / {branching} branches / {flowers} blooms"))
    sheet(out / "rose_growth_views.png", "Single rose to flowering bush / five views",
          "Each row is one fixed 3D plant · only the camera changes",
          cells, 5)
    selected = [
        ("rose_straight_none_one", "One straight stem", "One rose, no side branches"),
        ("rose_gentle_few_few", "A few curved stems", "Five roses, three side branches"),
        ("rose_winding_many_many", "A broadly winding bush", "Fifteen roses, fifteen side branches"),
    ]
    cells = [(out / (name + "_front_render.png"), title, detail) for name, title, detail in selected]
    sheet(out / "single_rose_to_bush.png", "Stem mutations / single rose to flowering bush",
          "Stem-aligned blooms · small seeded changes to shape, scale and rotation · same rose and leaf families",
          cells, 3, image_size=350)
    cells = []
    for entry in catalog["plants"]:
        if entry["group"] == "species":
            cells.append((out / (entry["id"] + "_front_render.png"), entry["metadata"]["flower"].title(),
                          "Same stem system · 15 blooms"))
    sheet(out / "other_flowering_bushes.png", "Stem mutations / interchangeable blooms",
          "The same growth controls also assemble existing daisy, hibiscus and lily components",
          cells, 3, image_size=300)


if __name__ == "__main__":
    main()
