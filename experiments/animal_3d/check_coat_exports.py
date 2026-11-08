"""Check the exported buffers, not just Blender's pre-export mesh data."""

import argparse
import hashlib
import json
import math
from pathlib import Path

from audit_gltf_assets import accessor_values, audit, read_glb
from uv_geometry import area, overlaps


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    args = parser.parse_args()
    inventory = json.loads(Path(__file__).with_name("sourced_asset_inventory.json").read_text())["files"]
    manifests = sorted(args.input.glob("*_uv.json"))
    assert len(manifests) == 21, f"Expected all 21 prepared meshes, got {len(manifests)}"
    reports = []
    for path in manifests:
        manifest = json.loads(path.read_text())
        source = next(s for s in inventory if s["sha256"] == manifest["source_sha256"])
        glb = args.input / manifest["glb"]
        report = audit(glb)
        assert report["sha256"] == manifest["sha256"]
        assert report["triangles"] == source["triangles"], manifest["id"]
        assert report["uv_on_all_primitives"] and report["uv2_on_all_primitives"]
        # Stag's antlers are a rigid child of the head rather than skinned;
        # retain that source structure instead of requiring weights on them.
        assert report["skinned_primitives"] == source.get("skinned_primitives", True)
        assert report["maximum_weight_error"] < 1e-5
        if "skin_joint_counts" in source:
            assert report["skin_joint_counts"] == source["skin_joint_counts"]
        else:
            assert report["skin_joint_counts"] == source["armature_bones"]
        expected = source.get("clips", source.get("actions"))
        assert len(report["clips"]) == len(expected), (manifest["id"], report["clips"], expected)
        # Blender prefixes some action names with the exported armature name.
        assert all(any(name == clip or name.endswith("|" + clip) for name in report["clips"])
                   for clip in expected), (manifest["id"], report["clips"], expected)
        document, binary = read_glb(glb)
        triangles = []
        for mesh in document["meshes"]:
            for primitive in mesh["primitives"]:
                attrs = primitive["attributes"]
                uv = accessor_values(document, binary, attrs["TEXCOORD_0"])
                flow = accessor_values(document, binary, attrs["TEXCOORD_1"])
                assert all(all(math.isfinite(v) for v in row) for row in uv + flow)
                assert all(-1e-5 <= v <= 1.00001 for row in uv for v in row)
                indices = [int(v[0]) for v in accessor_values(document, binary, primitive["indices"])]
                triangles.extend([[uv[i] for i in indices[k:k + 3]] for k in range(0, len(indices), 3)])
        assert not overlaps(triangles), manifest["id"]
        assert all(area(t) > 1e-15 for t in triangles), manifest["id"]
        report["id"] = manifest["id"]
        reports.append(report)
        print(manifest["id"], "export passed", flush=True)
    (args.input / "export_validation.json").write_text(json.dumps(reports, indent=2) + "\n")


if __name__ == "__main__":
    main()
