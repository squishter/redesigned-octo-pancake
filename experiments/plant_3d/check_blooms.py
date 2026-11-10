"""Validate petal unfolding, family eligibility and independent flower maturity."""

import argparse
import json
from pathlib import Path

import numpy as np

from build_plants import validate
from plant_components import BLOOM_PROFILES, BUDS, FLOWERS, flower_mesh
from stem_growth import SINGLE_BLOOM_MIN, assemble, make_recipe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("/tmp/plant-blooms"))
    args = parser.parse_args()
    cases = []
    for family in BLOOM_PROFILES:
        topology = None
        widths = []
        for stage in (0., .25, .5, .75, 1.):
            mesh = flower_mesh(family, seed=81, controls=dict(bloom=stage))
            validate(mesh)
            if topology is not None:
                assert mesh.triangles == topology, family + " stage changes topology"
            topology = mesh.triangles
            points = np.array(mesh.vertices)
            widths.append(float(np.ptp(points[:, 0])))
            saved = json.loads(json.dumps(dict(bloom=stage)))
            assert mesh.vertices == flower_mesh(family, seed=81, controls=saved).vertices
            if stage == 1.:
                assert mesh.vertices == flower_mesh(family, seed=81).vertices, "Default mature geometry changed"
        assert widths[-1] > widths[0] * 1.4, family + " doesn't visibly unfold"
        assert all(a <= b + 1e-12 for a, b in zip(widths, widths[1:])), family + " opening reverses"
        cases.append(dict(family=family, widths=widths, stages=5))
    for family in (*FLOWERS, *BUDS):
        if family in BLOOM_PROFILES:
            continue
        try:
            flower_mesh(family, controls=dict(bloom=.5))
        except ValueError:
            pass
        else:
            raise AssertionError("Unsupported bloom deformation accepted: " + family)
    for bad in (-.1, 1.1, float("nan")):
        try:
            flower_mesh("rose", controls=dict(bloom=bad))
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid bloom stage accepted")
    recipe = make_recipe("gentle", "many", "many", seed=81, controls=dict(bloom_min=.1, bloom_max=1.))
    mixed, metadata = assemble(recipe)
    blooms = [s["bloom"] for s in mixed.attachments if s["kind"] == "flower"]
    assert len(set(blooms)) == 15 and min(blooms) < .35 and max(blooms) > .8
    assert all(.1 <= b <= 1. for b in blooms)
    replay, _ = assemble(json.loads(json.dumps(recipe)))
    assert mixed.vertices == replay.vertices
    posed, _ = assemble(recipe, pose="reaching")
    assert blooms == [s["bloom"] for s in posed.attachments if s["kind"] == "flower"], "Pose aged the flowers"
    closed_recipe = make_recipe("gentle", "many", "many", seed=81, controls=dict(bloom_min=.2, bloom_max=.2))
    closed, _ = assemble(closed_recipe)
    assert all(s["bloom"] == .2 for s in closed.attachments if s["kind"] == "flower")
    # Centers deform with petals, while stems/leaves and attachment sites stay fixed.
    static = np.isin(np.array(mixed.labels), (1, 2, 6))
    assert np.array_equal(np.array(mixed.vertices)[static], np.array(closed.vertices)[static])
    assert [(s["branch"], s["at"], s["root"], s["frame"], s["scale"]) for s in mixed.attachments] == [
        (s["branch"], s["at"], s["root"], s["frame"], s["scale"]) for s in closed.attachments]
    unsupported, _ = assemble(recipe, flower="calla")
    assert all(s["bloom"] == 1. for s in unsupported.attachments if s["kind"] == "flower")
    # Recipes saved before this feature must regenerate their original open heads.
    legacy = json.loads(json.dumps(recipe))
    legacy["controls"].pop("bloom_min")
    legacy["controls"].pop("bloom_max")
    old, _ = assemble(legacy)
    assert all(s["bloom"] == 1. for s in old.attachments if s["kind"] == "flower")
    try:
        make_recipe(controls=dict(bloom_min=.8, bloom_max=.2))
    except ValueError:
        pass
    else:
        raise AssertionError("Reversed bloom range accepted")
    single_stages = []
    for seed in (0, 41, 81, 309):
        for branches in ("none", "few", "many"):
            # The actual head count controls the rule, including a 'many'
            # preset overridden to one flower and any amount of branching.
            single = make_recipe("gentle", branches, "many", seed=seed,
                                 controls=dict(flower_count=1, leaf_density=0.))
            head, _ = assemble(single)
            stages = [s["bloom"] for s in head.attachments if s["kind"] == "flower"]
            assert len(stages) == 1 and SINGLE_BLOOM_MIN <= stages[0] <= 1.
            assert single["controls"]["bloom_max"] == 1., "Fully open was excluded"
            single_stages.extend(stages)
    constrained = make_recipe(flowers="one", controls=dict(bloom_min=.10, bloom_max=.20))
    mesh, _ = assemble(constrained)
    assert [s["bloom"] for s in mesh.attachments if s["kind"] == "flower"] == [SINGLE_BLOOM_MIN]
    mature = make_recipe(flowers="one", controls=dict(bloom_min=1., bloom_max=1.))
    mesh, _ = assemble(mature)
    assert [s["bloom"] for s in mesh.attachments if s["kind"] == "flower"] == [1.]
    assert make_recipe(flowers="many")["controls"]["bloom_min"] == .35
    assert make_recipe(flowers="few", controls=dict(bloom_min=.1))["controls"]["bloom_min"] == .1
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "bloom_validation.json").write_text(json.dumps(dict(
        failures=0, eligible_families=len(cases), component_stages=len(cases) * 5,
        mixed_rose_stages=blooms, single_bloom_stages=single_stages, cases=cases), indent=2))
    print(f"PASSED: {len(cases)} families, {len(cases) * 5} stages, mixed maturity, single-bloom floor, poses and replay.")


if __name__ == "__main__":
    main()
