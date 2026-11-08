"""Blender: sample an actual skinned source for CPU preview and UV checks."""

import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    if args.input.suffix == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(args.input), load_ui=False, use_scripts=False)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(args.input))
    arms = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    widgets = {b.custom_shape for a in arms for b in a.pose.bones if b.custom_shape}
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and o not in widgets and not o.hide_render]
    actions = list(bpy.data.actions)
    action = next((a for a in actions if "walk" in a.name.lower()), actions[0] if actions else None)
    for arm in arms:
        arm.animation_data_create()
        for track in arm.animation_data.nla_tracks:
            track.mute = True
        if action:
            arm.animation_data.action = action
    start = action.frame_range[0] if action else 0
    duration = action.frame_range[1] - start if action else 1
    if args.input.parent.name == "gobkit":
        start, duration = 91, 24
    snapshots = []
    image_cache = {}
    uv_hashes, geometry_hashes = [], []
    for phase in (0.12, 0.62):
        bpy.context.scene.frame_set(int(start + duration * phase))
        bpy.context.view_layer.update()
        vertices, normals, atlas, flow, colors, triangles = [], [], [], [], [], []
        evaluated_uv, evaluated_geometry = [], []
        for obj in meshes:
            evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=bpy.context.evaluated_depsgraph_get())
            mesh.calc_loop_triangles()
            matrix = evaluated.matrix_world
            # A deformed quad may choose a different triangulation diagonal.
            # Compare stable mesh corners/vertices, not expanded triangle order.
            evaluated_uv.append((obj.name, [[tuple(v.uv) for v in layer.data] for layer in mesh.uv_layers]))
            evaluated_geometry.append((obj.name, [tuple(matrix @ v.co) for v in mesh.vertices]))
            normal_matrix = matrix.to_3x3().inverted().transposed()
            for triangle in mesh.loop_triangles:
                indices = []
                material = mesh.materials[triangle.material_index] if mesh.materials else None
                color, image = (0.55, 0.55, 0.55, 1), None
                if material:
                    color = tuple(material.diffuse_color)
                    if material.use_nodes:
                        shader = next((n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
                        if shader:
                            color = tuple(shader.inputs["Base Color"].default_value)
                        image = next((n.image for n in material.node_tree.nodes if n.type == "TEX_IMAGE" and n.image), None)
                for loop in triangle.loops:
                    index = mesh.loops[loop].vertex_index
                    indices.append(len(vertices))
                    vertices.append(tuple(matrix @ mesh.vertices[index].co))
                    normals.append(tuple((normal_matrix @ mesh.corner_normals[loop].vector).normalized()))
                    uv = tuple(mesh.uv_layers[0].data[loop].uv) if mesh.uv_layers else (0, 0)
                    atlas.append(uv)
                    flow.append(tuple(mesh.uv_layers[1].data[loop].uv) if len(mesh.uv_layers) > 1 else (0, 0))
                    pixel = color
                    if image:
                        if image.name not in image_cache:
                            image_cache[image.name] = (*image.size, image.channels, tuple(image.pixels))
                        width, height, channels, pixels = image_cache[image.name]
                        if pixels:
                            x = min(width - 1, int((uv[0] % 1) * width))
                            y = min(height - 1, int((uv[1] % 1) * height))
                            offset = (y * width + x) * channels
                            pixel = pixels[offset:offset + 3]
                    colors.append(pixel[:3])
                triangles.append(indices)
            evaluated.to_mesh_clear()
        snapshots.append(dict(vertices=vertices, normals=normals, atlas=atlas, flow=flow,
                              colors=colors, triangles=triangles, phase=phase))
        uv_hashes.append(hashlib.sha256(repr(evaluated_uv).encode()).hexdigest())
        geometry_hashes.append(hashlib.sha256(repr(evaluated_geometry).encode()).hexdigest())
    assert uv_hashes[0] == uv_hashes[1], "Skinning changed surface UV coordinates"
    if action:
        assert geometry_hashes[0] != geometry_hashes[1], "Animation did not deform the mesh"
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(dict(source=str(args.input), action=action.name if action else None,
                                        stable_evaluated_uv=True, snapshots=snapshots), separators=(",", ":")))
    print("SNAPSHOT_READY", args.input.name, flush=True)


if __name__ == "__main__":
    main()
