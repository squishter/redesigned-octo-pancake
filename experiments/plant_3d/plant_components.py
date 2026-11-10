"""Original botanical component families and bounded, replayable mutations.

Local +Y is the attachment axis; leaf faces point +Z. Flowers open along +Y.
Recipes contain resolved numeric controls so variants can be rebuilt exactly.
"""

import hashlib
import math

import numpy as np

from mesh_geometry import Mesh, ellipsoid, frame, tube


LEAVES = (
    "oval", "lance", "heart", "arrow", "round", "oak_lobed", "serrated", "ribbon",
    "fan", "trifoliate", "pinnate", "needle_cluster", "maple", "ivy", "ginkgo",
    "monstera", "split_philodendron", "willow", "eucalyptus", "holly", "birch",
    "fern", "palm", "succulent",
)
# Count, layers, petal length/width, cup, construction. Names describe stylized families.
FLOWERS = {
    "daisy": (12, 1, .26, .065, .015, "round"),
    "cosmos": (8, 1, .27, .115, .025, "notched"),
    "sunflower": (18, 2, .25, .055, .025, "point"),
    "poppy": (4, 1, .28, .235, .12, "ruffled"),
    "buttercup": (5, 1, .22, .14, .10, "round"),
    "lily": (6, 1, .32, .11, .15, "point"),
    "tulip": (6, 1, .18, .15, .33, "round"),
    "rose": (7, 4, .24, .145, .16, "round"),
    "camellia": (8, 3, .25, .135, .055, "round"),
    "dahlia": (12, 4, .27, .07, .12, "point"),
    "aster": (22, 1, .27, .035, .025, "point"),
    "gerbera": (16, 2, .28, .055, .035, "spoon"),
    "bell": (5, 1, .15, .08, .30, "bell"),
    "trumpet": (5, 1, .26, .14, .30, "trumpet"),
    "orchid": (5, 1, .25, .13, .04, "orchid"),
    "star": (5, 1, .28, .13, .025, "point"),
    "magnolia": (9, 2, .27, .15, .16, "round"),
    "lotus": (10, 3, .28, .10, .14, "point"),
    "zinnia": (14, 3, .24, .08, .025, "notched"),
    "chrysanthemum": (22, 4, .28, .035, .17, "spoon"),
    "anemone": (8, 1, .25, .15, .04, "round"),
    "hibiscus": (5, 1, .30, .19, .045, "hibiscus"),
    "daffodil": (6, 1, .27, .10, .01, "daffodil"),
    "iris": (6, 1, .31, .12, .12, "iris"),
    "pansy": (5, 1, .23, .17, .02, "pansy"),
    "anthurium": (1, 1, .30, .20, .06, "anthurium"),
    "calla": (1, 1, .28, .20, .33, "calla"),
    "fuchsia": (4, 1, .26, .07, .16, "fuchsia"),
    "hydrangea": (4, 1, .10, .075, .01, "hydrangea"),
    "allium": (5, 1, .055, .02, .01, "allium"),
    "lavender": (5, 1, .06, .03, .08, "lavender"),
    "bleeding_heart": (1, 1, .20, .18, .05, "bleeding_heart"),
}
BUDS = ("round_bud", "pointed_bud", "opening_bud", "ribbed_bud", "sepal_bud")
# Closed width, height, hub and bulge distinguish layered, cup and ray flowers.
BLOOM_SHAPES = {
    "layered": dict(width=.30, height=1.18, hub=.55, bulge=.16, tip=.035),
    "cup": dict(width=.48, height=1.22, hub=.62, bulge=.22, tip=.025),
    "ray": dict(width=.32, height=1.05, hub=.62, bulge=.18, tip=.04),
}
BLOOM_PROFILES = {
    **dict.fromkeys(("rose", "camellia", "dahlia", "zinnia", "chrysanthemum", "lotus"), "layered"),
    **dict.fromkeys(("tulip", "magnolia", "buttercup", "poppy", "anemone"), "cup"),
    **dict.fromkeys(("lily", "cosmos", "daisy", "gerbera", "aster", "sunflower", "star", "hibiscus"), "ray"),
}
VARIANTS = ("reference", "slender", "ruffled", "cupped")
LEAF_LIMITS = {
    "length": (.65, 1.4), "width": (.5, 1.5), "tip": (.55, 1.5),
    "lobe_depth": (.5, 1.5), "curl": (-.1, .55), "twist": (-.7, .7),
    "cupping": (.4, 1.8), "margin": (0., .08), "spread": (.65, 1.35),
    "asymmetry": (-.12, .12),
}
FLOWER_LIMITS = {
    "length": (.7, 1.3), "width": (.6, 1.4), "opening": (.4, 1.1),
    "cup": (.6, 1.7), "curl": (-.12, .25), "ruffle": (0., .05),
    "tip": (.55, 1.5), "ring_twist": (-.25, .25), "center": (.7, 1.3),
    "asymmetry": (0., .1), "spread": (.75, 1.25), "bloom": (0., 1.),
}


def _rng(kind, seed):
    if not isinstance(seed, int) or isinstance(seed, bool) or not 0 <= seed < 2 ** 32:
        raise ValueError("Seed must be an integer in [0, 2^32)")
    digest = hashlib.sha256(kind.encode()).digest()
    return np.random.default_rng(np.random.SeedSequence([seed, int.from_bytes(digest[:4], "little")]))


def recipe(group, kind, seed=0, variant="reference", controls=None):
    if variant not in VARIANTS:
        raise ValueError("Unknown mutation variant")
    choices = LEAVES if group == "leaves" else (*FLOWERS, *BUDS) if group == "flowers" else ()
    if kind not in choices:
        raise ValueError("Unknown component family")
    rng = _rng(kind, seed)
    if group == "leaves":
        values = dict(length=1., width=1., tip=1., lobe_depth=1., curl=.10,
                      twist=0., cupping=1., margin=0., spread=1., asymmetry=0.)
        presets = {
            "slender": dict(length=1.18, width=.68, tip=1.25, spread=.82, twist=.12),
            "ruffled": dict(width=1.14, lobe_depth=1.35, margin=.045, twist=-.15, asymmetry=.06),
            "cupped": dict(length=.94, width=1.05, curl=.42, twist=.52, cupping=1.5, spread=.9),
        }
        limits = LEAF_LIMITS
    else:
        values = dict(length=1., width=1., opening=1., cup=1., curl=0., ruffle=0.,
                      tip=1., ring_twist=0., center=1., asymmetry=0., spread=1., bloom=1.)
        presets = {
            "slender": dict(length=1.13, width=.7, tip=1.25, curl=-.06, spread=.85),
            "ruffled": dict(width=1.13, opening=.93, ruffle=.033, ring_twist=.14, asymmetry=.06),
            "cupped": dict(width=1.04, opening=.62, cup=1.48, curl=.16, spread=.88),
        }
        limits = FLOWER_LIMITS
    values.update(presets.get(variant, {}))
    # Seeded shape variation is small enough to preserve each family's construction.
    for key in ("length", "width", "tip", "spread"):
        values[key] *= float(rng.uniform(.96, 1.04))
    for key, value in (controls or {}).items():
        if key not in limits:
            raise ValueError(f"Unknown {group} control: {key}")
        values[key] = value
    for key, value in values.items():
        if not isinstance(value, (int, float)) or not math.isfinite(value) or not limits[key][0] <= value <= limits[key][1]:
            raise ValueError(f"Invalid {group} control: {key}")
    if group == "flowers" and values["bloom"] < 1. and kind not in BLOOM_PROFILES:
        raise ValueError("Bloom-stage deformation is not supported for " + kind)
    return dict(group=group, family=kind, seed=seed, variant=variant, controls=values)


def _surface(mesh, points, along, across, label, part, skip=None):
    faces = []
    for i in range(along):
        for j in range(across):
            if skip and skip(i, j):
                continue
            a = i * (across + 1) + j
            b = a + across + 1
            faces.extend(((a, b, b + 1), (a, b + 1, a + 1)))
    mesh.add(points, faces, label, part)


def _leaf_point(x, y, p, s=0.):
    angle = p["twist"] * y
    z = .055 * p["cupping"] * (1 - s * s) * math.sin(math.pi * y)
    z += p["curl"] * y * y + .02 * math.sin(2 * math.pi * y) * s
    return (x * math.cos(angle), y * p["length"], z + x * math.sin(angle))


def _blade(kind, p, part):
    mesh = Mesh()
    if kind == "maple":
        center = _leaf_point(0, .50, p)
        points = [center]
        for i in range(100):
            a = math.tau * i / 100
            radius = .38 * (1 - .28 * p["lobe_depth"] + .28 * p["lobe_depth"] * math.cos(5 * (a - math.pi / 2)))
            x, y = radius * math.cos(a) * p["width"], .50 + radius * math.sin(a)
            points.append(_leaf_point(x, y, p, x / .4))
        mesh.add(points, [(0, i + 1, (i + 1) % 100 + 1) for i in range(100)], 2, part)
        tube(mesh, [_leaf_point(0, t, p) for t in np.linspace(0, .82, 18)], .009, 6, part + 1)
        for i in range(5):
            a = math.pi / 2 + math.tau * i / 5
            path = [_leaf_point(.34 * u * math.cos(a) * p["width"], .50 + .34 * u * math.sin(a), p)
                    for u in np.linspace(0, 1, 10)]
            tube(mesh, path, .006, 6, part + 1)
        return mesh
    widths = dict(oval=.28, lance=.14, heart=.37, arrow=.30, round=.39, oak_lobed=.32,
                  serrated=.27, ribbon=.065, fan=.43, ivy=.39, ginkgo=.46, monstera=.38,
                  split_philodendron=.34, willow=.075, eucalyptus=.34, holly=.26,
                  birch=.29, succulent=.20, maple=.43)
    along, across = (60, 24) if kind == "monstera" else (36, 10)
    points = []
    for i in range(along + 1):
        t = i / along
        profile = math.sin(math.pi * t) ** (.55 * p["tip"] if kind in ("round", "eucalyptus") else .85 * p["tip"])
        if kind in ("heart", "ivy", "monstera"):
            profile = math.sin(math.pi * t) ** (.5 * p["tip"]) * (1.25 - .8 * t)
        if kind == "arrow":
            profile *= .35 + 1.4 * abs(t - .68)
        elif kind in ("oak_lobed", "maple", "ivy"):
            lobes = 7 if kind == "oak_lobed" else 5 if kind == "maple" else 3
            depth = .25 * p["lobe_depth"]
            profile *= 1 - depth + depth * math.cos(lobes * math.pi * t)
        elif kind in ("serrated", "birch", "holly"):
            count = 20 if kind == "serrated" else 16 if kind == "birch" else 8
            depth = (.2 if kind == "holly" else .10) * p["lobe_depth"]
            profile *= 1 - depth + depth * math.cos(count * math.pi * t)
        elif kind == "split_philodendron":
            profile *= .62 + .38 * math.cos(10 * math.pi * t)
        elif kind in ("fan", "ginkgo"):
            profile = t ** .8
        width = max(.0015, widths[kind] * p["width"] * profile)
        for j in range(across + 1):
            s = 2 * j / across - 1
            x = s * width * (1 + p["asymmetry"] * s)
            x += s * p["margin"] * math.sin(math.pi * t) * math.sin(20 * math.pi * t)
            y = t
            if kind in ("heart", "ivy", "monstera"):
                y += .16 * (1 - s * s) * (1 - t) ** 3
            if kind in ("fan", "ginkgo"):
                y -= .20 * s * s * t ** 5
                if kind == "ginkgo":
                    y -= .12 * math.exp(-s * s * 18) * t ** 8
            points.append(_leaf_point(x, y, p, s))

    def holes(i, j):
        # Three pairs of true geometric fenestrations, never texture alpha.
        return any(((i - row) / 3.5) ** 2 + ((j - col) / 2.) ** 2 < 1
                   for row in (18, 30, 42) for col in (6, 17))

    _surface(mesh, points, along, across, 2, part, holes if kind == "monstera" else None)
    midrib = []
    for t in np.linspace(0., .95, 18):
        y = t + (.16 * (1 - t) ** 3 if kind in ("heart", "ivy", "monstera") else 0.)
        if kind == "ginkgo":
            y -= .12 * t ** 8
        midrib.append(np.array(_leaf_point(0., y, p)) + (0., 0., .006))
    tube(mesh, midrib, .008, 6, part + 1)
    if kind == "succulent":
        # A second curved surface and perimeter wall give the fleshy leaf thickness.
        bottom = [(x, y, z - .008 - .045 * math.sin(math.pi * (i // (across + 1)) / along))
                  for i, (x, y, z) in enumerate(points)]
        _surface(mesh, bottom, along, across, 2, part)
        for side in (0, across):
            wall = [points[i * (across + 1) + side] for i in range(along + 1)]
            wall += [bottom[i * (across + 1) + side] for i in range(along, -1, -1)]
            # Thin side walls use the grid helper to avoid an open billboard.
            pairs = []
            for i in range(along + 1):
                pairs.extend((wall[i], wall[-i - 1]))
            _surface(mesh, pairs, along, 1, 2, part)
        for row in (0, along):
            pairs = []
            for j in range(across + 1):
                at = row * (across + 1) + j
                pairs.extend((points[at], bottom[at]))
            _surface(mesh, pairs, across, 1, 2, part)
    return mesh


def leaf_mesh(kind, curl=None, part=1, seed=0, variant="reference", controls=None):
    controls = dict(controls or {})
    if curl is not None:
        controls["curl"] = curl
    record = recipe("leaves", kind, seed, variant, controls)
    p = record["controls"]
    if kind not in ("trifoliate", "pinnate", "needle_cluster", "fern", "palm"):
        return _blade(kind, p, part)
    mesh = Mesh()
    count = dict(trifoliate=3, pinnate=9, needle_cluster=9, fern=17, palm=11)[kind]
    for i in range(count):
        if kind == "trifoliate":
            axis, root, length = ((i - 1) * .72 * p["spread"], 1., 0.), (0., .12, 0.), .74
        elif kind in ("pinnate", "fern"):
            row = i // 2
            t = .10 + row * (.095 if kind == "fern" else .17)
            sign = -1 if i % 2 else 1
            axis, root = (sign * p["spread"], .45, 0.), (0., t, .05 * t * t)
            length = (.46 if kind == "fern" else .50) * (1 - .55 * row / (count // 2))
        else:
            angle = math.tau * i / count if kind == "needle_cluster" else (i / (count - 1) - .5) * 2.6
            axis = ((.55 * math.cos(angle), 1., .55 * math.sin(angle)) if kind == "needle_cluster"
                    else (math.sin(angle) * p["spread"], math.cos(angle), 0.))
            root, length = (0., .05, 0.), .93
        child_p = {**p, "length": p["length"], "width": p["width"] * (.65 if kind == "fern" else 1.)}
        child = _blade("ribbon" if kind in ("needle_cluster", "palm") else "lance" if kind == "fern" else "oval",
                       child_p, part + i * 2)
        if kind in ("fern", "palm", "needle_cluster"):
            # Fine leaflet veins alias into dots at puzzle resolution. The
            # main rachis remains explicit; each narrow leaflet is one area.
            child.labels = [2] * len(child.labels)
            child.parts = [part + i * 2] * len(child.parts)
        mesh.merge(child, frame(axis) * length, np.array(root))
    tube(mesh, [(0, 0, 0), (0, .9 * p["length"], p["curl"] * .3)], .012, 6, part + 100)
    return mesh


def _petals(mesh, count, layers, length, width, cup, shape, p, part, phase=0., center=True,
            hub=.055, center_radius=None, bloom_profile=None):
    bloom = p.get("bloom", 1.)
    maturity = bloom * bloom * (3 - 2 * bloom)
    closed = BLOOM_SHAPES[bloom_profile] if bloom_profile else None
    for ring in range(layers):
        scale = .73 ** ring
        for petal in range(count):
            a = math.tau * (petal + .5 * ring) / count + ring * (.16 + p["ring_twist"]) + phase
            if shape in ("pansy", "orchid"):
                a = [-math.pi / 2, -.15, math.pi * .34, math.pi * .66, math.pi + .15][petal]
            points = []
            along, across = 14, 8
            for i in range(along + 1):
                t = i / along
                power = .50 if shape in ("round", "ruffled", "notched", "pansy", "hibiscus") else .95
                tip = math.sin(math.pi * t) ** (power * p["tip"])
                if shape == "spoon":
                    tip *= .35 + t
                w = max(.001, width * tip * scale * p["width"])
                if shape in ("orchid", "pansy"):
                    w *= 1.55 if petal == 0 else .8 if shape == "orchid" and petal in (2, 3) else 1.
                for j in range(across + 1):
                    s = 2 * j / across - 1
                    r = (hub + length * p["length"] * t * p["opening"]) * scale
                    y = cup * p["cup"] * t * t + (1 - p["opening"]) * length * t + ring * .035
                    y += p["curl"] * t ** 3 + .022 * s * s * math.sin(math.pi * t) + petal * .0015
                    y += p["asymmetry"] * .3 * math.sin(petal * 2.4) * t * t
                    y += (p["ruffle"] + (.024 if shape in ("ruffled", "hibiscus") else 0.)) * math.cos(9 * s + 5 * t) * t
                    if shape == "notched":
                        r -= .025 * math.exp(-s * s * 16) * t ** 6
                    if shape in ("orchid", "pansy") and petal == 0:
                        y -= .10 * t
                    if shape == "iris":
                        y += (.22 if petal % 2 else -.23) * t * t
                        r *= .75 if petal % 2 else 1.1
                    petal_width = w
                    if closed and bloom < 1.:
                        closed_r = (hub * closed["hub"] * (1 - t) + length * p["length"] *
                                    (closed["bulge"] * math.sin(math.pi * t) + closed["tip"] * t)) * scale
                        closed_y = ring * .035 + length * p["length"] * scale * closed["height"] * t
                        closed_y += .02 * s * s * math.sin(math.pi * t) + petal * .0008
                        r = closed_r * (1 - maturity) + r * maturity
                        y = closed_y * (1 - maturity) + y * maturity
                        petal_width *= closed["width"] + (1 - closed["width"]) * maturity
                    x = r * math.cos(a) - s * petal_width * math.sin(a)
                    z = r * math.sin(a) + s * petal_width * math.cos(a)
                    points.append((x, y, z))
            _surface(mesh, points, along, across, 3, part + ring * count + petal)
    if center:
        radius = (center_radius if center_radius is not None else .09 if shape == "anemone" else .065) * p["center"]
        height = min(.045, radius * .7)
        center_y = height + (layers - 1) * .035
        if closed and bloom < 1.:
            factor = .25 + .75 * maturity
            radius *= factor
            height *= factor
            center_y *= .65 + .35 * maturity
        ellipsoid(mesh, (0, center_y, 0), (radius, height, radius), 4, part + 9000)


def _corolla(mesh, length, cup, p, part, lobes=5, bell=False):
    points = []
    along, across = 18, 60
    for i in range(along + 1):
        t = i / along
        for j in range(across + 1):
            a = math.tau * j / across
            radius = (.035 + length * p["length"] * p["opening"] * t ** (.6 if bell else 1.5))
            radius *= 1 + (.12 * p["tip"] + p["ruffle"]) * math.cos(lobes * a) * t ** 5
            y = cup * p["cup"] * t - .035 * math.cos(lobes * a) * t ** 5 + p["curl"] * t ** 3
            points.append((radius * math.cos(a), y, radius * math.sin(a)))
    _surface(mesh, points, along, across, 3, part)


def _spathe(mesh, kind, p, part):
    if kind == "anthurium":
        leaf = _blade("heart", {**recipe("leaves", "heart")["controls"], "curl": .22,
                                "width": p["width"], "length": p["length"]}, part)
        leaf.labels = [3] * len(leaf.labels)
        leaf.parts = [part] * len(leaf.parts)
        # A leaf-like colored spathe stands behind a protruding spadix.
        mesh.merge(leaf, np.diag((.7, .65, .7)), np.array((0., -.10, -.03)))
        axis = np.array((0., .29, .12))
        tube(mesh, [(0, .10, .01), axis], .027 * p["center"], 4, part + 9000)
    else:
        points = []
        along, across = 22, 22
        for i in range(along + 1):
            t = i / along
            for j in range(across + 1):
                s = j / across
                a = -.3 + s * 5.6
                radius = (.028 + .22 * t ** 1.4) * p["width"] * p["opening"]
                y = .46 * t * p["length"] + .08 * math.cos(a) * t ** 3
                points.append((radius * math.sin(a), y, radius * math.cos(a)))
        _surface(mesh, points, along, across, 3, part)
        tube(mesh, [(0, 0, 0), (0, .35 * p["cup"], 0)], .022 * p["center"], 4, part + 9000)


def flower_mesh(kind, opening=None, part=1, seed=0, variant="reference", controls=None):
    controls = dict(controls or {})
    if opening is not None:
        controls["opening"] = opening
    p = recipe("flowers", kind, seed, variant, controls)["controls"]
    mesh = Mesh()
    if kind in BUDS:
        height = .14 if kind == "round_bud" else .22
        ellipsoid(mesh, (0, height * .7, 0), (.10 * p["width"], height * p["length"], .10), 5, part)
        if kind in ("opening_bud", "sepal_bud"):
            for i in range(5):
                child = leaf_mesh("lance", curl=.18, part=part + i * 10 + 10)
                child.labels = [3 if kind == "opening_bud" else 5] * len(child.labels)
                angle = math.tau * i / 5
                mesh.merge(child, frame((math.cos(angle) * p["opening"], 1., math.sin(angle) * p["opening"])) * .20,
                           np.array((0., .12, 0.)))
        if kind == "ribbed_bud":
            for i in range(7):
                a = math.tau * i / 7
                path = [(math.sin(t) * .102 * math.cos(a), height * (.7 + math.cos(t)),
                         math.sin(t) * .102 * math.sin(a)) for t in np.linspace(.15, math.pi - .15, 15)]
                tube(mesh, path, .005, 6, part + i + 1)
        return mesh
    count, layers, length, width, cup, shape = FLOWERS[kind]
    if shape in ("bell", "trumpet"):
        _corolla(mesh, length, cup, p, part, bell=shape == "bell")
        ellipsoid(mesh, (0, .08, 0), (.04, .04, .04), 4, part + 9000)
    elif shape in ("anthurium", "calla"):
        _spathe(mesh, shape, p, part)
    elif shape in ("hydrangea", "allium", "lavender"):
        florets = 9 if shape == "hydrangea" else 18 if shape == "allium" else 10
        for i in range(florets):
            a = i * 2.3999632297
            if shape == "hydrangea":
                r = .24 * math.sqrt(i / max(1, florets - 1)) * p["spread"]
                root, axis = np.array((r * math.cos(a), .10 - .18 * r, r * math.sin(a))), (0, 1, 0)
            elif shape == "allium":
                y = 1 - 2 * (i + .5) / florets
                direction = np.array((math.sqrt(1 - y * y) * math.cos(a), y, math.sqrt(1 - y * y) * math.sin(a)))
                root, axis = direction * .18 * p["spread"] + (0, .18, 0), direction
                tube(mesh, [(0, 0, 0), root], .004, 1, part + 8000 + i)
            else:
                root = np.array((.06 * math.cos(a), .04 + i * .037 * p["length"], .06 * math.sin(a)))
                axis = (math.cos(a), .6, math.sin(a))
                tube(mesh, [(0, 0, 0), (0, .4, 0)], .012, 1, part + 8000)
            child = Mesh()
            _petals(child, count, 1, length, width, cup, "round" if shape == "hydrangea" else "point",
                    p, part + i * 100, center=True, hub=.018 if shape == "hydrangea" else .01,
                    center_radius=.018 if shape == "hydrangea" else .012)
            mesh.merge(child, frame(axis), root)
    elif shape == "bleeding_heart":
        for sign in (-1, 1):
            ellipsoid(mesh, (sign * .09 * p["width"], .11, 0),
                      (.13 * p["width"], .17 * p["length"], .09 * p["opening"]), 3, part + (sign + 1))
        # Pendant inner teardrop is a distinct organ at the heart's lower cleft.
        ellipsoid(mesh, (0, -.055, .02), (.045, .11 * p["cup"], .045), 4, part + 9000)
    else:
        _petals(mesh, count, layers, length, width, cup, shape, p, part,
                bloom_profile=BLOOM_PROFILES.get(kind))
        if kind == "sunflower":
            maturity = p["bloom"] ** 2 * (3 - 2 * p["bloom"])
            factor = .25 + .75 * maturity
            ellipsoid(mesh, (0, .09 * (.65 + .35 * maturity), 0),
                      (.105 * p["center"] * factor, .04 * factor, .105 * p["center"] * factor), 4, part + 9000)
        if shape in ("hibiscus", "daffodil", "fuchsia"):
            if shape == "daffodil":
                _corolla(mesh, .075, .17, p, part + 500, lobes=6)
            elif shape == "fuchsia":
                _corolla(mesh, .10, .22, p, part + 500, lobes=4, bell=True)
            else:
                maturity = p["bloom"] ** 2 * (3 - 2 * p["bloom"])
                center_height = .29 * p["cup"] * (.35 + .65 * maturity)
                tube(mesh, [(0, .04, 0), (0, center_height, .025)], .014, 4, part + 9001)
                for i in range(5):
                    a = math.tau * i / 5
                    ellipsoid(mesh, (.035 * math.cos(a), center_height, .025 + .035 * math.sin(a)),
                              (.016, .018, .016), 4, part + 9010 + i)
    return mesh
