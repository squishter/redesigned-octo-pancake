"""Blender experiment: skinned quadrupeds -> posed, surface-tagged triangles.

Run with Blender, not system Python. No downloaded assets or add-ons required.
This is a pipeline prototype, not an anatomically finished animal asset pack.
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


PROFILES = {
    "cat": dict(length=1.0, height=0.74, width=0.19, chest=0.23,
                neck=(1.05, 0, 0.90), nose=(1.23, 0, 0.89), skull=0.135,
                muzzle=0.065, limb=0.048, paw=0.085, tail=0.8),
    "wolf": dict(length=1.16, height=0.97, width=0.22, chest=0.29,
                 neck=(1.30, 0, 1.20), nose=(1.70, 0, 1.10), skull=0.145,
                 muzzle=0.12, limb=0.065, paw=0.12, tail=0.72),
    "horse": dict(length=1.42, height=1.65, width=0.28, chest=0.39,
                  neck=(1.65, 0, 2.28), nose=(1.97, 0, 1.88), skull=0.19,
                  muzzle=0.12, limb=0.057, paw=0.10, tail=0.95),
}


def ellipsoid(name, center, radius, direction=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = radius
    if direction is not None:
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(Vector(direction))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def segment(name, a, b, radius_a, radius_b):
    a, b = Vector(a), Vector(b)
    axis = (b - a).normalized()
    side = Vector((0, 1, 0))
    if abs(axis.dot(side)) > 0.95:
        side = Vector((1, 0, 0))
    across = axis.cross(side).normalized()
    side = across.cross(axis).normalized()
    vertices, faces = [], []
    rings, sides = 10, 16
    for k in range(rings):
        t = k / (rings - 1)
        radius = radius_a * (1 - t) + radius_b * t
        for j in range(sides):
            angle = j * math.tau / sides
            vertices.append(a.lerp(b, t) + radius * (side * math.cos(angle) + across * math.sin(angle)))
    for k in range(rings - 1):
        for j in range(sides):
            n = (j + 1) % sides
            faces.append((k * sides + j, k * sides + n, (k + 1) * sides + n, (k + 1) * sides + j))
    faces += [tuple(reversed(range(sides))), tuple((rings - 1) * sides + j for j in range(sides))]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    return mat


def make_animal(species):
    print(f"BUILD {species}: anatomy", flush=True)
    p = PROFILES[species]
    length, height, width, depth = (p[k] for k in ("length", "height", "width", "chest"))
    head = Vector(p["neck"])
    nose = Vector(p["nose"])
    skull, limb = p["skull"], p["limb"]
    bone_defs = {}
    chains = {}

    def bone(name, a, b, parent=None, radius=0.1):
        bone_defs[name] = dict(a=Vector(a), b=Vector(b), parent=parent, radius=radius)
        return name

    bone("root", (0, 0, 0), (0, 0, 0.2))
    bone("pelvis", (0.12 * length, 0, height), (0.34 * length, 0, height), "root", depth)
    bone("lumbar", (0.34 * length, 0, height), (0.64 * length, 0, height), "pelvis", depth)
    bone("chest", (0.64 * length, 0, height), (0.88 * length, 0, height + 0.02), "lumbar", depth)
    bone("neck", (0.88 * length, 0, height + 0.02), head, "chest", skull * 1.6)
    bone("head", head, nose, "neck", skull)
    chains["body"] = ["pelvis", "lumbar", "chest", "neck"]
    chains["head"] = ["head"]
    for side in (-1, 1):
        y = side * width * 0.72
        for front in (True, False):
            name = ("fore" if front else "hind") + (".L" if side < 0 else ".R")
            if front:
                points = [(0.83 * length, y, height - 0.05),
                          (0.79 * length, y, height * 0.64),
                          (0.86 * length, y, height * 0.20),
                          (0.94 * length, y, 0.065)]
            else:
                points = [(0.14 * length, y, height),
                          (0.38 * length, y, height * 0.66),
                          (0.12 * length, y, height * 0.29),
                          (0.27 * length, y, 0.065)]
            parent = "chest" if front else "pelvis"
            chain = []
            for j in range(3):
                joint_name = f"{name}.{j}"
                bone(joint_name, points[j], points[j + 1], parent,
                     limb * ([2.5, 1.1, 0.8][j] if not front else [1.7, 1.0, 0.8][j]))
                parent = joint_name
                chain.append(joint_name)
            chains[name] = chain
    tail_points = []
    for k in range(9):
        t = k / 8
        tail_points.append(Vector((0.05 * length - p["tail"] * t,
                                   0.04 * math.sin(t * math.pi),
                                   height + (0.15 if species == "cat" else -0.55) * t
                                   + 0.10 * math.sin(t * math.pi))))
    chains["tail"] = []
    for k in range(8):
        name = f"tail.{k}"
        bone(name, tail_points[k], tail_points[k + 1], "pelvis" if k == 0 else f"tail.{k-1}", limb)
        chains["tail"].append(name)

    skin = []
    skin.append(ellipsoid("ribcage", (0.66 * length, 0, height - depth * 0.23),
                          (0.46 * length, width, depth)))
    skin.append(ellipsoid("pelvic_mass", (0.15 * length, 0, height - depth * 0.06),
                          (0.26 * length, width * 0.93, depth * 0.88)))
    skin.append(ellipsoid("lumbar_mass", (0.37 * length, 0, height),
                          (0.30 * length, width * 0.80, depth * 0.67)))
    skin.append(segment("neck_mass", (0.82 * length, 0, height), head,
                        depth * 0.71, skull * 0.84))
    skin.append(ellipsoid("skull", head, (skull * 1.1, skull * 0.88, skull)))
    muzzle_at = head.lerp(nose, 0.69)
    skin.append(ellipsoid("muzzle", muzzle_at,
                          (p["muzzle"] * 0.85, p["muzzle"] * 0.85, (nose - head).length * 0.45), nose - head))
    skin.append(ellipsoid("cheek", head + Vector((skull * 0.32, 0, -skull * 0.45)),
                          (skull * 0.85, skull * 0.83, skull * 0.65)))
    for name, chain in chains.items():
        if name in ("body", "head", "tail"):
            continue
        for j, bone_name in enumerate(chain):
            b = bone_defs[bone_name]
            radius = b["radius"]
            skin.append(segment(bone_name, b["a"], b["b"], radius, limb * (1.1 if j == 0 else 0.75)))
            skin.append(ellipsoid(bone_name + "_joint", b["b"], (limb, limb, limb)))
        foot = bone_defs[chain[-1]]["b"]
        skin.append(ellipsoid(name + "_foot", foot + Vector((p["paw"] * 0.30, 0, -0.005)),
                              (p["paw"], limb * 1.12, 0.060)))
    for k, bone_name in enumerate(chains["tail"]):
        b = bone_defs[bone_name]
        t = k / 8
        radius = (0.037 * (1 - t * 0.45) if species == "cat" else
                  0.040 + 0.045 * math.sin(t * math.pi) if species == "wolf" else
                  0.045 + 0.018 * t)
        skin.append(segment(bone_name, b["a"], b["b"], radius, radius * 0.87))

    ear_objects = []
    for side in (-1, 1):
        base = head + Vector((-skull * 0.45, side * skull * 0.65, skull * 0.65))
        ear_height = skull * (0.95 if species == "cat" else 1.35 if species == "wolf" else 1.25)
        verts = [base + Vector((-0.045, -0.04, 0)), base + Vector((0.06, -0.04, 0)),
                 base + Vector((0.015, 0, ear_height)),
                 base + Vector((-0.045, 0.04, 0)), base + Vector((0.06, 0.04, 0))]
        mesh = bpy.data.meshes.new("ear")
        mesh.from_pydata(verts, [], [(0, 1, 2), (3, 2, 4), (0, 3, 4, 1), (0, 2, 3), (1, 4, 2)])
        obj = bpy.data.objects.new("ear", mesh)
        bpy.context.collection.objects.link(obj)
        skin.append(obj)
        ear_objects.append((base, ear_height, side))

    bpy.ops.object.select_all(action="DESELECT")
    for obj in skin:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = skin[0]
    bpy.ops.object.join()
    print(f"BUILD {species}: joined skin", flush=True)
    body = bpy.context.object
    body.name = species + "_skin"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    remesh = body.modifiers.new("Continuous anatomical skin", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = 0.022 if species != "horse" else 0.028
    bpy.ops.object.modifier_apply(modifier=remesh.name)
    print(f"BUILD {species}: remeshed skin", flush=True)
    smooth = body.modifiers.new("Relax skin", "SMOOTH")
    smooth.factor, smooth.iterations = 0.75, 7
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    for polygon in body.data.polygons:
        polygon.use_smooth = True
    coat_mat = material("coat", (0.55, 0.30, 0.12))
    detail_mat = material("face", (0.035, 0.025, 0.02))
    inner_mat = material("inner_ear", (0.55, 0.30, 0.28))
    body.data.materials.append(coat_mat)

    arm_data = bpy.data.armatures.new(species + "_skeleton")
    arm = bpy.data.objects.new(species + "_rig", arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    body.select_set(False)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, b in bone_defs.items():
        edit = arm_data.edit_bones.new(name)
        edit.head, edit.tail = b["a"], b["b"]
        edit.align_roll(Vector((0, 1, 0)))
        if b["parent"]:
            edit.parent = arm_data.edit_bones[b["parent"]]
    bpy.ops.object.mode_set(mode="OBJECT")
    print(f"BUILD {species}: skeleton", flush=True)
    arm.show_in_front = True
    for name, pb in arm.pose.bones.items():
        pb.rotation_mode = "XYZ"
        if name == "root":
            continue
        limit = pb.constraints.new("LIMIT_ROTATION")
        limit.name = "Anatomical joint range (rest-relative)"
        limit.owner_space = "LOCAL"
        limit.use_limit_x = limit.use_limit_y = limit.use_limit_z = True
        limit.min_x, limit.max_x = -0.25, 0.25
        limit.min_y, limit.max_y = -0.20, 0.20
        limit.min_z, limit.max_z = (-1.8, 1.0) if name.endswith(".1") else (-1.4, 1.4)
        limit.use_transform_limit = True

    deform_objects = [body]
    for side in (-1, 1):
        eye_at = head + Vector((skull * 0.53, side * skull * 0.79, skull * 0.20))
        eye = ellipsoid("eye", eye_at, (skull * 0.18, skull * 0.10, skull * 0.12))
        eye.data.materials.append(detail_mat)
        deform_objects.append(eye)
    nose_obj = ellipsoid("nose", nose, (skull * 0.23, p["muzzle"] * 0.75, skull * 0.18))
    nose_obj.data.materials.append(detail_mat)
    deform_objects.append(nose_obj)
    for base, ear_height, side in ear_objects:
        inner = ellipsoid("inner_ear", base + Vector((0.025, 0, ear_height * 0.42)),
                          (0.012, 0.023, ear_height * 0.31))
        inner.data.materials.append(inner_mat)
        deform_objects.append(inner)

    def closest(point, chain):
        best = None
        along = 0.0
        for bone_name in chain:
            b = bone_defs[bone_name]
            axis = b["b"] - b["a"]
            t = max(0, min(1, (point - b["a"]).dot(axis) / axis.length_squared))
            delta = point - b["a"].lerp(b["b"], t)
            rank = delta.length / b["radius"]
            radial = axis.normalized().cross(Vector((0, 1, 0))).normalized()
            result = (rank, along + axis.length * t,
                      math.atan2(delta.dot(radial), delta.y) / math.tau, bone_name)
            if best is None or rank < best[0]:
                best = result
            along += axis.length
        return best

    for obj in deform_objects:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        arm.select_set(False)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        print(f"WEIGHT {species} {obj.name}: {len(obj.data.vertices)} vertices", flush=True)
        rest_values, part_values, coordinate_values = [], [], []
        for name in bone_defs:
            obj.vertex_groups.new(name=name)
        for v in obj.data.vertices:
            point = v.co
            rest_values.extend(point)
            if obj != body:
                weights = [("head", 1.0)]
                component, hit = 1, closest(point, chains["head"])
            else:
                hits = [(i, closest(point, chain)) for i, chain in enumerate(chains.values())]
                component, hit = min(hits, key=lambda h: h[1][0])
                candidates = [(name, closest(point, [name])[0]) for name in bone_defs if name != "root"]
                candidates.sort(key=lambda pair: pair[1])
                weights = [(name, math.exp(-min(40, rank * rank * 2.0))) for name, rank in candidates[:4]]
                total = sum(w for _, w in weights)
                weights = [(name, w / total) for name, w in weights]
            for name, weight in weights:
                obj.vertex_groups[name].add([v.index], weight, "REPLACE")
            part_values.append(component)
            chain_name = list(chains)[component]
            along = hit[1]
            if chain_name.startswith(("fore", "hind")):
                attachment = bone_defs[chains[chain_name][0]]["a"]
                along += closest(attachment, chains["body"])[1]
            elif chain_name == "head":
                along += sum((bone_defs[n]["b"] - bone_defs[n]["a"]).length for n in chains["body"])
            elif chain_name == "tail":
                along = -along
            coordinate_values.extend((along, hit[2], component))
        # Creating a deform layer or another attribute can invalidate Blender
        # RNA layer references. Finish allocating before fetching/writing them.
        obj.data.attributes.new("part_id", "INT", "POINT")
        obj.data.attributes.new("rest_position", "FLOAT_VECTOR", "POINT")
        obj.data.attributes.new("coat_coordinates", "FLOAT_VECTOR", "POINT")
        obj.data.attributes["part_id"].data.foreach_set("value", part_values)
        obj.data.attributes["rest_position"].data.foreach_set("vector", rest_values)
        obj.data.attributes["coat_coordinates"].data.foreach_set("vector", coordinate_values)
        obj.data.uv_layers.new(name="CoatUV")
        for loop in obj.data.loops:
            co = obj.data.attributes["coat_coordinates"].data[loop.vertex_index].vector
            obj.data.uv_layers["CoatUV"].data[loop.index].uv = (co.x, co.y)
        mod = obj.modifiers.new("Skin deformation", "ARMATURE")
        mod.object = arm
        mod.use_deform_preserve_volume = True
        obj.parent = arm
        obj.select_set(False)
    print(f"BUILD {species}: skin weights and UVs", flush=True)

    targets = {}
    for name, chain in chains.items():
        if not name.startswith(("fore", "hind")):
            continue
        target = bpy.data.objects.new(name + "_ground_target", None)
        target.location = bone_defs[chain[1]]["b"]
        bpy.context.collection.objects.link(target)
        targets[name] = target
        ik = arm.pose.bones[chain[1]].constraints.new("IK")
        ik.name, ik.target, ik.chain_count = "Grounded two-bone IK", target, 2
        ik.use_stretch = False
        # The terminal bone keeps its resting world orientation while the
        # two upper bones solve against the wrist/hock target.
        target.rotation_mode = "QUATERNION"
        target.rotation_quaternion = arm.data.bones[chain[2]].matrix_local.to_quaternion()
        foot = arm.pose.bones[chain[2]].constraints.new("COPY_ROTATION")
        foot.name, foot.target = "Planted foot orientation", target
        foot.owner_space = foot.target_space = "WORLD"
        for bname in chain[:2]:
            pb = arm.pose.bones[bname]
            pb.lock_ik_x = pb.lock_ik_y = True
            pb.use_ik_limit_z = True
            pb.ik_min_z, pb.ik_max_z = (-1.6, 1.2) if bname.endswith(".0") else (-1.8, 1.6)
            pb.ik_stretch = 0.0
    return p, arm, deform_objects, bone_defs, chains, targets


def set_pose(pose, species, arm, bones, chains, targets):
    for pb in arm.pose.bones:
        pb.rotation_euler = (0, 0, 0)
        pb.location = (0, 0, 0)
    for name, target in targets.items():
        target.location = bones[chains[name][1]]["b"]
    if pose == "walk":
        stride = min(0.10, PROFILES[species]["height"] * 0.10)
        offsets = {"fore.L": stride, "fore.R": -stride, "hind.L": -stride, "hind.R": stride}
        for name, target in targets.items():
            target.location.x += offsets[name]
            if name == "fore.R":
                target.location.z += 0.12
        arm.pose.bones["neck"].rotation_euler.z = 0.06
    elif pose == "sit":
        arm.pose.bones["root"].location.y = -PROFILES[species]["height"] * 0.65
        arm.pose.bones["pelvis"].rotation_euler.z = -0.72
        arm.pose.bones["neck"].rotation_euler.z = 0.72
        arm.pose.bones["tail.0"].rotation_euler.z = 0.72
        for name, target in targets.items():
            target.location.x = 0.73 if name.startswith("fore") else 0.35
            target.location.z = PROFILES[species]["height"] * (0.20 if name.startswith("fore") else 0.29)
    elif pose != "stand":
        raise ValueError(pose)
    bpy.context.view_layer.update()


def export_snapshot(path, species, pose, objects, arm, bones, chains):
    vertices, triangles, normals, uv, parts, materials, rest = [], [], [], [], [], [], []
    graph = bpy.context.evaluated_depsgraph_get()
    for obj in objects:
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=graph)
        mesh.calc_loop_triangles()
        start = len(vertices)
        for v in mesh.vertices:
            vertices.append(list(evaluated.matrix_world @ v.co))
            normals.append(list((evaluated.matrix_world.to_3x3() @ v.normal).normalized()))
            uv.append(list(mesh.attributes["coat_coordinates"].data[v.index].vector))
            rest.append(list(mesh.attributes["rest_position"].data[v.index].vector))
            parts.append(mesh.attributes["part_id"].data[v.index].value)
        for triangle in mesh.loop_triangles:
            triangles.append([start + i for i in triangle.vertices])
            mat = mesh.materials[triangle.material_index].name.split(".")[0]
            materials.append(0 if mat == "coat" else 2 if mat == "inner_ear" else 3)
        evaluated.to_mesh_clear()
    skeleton = {}
    for pb in arm.pose.bones:
        basis = pb.bone.matrix_local.inverted()
        if pb.parent:
            basis = basis @ pb.parent.bone.matrix_local @ pb.parent.matrix.inverted()
        local_rotation = (basis @ pb.matrix).to_euler("XYZ")
        lo, hi = -1.4, 1.4
        if pb.name.startswith(("fore", "hind")):
            if pb.name.endswith(".0"):
                lo, hi = -1.6, 1.2
            elif pb.name.endswith(".1"):
                lo, hi = -1.8, 1.6
        skeleton[pb.name] = dict(a=list(arm.matrix_world @ pb.head), b=list(arm.matrix_world @ pb.tail),
                                 parent=pb.parent.name if pb.parent else None,
                                 rotation=list(local_rotation), minimum=[-0.25, -0.2, lo], maximum=[0.25, 0.2, hi])
    weights = [v.groups for obj in objects for v in obj.data.vertices]
    skinning = dict(max_influences=max(len(groups) for groups in weights),
                    max_weight_error=max(abs(sum(g.weight for g in groups) - 1) for groups in weights))
    result = dict(species=species, pose=pose, vertices=vertices, triangles=triangles, normals=normals,
                  uv=uv, parts=parts, materials=materials, rest=rest, skeleton=skeleton, skinning=skinning,
                  chain_names=list(chains), rest_bones={n: dict(a=list(b["a"]), b=list(b["b"])) for n, b in bones.items()})
    path.write_text(json.dumps(result, separators=(",", ":")))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--species", default="cat,wolf,horse")
    parser.add_argument("--reuse", action="store_true", help="Re-pose existing .blend models")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    args.out.mkdir(parents=True, exist_ok=True)
    for species in args.species.split(","):
        blend_path = args.out / f"{species}.blend"
        if args.reuse:
            bpy.ops.wm.open_mainfile(filepath=str(blend_path))
            arm = bpy.data.objects[species + "_rig"]
            objects = [o for o in bpy.data.objects if o.type == "MESH" and o.parent == arm]
            bones = {b.name: dict(a=b.head_local, b=b.tail_local) for b in arm.data.bones}
            chains = {"body": ["pelvis", "lumbar", "chest", "neck"], "head": ["head"]}
            for name in ("fore.L", "hind.L", "fore.R", "hind.R"):
                chains[name] = [f"{name}.{j}" for j in range(3)]
            chains["tail"] = [f"tail.{j}" for j in range(8)]
            targets = {name: bpy.data.objects[name + "_ground_target"] for name in chains
                       if name.startswith(("fore", "hind"))}
        else:
            bpy.ops.object.select_all(action="SELECT")
            bpy.ops.object.delete(use_global=False)
            _, arm, objects, bones, chains, targets = make_animal(species)
            bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
        for pose in (["stand", "walk", "sit"] if species == "cat" else ["stand", "walk"]):
            set_pose(pose, species, arm, bones, chains, targets)
            export_snapshot(args.out / f"{species}_{pose}.json", species, pose, objects, arm, bones, chains)
            print(f"EXPORTED {species} {pose}", flush=True)
        set_pose("stand", species, arm, bones, chains, targets)
        bpy.ops.object.select_all(action="DESELECT")
        arm.select_set(True)
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.export_scene.gltf(filepath=str(args.out / f"{species}.glb"), export_format="GLB",
                                  use_selection=True, export_animations=False, export_skins=True)


if __name__ == "__main__":
    main()
