# Coat UV preparation and expanded mesh roster

This work prepares assets for the 3D-to-2D experiment. It does not switch the
production generator or create a new parametric animal generator.

## Prepared original collection

All 21 previously downloaded Quaternius sources receive two per-corner UV sets:

- **CoatUV / TEXCOORD_0 / Godot UV:** a separate nonoverlapping 0–1 paint atlas
  per animal. It uses angle-based projection charts on an exactly welded proxy.
  The original mesh is never welded. Small collapsed/overlapping patches get
  independent charts, followed by packing with padding.
- **CoatFlow / TEXCOORD_1 / Godot UV2:** anatomical pattern coordinates.
  `part = floor(U / 16)`, `along = U - part * 16`, `around = V`. U is intentionally
  unbounded. Part order is body, head, front left/right, hind left/right, tail,
  ears left/right, horns left/right. The actual regions present are recorded
  per animal; appendages weighted to the head remain in the head region.
  The torso uses a continuous longitudinal field; limbs/tail follow rest-bone
  paths. Limb phase starts at its torso attachment. Angular wrap is resolved
  per polygon before interpolation.

Both fields stay attached to the rest skin under animation. The second set is
pattern data, **not lightmap UVs**; keep it out of automatic lightmap generation.
UVs give stable inputs for stripes, spots and limb rings. They do not themselves
ensure seamless markings across anatomical chart borders. Shoulder/face seams
and coat design still need visual polish before production puzzle adoption.

The preparer checks a UV-independent geometry/topology/material-assignment/
vertex-weight digest before and after modification. Blender sources preserve
the original rigs and actions. Export retains all skin influences; legacy Farm
materials become equivalent flat-color Principled materials in GLB only.
Existing cat/dog conversions retain their previously flattened gray colors.

`check_coat_exports.py` checks the resulting GLB buffers against the original
inventory: triangles, skin-joint counts, clip identities, normalized weights,
both UV sets, finite/bounded atlas values, collapsed triangles, and positive-area
UV overlaps. `check_sourced_assets.gd --require-uv=2` imports them into Godot and
samples walking animations. `snapshot_sourced_mesh.py` checks that evaluated UVs
stay identical while two sampled poses change the actual skinned vertices.

## Additional sources

The expanded collection adds **16 meshes**, with different styles allowed:

| Group | Additions | Technical limits |
| --- | --- | --- |
| Domestic dogs | Corgi, German Shepherd, Labrador | Shepherd includes camping gear. Labrador has one idle clip, so new locomotion would need pose work. |
| Domestic cats | Omabuarts Toon Cat, DreamNoms Tuxedo Cat | Different silhouettes, not claimed as specific breeds. Toon has one combined track; Tuxedo has six clips including walking and sit transitions. |
| Larger wildlife | Elephant, lion cub, hippo, rhino | Elephant has authored locomotion. Lion cub has only idle. Hippo/rhino are coarse toy-style animals. |
| More wildlife | Bat, duck, platypus, red-panda-style `Red`, anglerfish, shark, jellyfish | Gobkit's first-release files use one track with published frame ranges. |

The existing source UVs in these additions are preserved; they can include
intentional palette/symmetry overlap. Only the previously missing Tuxedo Cat
EyeRims receive a new planar UV map. These additions have **not** received the
separate coat atlas/flow preparation of the original 21 meshes.

All sources are CC0 or CC BY. See [full credits](EXTRA_ASSET_CREDITS.md).
Downloads are pinned by commit and hashed. Meshopt compression, quantization,
and WebP are decoded/converted for the three selected Daydaze-mirrored models,
because the current Godot runtime rejects their original required extensions.
Keep upstream modification credits and author attribution with adopted assets.

Excluded: RUN/Series Facet Fauna dogs/cats currently restrict non-RUN use until
2028; this is not a usable free Godot collection today. WildMesh candidates have
conflicting noncommercial/attribution reports and were not adopted. Additional
tiger/giraffe/penguin downloads were investigated but are outside the selected
bundle. The CC0 [LazyGraph tiger/lion base](https://blendswap.com/blend/27158)
remains a good lead; its download requires sign-in and was not obtained.

## Artifacts in this workspace

- `/workspace/animal-asset-research/uv-ready/`: 21 `.blend` and `.glb` pairs,
  per-model atlas/UV reports, combined manifest and export validation.
- `/workspace/animal-asset-research/additional-animals/`: 16 selected GLBs,
  license notices, attribution, source download records and prepared inventory.
- `/workspace/animal-asset-research/coat-uv-preview.png`: actual skinned meshes
  with color, atlas checker and flow stripes in two poses.
- `/workspace/animal-asset-research/additional-animals-preview.png`: actual
  additional meshes, using a CPU preview of source colors. This approximates
  materials; it is not a final Godot render or a claim of consistent art direction.

The original preparation artifacts remain at those workspace locations. The
37 selected GLBs are now also bundled in `assets/animals/` for the
[runtime posing library](../../gen/animal_3d/README.md), with licenses and hashes.
The Blender sources remain outside Git. All work is on `codex/realistic-animals`.

## Reproduce

Use Blender 4.3+ with automatic source scripts disabled. Alternatively, use a
Python 3.11 virtual environment with `bpy==4.3.0` and `numpy<2`, passing its Python
path as `--blender-python=...` to the batch preparer. Each asset is prepared and
reopened for export in separate processes; any failed check stops the batch.

```sh
python3 experiments/animal_3d/prepare_coat_batch.py \
  --source-root=/workspace/animal-asset-research/quaternius \
  --out=/workspace/animal-asset-research/uv-ready
python3 experiments/animal_3d/check_coat_exports.py \
  --input=/workspace/animal-asset-research/uv-ready
godot --headless -s res://experiments/animal_3d/check_sourced_assets.gd -- \
  --input=/workspace/animal-asset-research/uv-ready --require-uv=2

python3 experiments/animal_3d/fetch_extra_animals.py --out=/tmp/extra-sources
# Install @gltf-transform/cli@4.5.1 in an isolated tools directory first.
python3 experiments/animal_3d/prepare_extra_assets.py \
  --sources=/tmp/extra-sources --out=/tmp/additional-animals \
  --gltf-transform=/path/to/node_modules/.bin/gltf-transform
godot --headless -s res://experiments/animal_3d/check_sourced_assets.gd -- \
  --input=/tmp/additional-animals --any-animation --require-uv=1
```

For Gobkit walking specifically, sample its combined track using
`--sample-start=3.8` (frame 91 at 24 fps). The general importer check samples its
idle segment. The supplied skeletons do not add joint constraints in Godot;
new procedural poses still need species-specific constraints/contact checks.
