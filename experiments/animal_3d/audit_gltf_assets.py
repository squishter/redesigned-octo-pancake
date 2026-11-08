"""Inspect downloaded GLBs without executing or modifying asset contents.

python3 experiments/animal_3d/audit_gltf_assets.py /path/to/models/*.glb
"""

import argparse
import hashlib
import json
import math
import struct
from pathlib import Path


def accessor_values(document, binary, index):
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    assert view["buffer"] == 0 and "sparse" not in accessor
    formats = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[accessor["type"]]
    unpacker = struct.Struct("<" + formats[accessor["componentType"]] * components)
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", unpacker.size)
    normalizer = {5121: 255, 5123: 65535}.get(accessor["componentType"], 1) if accessor.get("normalized") else 1
    return [tuple(v / normalizer for v in unpacker.unpack_from(binary, offset + i * stride))
            for i in range(accessor["count"])]


def read_glb(path):
    data = path.read_bytes()
    assert data[:4] == b"glTF" and struct.unpack_from("<I", data, 4)[0] == 2, path
    assert struct.unpack_from("<I", data, 8)[0] == len(data), path
    position, document, binary = 12, None, b""
    while position < len(data):
        length, kind = struct.unpack_from("<II", data, position)
        payload = data[position + 8:position + 8 + length]
        if kind == 0x4E4F534A:
            document = json.loads(payload)
        elif kind == 0x004E4942:
            binary = payload
        position += 8 + length
    assert document is not None
    return document, binary


def audit(path):
    document, binary = read_glb(path)
    data = path.read_bytes()
    primitives = [p for m in document.get("meshes", []) for p in m["primitives"]]
    vertices = triangles = 0
    maximum_weight_error = 0.0
    max_influences = 0
    for primitive in primitives:
        attributes = primitive["attributes"]
        count = document["accessors"][attributes["POSITION"]]["count"]
        vertices += count
        assert primitive.get("mode", 4) == 4, "Expected triangle topology"
        triangles += (document["accessors"][primitive["indices"]]["count"]
                      if "indices" in primitive else count) // 3
        if "WEIGHTS_0" in attributes:
            sets = [accessor_values(document, binary, attributes[key]) for key in sorted(attributes)
                    if key.startswith("WEIGHTS_")]
            weights = [sum(rows, ()) for rows in zip(*sets)]
            assert all(all(math.isfinite(x) and x >= 0 for x in row) for row in weights)
            maximum_weight_error = max(maximum_weight_error, max(abs(sum(row) - 1) for row in weights))
            max_influences = max(max_influences, max(sum(x > 0 for x in row) for row in weights))
    return dict(file=path.name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
                triangles=triangles, vertices=vertices, primitives=len(primitives),
                skin_joint_counts=[len(s["joints"]) for s in document.get("skins", [])],
                bone_names=[[document["nodes"][i].get("name", "") for i in s["joints"]]
                            for s in document.get("skins", [])],
                clips=[a.get("name", "") for a in document.get("animations", [])],
                materials=[m.get("name", "") for m in document.get("materials", [])],
                uv_on_all_primitives=all("TEXCOORD_0" in p["attributes"] for p in primitives),
                uv2_on_all_primitives=all("TEXCOORD_1" in p["attributes"] for p in primitives),
                skinned_primitives=all("JOINTS_0" in p["attributes"] and "WEIGHTS_0" in p["attributes"]
                                       for p in primitives),
                maximum_weight_error=maximum_weight_error, maximum_bone_influences=max_influences,
                images=len(document.get("images", [])))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("files", type=Path, nargs="+")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    reports = [audit(path) for path in args.files]
    if args.out:
        args.out.write_text(json.dumps(reports, indent=2) + "\n")
    for report in reports:
        print(f'{report["file"]}: {report["triangles"]} tris, '
              f'{report["skin_joint_counts"]} joints, {len(report["clips"])} clips, '
              f'UV={report["uv_on_all_primitives"]}, weight error={report["maximum_weight_error"]:.7f}')
