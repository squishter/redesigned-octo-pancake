"""Build the 3 x 3 x 3 stem/branch/bloom study and optional custom plants."""

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

from build_plants import validate
from mesh_geometry import Mesh, tube, write_glb
from stem_growth import BRANCHING, CURVES, FLOWERING, VERSION, assemble, make_recipe, skeleton


def save(mesh, metadata, directory, name):
    validate(mesh)
    glb, surface = directory / (name + ".glb"), directory / (name + ".json")
    write_glb(mesh, glb, metadata)
    surface.write_text(json.dumps(mesh.data(metadata), separators=(",", ":")))
    return dict(id=name, mesh=str(glb.relative_to(directory.parent)),
                data=str(surface.relative_to(directory.parent)),
                sha256=hashlib.sha256(glb.read_bytes()).hexdigest(), metadata=metadata)


def verify_puzzles(out):
    catalog = json.loads((out / "catalog.json").read_text())
    entries = {e["id"]: e for e in catalog["plants"]}
    files = sorted((out / "previews").glob("*_collage.json"))
    assert len(files) == sum(e["pipeline"] for e in entries.values())
    for path in files:
        saved = json.loads(path.read_text())["source"]["plant_mesh"]
        mesh, _ = assemble(saved["growth"], saved["leaf"], saved["flower"], saved["pose"],
                           saved["component_variant"], saved["controls"])
        original = json.loads((out / entries[path.name.removesuffix("_collage.json")]["data"]).read_text())
        assert np.array_equal(np.array(mesh.vertices), np.array(original["vertices"])), path
        assert mesh.triangles == original["triangles"] and mesh.parts == original["parts"]
    print(f"PASSED: exactly rebuilt {len(files)} plants from saved Godot puzzle recipes.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("/tmp/plant-stems-v4"))
    parser.add_argument("--single", action="store_true")
    parser.add_argument("--verify-puzzles", action="store_true")
    parser.add_argument("--curve", choices=CURVES, default="gentle")
    parser.add_argument("--branching", choices=BRANCHING, default="few")
    parser.add_argument("--flowers", choices=FLOWERING, default="few")
    parser.add_argument("--seed", type=int, default=81)
    parser.add_argument("--leaf", default="serrated")
    parser.add_argument("--flower", default="rose")
    parser.add_argument("--control", action="append", default=[])
    args = parser.parse_args()
    if args.verify_puzzles:
        verify_puzzles(args.out)
        return
    stems, plants = args.out / "stems", args.out / "plants"
    stems.mkdir(parents=True, exist_ok=True)
    plants.mkdir(parents=True, exist_ok=True)
    controls = {}
    for assignment in args.control:
        name, separator, value = assignment.partition("=")
        if not separator:
            parser.error("Use --control=NAME=NUMBER")
        controls[name] = float(value)
    if args.single:
        record = make_recipe(args.curve, args.branching, args.flowers, args.seed, controls)
        mesh, metadata = assemble(record, args.leaf, args.flower)
        name = args.flower + "_" + args.curve + "_" + args.branching + "_" + args.flowers
        print(json.dumps(save(mesh, metadata, plants, name), indent=2))
        return
    if controls:
        parser.error("Use --single with custom --control values")
    catalog = dict(version=VERSION, stems=[], plants=[], curve_presets=list(CURVES),
                   branching_presets=list(BRANCHING), flowering_presets=list(FLOWERING))
    for curve in CURVES:
        for branching in BRANCHING:
            record = make_recipe(curve, branching, "one", args.seed)
            tree = skeleton(record)
            mesh = Mesh()
            for branch in tree["branches"]:
                tube(mesh, branch["points"], branch["radius"], 1, 10 + branch["id"])
            metadata = dict(version=VERSION, seed=args.seed, growth=record,
                            stem=curve + "_" + branching, curve=curve, branching=branching)
            catalog["stems"].append(save(mesh, metadata, stems, "stem_" + curve + "_" + branching))
            for flowering in FLOWERING:
                record = make_recipe(curve, branching, flowering, args.seed)
                mesh, metadata = assemble(record, args.leaf, args.flower)
                name = args.flower + "_" + curve + "_" + branching + "_" + flowering
                selected = (curve, branching, flowering) in (
                    ("straight", "none", "one"), ("gentle", "few", "few"), ("winding", "many", "many"))
                entry = save(mesh, metadata, plants, name)
                entry.update(group="matrix", curve=curve, branching=branching, flowering=flowering,
                             views=["front", "three_quarter", "side", "back", "high"] if selected else ["front"],
                             pipeline=selected or (curve, branching, flowering) in (
                                 ("gentle", "none", "many"), ("winding", "many", "one")))
                catalog["plants"].append(entry)
    for pose in ("reaching", "nodding"):
        record = make_recipe("winding", "many", "many", args.seed)
        mesh, metadata = assemble(record, args.leaf, args.flower, pose)
        entry = save(mesh, metadata, plants, args.flower + "_winding_many_many_" + pose)
        entry.update(group="pose", views=["front"], pipeline=False)
        catalog["plants"].append(entry)
    for flower, leaf in (("daisy", "oval"), ("hibiscus", "ivy"), ("lily", "lance")):
        record = make_recipe("gentle", "many", "many", args.seed)
        mesh, metadata = assemble(record, leaf, flower)
        entry = save(mesh, metadata, plants, flower + "_bush")
        entry.update(group="species", views=["front"], pipeline=False)
        catalog["plants"].append(entry)
    (args.out / "catalog.json").write_text(json.dumps(catalog, indent=2))
    print(f"Built {len(catalog['stems'])} stem structures, 27 rose combinations, two poses and three other flower bushes.")


if __name__ == "__main__":
    main()
