# Online source audit

The delivered component library is original authored geometry. The following
source was actually downloaded and inspected separately; it is not included
in the library's family or mutation counts.

## Downloaded: Glass Vase with Flowers

- Publisher: [Khronos glTF Sample Assets](https://github.com/KhronosGroup/glTF-Sample-Assets/tree/main/Models/GlassVaseFlowers).
- Flower author: Rico Cilliers; glass vase: Eric Chadwick.
- The model's [README Legal section](https://github.com/KhronosGroup/glTF-Sample-Assets/blob/main/Models/GlassVaseFlowers/README.md)
  explicitly licenses both contributions as CC0-1.0.
- GLB download: [upstream binary](https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/GlassVaseFlowers/glTF-Binary/GlassVaseFlowers.glb).
- Audited binary size: 1,819,824 bytes.
- SHA-256: `faa2e19329961652b585cc62132ef50b1d95dca8a6a2fd63409158e680563761`.

The actual GLB has one combined `Flowers` mesh with 2,561 position vertices,
one `MASK` material, no skin and no morph targets. Two scene nodes instance
that same flower mesh beside different glass demonstrations; they do not
provide two independent flower assets. The other two meshes are glass vases.
These measurements are recorded in [source_audit.json](source_audit.json).

It is a useful source to retain for later extraction. It is not a drop-in
library of separable, bendable leaves or flower heads. Adapting it requires
per-organ segmentation, pivot normalization and alpha-aware extraction. The
current plant projector traces triangle geometry and does not sample texture
alpha, so using its MASK material directly would produce incorrect outlines.

Reproduce the download and structural audit:

```sh
python experiments/plant_3d/audit_source.py --out=/tmp/plant-sources
```

The script preserves the upstream README, source GLB and SHA-256 audit. It
does not import the model into the authored component catalog. The pinned
hash above identifies the inspected content even if upstream `main` changes.

## Other publishers checked

| Source | Publisher evidence | Status |
| --- | --- | --- |
| [Quaternius Stylized Nature MegaKit](https://quaternius.com/packs/stylizednaturemegakit.html) | CC0; FBX/OBJ/Blend/glTF; 35 plant/flower models in the full pack; tiered free/extra/source distribution | Candidate only. The page's tree-leaf texture variants do not establish reusable individual leaf geometry. Audit actual files and which tier contains a selected asset before counting it. |
| [Poly Haven Gazania](https://polyhaven.com/a/flower_gazania), [Heliophila](https://polyhaven.com/a/flower_heliophila), [Ursinia](https://polyhaven.com/a/flower_ursinia) | CC0 flower assets with alpha maps and glTF/Blend downloads | Candidate realistic references. Whole-plant/clump segmentation and alpha geometry still need inspection. |
| [Kenney Nature Kit](https://kenney.nl/assets/nature-kit) | CC0 nature asset kit | Candidate simpler silhouettes. The publisher page does not establish a broad flower-head library or rigs. |

The original procedural constructions were expanded instead of counting
uninspected online files toward the user's requested leaf and flower roster.
Future imports should preserve publisher/author links, exact download hashes,
licenses, organ IDs, local root frames and bounded deformation controls.
