"""Validate the 3D investigation's exported meshes and pose invariants."""

import argparse
import json
from pathlib import Path

import numpy as np

from project_line_art import project


def check_models(directory):
    reference = {}
    count = 0
    for path in sorted(directory.glob("*.json")):
        model = json.loads(path.read_text())
        if "vertices" not in model:
            continue
        vertices, uv, rest = (np.asarray(model[k]) for k in ("vertices", "uv", "rest"))
        assert np.isfinite(vertices).all(), f"{path}: non-finite geometry"
        assert len(vertices) == len(uv) == len(rest), f"{path}: missing surface coordinates"
        assert set(model["materials"]) == {0, 2, 3}, f"{path}: lost coat/ear/face material IDs"
        assert vertices[:, 2].min() >= -0.02, f"{path}: skin below the ground"
        assert len(model["skeleton"]) == 26, f"{path}: incomplete skeleton"
        assert model["skinning"]["max_influences"] <= 4, f"{path}: too many bone weights"
        assert model["skinning"]["max_weight_error"] < 1e-5, f"{path}: unnormalized skin weights"
        for name, bone in model["skeleton"].items():
            rest_bone = model["rest_bones"][name]
            length = np.linalg.norm(np.subtract(bone["b"], bone["a"]))
            rest_length = np.linalg.norm(np.subtract(rest_bone["b"], rest_bone["a"]))
            assert abs(length - rest_length) < 1e-4, f"{path}: stretched {name}"
            if name != "root":
                rotation = np.array(bone["rotation"])
                assert (rotation >= np.array(bone["minimum"]) - 0.01).all(), f"{path}: {name} below joint limit"
                assert (rotation <= np.array(bone["maximum"]) + 0.01).all(), f"{path}: {name} above joint limit"
            if name.startswith(("fore", "hind")) and name.endswith(".2"):
                if model["pose"] == "walk" and name == "fore.R.2":
                    assert bone["b"][2] > 0.15, f"{path}: swing foot did not lift"
                else:
                    assert abs(bone["b"][2] - 0.065) < 0.003, f"{path}: foot floats/sinks: {name}"
        key = model["species"]
        if key not in reference:
            reference[key] = model
        else:
            first = reference[key]
            assert np.array_equal(rest, first["rest"]), f"{path}: rest surface moved"
            assert np.array_equal(uv, first["uv"]), f"{path}: coat coordinates slid"
            assert model["parts"] == first["parts"], f"{path}: component identities changed"
            assert not np.allclose(vertices, first["vertices"]), f"{path}: pose did not deform the mesh"
        count += 1
        print(f"{path.stem}: 26 fixed-length bones, bounded joints, stable surface IDs/UVs, grounded support feet")
    assert count == 7 and len(reference) == 3, f"Expected 7 poses of 3 species, found {count}"


def check_occlusion():
    # Two exactly overlapping triangles at different depths. The back face
    # must disappear even though it is processed after the front face.
    elevation = np.radians(7)
    right = np.array([1.0, 0, 0])
    direction = np.array([0, -np.cos(elevation), np.sin(elevation)])
    up = np.cross(direction, right)
    triangle = np.array([-right - up, right - up, up])
    vertices = np.vstack((triangle + direction * 0.2, triangle - direction * 0.2))
    model = dict(species="horse", vertices=vertices, triangles=[[0, 1, 2], [3, 4, 5]],
                 normals=[direction] * 6, uv=[[0, 0, 0]] * 6, rest=vertices, materials=[3, 0])
    labels, *_ = project(model, 0, 64)
    assert labels[32, 32] == 3, "A hidden surface overpainted the front surface"
    assert set(np.unique(labels)) == {0, 3}, "A hidden triangle leaked into the picture"
    print("Depth buffer: hidden triangle fully occluded")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--models", type=Path, required=True)
    args = parser.parse_args()
    check_models(args.models)
    check_occlusion()
    print("PASSED")
