"""Blender: add coat atlases and anatomical flow UVs without changing the rig.

blender --background --factory-startup --disable-autoexec --python \
  experiments/animal_3d/prepare_coat_uvs.py -- --source-root=... --out=...

Unwrap a welded *proxy*, then transfer per-corner UVs to the original mesh.
This preserves split normals, material boundaries, vertex weights and clips.
"""

import argparse
import hashlib
import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from uv_geometry import overlaps


PARTS = ["body", "head", "fore_L", "fore_R", "hind_L", "hind_R", "tail", "ear_L", "ear_R", "horn_L", "horn_R"]
FLOW_STRIDE = 16.0
GENERIC_CAT = {
    "Bone": "body", "Bone.001": "body", "Bone.002": "body", "Bone.003": "head",
    **{f"Bone.{i:03}": "tail" for i in range(4, 8)},
    **{f"Bone.{i:03}": "hind_L" for i in range(8, 11)},
    **{f"Bone.{i:03}": "hind_R" for i in range(11, 14)},
    **{f"Bone.{i:03}": "fore_R" for i in range(14, 17)},
    **{f"Bone.{i:03}": "fore_L" for i in range(17, 20)},
}


def part_of(name):
    name = re.sub(r"_end$", "", name)
    if name in GENERIC_CAT:
        return GENERIC_CAT[name]
    lower = name.lower()
    side = "L" if re.search(r"[._]l$|left", lower) else "R"
    if lower.startswith(("ik", "pole", "ff")) or lower == "root":
        return None
    if "ear" in lower:
        return "ear_" + side
    if any(word in lower for word in ("horn", "antler")):
        return "horn_" + side
    if "head" in lower or "jaw" in lower:
        return "head"
    if "tail" in lower:
        return "tail"
    if any(word in lower for word in ("front", "fore")):
        return "fore_" + side
    if any(word in lower for word in ("backleg", "backfoot", "backup", "backlow", "backshoulder", "hind")):
        return "hind_" + side
    return "body"


def geometry_digest(objects):
    """UV-independent signature: positions, topology, material assignments, weights."""
    data = []
    for obj in objects:
        data.append((obj.name, [tuple(v.co) for v in obj.data.vertices],
                     [(tuple(p.vertices), p.material_index) for p in obj.data.polygons],
                     [[(g.group, g.weight) for g in v.groups] for v in obj.data.vertices],
                     [g.name for g in obj.vertex_groups]))
    return hashlib.sha256(repr(data).encode()).hexdigest()


class Anatomy:
    def __init__(self, meshes, arms):
        self.bones = {}
        self.chains = defaultdict(list)
        for arm in arms:
            for bone in arm.data.bones:
                part = part_of(bone.name)
                if part is not None:
                    a, b = (arm.matrix_world @ p for p in (bone.head_local, bone.tail_local))
                    self.bones[bone.name] = (part, a, b)
                    self.chains[part].append((bone.name, a, b))
        points = [obj.matrix_world @ v.co for obj in meshes for v in obj.data.vertices]
        low = Vector(tuple(min(p[k] for p in points) for k in range(3)))
        high = Vector(tuple(max(p[k] for p in points) for k in range(3)))
        self.center = (low + high) * 0.5
        body = self.chains["body"]
        heads = self.chains["head"]
        head = heads[0][1] if heads else high
        back = max((b[1] for b in body), key=lambda p: (p - head).length) if body else self.center
        forward = head - back
        forward.z = 0
        if forward.length < 1e-5:
            forward = Vector((1, 0, 0)) if high.x - low.x > high.y - low.y else Vector((0, -1, 0))
        self.forward = forward.normalized()
        self.side = self.forward.cross(Vector((0, 0, 1))).normalized()
        self.length = max((head - back).dot(self.forward), (high - low).length * 0.2, 1e-4)
        self.body_origin = min(p.dot(self.forward) for p in points) - self.length * 0.01
        self.body_axis_origin = back
        self.paths = {}
        for part, bones in self.chains.items():
            if part == "body":
                bones.sort(key=lambda row: row[1].dot(self.forward))
            elif part.startswith(("fore_", "hind_")):
                bones.sort(key=lambda row: -row[1].z)
            else:
                bones.sort(key=lambda row: int(re.findall(r"\d+", row[0])[0]) if re.findall(r"\d+", row[0]) else 0)
            path = [row[1] for row in bones] + [bones[-1][2]]
            path = [p for i, p in enumerate(path) if i == 0 or (p - path[i - 1]).length > 1e-5]
            if len(path) < 2:
                path.append(path[0] + self.forward * self.length * 0.1)
            self.paths[part] = path
        if "body" not in self.paths:
            self.paths["body"] = [self.center - self.forward * self.length / 2,
                                   self.center + self.forward * self.length / 2]

    def face_part(self, obj, face):
        weights = defaultdict(float)
        for index in face.vertices:
            for group in obj.data.vertices[index].groups:
                name = obj.vertex_groups[group.group].name
                part = self.bones.get(name, (None,))[0]
                if part is not None:
                    weights[part] += group.weight
        if weights:
            return max(weights, key=weights.get)
        if obj.parent_type == "BONE":
            return self.bones.get(obj.parent_bone, ("body",))[0]
        return "body"

    def coordinate(self, point, part):
        if part == "body":
            # A single longitudinal field avoids nearest-segment jumps where
            # spine and neck helper bones overlap or double back in the rig.
            delta = point - self.body_axis_origin
            angle = math.atan2(delta.z, delta.dot(self.side)) / math.tau + 0.5
            return ((point.dot(self.forward) - self.body_origin) / self.length,
                    angle, delta.length / self.length)
        path = self.paths.get(part, self.paths["body"])
        best, along, result = float("inf"), 0.0, None
        for a, b in zip(path, path[1:]):
            axis = b - a
            if axis.length_squared < 1e-12:
                continue
            t = max(0, min(1, (point - a).dot(axis) / axis.length_squared))
            center = a.lerp(b, t)
            delta = point - center
            if delta.length_squared < best:
                best = delta.length_squared
                direction = axis.normalized()
                if part.startswith(("fore_", "hind_")):
                    outward = path[0] - self.center
                    outward = self.side * (1 if outward.dot(self.side) >= 0 else -1)
                    reference = outward - direction * outward.dot(direction)
                else:
                    reference = self.side.cross(direction)
                if reference.length < 1e-5:
                    reference = self.forward - direction * self.forward.dot(direction)
                reference.normalize()
                across = direction.cross(reference).normalized()
                angle = math.atan2(delta.dot(across), delta.dot(reference)) / math.tau + 0.5
                result = ((along + axis.length * t) / self.length, angle, math.sqrt(best) / self.length)
            along += axis.length
        return result


def make_proxy(obj, anatomy):
    vertices, faces, lookup, face_map, parts = [], [], {}, [], []
    def key(point):
        # glTF's split vertices repeat exact positions. A fuzzy weld can erase
        # small but real facial triangles, so only identical positions merge.
        return tuple(point)

    for face in obj.data.polygons:
        indices = []
        for index in face.vertices:
            point = obj.matrix_world @ obj.data.vertices[index].co
            k = key(point)
            if k not in lookup:
                lookup[k] = len(vertices)
                vertices.append(point)
            indices.append(lookup[k])
        if len(set(indices)) < 3:
            continue
        faces.append(indices)
        face_map.append(face.index)
        parts.append(anatomy.face_part(obj, face))
    mesh = bpy.data.meshes.new(obj.name + "_unwrap_proxy")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    proxy = bpy.data.objects.new(mesh.name, mesh)
    bpy.context.collection.objects.link(proxy)
    mesh.uv_layers.new(name="CoatUV")
    return proxy, face_map, parts, key


def apply_uvs(objects, anatomy):
    proxies = [(obj, *make_proxy(obj, anatomy)) for obj in objects]
    bpy.context.scene.tool_settings.use_uv_select_sync = True
    bpy.ops.object.select_all(action="DESELECT")
    for _, proxy, *_ in proxies:
        proxy.select_set(True)
    bpy.context.view_layer.objects.active = proxies[0][1]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    # Angle charts keep the paint atlas independent of difficult legacy skin
    # topology. Anatomical stripe direction is supplied separately by CoatFlow.
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.012,
                             margin_method="FRACTION", correct_aspect=False, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    repaired = 0
    for _, proxy, *_ in proxies:
        mesh = proxy.data
        mesh.calc_loop_triangles()
        coords = [[tuple(mesh.uv_layers.active.data[i].uv) for i in t.loops] for t in mesh.loop_triangles]
        bad = {mesh.loop_triangles[i].polygon_index for pair in overlaps(coords) for i in pair}
        for t, uv in zip(mesh.loop_triangles, coords):
            a, b, c = [Vector(p) for p in uv]
            if abs((b - a).cross(c - a)) < 1e-14:
                bad.add(t.polygon_index)
        for index in bad:
            face = mesh.polygons[index]
            for k, loop in enumerate(face.loop_indices):
                angle = k * math.tau / len(face.loop_indices)
                mesh.uv_layers.active.data[loop].uv = (index * 0.0001 + math.cos(angle) * 0.005,
                                                     math.sin(angle) * 0.005)
        repaired += len(bad)
    if repaired:
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.pack_islands(rotate=True, margin=0.012, margin_method="FRACTION")
        bpy.ops.object.mode_set(mode="OBJECT")
    atlas_triangles, source_areas, flow_parts = [], [], defaultdict(int)
    for obj, proxy, face_map, parts, key in proxies:
        original = obj.data
        atlas = original.uv_layers.new(name="CoatUV")
        flow = original.uv_layers.new(name="CoatFlow")
        # Fetch RNA references only after allocating both layers.
        atlas = original.uv_layers["CoatUV"]
        flow = original.uv_layers["CoatFlow"]
        for loop in atlas.data:
            loop.uv = (0, 0)
        for loop in flow.data:
            loop.uv = (0, 0)
        source_uv = proxy.data.uv_layers.active.data
        for proxy_face, source_index, part in zip(proxy.data.polygons, face_map, parts):
            mapping = {key(proxy.data.vertices[proxy.data.loops[i].vertex_index].co): source_uv[i].uv.copy()
                       for i in proxy_face.loop_indices}
            source_face = original.polygons[source_index]
            points = [obj.matrix_world @ original.vertices[original.loops[i].vertex_index].co
                      for i in source_face.loop_indices]
            coordinates = [anatomy.coordinate(p, part) for p in points]
            angles = [c[1] for c in coordinates]
            if max(angles) - min(angles) > 0.5:
                angles = [v + 1 if v < 0.5 else v for v in angles]
            phase = 0.0
            if part.startswith(("fore_", "hind_")):
                phase = anatomy.coordinate(anatomy.paths.get(part, anatomy.paths["body"])[0], "body")[0]
            for i, point, co, angle in zip(source_face.loop_indices, points, coordinates, angles):
                atlas.data[i].uv = mapping[key(point)]
                flow.data[i].uv = (PARTS.index(part) * FLOW_STRIDE + phase + co[0], angle)
            flow_parts[part] += 1
        # Keep the atlas as UV0/active. Flow is the second UV set (Godot UV2).
        original.uv_layers.active_index = original.uv_layers.find("CoatUV")
        original.uv_layers["CoatUV"].active_render = True
        original.calc_loop_triangles()
        for triangle in original.loop_triangles:
            atlas_triangles.append([tuple(atlas.data[i].uv) for i in triangle.loops])
            a, b, c = [obj.matrix_world @ original.vertices[i].co for i in triangle.vertices]
            source_areas.append((b - a).cross(c - a).length / (2 * anatomy.length ** 2))
        bpy.data.objects.remove(proxy, do_unlink=True)
    return atlas_triangles, source_areas, dict(flow_parts), repaired


def uv_validation(triangles, source_areas):
    area, degenerate, source_degenerate = 0.0, 0, 0
    bounds = [1.0, 1.0, 0.0, 0.0]
    for triangle, source_area in zip(triangles, source_areas):
        a, b, c = [Vector(p) for p in triangle]
        value = abs((b - a).cross(c - a)) / 2
        if source_area < 1e-12:
            source_degenerate += 1
        elif value < 1e-15:
            degenerate += 1
        area += value
        for x, y in triangle:
            assert math.isfinite(x) and math.isfinite(y) and -1e-5 <= x <= 1.00001 and -1e-5 <= y <= 1.00001, (x, y)
            bounds = [min(bounds[0], x), min(bounds[1], y), max(bounds[2], x), max(bounds[3], y)]
    assert area > 0.05 and degenerate == 0, f"Degenerate atlas: area={area}, triangles={degenerate}"
    intersections = overlaps(triangles)
    assert not intersections, f"Overlapping atlas triangles: {len(intersections)}"
    return dict(uv_area=area, bounds=bounds, degenerate_triangles=degenerate,
                source_degenerate_triangles=source_degenerate, overlapping_triangle_pairs=0)


def export_blend(blend_path, glb_path, legacy=False):
    bpy.ops.wm.open_mainfile(filepath=str(blend_path), load_ui=False, use_scripts=False)
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    arms = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    widgets = {b.custom_shape for a in arms for b in a.pose.bones if b.custom_shape}
    objects = [o for o in bpy.context.scene.objects if o.type == "MESH" and o not in widgets and not o.hide_render]
    if legacy:
        replacements = {}
        for obj in objects:
            for slot in obj.material_slots:
                original = slot.material
                if original is None:
                    continue
                if original.name not in replacements:
                    material = bpy.data.materials.new(original.name + "_gltf")
                    material.diffuse_color = original.diffuse_color
                    material.use_nodes = True
                    shader = material.node_tree.nodes.get("Principled BSDF")
                    shader.inputs["Base Color"].default_value = original.diffuse_color
                    shader.inputs["Roughness"].default_value = 0.8
                    replacements[original.name] = material
                slot.material = replacements[original.name]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if obj.type in ("MESH", "ARMATURE", "EMPTY") and not obj.hide_render and obj not in widgets:
            obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(glb_path), export_format="GLB", use_selection=True,
                              export_skins=True, export_all_influences=True,
                              export_animations=True, export_animation_mode="ACTIONS",
                              export_frame_range=False, export_texcoords=True)
    print("GLB_READY", glb_path.stem, flush=True)


def process(path, output, identifier, no_export=False):
    if path.suffix == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False, use_scripts=False)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(path), merge_vertices=False)
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    arms = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    widgets = {bone.custom_shape for arm in arms for bone in arm.pose.bones if bone.custom_shape}
    objects = [obj for obj in bpy.context.scene.objects
               if obj.type == "MESH" and not obj.hide_render and obj not in widgets]
    assert objects and arms, f"No skinned animal: {path}"
    assert all(len(obj.data.uv_layers) == 0 for obj in objects), "Existing UVs require a preservation policy"
    signature = geometry_digest(objects)
    clips = [a.name for a in bpy.data.actions]
    anatomy = Anatomy(objects, arms)
    triangles, source_areas, parts, repaired = apply_uvs(objects, anatomy)
    assert geometry_digest(objects) == signature, "UV generation changed source geometry/skin weights"
    output.mkdir(parents=True, exist_ok=True)
    (output / (identifier + "_atlas.json")).write_text(json.dumps(dict(triangles=triangles), separators=(",", ":")))
    validation = uv_validation(triangles, source_areas)
    output.mkdir(parents=True, exist_ok=True)
    blend_path = output / (identifier + ".blend")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    glb_path = output / (identifier + ".glb")
    if not no_export:
        export_blend(blend_path, glb_path, path.suffix == ".blend")
    report = dict(id=identifier, source=str(path), source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                  glb=glb_path.name, blend=blend_path.name,
                  uv_layers=["CoatUV", "CoatFlow"], flow_part_stride=FLOW_STRIDE, part_names=PARTS,
                  part_faces=parts, source_actions=clips, geometry_and_weights_preserved=True, **validation)
    report["fallback_chart_faces"] = repaired
    (output / (identifier + "_atlas.json")).write_text(json.dumps(dict(triangles=triangles), separators=(",", ":")))
    (output / (identifier + "_uv.json")).write_text(json.dumps(report, indent=2) + "\n")
    print("UV_READY", identifier, validation, flush=True)
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--only", help="Comma-separated output IDs")
    parser.add_argument("--no-export", action="store_true")
    parser.add_argument("--export-blend", type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    if args.export_blend:
        export_blend(args.export_blend, args.out / (args.export_blend.stem + ".glb"),
                     args.export_blend.name.startswith("farm_"))
        return
    inputs = [(p, "ultimate_" + p.stem) for p in sorted((args.source_root / "ultimate").glob("*.glb"))]
    inputs += [(p, "farm_" + p.stem) for p in sorted((args.source_root / "farm").glob("*.blend"))]
    inputs += [(p, "vol2_" + p.stem.removeprefix("animal-")) for p in sorted(args.source_root.glob("animal-*.glb"))]
    if args.only:
        inputs = [(p, identifier) for p, identifier in inputs if identifier in args.only.split(",")]
    assert inputs, "No source models selected"
    reports = [process(path, args.out, identifier, args.no_export) for path, identifier in inputs]
    (args.out / "uv_manifest.json").write_text(json.dumps(reports, indent=2) + "\n")


if __name__ == "__main__":
    main()
