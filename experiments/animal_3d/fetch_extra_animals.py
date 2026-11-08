"""Download pinned, openly licensed source assets, retaining notices and hashes.

python3 experiments/animal_3d/fetch_extra_animals.py --out=/path/to/extra-sources
No code from the source repositories is downloaded or executed.
"""

import argparse
import hashlib
import json
import struct
from pathlib import Path
from urllib.request import urlopen


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    files = []

    def fetch(relative, repository, revision, path, creator, license_id, primary):
        url = f"https://raw.githubusercontent.com/{repository}/{revision}/{path}"
        destination = args.out / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        data = urlopen(url, timeout=60).read()
        assert not data.startswith(b"version https://git-lfs"), "LFS pointer is not an asset"
        destination.write_bytes(data)
        files.append(dict(file=relative, url=url, revision=revision, creator=creator,
                          license=license_id, primary=primary, bytes=len(data),
                          sha256=hashlib.sha256(data).hexdigest()))
        print(relative, len(data), flush=True)

    gob_revision = "4e73c68fa6e8ca9d948fcc0ce7215c830a022c3b"
    for name in ["Corgi", "Hippo", "Rhino", "Bat", "Duck", "Platypus", "Anglerfish", "Shark", "Jellyfish", "Red"]:
        fetch(f"gobkit/{name}.glb", "Ariescar/gobkit-free-assets", gob_revision,
              f"animal/{name}.glb", "Gobkit / Alsomind Tech Co., Ltd.", "CC0-1.0",
              "https://github.com/Ariescar/gobkit-free-assets")
    for name in ["LICENSE", "animal/Texture001.png"]:
        fetch("gobkit/" + name.split("/")[-1], "Ariescar/gobkit-free-assets", gob_revision,
              name, "Gobkit / Alsomind Tech Co., Ltd.", "CC0-1.0",
              "https://github.com/Ariescar/gobkit-free-assets")
    cat_revision = "881c1de6a9e813b7c269be80a9bf91baf588f5f2"
    for folder, names, creator, primary in [
        ("toon-cat", ["toon_cat_free.glb", "LICENSE.md"], "Omabuarts Studio",
         "https://sketchfab.com/3d-models/toon-cat-free-b2bd1ee7858444bda366110a2d960386"),
        ("tuxedo-cat", ["scene.gltf", "scene.bin", "LICENSE.md"], "DreamNoms",
         "https://sketchfab.com/3d-models/tuxedo-cat-animated-20-783fcb78b55b4394a212c2b6392e1113"),
    ]:
        for name in names:
            fetch(f"{folder}/{name}", "lhns/steam-frame-nix", cat_revision,
                  f"modules/pet/sources/{folder}/{name}", creator, "CC-BY-4.0", primary)
    for name in ["shepherd.glb", "DOG-CREDITS.txt"]:
        fetch("shepherd/" + name, "YenanLiu/soundworld4d-demo",
              "004f7e5acf1accbfe669ae9c19afcb4bd977f637", "episodes/assets/living/" + name,
              "Quaternius", "CC-BY-3.0", "https://poly.pizza/m/Hssa6NPc6W")
    # The mirror has already decimated/repacked these CC BY sources. Preserve
    # those modification credits; its compressed GLBs require normalization.
    for name, creator, model_id in [
        ("labrador", "kenchoo; original Dog by all of life", "labrador-dog-1f56cfbab07e4fe49b5d9e521c82073a"),
        ("elephant", "Rukh3D", "elephant-4ae161372d6a4219a87340339d1ffe03"),
        ("lion", "kenchoo; original Baby-Lion by hendrikReyneke", "baby-lion-c9599625dc474262aab754d7b63841f5"),
    ]:
        fetch(f"daydaze/{name}.glb", "dpologdvinity/daydaze", "d381c3b268f7ff4321cbe9a123e5ede6cbc0ea73",
              f"public/models/animals/{name}.glb", creator, "CC-BY-4.0", "https://sketchfab.com/3d-models/" + model_id)
    fetch("daydaze/UPSTREAM-CREDITS.md", "dpologdvinity/daydaze", "d381c3b268f7ff4321cbe9a123e5ede6cbc0ea73",
          "docs/assets.md", "See individual model credits", "See individual model licenses",
          "https://github.com/dpologdvinity/daydaze")
    (args.out / "downloads.json").write_text(json.dumps(files, indent=2) + "\n")
    # This source uses one external buffer and no images. Repackage losslessly
    # for the Godot importer; no geometry, UV, skin or animation conversion.
    folder = args.out / "tuxedo-cat"
    document = json.loads((folder / "scene.gltf").read_text())
    assert len(document["buffers"]) == 1 and not document.get("images")
    binary = (folder / document["buffers"][0].pop("uri")).read_bytes()
    payload = json.dumps(document, separators=(",", ":")).encode()
    payload += b" " * (-len(payload) % 4)
    binary += b"\x00" * (-len(binary) % 4)
    data = (struct.pack("<4sII", b"glTF", 2, 28 + len(payload) + len(binary))
            + struct.pack("<II", len(payload), 0x4E4F534A) + payload
            + struct.pack("<II", len(binary), 0x004E4942) + binary)
    (folder / "tuxedo_cat.glb").write_bytes(data)


if __name__ == "__main__":
    main()
