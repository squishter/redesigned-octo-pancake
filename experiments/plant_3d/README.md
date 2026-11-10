# Mutable plant mesh library

The native [Godot entry point](../../gen/plant_3d/README.md) is now available as
`PlantMeshGenerator.generate(seed, options)`, returning the same normalized
contour/paint-family contract as posed animals. It assembles runtime stems and
deforms baked modular components without Python. Picture-type registration
and game integration remain separate.

[Per-flower bloom stages](BLOOM_STAGES.md) add continuous petal unfolding for
19 eligible flower families. Plants can mix closed, opening and mature heads,
using independent seeded stages while retaining their stem-aligned orientation.

[Independent stem, branching and bloom mutations](STEM_GROWTH.md) now extend
the library: straight/gentle/winding axes × no/few/many branches × 1/5/15
blooms, including single roses and full bushes. The component library below
and its version-2 outputs remain available separately.

The library now contains **24 leaf families, 32 flower families, five buds and
three branching stems**. Each leaf/flower/bud family has four reviewed mutation
recipes: reference, slender, ruffled and cupped. That produces **96 leaf meshes,
128 flower meshes and 20 buds**, plus three stems: **247 component GLBs**.
These are original authored meshes. Online assets are audited separately and
are not included in those counts.

The generator exposes continuous shape controls in addition to the four
examples. Mutations change proportions, contours, curvature and organ layout;
they are not color changes or uniform resizing. `check_components.py` verifies
four different shapes per family after removing translation and uniform scale,
exact recipe replay, different seeded shapes, control bounds and valid geometry.

## Families

| Group | Families |
| --- | --- |
| Original leaves, 12 | Oval, lance, heart, arrow, round, oak lobed, serrated, ribbon, fan, trifoliate, pinnate, needle cluster |
| Added leaves, 12 | Maple, ivy, ginkgo, monstera, split philodendron, willow, eucalyptus, holly, birch, fern, palm, succulent |
| Original flowers, 16 | Daisy, cosmos, sunflower, poppy, buttercup, lily, tulip, rose, camellia, dahlia, aster, gerbera, bell, trumpet, orchid, star |
| Added flowers, 16 | Magnolia, lotus, zinnia, chrysanthemum, anemone, hibiscus, daffodil, iris, pansy, anthurium, calla, fuchsia, hydrangea, allium, lavender, bleeding heart |
| Buds, 5 | Round, pointed, opening, ribbed, sepal |
| Stems, 3 | Single spire, forked spray, branching bush |

Names describe stylized botanical families, not botanically accurate species.
The constructions include single/layered petals, tubular corollas, a daffodil
crown, iris standards/falls, a hibiscus staminal column, spathes/spadices,
clustered florets and pendant pouches. Leaves include palmate, compound, frond,
needle and fleshy forms. Monstera holes are real geometric openings rather
than transparent texture cards. Narrow fronds retain a central rachis; fine
leaflet veins are omitted from their paint labels to prevent dotted artifacts
at puzzle resolution.

## Mutation API

`plant_components.py` is the reusable authoring API. Local +Y is the attachment
axis; leaf faces point +Z and flowers open along +Y. Seeds are explicit integers
in [0, 2^32); family names use a stable SHA-256 seed key rather than Python's
process-dependent hash. Every resolved numeric control is stored in a recipe.

| Leaves | Flowers and buds |
| --- | --- |
| Length, width, tip shape | Petal length, width, tip shape |
| Lobe depth, margin waviness | Opening, cup depth, petal curl, ruffling |
| Curl, twist, cupping | Ring rotation, center size |
| Leaflet spread, asymmetry | Floret spread, asymmetry |

The controls that affect an organ depend on its construction: a simple bud
has no petal rings, and a spathe has no floret cluster. `LEAF_LIMITS` and
`FLOWER_LIMITS` define the accepted numeric ranges. Invalid names, nonfinite
values and out-of-range controls fail before geometry is generated.

From the repository root, with Python/NumPy installed:

```sh
# Generate the full library, four examples per family and 36 posed assemblies.
python experiments/plant_3d/build_plants.py --out=/tmp/plant-library-v2

# Export an individual custom flower or leaf with explicit controls.
python experiments/plant_3d/build_plants.py --out=/tmp/custom-plants \
  --component=flowers:iris --variant=cupped --seed=207 --control=opening=0.72
python experiments/plant_3d/build_plants.py --out=/tmp/custom-plants \
  --component=leaves:ginkgo --variant=ruffled --seed=208 --control=twist=-0.3
```

Inside Python, add `experiments/plant_3d` to the import path:

```python
from plant_components import leaf_mesh, flower_mesh, recipe

saved = recipe("flowers", "daffodil", seed=207, variant="cupped",
               controls={"opening": 0.72, "width": 0.9})
mesh = flower_mesh(saved["family"], seed=saved["seed"],
                   variant=saved["variant"], controls=saved["controls"])
leaf = leaf_mesh("ginkgo", seed=208, controls={"twist": -0.3, "curl": 0.25})
```

Exported GLBs are static snapshots of these generated meshes. The Python
source and recipes provide mutation; the GLBs do not claim to contain skeletal
rigs or morph targets. No Python/Blender runtime in the Android game is proposed.
The generator normalizes the attachment convention, preserves semantic paint
families and assigns distinct IDs to individual petals/leaflets. Complete plant
GLBs retain separate **Stems**, **Leaves** and **Flowers** nodes.

## Assembly and posing

Twelve deliberately chosen leaf/flower pairings are each built in upright,
reaching and nodding poses. The pose changes stem bend in two axes, branch
spread, leaf pitch/curl and flower opening. Attachment frames follow the
bent branches. Each assembly selects a component mutation recipe; variation
also comes from independent, deterministic organ seeds. Rebuilding always
starts from the source recipe, so posing does not accumulate errors.

Pose changes retain topology and organ IDs for a given assembly. Shape
mutations are an authoring operation and need not retain topology across
families. The three stem templates, 24 leaves and 32 flowers allow 2,304 raw
combinations before mutation, pose, size or camera choices. This is not a claim
that every combination is botanically compatible or free of intersections.

`projection.gd` reuses the posed-animal CPU triangle visibility and contour
helpers. A visible pixel carries both an organ ID and a paint family. Organ
boundaries keep overlapping petals distinct; paint families keep colors and
gem patterns coordinated. Hidden triangles, mesh triangle edges and shading
never become picture lines. No scene nodes or GPU viewport are required.

The adapter exercises the existing `PictureSources` downstream APIs for
collage and diamond kits. This remains an experimental asset library: a
production plant picture type, game catalog entry and live editor have not
been added. Native runtime evaluation and compact baking are provided by the
entry point above; camera curation, collision constraints and Android profiling
remain follow-up integration work.

## Checks and review sheets

Use Godot **4.7.2**, matching this repository's CI. In this workspace the
executable is `/workspace/.environment/bin/godot`; the global `godot` is older.
NumPy is needed for geometry and Pillow for assembling the review sheets.

```sh
python experiments/plant_3d/check_components.py --out=/tmp/plant-library-v2
# Import once in a fresh checkout to create Godot's global class cache.
godot --headless --import
godot --headless -s res://experiments/plant_3d/check_plants.gd -- --input=/tmp/plant-library-v2
python experiments/plant_3d/build_plants.py --out=/tmp/plant-library-v2 --verify-puzzles
python experiments/plant_3d/make_sheets.py --input=/tmp/plant-library-v2
```

For a sandbox that cannot write to Godot's normal user directory, prefix its
command with `XDG_DATA_HOME=/tmp/plant-godot/data`,
`XDG_CONFIG_HOME=/tmp/plant-godot/config` and
`XDG_CACHE_HOME=/tmp/plant-godot/cache`.

Outputs are deliberately outside the repository:

- `catalog.json`: stable family/variant IDs, resolved recipes, component GLB
  SHA-256 hashes, geometry counts and relative paths.
- `components/`: 247 GLBs and corresponding plain surface JSON files.
- `plants/`: 36 assembled/posed GLBs and corresponding surface JSON files.
- `mutation_validation.json`: shape diversity, exact replay and bounds checks.
- `previews/validation.json`: component/assembly projection and topology checks.
- `previews/flowers_added.png`, `leaves_added.png`: the new families.
- `previews/flowers_mutations.png`, `leaves_mutations.png`: selected families
  shown as four distinct meshes each, using one consistent camera per family.
- `previews/flowers_library.png`, `leaves_library.png`, `stems_library.png`:
  complete family contact sheets.
- `previews/plant_*_views.png`, `plant_poses.png`, `plant_game_colors.png`:
  camera comparisons, assembled poses and puzzle color regions.
- `previews/*_collage.json`: twelve playable collage puzzles with saved recipes.

Checks include all 244 component mutations and three stems; 84 assembly
views/poses; finite, nondegenerate geometry; stable pose topology; attachment
frames; background leaks and paint-family separation; component GLB imports;
three-group assembly imports; worker/main-thread equality; depth occlusion;
twelve collage/kit pairs; metadata JSON round trips; and exact geometry rebuilt
from Godot's saved puzzle recipes. Total projection coverage is 331 cases.
These checks do not establish botanical realism, arbitrary self-collision
safety or a mobile performance budget.

This is recipe format **2**. The previous study and its generated archive
remain separate; version-1 recipes are not silently interpreted as version 2.

## Online sources

See [SOURCE_AUDIT.md](SOURCE_AUDIT.md) for the downloaded CC0 source, actual
mesh/material audit, preserved hashes, and the remaining publisher shortlist.
Authored components avoid a dependency on third-party texture alpha or rigs;
online meshes can still be adapted once they meet the same per-organ geometry
and mutation contract.
