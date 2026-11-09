"""Review actual Godot surface projections alongside extracted puzzle lines."""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


def sheet(folder, names, output):
    tile, caption = 320, 32
    image = Image.new("RGB", (tile * 2, (tile + caption) * len(names)), "white")
    draw = ImageDraw.Draw(image)
    for row, name in enumerate(names):
        for column, kind in enumerate(("model", "lines")):
            path = folder / f"{name}_{kind}.png"
            if not path.exists():
                raise FileNotFoundError(path)
            tile_image = Image.open(path).convert("RGB").resize((tile, tile), Image.Resampling.LANCZOS)
            image.paste(tile_image, (column * tile, row * (tile + caption) + caption))
        label = name.replace("ultimate_", "").replace("daydaze_", "").replace("_three_quarter_left", "")
        draw.text((8, row * (tile + caption) + 8), label.replace("_", " "), fill="#302536")
    image.save(output)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    sheet(args.input, [
        "toon_cat_toon_cat_free_tabby_three_quarter_left", "ultimate_husky_spots_three_quarter_left",
        "ultimate_horse_pinto_three_quarter_left", "ultimate_horse_dapple_three_quarter_left",
        "ultimate_cow_patches_three_quarter_left", "farm_zebra_zebra_three_quarter_left",
    ], args.out / "natural_coats.png")
    sheet(args.input, [
        "ultimate_husky_stars_three_quarter_left", "ultimate_husky_mosaic_three_quarter_left",
        "ultimate_husky_lace_three_quarter_left", "ultimate_husky_scales_three_quarter_left",
        "gobkit_shark_ribbons_three_quarter_left", "daydaze_elephant_petals_head_front",
    ], args.out / "decorative_coats.png")
    sheet(args.input, [
        "ultimate_husky_saddle_head_front", "ultimate_husky_saddle_head_front_close",
        "toon_cat_toon_cat_free_tabby_head_front", "toon_cat_toon_cat_free_tabby_head_front_high",
        "daydaze_labrador_petals_head_front", "daydaze_elephant_petals_head_front",
    ], args.out / "head_coats.png")


if __name__ == "__main__":
    main()
