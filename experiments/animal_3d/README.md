# Rigged 3D animals → 2D puzzle art

The current direction is **sourced meshes first**. See
[asset sourcing findings](ASSET_SOURCES.md) for the Quaternius shortlist,
downloaded model inventory, species coverage and import checks. The procedural
meshes below remain pipeline experiments; a parametric fallback is deferred.

[Coat UV preparation and expanded roster](UV_PREPARATION.md) documents the
two-channel UV exports for all 21 initial sources, 16 additional rigged meshes,
license credits, previews and reproduction commands.

[Runtime sourced-animal posing](../../gen/animal_3d/README.md) now loads all
37 bundled models, freezes authored poses, solves custom species/rig-specific
poses, and adds constrained seeded variations. Its 24 pose types include canine
sitting/play bows, feline crouches and equine trot/gallop phases. The pose studio
also offers curated silhouette views and three front head crops. Production
line-art integration of these sourced meshes is the next stage.

This is a working investigation of a replacement for the animal generator.
It uses the app wiring from `ccr-7d680ac7-axod0b` and leaves the production
generator in place while the replacement is evaluated.

The pipeline works. The procedural meshes are **rough anatomy prototypes**,
not finished realistic animal assets. Better meshes and skin weights remain
necessary; a 3D skeleton alone does not supply convincing anatomy.

## What is implemented

- Separate cat, wolf and horse body profiles, continuous voxel-remeshed skin,
  and a 26-bone armature: pelvis/spine, neck/head, four three-segment limbs,
  and an eight-segment tail.
- Normalized skin weights with at most four bone influences per vertex.
- Local joint limits, two-bone leg IK without bone stretching, and planted
  foot orientation controls. Stand/walk for all three animals; sit for the cat.
- Rest-surface coordinates and semantic component IDs retained through skin
  deformation. Coats use distance along a body/limb/tail and angle around it.
  Limb coordinates share the torso's phase at their attachment.
- Orthographic cameras at 0°, 35° and 70° yaw, with 7° elevation.
- A triangle depth buffer carrying interpolated UV, rest position, surface
  normal, component and material. Hidden surfaces never contribute lines.
- Silhouette, visible occlusion and coat/material boundaries, traced into
  vector paths. Mesh triangle edges are not drawn. This is sampled at 384 px
  in the validation run; the SVG paths can be rendered at any size.
- Blender sources and skinned GLBs, plus posed mesh JSON, model/rig/component
  previews, SVGs, PNGs and the existing generator's polyline/family/area-mark
  contract.
- An adapter that sends these projections through the existing region,
  collage and diamond-kit pipelines without changing the production catalog.

`build_models.py` runs inside Blender. `project_line_art.py` is a reference
CPU projector, using NumPy/SciPy/Pillow. Runtime use of Blender is not proposed.

## Reproduce

Requirements: Blender 4.3+, Python with NumPy, SciPy and Pillow, and Godot 4.7.
Run from the repository root. Outputs are intentionally outside the repository.

```sh
blender --background --threads 1 --factory-startup \
  --python experiments/animal_3d/build_models.py -- --out=/tmp/animal-3d

python3 experiments/animal_3d/check_models.py --models=/tmp/animal-3d

python3 experiments/animal_3d/project_line_art.py \
  --models=/tmp/animal-3d --out=/tmp/animal-3d/projections --size=384

godot --headless --import
godot --headless -s res://experiments/animal_3d/check_projections.gd -- \
  --input=/tmp/animal-3d/projections
```

The build supports `--species=cat,wolf,horse`. After editing poses or export
logic, `--reuse` reopens the existing `.blend` files and avoids rebuilding skin.
The complete validation expects the default three animals and all three angles.

Open `cat.blend`, `wolf.blend` or `horse.blend` to inspect the actual rig and
constraints. The `.glb` files contain rest meshes, skin weights and skeletons.
Blender constraints are **not** transferred to Godot by glTF; the JSON snapshots
are meshes evaluated after posing in Blender. The sourced-mesh runtime controller
is documented separately above.

## Validation

`check_models.py` checks all seven posed meshes for finite geometry, unchanged
bone lengths, evaluated local rotations within the configured limits, ground
clearance, support-foot contact, normalized weights, stable rest coordinates
and component IDs, and deformation between poses. An overlapping-triangle
test checks depth-buffer occlusion independently of the animal assets.

`check_projections.gd` checks all 21 projections for closed paintable areas,
background leaks and accidental joins between different coat families. It
also makes one collage and one diamond kit per species through the app's
existing `PictureSources` entry points and imports all three skinned GLBs as
Godot `Skeleton3D` scenes. It writes `*_game_colors.png` previews.

## Recommended production design

1. **Finish anatomy assets first.** Author and review a feline, canine and
   ungulate mesh at the target puzzle scale, including skull/stop/jaw, scapula,
   pelvis, paws/hooves and silhouette. Refine shoulder/groin weights and UV
   seams. Use separate heavy-animal rigs for elephants and hippos rather than
   stretching the same mesh to every species. Keep variation within species
   proportions. Procedural fur geometry is unnecessary for this output.
2. **Pose the skeleton, then deform the skin.** Implement species-specific
   limits and pole directions, feet on a shared ground, spine/neck controls,
   and gait phases. Sitting, curling and grazing need their own coordinated
   body and contact targets. Limits prevent reversed joints; they do not by
   themselves prevent body intersections or guarantee balanced poses. Add
   self-collision/contact checks before accepting a generated pose.
3. **Keep coats on the rest surface.** Use authored UV islands/component
   attributes for torso, each limb, head, ears, tail and hooves. Store coat
   family separately from geometric part ID. Interpolate and deform these
   coordinates with the mesh, never generate stripes in screen space.
4. **Project through curated cameras.** Start with side and three-quarter
   views; reject views that hide species cues or create unplayably small
   regions. Extract outer/occluding contours and coat isocontours, preserving
   shared junctions and area labels. Avoid a wireframe or indiscriminate
   normal-edge detector. Simplify small details at puzzle scale.
5. **Preserve the app contract.** Return the same unit-space polylines,
   closed flags, line families and area marks already consumed by
   `MandalaGenerator` → `PictureSources` → collage/kit generation. Record
   model revision, pose parameters, camera preset and coat seed in source
   metadata so a model update does not silently change an older puzzle.
6. **Choose the Android runtime after profiling.** The reference Python
   rasterizer establishes correctness, not a mobile performance budget.
   Godot's GPU can produce UV/ID/depth buffers, but `SubViewport` and scene
   nodes cannot run on the generator's existing `WorkerThreadPool` path.
   Schedule rendering on the main/render thread, then return plain buffers
   for worker-side contour and puzzle generation. Alternatively, bake an
   initial pose/camera library offline. Keep the model/pose/project stages
   separate so the app can change that implementation without changing its
   puzzle contract.

This prototype establishes that the 3D-to-2D route is viable and compatible
with the app. Asset quality, full self-collision,
detail filtering and Android performance are the remaining production work.
