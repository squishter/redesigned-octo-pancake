"""Build an authored modular plant study, GLBs and worker-safe surface data.

Only NumPy is required. Geometry is original to this project; no third-party
model or generator code is embedded. Run from the repository root:
    python experiments/plant_3d/build_plants.py --out=/tmp/plant-library-v2
"""

import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np

from mesh_geometry import Mesh, frame, tube, unit, write_glb
from plant_components import BUDS, FLOWERS, LEAVES, VARIANTS, flower_mesh, leaf_mesh, recipe

VERSION = 2
STEMS = ("single_spire", "forked_spray", "branching_bush")
POSES = {
    "upright": dict(bend_x=.03, bend_z=.02, spread=1., leaf_pitch=.15, leaf_curl=.10, opening=1.),
    "reaching": dict(bend_x=.27, bend_z=-.10, spread=1.2, leaf_pitch=.32, leaf_curl=.27, opening=.8),
    "nodding": dict(bend_x=-.16, bend_z=.20, spread=.8, leaf_pitch=-.18, leaf_curl=.38, opening=.65),
}
PAIRINGS = [
    ("single_spire", "lance", "lily"), ("single_spire", "oval", "tulip"),
    ("forked_spray", "serrated", "rose"), ("forked_spray", "pinnate", "cosmos"),
    ("branching_bush", "heart", "bell"), ("branching_bush", "oak_lobed", "daisy"),
    ("single_spire", "willow", "daffodil"), ("forked_spray", "ivy", "hibiscus"),
    ("single_spire", "monstera", "anthurium"), ("branching_bush", "birch", "hydrangea"),
    ("single_spire", "palm", "allium"), ("forked_spray", "fern", "iris"),
]


def plant(stem, leaf, flower, seed=41, pose="upright", overrides=None, component_variant="reference", growth=None):
    """Rebuild from a fixed recipe: posing never accumulates deformations."""
    if growth is not None:
        from stem_growth import assemble, make_recipe, resolve
        record = resolve(growth) if "version" in growth else make_recipe(seed=seed, **growth)
        if record["seed"] != seed:
            raise ValueError("Plant seed must match its saved growth recipe")
        return assemble(record, leaf, flower, pose, component_variant, overrides)
    if stem not in STEMS or leaf not in LEAVES or flower not in FLOWERS or pose not in POSES:
        raise ValueError("Unknown component or pose")
    controls = {**POSES[pose], **(overrides or {})}
    limits = dict(bend_x=(-.4, .4), bend_z=(-.4, .4), spread=(.6, 1.4),
                  leaf_pitch=(-.4, .5), leaf_curl=(0., .5), opening=(.35, 1.))
    if set(controls) != set(limits):
        raise ValueError("Unknown pose control")
    for key, value in controls.items():
        if not math.isfinite(value) or not limits[key][0] <= value <= limits[key][1]:
            raise ValueError(f"Invalid pose control: {key}")
    rng = np.random.default_rng(seed)
    mesh = Mesh()
    phase = rng.uniform(-.3, .3)
    height = rng.uniform(1.65, 1.85)

    def spine(t):
        return np.array((controls["bend_x"] * t * t + .035 * math.sin(t * 3),
                         height * t, controls["bend_z"] * t * t))

    trunk = np.array([spine(t) for t in np.linspace(0, 1, 25)])
    tube(mesh, trunk, .023, 1, 10)
    branches = [trunk]
    splits = [] if stem == "single_spire" else [.44, .66] if stem == "forked_spray" else [.25, .4, .54, .68]
    for i, t in enumerate(splits):
        angle = phase + (i * 2.4 if stem == "branching_bush" else i * math.pi)
        outward = np.array((math.cos(angle), 0., math.sin(angle)))
        reach = (.56 if stem == "forked_spray" else .66) * controls["spread"]
        root = spine(t)
        path = np.array([root + (spine(t + u * (1 - t) * .85) - root)
                         + outward * reach * math.sin(u * math.pi / 2)
                         for u in np.linspace(0, 1, 19)])
        tube(mesh, path, .016, 1, 11 + i)
        branches.append(path)
    if component_variant not in VARIANTS:
        raise ValueError("Unknown component mutation variant")
    next_part = 100000
    for branch_id, path in enumerate(branches):
        positions = [.24, .42, .60, .76] if branch_id == 0 else [.42, .68]
        for i, t in enumerate(positions):
            index = round(t * (len(path) - 1))
            root = path[index]
            tangent = unit(path[min(index + 1, len(path) - 1)] - path[max(0, index - 1)])
            angle = phase + i * 2.4 + branch_id * 1.7
            radial = np.array((math.cos(angle), 0., math.sin(angle)))
            axis = unit(radial + tangent * controls["leaf_pitch"])
            basis = frame(axis, tangent)
            length = (.48 if leaf not in ("pinnate", "trifoliate") else .55) * rng.uniform(.85, 1.1)
            organ = leaf_mesh(leaf, controls["leaf_curl"], next_part, seed=seed + next_part,
                              variant=component_variant)
            mesh.merge(organ, basis * length, root)
            mesh.attachments.append(dict(kind="leaf", branch=branch_id, root=root.tolist(),
                                         axis=axis.tolist(), frame=basis.tolist(), scale=length,
                                         part=next_part))
            next_part += 100000
        root = path[-1]
        tangent = unit(path[-1] - path[-2])
        # Tilt flowers toward an authored direction; each view sees the same geometry.
        axis = unit(tangent + np.array((.16 * math.sin(branch_id * 2.4), -.22, .55)))
        if flower == "bell":
            axis = unit((.2, -.7, .5))
        basis = frame(axis)
        organ = flower_mesh(flower, controls["opening"], next_part, seed=seed + next_part,
                            variant=component_variant)
        size = .95 if branch_id == 0 else .75
        mesh.merge(organ, basis * size, root)
        mesh.attachments.append(dict(kind="flower", branch=branch_id, root=root.tolist(),
                                     axis=axis.tolist(), frame=basis.tolist(), scale=size,
                                     part=next_part))
        next_part += 100000
        # Every stem type includes a bud on its own small pedicel.
        start = path[-5]
        end = start + basis @ np.array((.16, .05, 0.))
        tube(mesh, [start, (start + end) / 2 + np.array((0, .035, 0)), end], .010, 1, next_part)
        mesh.merge(flower_mesh(BUDS[branch_id % len(BUDS)], .5, next_part + 1), basis * .7, end)
        mesh.attachments.append(dict(kind="bud", branch=branch_id, root=end.tolist(),
                                     axis=axis.tolist(), frame=basis.tolist(), scale=.7,
                                     part=next_part + 1))
        next_part += 100000
    metadata = dict(version=VERSION, backend="authored modular study", stem=stem, leaf=leaf,
                    flower=flower, seed=seed, pose=pose, controls=controls, component_variant=component_variant)
    return mesh, metadata


def validate(mesh):
    points, triangles = np.array(mesh.vertices), np.array(mesh.triangles)
    assert len(points) and len(triangles) and np.isfinite(points).all()
    assert triangles.min() >= 0 and triangles.max() < len(points)
    assert len(mesh.labels) == len(mesh.parts) == len(points)
    area = np.linalg.norm(np.cross(points[triangles[:, 1]] - points[triangles[:, 0]],
                                  points[triangles[:, 2]] - points[triangles[:, 0]]), axis=1)
    assert (area > 1e-12).all(), "Degenerate triangle"
    for triangle in triangles:
        assert len(set(mesh.labels[i] for i in triangle)) == 1
        assert len(set(mesh.parts[i] for i in triangle)) == 1
    for socket in mesh.attachments:
        assert np.isfinite(socket["root"]).all()
        basis = np.asarray(socket["frame"])
        assert np.allclose(basis.T @ basis, np.eye(3)), "Attachment frame must be orthonormal"
        assert math.isfinite(socket["scale"]) and socket["scale"] > 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("/tmp/plant-library-v2"))
    parser.add_argument("--verify-puzzles", action="store_true",
                        help="Rebuild plants from Godot-saved puzzle recipes instead of generating")
    parser.add_argument("--component", help="Export one component, e.g. flowers:iris or leaves:ginkgo")
    parser.add_argument("--variant", choices=VARIANTS, default="reference")
    parser.add_argument("--seed", type=int, default=81)
    parser.add_argument("--control", action="append", default=[], help="Numeric override, e.g. opening=0.7")
    args = parser.parse_args()
    out = args.out
    if args.component:
        group, separator, family = args.component.partition(":")
        if not separator:
            parser.error("Use --component=leaves:FAMILY or --component=flowers:FAMILY")
        controls = {}
        for assignment in args.control:
            key, separator, value = assignment.partition("=")
            if not separator:
                parser.error("Use --control=NAME=NUMBER")
            controls[key] = float(value)
        record = recipe(group, family, args.seed, args.variant, controls)
        builder = leaf_mesh if group == "leaves" else flower_mesh
        mesh = builder(family, seed=args.seed, variant=args.variant, controls=record["controls"])
        validate(mesh)
        out.mkdir(parents=True, exist_ok=True)
        name = family + "__" + args.variant + "_" + str(args.seed)
        metadata = dict(version=VERSION, seed=args.seed, recipe=record)
        write_glb(mesh, out / (name + ".glb"), metadata)
        (out / (name + ".json")).write_text(json.dumps(mesh.data(metadata), separators=(",", ":")))
        print(out / (name + ".glb"))
        return
    if args.verify_puzzles:
        files = sorted((out / "previews").glob("*_collage.json"))
        assert len(files) == len(PAIRINGS), "Expected one saved puzzle per assembly"
        for path in files:
            saved = json.loads(path.read_text())["source"]["plant_mesh"]
            assert saved["version"] == VERSION
            rebuilt, _ = plant(saved["stem"], saved["leaf"], saved["flower"],
                               seed=int(saved["seed"]), pose=saved["pose"], overrides=saved["controls"],
                               component_variant=saved["component_variant"])
            original_path = out / "plants" / path.name.replace("_collage.json", ".json")
            original = json.loads(original_path.read_text())
            assert np.array_equal(np.asarray(rebuilt.vertices), np.asarray(original["vertices"])), path
            assert rebuilt.triangles == original["triangles"] and rebuilt.parts == original["parts"]
        print(f"Rebuilt {len(files)} plants exactly from Godot-saved puzzle metadata.")
        return
    components, plants = out / "components", out / "plants"
    components.mkdir(parents=True, exist_ok=True)
    plants.mkdir(parents=True, exist_ok=True)
    catalog = dict(version=VERSION, origin="Original authored components; see SOURCE_AUDIT.md for online candidates",
                   stems=[], leaves=[], flowers=[], plants=[], variants=[],
                   counts=dict(stems=len(STEMS), leaves=len(LEAVES), flowers=len(FLOWERS), buds=len(BUDS)),
                   mutation_variants=list(VARIANTS))

    def save_component(group, name, mesh, record=None):
        validate(mesh)
        path = components / f"{name}.glb"
        metadata = dict(kind=group, name=name, version=VERSION, seed=0)
        if record:
            metadata["recipe"] = record
        write_glb(mesh, path, metadata)
        surface = components / f"{name}.json"
        surface.write_text(json.dumps(mesh.data(metadata), separators=(",", ":")))
        entry = dict(id=name, file=str(path.relative_to(out)),
                                   data=str(surface.relative_to(out)),
                                   sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                                   vertices=len(mesh.vertices), triangles=len(mesh.triangles))
        if record:
            entry["recipe"] = record
            entry["family"] = record["family"]
            entry["variant"] = record["variant"]
        catalog[group if not record or record["variant"] == "reference" else "variants"].append(entry)

    for group, families, builder in (("leaves", LEAVES, leaf_mesh), ("flowers", (*FLOWERS, *BUDS), flower_mesh)):
        for name in families:
            for variant in VARIANTS:
                record = recipe(group, name, seed=81, variant=variant)
                mesh = builder(name, seed=81, variant=variant, controls=record["controls"])
                filename = name if variant == "reference" else name + "__" + variant
                save_component(group, filename, mesh, record)
    for name in STEMS:
        full, _ = plant(name, "oval", "daisy")
        stem = Mesh()
        triangles = np.array(full.triangles)
        selected = triangles[np.asarray(full.labels)[triangles[:, 0]] == 1]
        for face in selected:
            stem.add(np.asarray(full.vertices)[face], [(0, 1, 2)], 1, 0)
        stem.attachments = full.attachments
        save_component("stems", name, stem)
    # A fixed mesh assembly seen from different cameras, plus two independent poses.
    for index, (stem, leaf, flower) in enumerate(PAIRINGS):
        for pose in POSES:
            mutation = VARIANTS[index % len(VARIANTS)]
            mesh, metadata = plant(stem, leaf, flower, seed=41 + index, pose=pose, component_variant=mutation)
            validate(mesh)
            name = f"{index:02d}_{flower}_{pose}"
            glb = plants / f"{name}.glb"
            write_glb(mesh, glb, metadata)
            path = plants / f"{name}.json"
            path.write_text(json.dumps(mesh.data(metadata), separators=(",", ":")))
            catalog["plants"].append(dict(id=name, data=str(path.relative_to(out)),
                                          mesh=str(glb.relative_to(out)), **metadata))
            neutral, _ = plant(stem, leaf, flower, seed=41 + index, component_variant=mutation)
            assert neutral.triangles == mesh.triangles and neutral.parts == mesh.parts
            assert neutral.labels == mesh.labels
            replay, _ = plant(stem, leaf, flower, seed=41 + index, pose=pose, component_variant=mutation)
            assert replay.vertices == mesh.vertices, "Posing must be repeatable"
            if pose != "upright":
                assert np.max(np.abs(np.array(mesh.vertices) - neutral.vertices)) > .05
    # Mutating controls doesn't silently accept corrupt recipes.
    for overrides in ({"bend_x": float("nan")}, {"opening": 5}, {"unknown": 0}):
        try:
            plant(*PAIRINGS[0], overrides=overrides)
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid pose accepted")
    (out / "catalog.json").write_text(json.dumps(catalog, indent=2))
    print(f"Built {len(STEMS)} stems, {len(LEAVES)} leaves, {len(FLOWERS)} flowers + "
          f"{len(BUDS)} buds; {len(catalog['plants'])} posed assemblies. Geometry checks passed.")


if __name__ == "__main__":
    main()
