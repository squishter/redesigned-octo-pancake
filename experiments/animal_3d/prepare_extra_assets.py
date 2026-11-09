"""Make the selected additional sources importable without changing their rigs."""

import argparse
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

from audit_gltf_assets import accessor_values, audit


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--gltf-transform", type=Path, required=True, help="@gltf-transform/cli 4.5.1 executable")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    for folder, names in [
        ("gobkit", [p.name for p in (args.sources / "gobkit").glob("*.glb")] + ["LICENSE"]),
        ("toon-cat", ["toon_cat_free.glb", "LICENSE.md"]),
        ("shepherd", ["shepherd.glb", "DOG-CREDITS.txt"]),
    ]:
        destination = args.out / folder
        destination.mkdir(exist_ok=True)
        for name in names:
            shutil.copyfile(args.sources / folder / name, destination / name)
    # Tuxedo Cat's EyeRims have no UVs. Add a planar map to only that part;
    # retain every existing UV, position, weight, material, and animation byte.
    source = args.sources / "tuxedo-cat"
    document = json.loads((source / "scene.gltf").read_text())
    binary = bytearray((source / document["buffers"][0].pop("uri")).read_bytes())
    added = []
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            attrs = primitive["attributes"]
            if "TEXCOORD_0" in attrs:
                continue
            positions = accessor_values(document, binary, attrs["POSITION"])
            low = [min(p[k] for p in positions) for k in range(3)]
            extent = [max(p[k] for p in positions) - low[k] for k in range(3)]
            axes = sorted(range(3), key=lambda k: extent[k], reverse=True)[:2]
            uv = [tuple(0.02 + 0.96 * (p[k] - low[k]) / max(extent[k], 1e-12) for k in axes) for p in positions]
            binary.extend(b"\x00" * (-len(binary) % 4))
            offset = len(binary)
            binary.extend(b"".join(struct.pack("<ff", *p) for p in uv))
            view = len(document["bufferViews"])
            document["bufferViews"].append(dict(buffer=0, byteOffset=offset, byteLength=len(uv) * 8, target=34962))
            attrs["TEXCOORD_0"] = len(document["accessors"])
            document["accessors"].append(dict(bufferView=view, componentType=5126, count=len(uv), type="VEC2"))
            added.append(mesh.get("name"))
    document["buffers"][0]["byteLength"] = len(binary)
    payload = json.dumps(document, separators=(",", ":")).encode()
    payload += b" " * (-len(payload) % 4)
    binary.extend(b"\x00" * (-len(binary) % 4))
    data = (struct.pack("<4sII", b"glTF", 2, 28 + len(payload) + len(binary))
            + struct.pack("<II", len(payload), 0x4E4F534A) + payload
            + struct.pack("<II", len(binary), 0x004E4942) + binary)
    destination = args.out / "tuxedo-cat"
    destination.mkdir(exist_ok=True)
    (destination / "tuxedo_cat.glb").write_bytes(data)
    shutil.copyfile(source / "LICENSE.md", destination / "LICENSE.md")
    (destination / "MODIFICATIONS.txt").write_text("Added planar primary UVs to " + ", ".join(added) + "; losslessly repackaged glTF as GLB. Existing UVs and skin/animations retained.\n")
    destination = args.out / "daydaze"
    destination.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as temporary:
        for name in ["labrador", "elephant", "lion"]:
            decoded, floating = [str(Path(temporary) / (prefix + name + ".glb")) for prefix in ["decoded-", "float-"]]
            for command, source_file, output in [
                ("copy", str(args.sources / "daydaze" / (name + ".glb")), decoded),
                ("dequantize", decoded, floating),
                ("png", floating, str(destination / (name + ".glb"))),
            ]:
                subprocess.run([str(args.gltf_transform), command, source_file, output], check=True)
    shutil.copyfile(args.sources / "daydaze/UPSTREAM-CREDITS.md", destination / "UPSTREAM-CREDITS.md")
    (destination / "MODIFICATIONS.txt").write_text("Decoded meshopt, dequantized existing attributes, converted WebP to PNG for Godot. Upstream mirror had already decimated/repacked sources and retained a subset of clips. No new walking clips were created.\n")
    shutil.copyfile(Path(__file__).with_name("EXTRA_ASSET_CREDITS.md"), args.out / "ATTRIBUTION.md")
    shutil.copyfile(args.sources / "downloads.json", args.out / "source_downloads.json")
    reports = [dict(path=str(p.relative_to(args.out)), **audit(p)) for p in sorted(args.out.rglob("*.glb"))]
    assert len(reports) == 16
    (args.out / "inventory.json").write_text(json.dumps(reports, indent=2) + "\n")


if __name__ == "__main__":
    main()
