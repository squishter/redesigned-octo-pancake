"""Independently compare Godot neutral skins with the original glTF bind math.

python3 experiments/animal_3d/check_pose_bind_space.py --input=/tmp/animal-poses/bind_checks
Requires NumPy and SciPy. No Blender or Godot skinning implementation is reused.
"""

import argparse
import json
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree

from audit_gltf_assets import accessor_values, read_glb


def matrix(node):
    if "matrix" in node:
        return np.array(node["matrix"]).reshape(4, 4).T
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    rotation = np.array([
        [1 - 2 * (y*y + z*z), 2 * (x*y - z*w), 2 * (x*z + y*w)],
        [2 * (x*y + z*w), 1 - 2 * (x*x + z*z), 2 * (y*z - x*w)],
        [2 * (x*z - y*w), 2 * (y*z + x*w), 1 - 2 * (x*x + y*y)],
    ])
    result = np.eye(4)
    result[:3, :3] = rotation @ np.diag(node.get("scale", [1, 1, 1]))
    result[:3, 3] = node.get("translation", [0, 0, 0])
    return result


def source_skin(path):
    document, binary = read_glb(path)
    worlds = {}

    def traverse(index, parent):
        node = document["nodes"][index]
        worlds[index] = parent @ matrix(node)
        for child in node.get("children", []):
            traverse(child, worlds[index])

    for root in document["scenes"][document.get("scene", 0)]["nodes"]:
        traverse(root, np.eye(4))
    points = []
    for index, node in enumerate(document["nodes"]):
        if "mesh" not in node or index not in worlds:
            continue
        skin = document["skins"][node["skin"]] if "skin" in node else None
        if skin:
            binds = np.array(accessor_values(document, binary, skin["inverseBindMatrices"])).reshape(-1, 4, 4).transpose(0, 2, 1)
            palette = np.array([worlds[joint] @ bind for joint, bind in zip(skin["joints"], binds)])
        for primitive in document["meshes"][node["mesh"]]["primitives"]:
            attrs = primitive["attributes"]
            vertices = np.array(accessor_values(document, binary, attrs["POSITION"]))
            vertices = np.column_stack((vertices, np.ones(len(vertices))))
            if skin and "WEIGHTS_0" in attrs:
                result = np.zeros((len(vertices), 4))
                for channel in range(2):
                    if f"WEIGHTS_{channel}" not in attrs:
                        continue
                    weights = np.array(accessor_values(document, binary, attrs[f"WEIGHTS_{channel}"]))
                    joints = np.array(accessor_values(document, binary, attrs[f"JOINTS_{channel}"]), dtype=int)
                    for influence in range(4):
                        result += np.einsum("nij,nj->ni", palette[joints[:, influence]], vertices) * weights[:, influence, None]
            else:
                result = vertices @ worlds[index].T
            points.extend(result[:, :3])
    points = np.array(points)
    lo, hi = points.min(axis=0), points.max(axis=0)
    return (points - np.array([(lo[0]+hi[0])/2, lo[1], (lo[2]+hi[2])/2])) / (hi[1] - lo[1])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    reports = []
    for path in sorted(args.input.glob("*.json")):
        snapshot = json.loads(path.read_text())
        source = source_skin(repo / snapshot["scene"].removeprefix("res://"))
        actual = np.array(snapshot["vertices"])
        error = max(cKDTree(source).query(actual)[0].max(), cKDTree(actual).query(source)[0].max())
        assert error < 0.001, (path.stem, error)
        reports.append(dict(model=path.stem, maximum_normalized_distance=float(error)))
        print(path.stem, "bind space passed", float(error))
    assert len(reports) == 37
    (args.input.parent / "bind_validation.json").write_text(json.dumps(reports, indent=2) + "\n")


if __name__ == "__main__":
    main()
