"""Review actual petal maturity from fixed cameras and on mixed-stage plants."""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops

from make_sheets import sheet


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path("/tmp/plant-blooms"))
    args = parser.parse_args()
    catalog = json.loads((args.input / "catalog.json").read_text())
    out = args.input / "previews"
    for entry in catalog["components"] + catalog["plants"]:
        for view in entry["views"]:
            name = entry["id"] + "_" + view
            color = Image.open(out / (name + "_model.png")).convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)
            line = Image.open(out / (name + "_lines.png")).convert("RGB")
            ImageChops.multiply(color, line).save(out / (name + "_render.png"))
    cells = []
    for entry in catalog["components"]:
        meta = entry["metadata"]
        cells.append((out / (entry["id"] + "_three_quarter_render.png"),
                      meta["family"].title() + " / " + meta["stage_label"],
                      f"Bloom {meta['bloom']:.2f} · fixed camera and scale"))
    sheet(out / "bloom_progression.png", "Flower maturity / petals unfold",
          "Each row uses one flower recipe · only bloom stage changes · the camera and scale stay fixed",
          cells, 4)
    cells = []
    for view in ("three_quarter", "high"):
        for entry in catalog["components"]:
            if entry["metadata"]["family"] == "rose":
                cells.append((out / (entry["id"] + "_" + view + "_render.png"),
                              entry["metadata"]["stage_label"],
                              ("Side view" if view == "three_quarter" else "High view") + " · same camera and scale"))
    sheet(out / "rose_opening.png", "Rose / tightly cupped to fully open",
          "The same petals fold upward and inward, then unfurl · geometry changes, with stable topology",
          cells, 4, image_size=280)
    lookup = {e["id"]: e for e in catalog["plants"]}
    labels = {"rose_closed": "All tightly cupped", "rose_half": "All partly open",
              "rose_open": "All fully open", "rose_mixed": "Mixed bloom stages"}
    cells = []
    for view in ("front", "high"):
        for name, label in labels.items():
            cells.append((out / (name + "_" + view + "_render.png"), label,
                          "15 blooms · same stems, orientations and sizes"))
    sheet(out / "rose_bush_maturity.png", "One rose bush / different stages of bloom",
          "Flower positions, stems, tiny shape variations and camera are fixed · maturity alone changes",
          cells, 4, image_size=280)
    cells = []
    for name in ("rose_mixed", "tulip_mixed", "lotus_mixed"):
        cells.append((out / (name + "_front_render.png"), lookup[name]["metadata"]["flower"].title(),
                      "Independent seeded bloom stage per head"))
    sheet(out / "mixed_bloom_plants.png", "Mixed bloom stages / one plant, many flowers",
          "Roses, tulips and lotus-inspired flowers mix closed, opening and mature heads",
          cells, 3, image_size=320)


if __name__ == "__main__":
    main()
