# Sourced animal meshes first

Reviewed 2026-11-08. The target is quality stylized animals with reasonable
detail and a consistent style. Use existing meshes and rigs before building
a parametric animal generator.

**Follow-up completed:** [UV preparation and expanded roster](UV_PREPARATION.md)
adds coat atlases/flow coordinates to the 21 initial files and sources 16 more
rigged animals. The user explicitly allows different styles for these roster
additions. The observations below describe the original downloaded files;
the UV-prepared derivatives are separate artifacts.

**Recommendation: start with Quaternius.** There is enough free material for
a coherent initial collection of about 13 animal types. This does not cover
every species/breed in the current generator. Keep those gaps explicit rather
than substituting an unrelated model or mixing several visual styles.

## Shortlist

| Collection | Coverage and fit | License / status |
| --- | --- | --- |
| [Quaternius Ultimate Animated Animal Pack](https://quaternius.com/packs/ultimateanimatedanimals.html) | Best core collection: 12 models, eight broad animal types including variants; faceted, readable silhouettes with moderate detail. | Official page explicitly lists CC0. Downloaded and tested all 12 converted GLBs. |
| [Quaternius Farm Animal Pack](https://quaternius.com/packs/farmanimal.html) | Seven models; adds llama, pig, sheep and zebra. Same artist, but older/coarser geometry. Prefer the newer pack's horse/cattle when both exist. | Official page and downloaded original pack notice state CC0. Downloaded and opened all seven Blender sources. |
| [Quaternius Animal Pack Vol.2](https://www.patreon.com/quaternius/posts/animated-animals-13160113) | Adds a cat; also has dog/wolf/birds/fish. Older style needs a side-by-side review with the main collection. | Cat/dog conversion mirror includes a CC0 notice pointing to the [OpenGameArt listing](https://opengameart.org/content/animated-animales-low-poly). Creator's original release located. Downloaded and tested cat/dog conversions; original archive not inspected. |
| [Kenney Cube Pets](https://kenney.nl/assets/cube-pets) | Official page lists 24 files and animation. Very consistent, deliberately cuboid; a secondary direction if that shape language is wanted. | Official CC0. Listing checked; binaries not tested. The similarly named Animal Pack/Remastered collections are 2D, not replacement 3D meshes. |
| [ITHappy Animals Free](https://ithappystudios.com/free/animals-free/) | Seven coherent models, including a tiger, with rigs and animations. Visually promising alternative to Quaternius. | Free download is not automatically CC0. [ArtStation's distribution](https://www.artstation.com/marketplace/p/1WdKK/animals-free) shows a Standard license with project/sales limits. Confirm the selected distributor's terms before adopting it. Binaries not tested. |
| [Gobkit free animal packs](https://github.com/Ariescar/gobkit-free-assets) | Ten first-release animals downloaded from the publisher's GitHub repository, including Corgi, hippo, rhino and red panda. Coarse toy style. | CC0 notice retained; all ten pass Godot rig, UV and animation checks, including the published walk frame range. The website itself remains inaccessible to the execution environment. |

Quaternius uses public-domain CC0 terms on the two primary pack pages above,
including commercial use. The downloaded license notices are retained beside
the local source files. This finding is specific to these packs, not a blanket
claim about every current/future pack from any publisher.

## Actual file inspection

The downloaded sources are at `/workspace/animal-asset-research/quaternius/`.
They are evaluation artifacts, not bundled app assets. The checked-in
[`sourced_asset_inventory.json`](sourced_asset_inventory.json) records the
creator pages, mirror URLs, SHA-256 hashes, geometry, rig and animation data.

| Main collection GLB | Triangles | Skin joints | Animation clips |
| --- | ---: | ---: | ---: |
| Alpaca | 2,060 | 46 | 13 |
| Bull | 2,418 | 42 | 12 |
| Cow | 2,450 | 42 | 12 |
| Deer | 2,096 | 46 | 13 |
| Donkey | 2,000 | 50 | 13 |
| Fox | 1,848 | 51 | 12 |
| Horse | 2,182 | 50 | 13 |
| Horse White | 2,182 | 50 | 13 |
| Husky | 1,920 | 49 | 12 |
| Shiba Inu | 1,950 | 46 | 12 |
| Stag | 3,667 | 38 | 13 |
| Wolf | 1,962 | 51 | 12 |

These counts include exported helper/IK joints; they are not all deform bones.
All 12 have skin weights and named animation clips. Weight sums differ from
one by less than 0.000001. Godot 4.7 imported each skeleton and successfully
sampled its walking animation. Typical clips include idle, eating, walk,
gallop and jump; names and availability vary, so use the actual clip list.

The seven original farm Blender files have 24–28 bones, 562–1,354 triangles
and six actions each: Death, Idle, Jump, Run, Walk and WalkSlow. They were
opened with automatic asset scripts disabled. The cat/dog conversion samples
have 34 exported joints, 807/602 triangles and two clips each; both also pass
Godot import/walk sampling.

**The inspected files have no UV maps.** They use material regions rather
than a complete coat unwrap. The cat/dog conversions also flattened the
material color values, although the cat's material names survive. Keep the
original geometry/rigs, but create a separate rest-surface coat coordinate
layer or unwrap before procedural stripes/spots. Do not treat these as
drop-in assets for the prototype's existing coat-coordinate contract.

GLB files carry skeletons/weights and baked animation, not Blender's IK or
joint-limit controllers. Start with sampled authored clips. Add and validate
constraints when implementing new procedural poses; a supplied rig does not
itself guarantee every new pose will be anatomically reasonable.

## Coverage decision

A sensible first roster is the 12 newer models plus cat, llama, pig, sheep
and zebra from the older collections: **17 model variants / 13 broad animal
types**. Keep the final roster subject to a common-camera silhouette and
line-art review, especially the lower-detail older models.

| Current generator animals | Sourcing result |
| --- | --- |
| Cat, dog, wolf, fox, horse, zebra, cow, deer | Matching Quaternius types found. Dogs include husky, Shiba Inu and pug variants; deer includes stag. |
| Tiger, lion, leopard, cheetah, bear, elephant, hippo | Not covered by the recommended Quaternius collections. Broader packs are leads, not verified compatible additions. |
| Dachshund | No matching breed found in the recommended collections; do not label another dog mesh as a dachshund. |
| Additional types | Alpaca, donkey, llama, pig and sheep can expand the initial roster. |

This is enough to start with sourced assets under the user's style priority.
A parametric fallback is deferred. If all original 16 types become mandatory,
the missing eight remain an asset-sourcing/style task before that decision.

## Re-run technical checks

```sh
python3 experiments/animal_3d/audit_gltf_assets.py \
  /workspace/animal-asset-research/quaternius/ultimate/*.glb \
  /workspace/animal-asset-research/quaternius/animal-cat.glb \
  /workspace/animal-asset-research/quaternius/animal-dog.glb

godot --headless -s res://experiments/animal_3d/check_sourced_assets.gd -- \
  --input=/workspace/animal-asset-research/quaternius
```

The Godot check recursively imports distinct GLBs, deduplicates by SHA-256,
requires a skeleton and walking clip, and checks that sampling the clip
changes the bone pose. It passed for all 14 distinct GLBs. This is an import
and animation check, not certification of every animation or final line art.

Next implementation work should adapt one fox/horse/deer mesh through the
projection pipeline, add coat coordinates, then review the resulting 2D art
at puzzle scale before importing the complete roster into the main catalog.
