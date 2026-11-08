"""Compare runtime static variations under a shared camera per animal."""

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from preview_sourced_mesh import render


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--models", default="ultimate_fox,ultimate_horse,tuxedo_cat_tuxedo_cat,daydaze_labrador,daydaze_elephant")
    args = parser.parse_args()
    ids = args.models.split(",")
    sheet = Image.new("RGB", (1200, len(ids) * 325), "#f6f6f6")
    draw = ImageDraw.Draw(sheet)
    for row, model_id in enumerate(ids):
        data = json.loads((args.input / (model_id + ".json")).read_text())
        snapshots = data["snapshots"]
        extent = np.ptp(snapshots[0]["vertices"], axis=0)
        yaw = 25 if extent[0] > extent[1] else 65
        radians = math.radians(yaw)
        right = np.array((math.cos(radians), math.sin(radians), 0))
        direction = np.array((math.sin(radians) * 0.97, -math.cos(radians) * 0.97, 0.243))
        up = np.cross(direction, right)
        points = np.concatenate([np.array(s["vertices"]) for s in snapshots])
        screen = np.column_stack((points @ right, -points @ up))
        frame = dict(yaw=yaw, low=screen.min(axis=0).tolist(), high=screen.max(axis=0).tolist())
        for column, snapshot in enumerate(snapshots):
            x, y = column * 300, row * 325
            sheet.paste(render(snapshot, size=300, frame=frame), (x, y))
            label = "Base pose" if column == 0 else "Variation " + str(column)
            draw.text((x + 8, y + 301), model_id.replace("ultimate_", "").replace("daydaze_", "") + " | " + label, fill="#273a45")
    sheet.save(args.out)


if __name__ == "__main__":
    main()
