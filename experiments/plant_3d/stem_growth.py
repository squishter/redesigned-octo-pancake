"""Seeded, arc-length sampled stems with independent branching and bloom load.

Curvature is bounded relative to stem thickness. Winding adds broad bends,
not coils. The same branch graph supplies every leaf and flower attachment.
"""

import math

import numpy as np

from mesh_geometry import Mesh, frame, tube, unit
from plant_components import BLOOM_PROFILES, BUDS, FLOWERS, LEAVES, VARIANTS, flower_mesh, leaf_mesh, recipe as component_recipe


VERSION = 4
CURVES = ("straight", "gentle", "winding")
BRANCHING = ("none", "few", "many")
FLOWERING = ("one", "few", "many")
FLOWER_COUNTS = dict(one=1, few=5, many=15)
SINGLE_BLOOM_MIN = .55  # Between the partly-open (.40) and mostly-open (.70) examples.
POSES = {
    "upright": dict(bend_x=0., bend_z=0., spread=1., leaf_pitch=.18, leaf_curl=.10, opening=1.),
    "reaching": dict(bend_x=.18, bend_z=-.10, spread=1.12, leaf_pitch=.3, leaf_curl=.24, opening=.85),
    "nodding": dict(bend_x=-.16, bend_z=.12, spread=.85, leaf_pitch=-.1, leaf_curl=.35, opening=.72),
}
LIMITS = {
    "length": (1.4, 3.2), "radius": (.012, .04), "curve_amount": (0., 1.),
    "bends": (.35, 2.8), "spread": (.55, 1.4), "primary_count": (0, 7),
    "secondary_count": (0, 3), "flower_count": (1, 24), "bud_count": (0, 6),
    "leaf_scale": (.16, .55), "flower_scale": (.32, 1.15), "leaf_density": (0., 1.5),
    "bend_angle_min": (0., 60.), "bend_angle_max": (0., 65.),
    "branch_spacing_min": (.025, .12), "branch_spacing_max": (.08, .3), "cluster_chance": (0., 1.),
    "flower_angle_jitter": (0., 10.), "flower_scale_jitter": (0., .15), "flower_shape_jitter": (0., .10),
    "bloom_min": (0., 1.), "bloom_max": (0., 1.),
}
INTEGERS = {"primary_count", "secondary_count", "flower_count", "bud_count"}
STRIDE = 100000


def make_recipe(curve="gentle", branching="few", flowers="few", seed=81, controls=None):
    if curve not in CURVES or branching not in BRANCHING or flowers not in FLOWERING:
        raise ValueError("Unknown curve, branching or flowering preset")
    if not isinstance(seed, int) or isinstance(seed, bool) or not 0 <= seed < 2 ** 32:
        raise ValueError("Seed must be an integer in [0, 2^32)")
    values = dict(
        length=2.25, radius=.024, curve_amount=0. if curve == "straight" else 1.,
        bends=dict(straight=.5, gentle=.55, winding=1.8)[curve], spread=.95,
        primary_count=dict(none=0, few=3, many=5)[branching],
        secondary_count=2 if branching == "many" else 0,
        flower_count=FLOWER_COUNTS[flowers], bud_count=0,
        leaf_scale=.42 if branching == "none" else .31,
        flower_scale=dict(one=1., few=.73, many=.56)[flowers], leaf_density=1.,
        bend_angle_min=dict(straight=0., gentle=8., winding=20.)[curve],
        bend_angle_max=dict(straight=0., gentle=22., winding=55.)[curve],
        branch_spacing_min=.035, branch_spacing_max=.22, cluster_chance=.55,
        flower_angle_jitter=6., flower_scale_jitter=.10, flower_shape_jitter=.045,
        bloom_min=.35, bloom_max=1.,
    )
    for key, value in (controls or {}).items():
        if key not in LIMITS:
            raise ValueError("Unknown stem control: " + key)
        values[key] = value
    for key, value in values.items():
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValueError("Invalid stem control: " + key)
        if not LIMITS[key][0] <= value <= LIMITS[key][1]:
            raise ValueError("Stem control out of range: " + key)
        if key in INTEGERS:
            if int(value) != value:
                raise ValueError("Stem count must be an integer: " + key)
            values[key] = int(value)
    if values["primary_count"] == 0 and values["secondary_count"]:
        raise ValueError("Secondary branches need primary branches")
    if values["bend_angle_min"] > values["bend_angle_max"]:
        raise ValueError("Minimum bend angle exceeds maximum")
    if values["bloom_min"] > values["bloom_max"]:
        raise ValueError("Minimum bloom stage exceeds maximum")
    if values["flower_count"] == 1:
        values["bloom_min"] = max(SINGLE_BLOOM_MIN, values["bloom_min"])
        values["bloom_max"] = max(values["bloom_min"], values["bloom_max"])
    if values["branch_spacing_min"] > values["branch_spacing_max"]:
        raise ValueError("Minimum branch spacing exceeds maximum")
    if max(0, values["primary_count"] - 1) * values["branch_spacing_min"] > .60:
        raise ValueError("The primary branch count and minimum spacing do not fit")
    return dict(version=VERSION, curve=curve, branching=branching, flowers=flowers,
                seed=seed, controls=values)


def resolve(record):
    if not isinstance(record, dict) or record.get("version") != VERSION:
        raise ValueError("Unsupported stem recipe version")
    if set(record) != {"version", "curve", "branching", "flowers", "seed", "controls"}:
        raise ValueError("Malformed stem recipe")
    controls = dict(record["controls"])
    # Previously saved v4 recipes had fully open heads. Preserve their geometry.
    controls.setdefault("bloom_min", 1.)
    controls.setdefault("bloom_max", 1.)
    return make_recipe(record["curve"], record["branching"], record["flowers"], record["seed"], controls)


def pose_controls(pose="upright", overrides=None):
    if pose not in POSES:
        raise ValueError("Unknown plant pose")
    result = {**POSES[pose], **(overrides or {})}
    bounds = dict(bend_x=(-.35, .35), bend_z=(-.35, .35), spread=(.7, 1.3),
                  leaf_pitch=(-.4, .5), leaf_curl=(0., .5), opening=(.4, 1.))
    if set(result) != set(bounds):
        raise ValueError("Unknown pose control")
    for key, value in result.items():
        if not math.isfinite(value) or not bounds[key][0] <= value <= bounds[key][1]:
            raise ValueError("Invalid pose control: " + key)
    return result


def sample(path, t):
    """Interpolate along equal-length centerline segments and return a tangent."""
    points = np.asarray(path)
    f = min(max(t, 0.), 1.) * (len(points) - 1)
    index = min(int(f), len(points) - 2)
    return points[index] * (1 - (f - index)) + points[index + 1] * (f - index), unit(points[index + 1] - points[index])


def _path(root, axis, length, radius, controls, rng, level):
    segments = max(24, math.ceil(length * 40))
    ds = length / segments
    basis = frame(axis)
    previous = unit(axis)
    points = [np.asarray(root, dtype=float)]
    # The osculating radius is at least 14 stem radii and 0.18 scene units.
    # Clamping direction changes also protects custom high-bend recipes.
    max_turn = ds / max(.18, 14 * radius)
    turns = max(1, round(controls["bends"] * (2. if level == 0 else 1.4)))
    intervals = rng.uniform(.7, 1.3, turns)
    knots = np.concatenate(([0.], np.cumsum(intervals) / intervals.sum()))
    sign = 1 if rng.random() < .5 else -1
    angles = np.array([sign * (-1) ** i * rng.uniform(controls["bend_angle_min"], controls["bend_angle_max"])
                       for i in range(turns)])
    peaks = np.concatenate(([0.], np.deg2rad(angles) * controls["curve_amount"]))
    planes = np.concatenate(([0.], rng.uniform(-.25, .25, turns)))
    for i in range(segments):
        t = (i + .5) / segments
        knot = min(int(np.searchsorted(knots, t, side="right")) - 1, turns - 1)
        blend = (t - knots[knot]) / (knots[knot + 1] - knots[knot])
        blend = blend * blend * (3 - 2 * blend)
        theta = peaks[knot] * (1 - blend) + peaks[knot + 1] * blend
        plane = planes[knot] * (1 - blend) + planes[knot + 1] * blend
        desired = basis @ np.array((math.sin(theta) * math.cos(plane), math.cos(theta), math.sin(theta) * math.sin(plane)))
        angle = math.acos(float(np.clip(np.dot(previous, desired), -1, 1)))
        if angle > max_turn:
            # Exact spherical interpolation, avoiding direction snaps.
            ratio = max_turn / angle
            desired = unit(previous * math.sin((1 - ratio) * angle) + desired * math.sin(ratio * angle))
        points.append(points[-1] + unit(previous + desired) * ds)
        previous = desired
    return np.asarray(points), dict(bend_angles=angles.tolist(), bend_positions=knots[1:].tolist(), axis=np.asarray(axis).tolist())


def _branch_positions(count, low, high, controls, rng):
    if not count:
        return []
    first = low + float(rng.uniform(0., .035))
    if count == 1:
        return [first]
    minimum, maximum = controls["branch_spacing_min"], controls["branch_spacing_max"]
    gaps = rng.uniform(minimum, maximum, count - 1)
    if rng.random() < controls["cluster_chance"]:
        index = int(rng.integers(0, len(gaps)))
        gaps[index] = rng.uniform(minimum, minimum + (maximum - minimum) * .10)
    available = high - first
    if gaps.sum() > available:
        gaps = minimum + (gaps - minimum) * (available - len(gaps) * minimum) / (gaps.sum() - len(gaps) * minimum)
    return [first, *(first + np.cumsum(gaps)).tolist()]


def path_stats(path):
    delta = np.diff(np.asarray(path), axis=0)
    lengths = np.linalg.norm(delta, axis=1)
    directions = delta / lengths[:, None]
    angles = np.arccos(np.clip(np.sum(directions[1:] * directions[:-1], axis=1), -1, 1))
    curvature = angles / ((lengths[1:] + lengths[:-1]) * .5)
    return dict(length=float(lengths.sum()), chord=float(np.linalg.norm(np.asarray(path)[-1] - np.asarray(path)[0])),
                max_curvature=float(curvature.max(initial=0)))


def skeleton(record, pose="upright", overrides=None):
    record = resolve(record)
    c = record["controls"]
    p = pose_controls(pose, overrides)
    rng = np.random.default_rng(record["seed"])
    # A fixed root rotation changes pose without stretching a branch.
    ax, az = p["bend_z"], -p["bend_x"]
    rx = np.array(((1, 0, 0), (0, math.cos(ax), -math.sin(ax)), (0, math.sin(ax), math.cos(ax))))
    rz = np.array(((math.cos(az), -math.sin(az), 0), (math.sin(az), math.cos(az), 0), (0, 0, 1)))
    rotation = rz @ rx
    phase = float(rng.uniform(-.3, .3))
    branches = []

    def add(parent, at, axis, length, radius, level):
        root = np.zeros(3) if parent < 0 else sample(branches[parent]["points"], at)[0]
        branch_rng = np.random.default_rng(np.random.SeedSequence([record["seed"], len(branches), 5317]))
        points, profile = _path(root, rotation @ unit(axis), length, radius, c, branch_rng, level)
        branch = dict(id=len(branches), parent=parent, at=at, level=level, radius=radius,
                      points=points.tolist(), **profile, **path_stats(points))
        branches.append(branch)
        return branch["id"]

    add(-1, 0., np.array((0., 1., 0.)), c["length"], c["radius"], 0)
    count = c["primary_count"]
    for i, t in enumerate(_branch_positions(count, .16, .80, c, rng)):
        azimuth = phase + i * 2.3999632297 + float(rng.uniform(-.18, .18))
        radial = np.array((math.cos(azimuth), 0., math.sin(azimuth)))
        axis = radial * c["spread"] * p["spread"] + np.array((0., .85, 0.))
        length = c["length"] * (.61 - .18 * i / max(1, count - 1))
        parent = add(0, t, axis, length, c["radius"] * .68, 1)
        for j, at in enumerate(_branch_positions(c["secondary_count"], .32, .80, c, rng)):
            angle = azimuth + (-.9 if j % 2 else .9) * (1 + .2 * (j // 2))
            axis = np.array((math.cos(angle) * c["spread"] * p["spread"], .95,
                             math.sin(angle) * c["spread"] * p["spread"]))
            add(parent, at, axis, length * .54, max(.008, c["radius"] * .44), 2)
    return dict(branches=branches, recipe=record, pose=pose, controls=p)


def _socket(branch, t, end, kind):
    root, tangent = sample(branch["points"], t)
    return dict(kind=kind, branch=branch["id"], at=t, root=np.asarray(end).tolist(),
                attachment=root.tolist(), tangent=tangent.tolist())


def flower_sockets(tree):
    """Farthest-site selection spreads blooms; count never changes the branch graph."""
    c = tree["recipe"]["controls"]
    candidates = []
    for branch in tree["branches"]:
        root, tangent = sample(branch["points"], 1.)
        candidates.append(_socket(branch, 1., root + tangent * .12, "flower"))
        # Pedicels are floral stalks, separate from the structural branch count.
        stations = np.linspace(.30, .91, 10 if branch["level"] == 0 else 3)
        for index, t in enumerate(stations):
            root, tangent = sample(branch["points"], float(t))
            for side in range(3 if branch["level"] == 0 else 1):
                angle = branch["id"] * 2.4 + index * 2.4 + side * math.tau / 3
                radial = np.array((math.cos(angle), .32, math.sin(angle)))
                end = root + unit(radial) * (.20 + .035 * (index % 3)) + tangent * .06
                candidates.append(_socket(branch, float(t), end, "flower"))
    selected = [candidates.pop(0)]  # The main stem always keeps its terminal flower.
    wanted = c["flower_count"] + c["bud_count"]
    if len(candidates) + 1 < wanted:
        raise ValueError("Not enough flower attachment sites")
    while len(selected) < wanted:
        centers = np.array([s["root"] for s in selected])
        scores = []
        for site in candidates:
            distance = np.linalg.norm(centers - site["root"], axis=1).min()
            scores.append(distance + .04 * site["at"])
        selected.append(candidates.pop(int(np.argmax(scores))))
    for i, site in enumerate(selected):
        site["kind"] = "flower" if i < c["flower_count"] else "bud"
    return selected


def assemble(record, leaf="serrated", flower="rose", pose="upright", component_variant="reference", overrides=None):
    record = resolve(record)
    if leaf not in LEAVES or flower not in FLOWERS or component_variant not in VARIANTS:
        raise ValueError("Unknown leaf, flower or component variant")
    tree = skeleton(record, pose, overrides)
    c, p = record["controls"], tree["controls"]
    mesh = Mesh()
    for branch in tree["branches"]:
        tube(mesh, branch["points"], branch["radius"], 1, 10 + branch["id"])
    part = STRIDE
    seed = record["seed"]
    for branch in tree["branches"]:
        count = round((4 if branch["level"] == 0 else 2 if branch["level"] == 1 else 1) * c["leaf_density"])
        for i, t in enumerate(np.linspace(.24, .77, count)):
            root, tangent = sample(branch["points"], float(t))
            angle = 2.4 * (i + branch["id"])
            axis = unit(np.array((math.cos(angle), p["leaf_pitch"], math.sin(angle))) + tangent * .15)
            basis = frame(axis, tangent)
            scale = c["leaf_scale"] * (1 - branch["level"] * .16)
            organ = leaf_mesh(leaf, curl=p["leaf_curl"], part=part, seed=(seed + part) % 2 ** 32,
                              variant=component_variant)
            mesh.merge(organ, basis * scale, root)
            site = _socket(branch, float(t), root, "leaf")
            site.update(axis=axis.tolist(), frame=basis.tolist(), scale=scale, part=part)
            mesh.attachments.append(site)
            part += STRIDE
    for i, site in enumerate(flower_sockets(tree)):
        branch = tree["branches"][site["branch"]]
        attachment = np.array(site["attachment"])
        root = np.array(site["root"])
        # A short, softly bowed pedicel joins the exact sampled branch point.
        mid = (attachment + root) * .5 + np.array((0., .025, 0.))
        tube(mesh, [attachment, mid, root], .009, 1, part)
        support_axis = unit(root - mid)
        support_frame = frame(support_axis, frame(np.array(site["tangent"]))[:, 2])
        organ_seed = (seed + part) % 2 ** 32
        rng = np.random.default_rng(np.random.SeedSequence([seed, part, 769]))
        theta = math.radians(float(rng.uniform(0., c["flower_angle_jitter"])))
        azimuth = float(rng.uniform(0., math.tau))
        axis = unit(support_axis * math.cos(theta) + math.sin(theta) *
                    (support_frame[:, 0] * math.cos(azimuth) + support_frame[:, 2] * math.sin(azimuth)))
        if flower in ("bell", "fuchsia", "bleeding_heart"):
            axis = -axis
        basis = frame(axis, support_frame[:, 2])
        roll = math.radians(float(rng.uniform(-1., 1.)) * c["flower_angle_jitter"] * 1.65)
        basis = basis @ np.array(((math.cos(roll), 0, math.sin(roll)), (0, 1, 0), (-math.sin(roll), 0, math.cos(roll))))
        bud = site["kind"] == "bud"
        scale = c["flower_scale"] * (.55 if bud else 1.) * float(rng.uniform(1 - c["flower_scale_jitter"], 1 + c["flower_scale_jitter"]))
        family = BUDS[i % len(BUDS)] if bud else flower
        shape = component_recipe("flowers", family, organ_seed, component_variant)["controls"]
        for key in ("width", "length", "center", "cup"):
            shape[key] *= float(rng.uniform(1 - c["flower_shape_jitter"], 1 + c["flower_shape_jitter"]))
        opening_jitter = c["flower_shape_jitter"] * .4
        shape["opening"] *= (.6 if bud else p["opening"]) * float(rng.uniform(1 - opening_jitter, 1 + opening_jitter))
        shape["opening"] = float(np.clip(shape["opening"], .4, 1.1))
        bloom_rng = np.random.default_rng(np.random.SeedSequence([seed, part, 2759]))
        stage = float(bloom_rng.uniform(c["bloom_min"], c["bloom_max"])) if family in BLOOM_PROFILES else 1.
        shape["bloom"] = stage
        organ = flower_mesh(family, part=part + 1, seed=organ_seed, variant=component_variant, controls=shape)
        mesh.merge(organ, basis * scale, root)
        site.update(axis=axis.tolist(), frame=basis.tolist(), scale=scale, part=part + 1,
                    support_axis=support_axis.tolist(), angle_nudge=math.degrees(theta), roll_nudge=math.degrees(roll),
                    shape_controls=shape, bloom=stage, bloom_profile=BLOOM_PROFILES.get(family, "fixed"))
        mesh.attachments.append(site)
        part += STRIDE
    stats = dict(structural_branches=len(tree["branches"]) - 1, flower_count=c["flower_count"],
                 bud_count=c["bud_count"], leaf_count=sum(s["kind"] == "leaf" for s in mesh.attachments),
                 total_stem_length=sum(b["length"] for b in tree["branches"]),
                 main_length=tree["branches"][0]["length"],
                 max_curvature=max(b["max_curvature"] for b in tree["branches"]))
    stages = [s["bloom"] for s in mesh.attachments if s["kind"] == "flower"]
    stats.update(bloom_min=min(stages), bloom_max=max(stages))
    metadata = dict(version=VERSION, backend="mutable stem graph", seed=seed,
                    stem=record["curve"] + "_" + record["branching"], leaf=leaf, flower=flower,
                    pose=pose, controls=p, component_variant=component_variant, growth=record, stats=stats)
    return mesh, metadata
