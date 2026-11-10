"""Bake compact modular surfaces for Godot; no Python is needed at runtime.

Topology is shared by the four variants. Petals unfold linearly in
smoothstep(bloom); ancillary stamens use a bounded endpoint approximation.
"""

import argparse
import hashlib
import json
import struct
import zlib
from pathlib import Path

import numpy as np

from build_plants import validate
from mesh_geometry import PALETTE
from plant_components import BLOOM_PROFILES, BUDS, FLOWERS, LEAVES, VARIANTS, flower_mesh, leaf_mesh


MAGIC = b"PLANT001"


def bake_family(group, family, builder, out):
    morph = family in BLOOM_PROFILES
    states = []
    reference = None
    endpoint_error = 0.
    for variant in VARIANTS:
        opened = builder(family, seed=81, variant=variant)
        validate(opened)
        if reference is None:
            reference = opened
        else:
            assert reference.triangles == opened.triangles and reference.labels == opened.labels
            assert reference.parts == opened.parts
        states.append(np.asarray(opened.vertices, dtype="<f4").tobytes())
        if morph:
            closed = builder(family, seed=81, variant=variant, controls={"bloom": 0.})
            validate(closed)
            assert opened.triangles == closed.triangles and opened.parts == closed.parts
            states.append(np.asarray(closed.vertices, dtype="<f4").tobytes())
            # Verify endpoint interpolation against the actual authoring model.
            half = builder(family, seed=81, variant=variant, controls={"bloom": .4})
            blend = .4 * .4 * (3 - 2 * .4)
            mixed = np.asarray(closed.vertices) * (1 - blend) + np.asarray(opened.vertices) * blend
            error = float(np.linalg.norm(mixed - half.vertices, axis=1).max())
            assert error < .006, (family, error)
            endpoint_error = max(endpoint_error, error)
    count = len(reference.vertices)
    triangles = np.asarray(reference.triangles, dtype="<u4").reshape(-1)
    labels = np.asarray(reference.labels, dtype="u1")
    parts = np.asarray(reference.parts, dtype="<u2")
    assert max(reference.parts) < 65536
    raw = (struct.pack("<IIII", count, len(triangles), len(VARIANTS), int(morph)) +
           triangles.tobytes() + labels.tobytes() + parts.tobytes() + b"".join(states))
    packed = MAGIC + struct.pack("<I", len(raw)) + zlib.compress(raw, level=9)
    name = ("leaf" if group == "leaves" else group[:-1]) + "_" + family + ".dat"
    (out / name).write_bytes(packed)
    return dict(file="res://assets/plants/" + name, vertices=count, triangles=len(triangles) // 3,
                sha256=hashlib.sha256(packed).hexdigest(), raw_sha256=hashlib.sha256(raw).hexdigest(),
                bloom_profile=BLOOM_PROFILES.get(family, "fixed"), bytes=len(packed),
                endpoint_error=endpoint_error)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("assets/plants"))
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    source = hashlib.sha256()
    for name in ("plant_components.py", "mesh_geometry.py"):
        source.update(name.encode())
        source.update(Path(__file__).with_name(name).read_bytes())
    catalog = dict(version=1, variants=list(VARIANTS), palette=PALETTE,
                   source_sha256=source.hexdigest(), leaves={}, flowers={}, buds={})
    for group, names, builder in (("leaves", LEAVES, leaf_mesh), ("flowers", FLOWERS, flower_mesh),
                                   ("buds", BUDS, flower_mesh)):
        for family in names:
            catalog[group][family] = bake_family(group, family, builder, args.out)
    revision = hashlib.sha256(json.dumps(catalog, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    catalog["revision"] = revision
    (args.out / "catalog.json").write_text(json.dumps(catalog, indent=2, sort_keys=True) + "\n")
    size = sum(info["bytes"] for group in ("leaves", "flowers", "buds") for info in catalog[group].values())
    print(f"Baked 24 leaves, 32 flowers and five buds, four variants each: {size / 1024**2:.2f} MiB.")


if __name__ == "__main__":
    main()
