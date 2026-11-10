"""Create fixed-camera flower opening stages and plants with mixed maturity."""

import argparse
import json
from pathlib import Path

from build_stems import save, verify_puzzles
from plant_components import BLOOM_PROFILES, flower_mesh, recipe
from stem_growth import VERSION, assemble, make_recipe


FAMILIES = ("rose", "tulip", "lotus", "poppy", "lily", "magnolia")
STAGES = ((.10, "Tightly cupped"), (.40, "Partly open"), (.70, "Mostly open"), (1., "Fully open"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("/tmp/plant-blooms"))
    parser.add_argument("--verify-puzzles", action="store_true")
    args = parser.parse_args()
    if args.verify_puzzles:
        verify_puzzles(args.out)
        return
    components, plants = args.out / "components", args.out / "plants"
    components.mkdir(parents=True, exist_ok=True)
    plants.mkdir(parents=True, exist_ok=True)
    catalog = dict(version=VERSION, bloom_profiles=BLOOM_PROFILES, components=[], plants=[])
    for family in FAMILIES:
        for stage, label in STAGES:
            record = recipe("flowers", family, seed=81, controls=dict(bloom=stage))
            mesh = flower_mesh(family, seed=81, controls=record["controls"])
            metadata = dict(version=VERSION, seed=81, family=family, bloom=stage, stage_label=label, recipe=record)
            entry = save(mesh, metadata, components, family + "_bloom_" + str(round(stage * 100)).zfill(3))
            entry.update(frame_group=family, views=["three_quarter", "high"] if family == "rose" else ["three_quarter"])
            catalog["components"].append(entry)
    cases = [
        ("rose_closed", "rose", "serrated", "many", "many", .10, .10, True),
        ("rose_half", "rose", "serrated", "many", "many", .50, .50, False),
        ("rose_open", "rose", "serrated", "many", "many", 1., 1., True),
        ("rose_mixed", "rose", "serrated", "many", "many", .10, 1., True),
        ("tulip_mixed", "tulip", "lance", "few", "few", .15, 1., False),
        ("lotus_mixed", "lotus", "round", "few", "few", .15, 1., False),
    ]
    for name, family, leaf, branches, flowers, low, high, pipeline in cases:
        growth = make_recipe("gentle", branches, flowers, seed=81, controls=dict(bloom_min=low, bloom_max=high))
        mesh, metadata = assemble(growth, leaf, family)
        entry = save(mesh, metadata, plants, name)
        entry.update(frame_group=family + "_plant", views=["front", "high"], pipeline=pipeline)
        catalog["plants"].append(entry)
    (args.out / "catalog.json").write_text(json.dumps(catalog, indent=2))
    print("Built 24 bloom-stage meshes and six fixed/mixed-stage plants.")


if __name__ == "__main__":
    main()
