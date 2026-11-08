"""CPU orthographic projection: visible surface IDs/UVs -> closed 2D art.

Uses NumPy, SciPy and Pillow. It deliberately needs neither a display nor a
GPU, so the same camera/visibility algorithm can be tested headlessly.
"""

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage


def project(model, yaw, size):
    vertices = np.asarray(model["vertices"])
    normals = np.asarray(model["normals"])
    uv = np.asarray(model["uv"])
    rest = np.asarray(model["rest"])
    triangles = np.asarray(model["triangles"])
    materials = np.asarray(model["materials"])
    angle, elevation = math.radians(yaw), math.radians(7)
    right = np.array((math.cos(angle), math.sin(angle), 0))
    direction = np.array((math.sin(angle) * math.cos(elevation),
                          -math.cos(angle) * math.cos(elevation), math.sin(elevation)))
    up = np.cross(direction, right)
    screen = np.column_stack((vertices @ right, -vertices @ up))
    lo, hi = screen.min(axis=0), screen.max(axis=0)
    scale = size * 0.86 / max(hi - lo)
    screen = (screen - (hi + lo) / 2) * scale + size / 2
    depths = vertices @ direction
    zbuffer = np.full((size, size), -np.inf)
    coordinates = np.zeros((size, size, 3))
    rest_buffer = np.zeros((size, size, 3))
    normal_buffer = np.zeros((size, size, 3))
    material_buffer = np.zeros((size, size), dtype=np.int32)
    for indices, material in zip(triangles, materials):
        p = screen[indices]
        x0, y0 = np.maximum(0, np.floor(p.min(axis=0)).astype(int))
        x1, y1 = np.minimum(size - 1, np.ceil(p.max(axis=0)).astype(int))
        if x0 > x1 or y0 > y1:
            continue
        a, b, c = p
        denominator = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(denominator) < 1e-8:
            continue
        yy, xx = np.mgrid[y0:y1 + 1, x0:x1 + 1] + 0.5
        wa = ((b[1] - c[1]) * (xx - c[0]) + (c[0] - b[0]) * (yy - c[1])) / denominator
        wb = ((c[1] - a[1]) * (xx - c[0]) + (a[0] - c[0]) * (yy - c[1])) / denominator
        wc = 1 - wa - wb
        z = wa * depths[indices[0]] + wb * depths[indices[1]] + wc * depths[indices[2]]
        target = zbuffer[y0:y1 + 1, x0:x1 + 1]
        visible = (wa >= -1e-6) & (wb >= -1e-6) & (wc >= -1e-6) & (z > target)
        if not visible.any():
            continue
        weights = np.stack((wa, wb, wc), axis=-1)[visible]
        target[visible] = z[visible]
        local_uv = uv[indices].copy()
        if np.ptp(local_uv[:, 1]) > 0.5:
            local_uv[local_uv[:, 1] < 0, 1] += 1
        coordinates[y0:y1 + 1, x0:x1 + 1][visible] = weights @ local_uv
        rest_buffer[y0:y1 + 1, x0:x1 + 1][visible] = weights @ rest[indices]
        normal_buffer[y0:y1 + 1, x0:x1 + 1][visible] = weights @ normals[indices]
        material_buffer[y0:y1 + 1, x0:x1 + 1][visible] = material

    inside = np.isfinite(zbuffer)
    labels = inside.astype(np.int32)
    u, v, component = coordinates.transpose(2, 0, 1)
    part = np.rint(component).astype(int)
    underside = np.sin(v * math.tau) < -0.30
    if model["species"] == "cat":
        stripes = np.sin(u * 37 + 0.6 * np.sin(v * math.tau * 3) + 0.25 * np.sin(u * 71)) > 0.48
        labels[inside & stripes] = 2
        labels[inside & underside & (part < 2)] = 4
    elif model["species"] == "wolf":
        saddle = (part == 0) & (u < 0.95) & (np.sin(v * math.tau) > 0.05)
        labels[inside & saddle] = 2
        labels[inside & underside & (part < 2)] = 4
    else:
        hooves = (rest_buffer[:, :, 2] < 0.16) & (part >= 2) & (part <= 5)
        labels[inside & hooves] = 3
    labels[inside & (material_buffer == 2)] = 4
    labels[inside & (material_buffer == 3)] = 3
    normal_buffer /= np.maximum(1e-8, np.linalg.norm(normal_buffer, axis=2, keepdims=True))
    return labels, zbuffer, normal_buffer, part, screen, scale


def vector_lines(labels, depth, parts):
    size = len(labels)
    edges = {}
    families = {}

    def edge(a, b, family):
        edges.setdefault(a, set()).add(b)
        edges.setdefault(b, set()).add(a)
        families[tuple(sorted((a, b)))] = family

    for axis in (0, 1):
        before = (slice(None, -1), slice(None)) if axis == 0 else (slice(None), slice(None, -1))
        after = (slice(1, None), slice(None)) if axis == 0 else (slice(None), slice(1, None))
        a, b = labels[before], labels[after]
        different = a != b
        both = (a > 0) & (b > 0)
        with np.errstate(invalid="ignore"):
            occlusion = both & (parts[before] != parts[after]) & (np.abs(depth[before] - depth[after]) > 0.045)
        yy, xx = np.nonzero(different | occlusion)
        for y, x in zip(yy.tolist(), xx.tolist()):
            family = (0 if a[y, x] == 0 or b[y, x] == 0 else
                      max(a[y, x], b[y, x]) if different[y, x] else 5)
            if axis == 0:
                p, q = (y + 1) * (size + 1) + x, (y + 1) * (size + 1) + x + 1
            else:
                p, q = y * (size + 1) + x + 1, (y + 1) * (size + 1) + x + 1
            edge(p, q, family)

    seen, lines, closed, line_families = set(), [], [], []
    starts = [p for p in edges if len(edges[p]) != 2] + list(edges)
    for start in starts:
        for neighbor in edges[start]:
            key = tuple(sorted((start, neighbor)))
            if key in seen:
                continue
            family = families[key]
            path, current, nxt = [start], start, neighbor
            while True:
                seen.add(tuple(sorted((current, nxt))))
                path.append(nxt)
                if nxt == start or len(edges[nxt]) != 2:
                    break
                candidates = [p for p in edges[nxt] if p != current]
                candidate = candidates[0]
                new_key = tuple(sorted((nxt, candidate)))
                if new_key in seen or families[new_key] != family:
                    break
                current, nxt = nxt, candidate
            points = np.array([(p % (size + 1), p // (size + 1)) for p in path], dtype=float)
            is_closed = path[-1] == path[0]
            if is_closed:
                points = points[:-1]
            if len(points) < 2:
                continue
            # Corner cutting keeps shared endpoints exact at every junction.
            for _ in range(2):
                following = np.roll(points, -1, axis=0) if is_closed else points[1:]
                previous = points if is_closed else points[:-1]
                smooth = np.stack((previous * 0.75 + following * 0.25,
                                   previous * 0.25 + following * 0.75), axis=1).reshape(-1, 2)
                points = smooth if is_closed else np.vstack((points[0], smooth, points[-1]))
            lines.append((points * 2 / size - 1).round(6).tolist())
            closed.append(int(is_closed))
            line_families.append(int(family))
    return lines, closed, line_families


def save_art(model, yaw, size, out):
    labels, depth, normals, parts, screen, scale = project(model, yaw, size)
    lines, closed, families = vector_lines(labels, depth, parts)
    marks = []
    for family in range(1, 5):
        components, count = ndimage.label(labels == family)
        for component in range(1, count + 1):
            distance = ndimage.distance_transform_edt(components == component)
            y, x = np.unravel_index(distance.argmax(), distance.shape)
            if distance[y, x] >= 2:
                marks.append(dict(at=[(x + 0.5) * 2 / size - 1, (y + 0.5) * 2 / size - 1], family=family))
    name = f'{model["species"]}_{model["pose"]}_{yaw}'
    design = dict(seed=0, species=model["species"], pose=model["pose"], yaw=yaw, symmetry="none",
                  polylines=lines, closed=closed, families=families,
                  family_names=["outline", "coat", "markings", "features", "belly", "anatomy"], marks=marks)
    (out / (name + "_lines.json")).write_text(json.dumps(design, separators=(",", ":")))
    art = Image.new("RGB", (size, size), "white")
    draw = ImageDraw.Draw(art)
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}"><rect width="100%" height="100%" fill="white"/>',
           '<g fill="none" stroke="#27211f" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round">']
    for line, loop in zip(lines, closed):
        pts = [((x + 1) * size / 2, (y + 1) * size / 2) for x, y in line]
        if loop:
            pts.append(pts[0])
        draw.line(pts, fill=(39, 33, 31), width=2, joint="curve")
        data = "M " + " L ".join(f"{x:.2f},{y:.2f}" for x, y in pts) + (" Z" if loop else "")
        svg.append(f'<path d="{data}"/>')
    svg.append("</g></svg>")
    (out / (name + ".svg")).write_text("\n".join(svg))
    art.save(out / (name + "_lines.png"))
    palette = np.array([[250, 248, 242], [180, 133, 81], [79, 64, 48], [35, 29, 26], [229, 213, 185]])
    if model["species"] == "wolf":
        palette[1:3] = [[160, 158, 149], [90, 94, 91]]
    if model["species"] == "horse":
        palette[1] = [151, 81, 43]
    light = np.array([-0.3, -0.6, 0.9])
    light /= np.linalg.norm(light)
    shade = 0.55 + 0.45 * np.maximum(0, normals @ light)
    shade[labels == 0] = 1
    shaded = np.uint8(np.clip(palette[labels] * shade[:, :, None], 0, 255))
    shaded_image = Image.fromarray(shaded)
    shaded_image.save(out / (name + "_model.png"))
    rig = shaded_image.copy()
    rig_draw = ImageDraw.Draw(rig)
    angle, elevation = math.radians(yaw), math.radians(7)
    right = np.array((math.cos(angle), math.sin(angle), 0))
    direction = np.array((math.sin(angle) * math.cos(elevation),
                          -math.cos(angle) * math.cos(elevation), math.sin(elevation)))
    up = np.cross(direction, right)
    origin = screen[0] - np.array([np.dot(model["vertices"][0], right), -np.dot(model["vertices"][0], up)]) * scale
    for bone_name, bone in model["skeleton"].items():
        if bone_name == "root":
            continue
        a, b = [np.array([np.dot(bone[p], right), -np.dot(bone[p], up)]) * scale + origin for p in ("a", "b")]
        rig_draw.line([tuple(a), tuple(b)], fill="#e9324f", width=2)
        rig_draw.ellipse((a[0] - 2, a[1] - 2, a[0] + 2, a[1] + 2), fill="white", outline="#e9324f")
    rig.save(out / (name + "_rig.png"))
    # Surface IDs are stable across poses, useful for inspecting coat ownership.
    part_palette = np.array([[229, 178, 89], [210, 112, 100], [108, 156, 198], [117, 184, 145],
                             [163, 122, 190], [224, 157, 183], [139, 150, 93]])
    part_rgb = part_palette[np.clip(parts, 0, 6)]
    part_rgb[labels == 0] = 255
    Image.fromarray(np.uint8(part_rgb)).save(out / (name + "_parts.png"))
    print(f"PROJECTED {name}: {len(lines)} paths, {len(marks)} area marks", flush=True)
    return name


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--models", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--size", type=int, default=512)
    parser.add_argument("--angles", default="0,35,70")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    names = []
    for path in sorted(args.models.glob("*.json")):
        model = json.loads(path.read_text())
        if "vertices" not in model:
            continue
        for yaw in map(int, args.angles.split(",")):
            names.append(save_art(model, yaw, args.size, args.out))
    # Compare the actual deformed surface with its projected vector art.
    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    font = ImageFont.truetype(font_path, 16)
    selected = [n for n in names if n.endswith("_35") or n in ("cat_stand_0", "horse_stand_0", "wolf_stand_0")]
    cell = args.size
    sheet = Image.new("RGB", (cell * 2, (cell + 30) * len(selected)), "white")
    draw = ImageDraw.Draw(sheet)
    for i, name in enumerate(selected):
        y = i * (cell + 30)
        draw.text((14, y + 6), name.replace("_", " ") + " degrees", font=font, fill="#27211f")
        sheet.paste(Image.open(args.out / (name + "_model.png")), (0, y + 30))
        sheet.paste(Image.open(args.out / (name + "_lines.png")), (cell, y + 30))
    sheet.save(args.out / "comparison.png")
    overview = Image.new("RGB", (cell * 3, (cell + 30) * 3), "white")
    draw = ImageDraw.Draw(overview)
    for row, species in enumerate(("cat", "wolf", "horse")):
        for col, (angle, kind) in enumerate(((35, "model"), (35, "lines"), (0, "lines"))):
            name = f"{species}_stand_{angle}"
            path = args.out / (name + f"_{kind}.png")
            if path.exists():
                x, y = col * cell, row * (cell + 30)
                draw.text((x + 12, y + 6), f"{species} / {angle} degrees / {kind}", font=font, fill="#27211f")
                overview.paste(Image.open(path), (x, y + 30))
    overview.save(args.out / "overview.png")


if __name__ == "__main__":
    main()
