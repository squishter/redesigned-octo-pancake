"""Download and audit one explicitly licensed upstream plant source.

This preserves the source for inspection; it does not count it as an authored
component or quietly turn its transparency cards into incorrect solid meshes.
"""

import argparse
import hashlib
import json
import struct
from pathlib import Path
from urllib.request import urlopen


ROOT = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/GlassVaseFlowers/"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("/tmp/plant-sources"))
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for name, relative in (("README.md", "README.md"), ("GlassVaseFlowers.glb", "glTF-Binary/GlassVaseFlowers.glb")):
        with urlopen(ROOT + relative, timeout=20) as response:
            content = response.read(16 * 1024 * 1024 + 1)
        if len(content) > 16 * 1024 * 1024:
            raise ValueError("Unexpectedly large source")
        (args.out / name).write_bytes(content)
        hashes[name] = hashlib.sha256(content).hexdigest()
    source = (args.out / "GlassVaseFlowers.glb").read_bytes()
    magic, version, total = struct.unpack_from("<III", source)
    if (magic, version, total) != (0x46546C67, 2, len(source)):
        raise ValueError("Invalid source GLB")
    size, kind = struct.unpack_from("<II", source, 12)
    if kind != 0x4E4F534A:
        raise ValueError("Missing GLB JSON")
    document = json.loads(source[20:20 + size])
    meshes = []
    for mesh in document["meshes"]:
        primitives = []
        for primitive in mesh["primitives"]:
            material = document["materials"][primitive["material"]]
            accessor = document["accessors"][primitive["attributes"]["POSITION"]]
            primitives.append(dict(vertices=accessor["count"], material=material.get("name", ""),
                                   alpha_mode=material.get("alphaMode", "OPAQUE"),
                                   has_morph_targets=bool(primitive.get("targets"))))
        meshes.append(dict(name=mesh.get("name", ""), primitives=primitives))
    report = dict(
        publisher="Khronos glTF Sample Assets", flower_author="Rico Cilliers",
        source="https://github.com/KhronosGroup/glTF-Sample-Assets/tree/main/Models/GlassVaseFlowers",
        license="CC0-1.0 (model README Legal section)", hashes=hashes,
        meshes=meshes, skins=len(document.get("skins", [])),
        conclusion="One combined MASK-material flower mesh, no skin. Requires alpha-aware geometry extraction and organ segmentation; not added to the modular catalog.",
    )
    (args.out / "audit.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
