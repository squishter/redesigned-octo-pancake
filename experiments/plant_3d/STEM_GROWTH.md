# Stem mutations: a single rose through a flowering bush

[Bloom-stage controls](BLOOM_STAGES.md) now add `bloom_min`/`bloom_max` for
independent closed-to-open variation on eligible flowers. Existing recipes
without those fields preserve their original fully open geometry.

`stem_growth.py` adds three independent controls to the existing leaf/flower
mesh library. The same rose and serrated-leaf families are used throughout
the comparison renders, with small per-organ variations.

| Control | Presets | Result |
| --- | --- | --- |
| Stem shape | `straight`, `gentle`, `winding` | Straight axes, a broad bow, or several alternating broad bends |
| Branching | `none`, `few`, `many` | 0, 3 or 15 structural side branches; the bush has five primary and ten secondary branches |
| Flowering | `one`, `few`, `many` | Exactly 1, 5 or 15 flower heads, regardless of branching |

That gives **27 combinations**, before seed, pose, custom counts or component
variation. Nine bare stem structures show the shape/branching combinations.
Changing flower count leaves the structural branch graph unchanged. A bare
stem can carry many blooms on short flower stalks; a leafy bush can carry only
one flower. Floral stalks are not counted as structural side branches.

No buds are added by default. A single-stem, single-flower rose is exactly
that; `bud_count` adds buds only when requested. Default flower sizes decrease
with the flowering preset to make crowded bushes readable. `flower_scale`
overrides that choice independently.

## Loose curves and attachments

Every bend chooses a target angle from a range: straight 0°, gentle 8–22°,
and winding 20–55°. Signs alternate for winding stems; the target magnitudes,
planes and distances between bend targets vary with the seed. `bend_angle_min`
and `bend_angle_max` set custom ranges in degrees. Smooth interpolation and
the curvature cap connect these targets without sharp corners.

Branch positions use irregular intervals rather than a fixed spacing. The
`branch_spacing_min`/`branch_spacing_max` controls bound intervals along a parent;
`cluster_chance` introduces occasional close pairs. Defaults include both close
intervals of roughly 0.04 parent lengths and open intervals above 0.13.

Centerlines are integrated using equal-length segments. Direction changes are
bounded so the local bend radius is at least `max(0.18, 14 * stem_radius)`.
Winding changes the number of alternating bends without forming coils or
hairpins. Tests also check forward progress along every branch. Straight
structural branches have identical arc and chord lengths.

Each child branch starts at an interpolated point on its parent. Leaves and
flower stalks use attachment points sampled from the same evaluated curves.
Reaching and nodding poses rebuild parents first, then children and organ
frames; branch lengths remain fixed. This avoids detached leaves/blooms and
does not accumulate deformation when a pose is applied again.

Flower positions are chosen from terminal and nodal sites using their spatial
separation. Each flower's +Y axis follows the last tangent of its supporting
flower stalk. Hanging flower families reverse that axis. Nothing rotates a
flower toward the camera. Each attachment records its support axis and the
resulting flower frame.

Per-flower seed streams add at most 6° of axial tilt, a small roll, ±10% scale,
and ±4.5% nudges to petal length/width, cup depth and center size. These changes
build on the existing seeded component variation. `flower_angle_jitter`,
`flower_scale_jitter` and `flower_shape_jitter` control these extra nudges.
Frames, tiny mutations and actual scale are retained on attachment records;
source recipes reproduce them exactly. Existing leaf deformation remains
independent.
Normal 3D occlusion can hide blooms in a particular camera view; recorded
flower counts refer to actual assembled heads. This is a deterministic
authoring system, not a collision solver or a new production game picture type.

## Use

The original component library remains reproducible with `build_plants.py`.
The separate growth study uses recipe format **4** and writes a new output
directory, preserving the version-2 artifacts.

```sh
# All nine stem structures, all 27 rose combinations, two alternate poses,
# and daisy/hibiscus/lily bushes.
python experiments/plant_3d/build_stems.py --out=/tmp/plant-stems-v4

# An individual straight, unbranched rose with one bloom.
python experiments/plant_3d/build_stems.py --single --out=/tmp/custom-rose \
  --curve=straight --branching=none --flowers=one --flower=rose --leaf=serrated

# A winding flowering bush; counts and sizes can be set explicitly.
python experiments/plant_3d/build_stems.py --single --out=/tmp/custom-bush \
  --curve=winding --branching=many --flowers=many --flower=rose \
  --control=flower_count=18 --control=bud_count=3 --control=spread=1.1
```

From Python with `experiments/plant_3d` on the import path:

```python
from stem_growth import make_recipe, assemble

growth = make_recipe(curve="winding", branching="many", flowers="many", seed=81)
mesh, metadata = assemble(growth, leaf="serrated", flower="rose")

# Saved numeric controls reproduce the exact same geometry.
replayed, _ = assemble(metadata["growth"], metadata["leaf"], metadata["flower"],
                       metadata["pose"], metadata["component_variant"], metadata["controls"])
```

The existing `build_plants.plant()` API also accepts `growth=make_recipe(...)`;
its `seed` must match the growth recipe's seed. Without `growth`, the original
version-2 behavior remains in place. The legacy stem name is superseded by
the explicit growth recipe when one is supplied.

`LIMITS` in `stem_growth.py` documents bounded custom controls: length, radius,
curve amount, bend frequency, spread, primary/secondary branch counts, bloom
count (1–24), bud count (0–6), leaf density and leaf/flower sizes. Counts must
be integers; invalid/nonfinite requests fail before geometry is generated.

Exported GLBs retain the **Stems**, **Leaves** and **Flowers** groups. They are
snapshots; the source and saved recipes generate mutations and poses.

## Render and verify

Use the repository's Godot 4.7.2 executable. In this workspace it is
`/workspace/.environment/bin/godot`. See the main README for writable XDG
directory settings in a sandbox.

```sh
python experiments/plant_3d/check_stems.py --out=/tmp/plant-stems-v4
godot --headless -s res://experiments/plant_3d/check_growth.gd -- --input=/tmp/plant-stems-v4
python experiments/plant_3d/build_stems.py --out=/tmp/plant-stems-v4 --verify-puzzles
python experiments/plant_3d/make_stem_sheets.py --input=/tmp/plant-stems-v4
```

The geometry checks exercise 108 recipes (all 27 combinations across four
seeds), independent branch/bloom choices, exact head counts, optional buds,
curvature bounds and no hairpins, unchanged lengths under poses, parent/organ
attachments, varied bend targets inside their ranges, close/open branch spacing,
flower alignment within the tilt bound, distinct flower scales and shapes,
maximum counts, invalid controls, saved-recipe replay and the
existing plant API. Every exported assembly also receives finite/triangle
validation.

The Godot checks cover all nine stems and all 27 rose combinations, five
cameras for three representative plants, two poses and three other flower
bushes. They check closed paint regions, background leaks, semantic separation,
worker projection, GLB import and five collage/diamond-kit pairs. Saved puzzle
recipes are then rebuilt in Python and compared with the exact source vertices.

`PatternIO` now retains full precision for source recipes while keeping puzzle
pixel coordinates rounded as before. This prevents values such as a 0.024 stem
radius from becoming 0.02 on save. `tests/run_source_recipe_io.gd` checks exact
nested parameters alongside compact coordinates, colors, byte grids and strings.

Review renders under `previews/`:

- `stem_structures.png`: bare stems, three shape rows × three branching columns.
- `rose_bloom_matrix_straight.png`, `rose_bloom_matrix_gentle.png`,
  `rose_bloom_matrix_winding.png`: branching rows × 1/5/15 bloom columns.
- `single_rose_to_bush.png`: three representative plants side by side.
- `rose_growth_views.png`: the same three plants from five cameras.
- `other_flowering_bushes.png`: interchangeable daisy, hibiscus and lily bushes.

These are real mesh projections from Godot, using the same unlit visibility
and contour route as posed animals. The colored review sheets combine that
flat color render with its extracted visible contours.

The original version-3 render and mesh archives remain available separately;
version-3 recipes are not silently reinterpreted as the ranged-bend version 4.
