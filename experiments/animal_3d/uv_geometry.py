"""Small, dependency-free UV intersection checks (shared edges are allowed)."""

from collections import defaultdict
import math


def cross(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def area(polygon):
    return abs(sum(a[0] * b[1] - b[0] * a[1]
                   for a, b in zip(polygon, polygon[1:] + polygon[:1]))) * 0.5


def intersection_area(first, second):
    polygon = list(first)
    sign = 1 if cross(*second) > 0 else -1
    for a, b in zip(second, second[1:] + second[:1]):
        result = []
        for p, q in zip(polygon, polygon[1:] + polygon[:1]):
            dp, dq = sign * cross(a, b, p), sign * cross(a, b, q)
            if dp >= 0:
                result.append(p)
            if (dp >= 0) != (dq >= 0):
                t = dp / (dp - dq)
                result.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
        polygon = result
        if len(polygon) < 3:
            return 0.0
    return area(polygon)


def overlaps(triangles):
    """Return triangle pairs with meaningful positive-area UV intersections."""
    boxes = [(min(p[0] for p in t), min(p[1] for p in t),
              max(p[0] for p in t), max(p[1] for p in t)) for t in triangles]
    bins, tested, result = defaultdict(list), set(), []
    areas = [area(t) for t in triangles]
    for i, (x0, y0, x1, y1) in enumerate(boxes):
        if areas[i] < 1e-13:
            continue
        cells = [(x, y) for x in range(math.floor(x0 * 32), math.floor(x1 * 32) + 1)
                 for y in range(math.floor(y0 * 32), math.floor(y1 * 32) + 1)]
        for cell in cells:
            for j in bins[cell]:
                pair = (j, i)
                if pair in tested:
                    continue
                tested.add(pair)
                a, b, c, d = boxes[j]
                if min(c, x1) - max(a, x0) <= 1e-10 or min(d, y1) - max(b, y0) <= 1e-10:
                    continue
                intersection = intersection_area(triangles[i], triangles[j])
                if intersection > max(1e-11, min(areas[i], areas[j]) * 1e-5):
                    result.append((j, i))
            bins[cell].append(i)
    return result
