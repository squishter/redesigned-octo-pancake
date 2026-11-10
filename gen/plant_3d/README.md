# Godot plant generator entry point

`PlantMeshGenerator.generate(seed_value: int, options: Dictionary = {}) -> Dictionary`
has the same entry/return shape as `AnimalMeshGenerator.generate`. It builds a
mutable plant in native GDScript, projects its visible surfaces, and returns
ordinary normalized contours and paint-family marks. It needs no scene nodes,
GPU, Python, Blender, or external downloads at runtime. It can run inside a
`WorkerThreadPool` job, as the animal source does.

```gdscript
var design := PlantMeshGenerator.generate(81, {
    "flower": "rose",
    "leaf": "serrated",
    "component_variant": "ruffled",
    "curve": "winding",
    "branching": "many",
    "flowers": "many",
    "pose": "upright",
    "camera": "three_quarter",
    "controls": {"bloom_min": .4, "bloom_max": 1.},
})
if design.is_empty():
    return # Invalid request or unavailable component data.

# JSON-safe replay token; save this inside the puzzle's source metadata.
var recipe: Dictionary = design.recipe
var replay := PlantMeshGenerator.generate(int(recipe.seed), {"recipe": recipe})
```

The optional `surface(seed, options)` method skips projection and returns
`{data, branches, stats, recipe}`. `data` contains `PackedVector3Array` vertices,
flat triangle indices, semantic labels, organ IDs, colors, and attachment
records. These are plain arrays, not a Godot `Mesh` or a scene instance.

## Input choices

`PlantMeshGenerator.catalog()` lists the valid family IDs and choices. Omitted,
empty, or `"random"` choices are picked deterministically from the seed.

| Option | Values |
| --- | --- |
| `flower` / `leaf` | 32 flower / 24 leaf IDs from `catalog()` |
| `component_variant` | `reference`, `slender`, `ruffled`, `cupped` |
| `curve` | `straight`, `gentle`, `winding` |
| `branching` | `none`, `few`, `many`: 0, 3, or 15 structural side branches |
| `flowers` | `one`, `few`, `many`: 1, 5, or 15 flower heads |
| `pose` | `upright`, `reaching`, `nodding` |
| `camera` | `front`, `three_quarter`, `side`, `back`, `high` |
| `projection_size` | Integer 64–512, default 320; distinct from final puzzle resolution |
| `recent` | Optional array of prior `{flower, leaf}` records; avoids the last three of each |
| `controls` | Optional continuous growth/organ controls below |
| `pose_controls` | Optional pose overrides; bounds in `PlantParameters.POSE_LIMITS` |
| `recipe` | Complete saved native recipe; incompatible versions/revisions/seeds return `{}` |

Preset choices are independent: a straight unbranched stem can have 15 blooms,
or a winding bush can have just one. Bloom load does not alter the structural
branch graph. Small pedicels join flowers to that graph. Each flower follows
its pedicel tangent with bounded tilt/roll, independent scale and shape nudges,
and its own bloom stage. Hanging flower families face down their supports.

Controls may be nested under `controls` or passed directly; direct values take
precedence. Unspecified controls use the preset defaults. Invalid explicit
choices, unknown nested controls, nonfinite/out-of-range numbers, fractional
counts, and inconsistent ranges return `{}`. There is no silent random fallback
for an explicit invalid family. Seeds are integers from 0 through 4294967295.

| Controls | Bounds / defaults |
| --- | --- |
| `length`, `radius` | 1.4–3.2 / .012–.04; default 2.25 / .024 |
| `curve_amount`, `bends` | 0–1 / .35–2.8; defaults follow curve preset |
| `bend_angle_min`, `bend_angle_max` | Degrees, 0–60 / 0–65; defaults 0–0, 8–22, or 20–55 |
| `spread` | .55–1.4; default .95 |
| `primary_count`, `secondary_count` | Integers 0–7 / 0–3 per primary; secondaries require primaries |
| `flower_count`, `bud_count` | Integers 1–24 / 0–6; additional buds default to zero |
| `branch_spacing_min`, `branch_spacing_max` | Fractions of parent length, .025–.12 / .08–.3; defaults .035 / .22 |
| `cluster_chance` | 0–1; default .55; allows close branch pairs |
| `leaf_scale`, `flower_scale` | .16–.55 / .32–1.15; defaults follow branch/flower presets |
| `leaf_density` | 0–1.5; default 1 |
| `flower_angle_jitter` | 0–10 degrees; default 6 |
| `flower_scale_jitter`, `flower_shape_jitter` | 0–.15 / 0–.10; default .10 / .045 |
| `bloom_min`, `bloom_max` | 0–1; default .35–1; **one flower raises the minimum to .55** |

`bloom` is continuous for 19 eligible flower families; fixed families remain
at stage 1. A requested single-flower range below .55 is raised to .55, including
its maximum if needed. Fully open (1) is always a valid upper stage. Individual
heads sample independently within the resolved range. Stems sample bend angles
and positions from ranges; curvature is bounded to broad bends rather than coils.

## Return contract and replay

| Field | Type / meaning |
| --- | --- |
| `polylines` | `Array[PackedVector2Array]` in [-1, 1] |
| `closed` | `PackedByteArray`, one flag per polyline |
| `families` | `PackedInt32Array`, one semantic paint family per polyline |
| `family_names` | `PackedStringArray`: outline, stems, leaves, petals, centers, buds, midribs, occlusion |
| `marks` | `Array` of `{at: Vector2, family: int}`, normalized area hints |
| `seed`, `curve`, `branching`, `flowers`, `flower`, `leaf`, `pose`, `camera`, `component_variant` | Resolved source choices |
| `controls`, `stats` | Resolved controls; actual organ counts, stem lengths/curvature, bloom range |
| `recipe` | Canonical JSON-safe native replay token |
| `asset_revision`, `source_sha256`, `projection_size`, `projection`, `backend` | Provenance and projector metadata |

Save `design.recipe`, not the geometry or attachment records. `PatternIO` retains
full precision inside puzzle `source` metadata. Native recipe version 1 is
separate from the offline Python growth recipes: the seed streams are different,
so the same Python seed does **not** promise identical native geometry. A Python
`growth` dictionary may supply curve/branch/flower presets and controls, but is
not a native replay token. Native replay is tested on Godot 4.7.2 and pinned to
the baked asset revision; changes to the assembly/RNG contract require a new
native recipe version. Retain old backends/assets if old puzzles must regenerate.

## Handoff to game integration

This change deliberately leaves `MandalaGenerator`, `PictureSources`, catalog
registration, unlocks/UI, framing, and export presets untouched. The integrating
session should call this entry point from its new source adapter, forward the
normalized arrays as for animals, and persist `recipe` in puzzle source metadata.
The test demonstrates injection into existing collage/kit consumers without
adding a production picture-type route.

**Before exporting:** include `assets/plants/*.dat` and `assets/plants/CREDITS.md`
in each export preset's non-resource include filter. Reference/preload
`PlantMeshGenerator` from the production adapter so its scripts and the JSON
catalog are reachable. The current animal-only include filter will omit the raw
plant component files. Export registration is left to the integration session.

The baked library is about 7.4 MiB. Runtime stems and per-organ deformation remain
continuous; component topology comes from four authored variants per family.
Bloom morphs interpolate open/closed endpoints; a tiny hibiscus-stamen endpoint
approximation is measured in the manifest. This is decorative geometry, with
no guarantee of botanical compatibility or collision-free arbitrary pairings.
Android performance and final puzzle-detail limits still need profiling.

## Rebuild and validate

```sh
# Offline only; requires NumPy. Deterministically rebuilds the shipped catalog/data.
python3 experiments/plant_3d/bake_runtime.py
# Godot 4.7.2; import a fresh checkout once.
godot --headless --editor --import --quit
godot --headless -s res://tests/run_plant_mesh.gd
godot --headless -s res://tests/run_source_recipe_io.gd
```

Checks cover all 244 baked component variants/checksums, the 27 growth presets,
custom counts/control limits, exact attachments, curvature, flower orientation,
opening limits, seed diversity, JSON recipe replay, worker parity, five camera
projections, paint-region closure, collage/kit consumers and mounted PCK data.
Preview PNGs are written outside the repo to `/tmp/plant-godot-checks`.

See [the authoring library](../../experiments/plant_3d/README.md) and
[asset provenance](../../assets/plants/CREDITS.md).
