# Per-flower stages of bloom

Petalled flowers can now range continuously from tightly cupped to fully
open. Petals rise and fold inward as the head closes, then spread as it
opens; centers become less exposed. This deforms geometry, rather than
uniformly resizing it.

`bloom` is normalized maturity in **0–1**. Comparison renders use 0.10, 0.40,
0.70 and 1.00. The chosen variant still supplies the petal style, so a mature
tulip can naturally remain cupped.

## Eligible families

| Closed construction | Families |
| --- | --- |
| Layered petals | Rose, camellia, dahlia, zinnia, chrysanthemum, lotus |
| Cup petals | Tulip, magnolia, buttercup, poppy, anemone |
| Ray/spreading petals | Lily, cosmos, daisy, gerbera, aster, sunflower, star, hibiscus |

These 19 families use three closed-petal profiles while retaining their
petal counts, layers and semantic IDs. Tubular corollas, spathes, complex
asymmetric constructions and multi-floret clusters retain their authored
shape. An explicit component-level bloom request for an unsupported family
fails; plant assembly automatically leaves those families at stage 1. The
existing separate bud components remain available.

## Controls

For a component, use `bloom`:

```sh
python experiments/plant_3d/build_plants.py --component=flowers:rose \
  --control=bloom=0.4 --out=/tmp/partly-open-rose
```

For a plant, `bloom_min`/`bloom_max` set the range sampled independently per
flower. New plants default to 0.35–1.0. Set both values equal for one uniform
stage. Flower count remains independent.

Plants with **exactly one flower** enforce a minimum stage of **0.55**, between
the partly-open (0.40) and mostly-open (0.70) examples, with fully open (1.0)
still allowed. This uses the actual flower count, including count overrides,
regardless of branching. Lower requested ranges are raised to that floor;
the resolved range is stored for replay. Multi-flower plants retain their
wider range, and standalone component studies can still show closed petals.

```sh
python experiments/plant_3d/build_stems.py --single --out=/tmp/mixed-rose \
  --curve=gentle --branching=many --flowers=many --flower=rose \
  --control=bloom_min=0.15 --control=bloom_max=1.0

python experiments/plant_3d/build_stems.py --single --out=/tmp/closed-rose \
  --curve=gentle --branching=many --flowers=many --flower=rose \
  --control=bloom_min=0.25 --control=bloom_max=0.25
```

```python
from plant_components import flower_mesh
from stem_growth import make_recipe, assemble

head = flower_mesh("rose", seed=81, controls={"bloom": 0.4})
growth = make_recipe("gentle", "many", "many", seed=81,
                     controls={"bloom_min": 0.15, "bloom_max": 1.0})
plant, metadata = assemble(growth, leaf="serrated", flower="rose")
```

Each attachment records its exact stage, profile and resolved shape controls.
An independent seeded stream sets maturity, so changing the range moves no
stems, leaves or flower attachments and changes no flower orientation or
scale. Reposing does not resample maturity. The older `opening` control
remains a petal-style/pose adjustment, separate from maturity.

Petal topology stays unchanged across stages. `bloom=1` preserves previous
geometry exactly. Version-4 growth recipes without bloom-range fields resolve
to 1–1, preserving older plants; this is a backward-compatible recipe
extension. Saved puzzle parameters retain full precision through `PatternIO`.

## Renders and checks

```sh
python experiments/plant_3d/build_blooms.py --out=/tmp/plant-blooms
python experiments/plant_3d/check_blooms.py --out=/tmp/plant-blooms
godot --headless -s res://experiments/plant_3d/check_bloom_projection.gd -- --input=/tmp/plant-blooms
python experiments/plant_3d/build_blooms.py --out=/tmp/plant-blooms --verify-puzzles
python experiments/plant_3d/make_bloom_sheets.py --input=/tmp/plant-blooms
```

Use Godot 4.7.2 and the writable XDG directory settings in the library README
for this workspace. NumPy generates geometry and Pillow assembles the sheets.

Twenty-four component meshes show six families at four stages, with a fixed
camera and scale for each family. Four versions of one rose bush share stems,
leaves and flower placements: closed, half-open, open and mixed. Tulip and
lotus-inspired plants also mix stages.

Review images under `previews/`:

- `rose_opening.png`: four rose stages, with side and high views.
- `bloom_progression.png`: rose, tulip, lotus, poppy, lily and magnolia.
- `rose_bush_maturity.png`: one 15-flower bush at four maturity settings.
- `mixed_bloom_plants.png`: three plant families with individually varied heads.

Checks cover 95 component stages across all 19 eligible families, monotonic
unfolding, valid triangles, stable topology, eligibility/invalid controls,
fixed/mixed maturity, unchanged attachment frames/scales, pose-stable stages,
replay and legacy compatibility. Forty Godot projections check closed paint
regions and GLB imports, plus three collage/diamond-kit pairs and exact
geometry replay from their saved metadata. The older version-2 and version-4
example plants also regenerate unchanged.
