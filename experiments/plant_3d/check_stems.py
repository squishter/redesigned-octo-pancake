"""Check independent growth axes, broad curvature, exact counts and replay."""

import argparse
import json
from pathlib import Path

import numpy as np

from build_plants import plant, validate
from stem_growth import (
    BRANCHING, CURVES, FLOWERING, FLOWER_COUNTS, assemble, flower_sockets,
    make_recipe, path_stats, sample, skeleton,
)


def check_tree(tree):
    for branch in tree["branches"]:
        points = np.array(branch["points"])
        delta = np.diff(points, axis=0)
        lengths = np.linalg.norm(delta, axis=1)
        assert np.isfinite(points).all() and np.all(lengths > 0)
        assert np.allclose(lengths, lengths[0], atol=1e-12), "Segments stretch"
        assert branch["max_curvature"] <= 1 / max(.18, 14 * branch["radius"]) + 1e-6
        # Every segment progresses along its branch, rather than coiling back.
        chord = points[-1] - points[0]
        assert np.min(delta @ (chord / np.linalg.norm(chord)) / lengths) > .3
        if branch["parent"] >= 0:
            parent = tree["branches"][branch["parent"]]
            root, _ = sample(parent["points"], branch["at"])
            assert np.array_equal(points[0], root), "Detached branch root"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("/tmp/plant-stems-v4"))
    args = parser.parse_args()
    reports = []
    primary_gaps = []
    winding_angles = []
    for seed in (0, 41, 81, 309):
        for curve in CURVES:
            for branching in BRANCHING:
                original = None
                for flowering in FLOWERING:
                    record = make_recipe(curve, branching, flowering, seed)
                    tree = skeleton(record)
                    check_tree(tree)
                    for branch in tree["branches"]:
                        targets = np.abs(branch["bend_angles"])
                        assert np.all(targets >= record["controls"]["bend_angle_min"] - 1e-12)
                        assert np.all(targets <= record["controls"]["bend_angle_max"] + 1e-12)
                    if curve == "winding" and flowering == "one":
                        winding_angles.extend(np.abs(tree["branches"][0]["bend_angles"]).tolist())
                    primary = [b["at"] for b in tree["branches"] if b["level"] == 1]
                    primary_gaps.extend(np.diff(primary).tolist())
                    assert len(tree["branches"]) - 1 == dict(none=0, few=3, many=15)[branching]
                    if original is not None:
                        assert original == tree["branches"], "Bloom load changed the structural graph"
                    original = tree["branches"]
                    sites = flower_sockets(tree)
                    assert len(sites) == FLOWER_COUNTS[flowering]
                    assert all(site["kind"] == "flower" for site in sites), "Unexpected default buds"
                    for site in sites:
                        root, _ = sample(tree["branches"][site["branch"]]["points"], site["at"])
                        assert np.array_equal(root, site["attachment"])
                    replay = skeleton(json.loads(json.dumps(record)))
                    assert tree == replay, "Saved stem recipe changed geometry"
                    main = tree["branches"][0]
                    assert abs(main["length"] - record["controls"]["length"]) < 1e-12
                    if curve == "straight":
                        assert all(abs(b["length"] - b["chord"]) < 1e-12 for b in tree["branches"])
                    elif curve == "winding":
                        dx = np.diff(np.array(main["points"])[:, 0])
                        signs = np.sign(dx[np.abs(dx) > 1e-6])
                        assert np.count_nonzero(signs[1:] != signs[:-1]) >= 2, "Winding has too few bends"
                    reports.append(dict(seed=seed, curve=curve, branching=branching, flowers=flowering,
                                        structural_branches=len(tree["branches"]) - 1,
                                        flower_count=len(sites), main_chord=main["chord"]))
    record = make_recipe("winding", "many", "many", 81)
    assert len({round(a, 3) for a in winding_angles}) > 10, "Bends reused fixed angles"
    assert min(primary_gaps) < .065 and max(primary_gaps) > .13, "Branch spacing lacks close and open intervals"
    rest = skeleton(record)
    for pose in ("reaching", "nodding"):
        posed = skeleton(record, pose)
        check_tree(posed)
        assert len(rest["branches"]) == len(posed["branches"])
        for a, b in zip(rest["branches"], posed["branches"]):
            assert abs(a["length"] - b["length"]) < 1e-12
        assert rest["branches"][0]["points"] != posed["branches"][0]["points"]
    # Max flower/bud controls work even without structural side branches.
    maximum = skeleton(make_recipe("winding", "none", "many", controls=dict(flower_count=24, bud_count=6)))
    sites = flower_sockets(maximum)
    assert sum(s["kind"] == "flower" for s in sites) == 24
    assert sum(s["kind"] == "bud" for s in sites) == 6
    extreme = skeleton(make_recipe("winding", "many", "many", controls=dict(
        bends=2.8, curve_amount=1., length=1.4, radius=.04, primary_count=7, secondary_count=3)))
    check_tree(extreme)
    for bad in (dict(bends=float("nan")), dict(flower_count=1.5), dict(primary_count=True),
                dict(secondary_count=7), dict(unknown=1), dict(bend_angle_min=45, bend_angle_max=30),
                dict(branch_spacing_min=.12, branch_spacing_max=.08),
                dict(primary_count=7, branch_spacing_min=.12)):
        try:
            make_recipe(controls=bad)
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid growth control accepted")
    # Confirm the existing plant API delegates to this same geometry.
    for branching, flowering in (("none", "one"), ("many", "many")):
        record = make_recipe("gentle", branching, flowering, seed=81)
        mesh, metadata = assemble(record)
        validate(mesh)
        wrapped, _ = plant("single_spire", "serrated", "rose", seed=81, growth=record)
        assert mesh.vertices == wrapped.vertices and mesh.parts == wrapped.parts
        assert sum(s["kind"] == "flower" for s in mesh.attachments) == FLOWER_COUNTS[flowering]
        tree = skeleton(record)
        scales, widths = [], []
        for site in mesh.attachments:
            parent = tree["branches"][site["branch"]]
            root, _ = sample(parent["points"], site["at"])
            assert np.array_equal(root, site["attachment"]), "Detached organ attachment"
            if site["kind"] == "flower":
                alignment = float(np.dot(site["axis"], site["support_axis"]))
                assert alignment >= np.cos(np.deg2rad(record["controls"]["flower_angle_jitter"])) - 1e-12
                assert np.dot(np.asarray(site["frame"])[:, 1], site["support_axis"]) >= np.cos(
                    np.deg2rad(record["controls"]["flower_angle_jitter"])) - 1e-12
                assert site["angle_nudge"] <= record["controls"]["flower_angle_jitter"]
                scales.append(site["scale"])
                widths.append(site["shape_controls"]["width"])
        if flowering == "many":
            assert len({round(v, 6) for v in scales}) == len(scales), "Flower scales repeat"
            assert len({round(v, 6) for v in widths}) == len(widths), "Flower mutations repeat"
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "growth_validation.json").write_text(json.dumps(dict(
        failures=0, recipes=len(reports), cases=reports,
        curvature_bound="radius >= max(0.18, 14 * stem_radius)",
        minimum_branch_interval=min(primary_gaps), maximum_branch_interval=max(primary_gaps),
        distinct_bend_targets=len({round(a, 3) for a in winding_angles})), indent=2))
    print(f"PASSED: {len(reports)} growth recipes; independent bloom counts, loose bends, attachments, poses and replay.")


if __name__ == "__main__":
    main()
