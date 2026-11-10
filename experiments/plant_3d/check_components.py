"""Check actual shape variety, recipe replay and mutation bounds for every family."""

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

from build_plants import validate
from plant_components import BUDS, FLOWERS, LEAVES, VARIANTS, flower_mesh, leaf_mesh, recipe


def shape_hash(mesh):
    vertices = np.asarray(mesh.vertices)
    # Ignore translation and uniform size: a claimed mutation must change shape.
    vertices -= vertices.mean(axis=0)
    vertices /= max(np.ptp(vertices, axis=0))
    return hashlib.sha256(vertices.round(7).astype("<f8").tobytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("/tmp/plant-library-v2"))
    args = parser.parse_args()
    reports = []
    for group, names, builder in (("leaves", LEAVES, leaf_mesh), ("flowers", (*FLOWERS, *BUDS), flower_mesh)):
        for family in names:
            fingerprints = set()
            for variant in VARIANTS:
                saved = json.loads(json.dumps(recipe(group, family, 81, variant)))
                mesh = builder(family, seed=81, variant=variant)
                validate(mesh)
                replay = builder(saved["family"], seed=saved["seed"], variant=saved["variant"],
                                 controls=saved["controls"])
                assert mesh.vertices == replay.vertices and mesh.triangles == replay.triangles
                assert mesh.parts == replay.parts and mesh.labels == replay.labels
                fingerprints.add(shape_hash(mesh))
            assert len(fingerprints) == len(VARIANTS), f"{family}: mutations only changed size"
            other_seed = builder(family, seed=93)
            assert shape_hash(other_seed) != shape_hash(builder(family, seed=81)), family
            # Invalid recipes must fail before producing nonfinite geometry.
            for bad in ({"width": float("nan")}, {"width": 20}, {"unknown": 0}):
                try:
                    builder(family, controls=bad)
                except ValueError:
                    pass
                else:
                    raise AssertionError(f"{family}: accepted invalid controls")
            reports.append(dict(group=group, family=family, distinct_mutations=len(fingerprints)))
    # Extremes exercise the public controls, not only the four demonstration presets.
    for group, family, builder, controls in (
        ("leaves", "monstera", leaf_mesh, dict(twist=-.7, curl=.55, width=.5)),
        ("leaves", "fern", leaf_mesh, dict(spread=1.35, lobe_depth=1.5)),
        ("flowers", "rose", flower_mesh, dict(opening=.4, curl=.25, width=1.4)),
        ("flowers", "calla", flower_mesh, dict(opening=.4, width=.6, cup=1.7)),
    ):
        validate(builder(family, controls=controls))
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "mutation_validation.json").write_text(json.dumps(dict(
        families=len(reports), distinct_meshes=sum(r["distinct_mutations"] for r in reports),
        cases=reports, failures=0), indent=2))
    print(f"PASSED: {len(reports)} families, {len(reports) * len(VARIANTS)} distinct shapes, recipe replay and bounds.")


if __name__ == "__main__":
    main()
