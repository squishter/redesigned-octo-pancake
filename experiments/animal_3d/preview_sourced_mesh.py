"""CPU depth-buffer previews of the sampled source meshes (no generated art)."""

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


def render(model, mode="colors", size=360, frame=None):
    vertices = np.array(model["vertices"])
    extent = np.ptp(vertices, axis=0)
    yaw = math.radians(frame["yaw"] if frame else (25 if extent[0] > extent[1] else 65))
    right = np.array((math.cos(yaw), math.sin(yaw), 0))
    direction = np.array((math.sin(yaw) * 0.97, -math.cos(yaw) * 0.97, 0.243))
    up = np.cross(direction, right)
    camera = model.get("camera")
    if camera:
        right = np.array(camera["right"])
        up = np.array(camera["up"])
        direction = np.array(camera["direction"])
    screen = np.column_stack((vertices @ right, -vertices @ up))
    lo, hi = screen.min(axis=0), screen.max(axis=0)
    if frame:
        lo, hi = np.array(frame["low"]), np.array(frame["high"])
    screen = (screen - (lo + hi) / 2) * (size * 0.86 / max(hi - lo)) + size / 2
    if camera:
        centered = vertices - np.array(camera["target"])
        screen = np.column_stack((centered @ right, -centered @ up)) * (size / camera["size"]) + size / 2
    depths = vertices @ direction
    zbuffer = np.full((size, size), -np.inf)
    output = np.full((size, size, 3), 0.965)
    normals, colors = np.array(model["normals"]), np.array(model["colors"])
    uv = np.array(model["atlas"] if mode == "checker" else model["flow"])
    for indices in model["triangles"]:
        p = screen[indices]
        x0, y0 = np.maximum(0, np.floor(p.min(axis=0)).astype(int))
        x1, y1 = np.minimum(size - 1, np.ceil(p.max(axis=0)).astype(int))
        if x0 > x1 or y0 > y1:
            continue
        a, b, c = p
        denominator = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(denominator) < 1e-9:
            continue
        yy, xx = np.mgrid[y0:y1 + 1, x0:x1 + 1] + 0.5
        wa = ((b[1] - c[1]) * (xx - c[0]) + (c[0] - b[0]) * (yy - c[1])) / denominator
        wb = ((c[1] - a[1]) * (xx - c[0]) + (a[0] - c[0]) * (yy - c[1])) / denominator
        wc = 1 - wa - wb
        z = wa * depths[indices[0]] + wb * depths[indices[1]] + wc * depths[indices[2]]
        target = zbuffer[y0:y1 + 1, x0:x1 + 1]
        visible = (wa >= 0) & (wb >= 0) & (wc >= 0) & (z > target)
        if camera:
            visible &= (z >= camera.get("clip_low", -np.inf)) & (z <= camera.get("clip_high", np.inf))
        if not visible.any():
            continue
        weights = np.stack((wa, wb, wc), axis=-1)[visible]
        normal = weights @ normals[indices]
        normal /= np.maximum(1e-8, np.linalg.norm(normal, axis=1, keepdims=True))
        shade = 0.55 + 0.45 * np.maximum(0, normal @ np.array((-0.3, -0.5, 0.812)))
        if mode == "colors":
            color = np.maximum(0, weights @ colors[indices]) ** (1 / 2.2)
        else:
            coords = weights @ uv[indices]
            if mode == "checker":
                pattern = (np.floor(coords[:, 0] * 24) + np.floor(coords[:, 1] * 24)) % 2
            else:
                longitudinal = coords[:, 0] % 16
                pattern = np.sin(longitudinal * 38 + 0.3 * np.sin(coords[:, 1] * math.tau * 3)) > 0
            color = np.where(pattern[:, None], np.array((0.13, 0.24, 0.32)), np.array((0.84, 0.70, 0.43)))
        target[visible] = z[visible]
        output[y0:y1 + 1, x0:x1 + 1][visible] = color * shade[:, None]
    return Image.fromarray((np.clip(output, 0, 1) * 255).astype(np.uint8))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--uv", action="store_true")
    args = parser.parse_args()
    paths = sorted(args.input.glob("*.json"))
    modes = ["colors", "checker", "flow"] if args.uv else ["colors"]
    columns = len(modes) * (2 if args.uv else 4)
    rows = len(paths) if args.uv else math.ceil(len(paths) / columns)
    sheet = Image.new("RGB", (columns * 300, rows * 325), "#f6f6f6")
    draw = ImageDraw.Draw(sheet)
    for index, path in enumerate(paths):
        data = json.loads(path.read_text())
        if args.uv:
            for pose, snapshot in enumerate(data["snapshots"]):
                for m, mode in enumerate(modes):
                    x, y = (pose * len(modes) + m) * 300, index * 325
                    sheet.paste(render(snapshot, mode, 300), (x, y))
                    draw.text((x + 8, y + 301), f"{path.stem} | {mode} | pose {pose + 1}", fill="#273a45")
        else:
            x, y = index % columns * 300, index // columns * 325
            sheet.paste(render(data["snapshots"][0], size=300), (x, y))
            draw.text((x + 8, y + 301), path.stem, fill="#273a45")
    sheet.save(args.out)


if __name__ == "__main__":
    main()
