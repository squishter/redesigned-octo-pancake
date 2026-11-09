# Animal asset credits

`posed/*.dat` contains frozen, normalized pose derivatives of these same models,
with anatomical coordinates and masks added for generated coat markings. The
original creators and licenses below also apply to those derivatives and their
projected animal artwork. Procedural coats and pose changes were added in this
project; they are not the creators' original textures or animations.

The 21 core Quaternius models (`models/farm_*`, `models/ultimate_*`, and
`models/vol2_*`) are CC0. Creator pack links and original conversion notices
are in `licenses/` and the experiment source inventories.


Models retain their individual licenses. These credits apply to the assets,
including derivatives, rather than to unrelated code in their download mirrors.
License links: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/),
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/),
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

| Files | Required credit / source | License | Changes and limitations |
| --- | --- | --- | --- |
| `models/gobkit_*.glb` (10 animals) | Gobkit / Alsomind Tech Co., Ltd., [original repository](https://github.com/Ariescar/gobkit-free-assets) | CC0 1.0 | Unchanged. Coarse, rounded toy style. One baked track: idle frames 0–29, attack 30–59, death 60–89, walk 90–119 at 24 fps. `Red` is the source's name (visually a red panda). |
| `models/toon_cat_toon_cat_free.glb` | “Toon Cat FREE” by Omabuarts Studio, [source](https://sketchfab.com/3d-models/toon-cat-free-b2bd1ee7858444bda366110a2d960386) | CC BY 4.0 | Unchanged source GLB. One combined animation track. |
| `models/tuxedo_cat_tuxedo_cat.glb` | “Tuxedo Cat Animated 2.0” by DreamNoms, [source](https://sketchfab.com/3d-models/tuxedo-cat-animated-20-783fcb78b55b4394a212c2b6392e1113) | CC BY 4.0 | Lossless GLB packaging; planar UV added only to previously unmapped EyeRims. Six clips including walk and sit transitions. |
| `models/shepherd_shepherd.glb` | “German Shepard” by Quaternius, [Poly Pizza source](https://poly.pizza/m/Hssa6NPc6W) | CC BY 3.0 as distributed | Unchanged. 22 clips. Includes backpack/camping gear; remove accessories before using as an ordinary dog silhouette. |
| `models/daydaze_labrador.glb` | “Labrador Dog” by kenchoo, [source](https://sketchfab.com/3d-models/labrador-dog-1f56cfbab07e4fe49b5d9e521c82073a), based on “Dog” by all of life ([original](https://skfb.ly/oHLVz)) | CC BY 4.0 | Mirror decimated/repacked it; this copy decodes meshopt, dequantizes attributes and converts WebP to PNG. Rigged, one idle clip; no authored walk. |
| `models/daydaze_elephant.glb` | “Elephant” by Rukh3D, [source](https://sketchfab.com/3d-models/elephant-4ae161372d6a4219a87340339d1ffe03) | CC BY 4.0 | Same format conversion; mirror retained six clips including walk/run/eat. |
| `models/daydaze_lion.glb` | “Baby Lion” by kenchoo, [source](https://sketchfab.com/3d-models/baby-lion-c9599625dc474262aab754d7b63841f5), based on “Baby-Lion” by hendrikReyneke ([original](https://skfb.ly/osDGs)) | CC BY 4.0 | Same format conversion; mirror decimated/repacked it. Rigged cub with one idle clip, not an adult male lion or walking library. Godot ignores differing UV sets on normal/roughness maps; base color imports. |

Mirrors and revisions, download URLs, byte counts and SHA-256 hashes are in
[additional asset inventory](../../experiments/animal_3d/additional_asset_inventory.json);
core records are in the [prepared inventory](../../experiments/animal_3d/prepared_asset_inventory.json).
Runtime paths and hashes are in `catalog.json`. Keep these credits with redistributed models and carry
the relevant attribution into the app when an asset is adopted.

Existing source UVs may intentionally overlap for palette textures, symmetric
parts or eyes. They were preserved. These additional assets have **not** been
given the separate nonoverlapping coat atlas and anatomical flow channel made
for the original 21 Quaternius sources.
