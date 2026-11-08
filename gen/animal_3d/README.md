# Sourced animal posing

The 37 sourced GLBs are bundled under `assets/animals/`, with their licenses and
source hashes. This is the runtime posing stage for the forthcoming 3D-to-2D
generator. The existing puzzle catalog still uses its current line-art generator.

## Use in Godot

Call on the main thread with a parent already in the scene tree:

```gdscript
var animal := AnimalPoseLibrary.spawn(self, "ultimate_fox")
var choices := animal.available_poses()  # Only poses supported by this mesh.
var info := animal.pose("idle", 42, 0.75)
var mesh := animal.snapshot()  # posed vertices/normals, UVs, colors and triangles

# Same authored frame, with explicit normalized control overrides:
animal.pose("idle", 42, 0.75, {"phase": 0.25, "look_yaw": -0.6, "tail_sweep": 0.8})
```

`model_ids()` lists stable catalog IDs; `model_info(id)` includes a display name,
rig family, source hash and whether the second UV channel carries CoatFlow.
`spawn(parent, id, height)` normalizes the neutral model's height to one scene unit
by default. It returns null for unknown models, invalid heights or missing parents.

`pose(preset, seed, amount, overrides)` freezes an authored animation sample or
solves a custom recipe, then adds deterministic variations. Amount is clamped to
0–1; zero disables variations and uses a fixed phase. Supported overrides use
-1–1, except `phase`, which uses
0–1. Invalid/nonfinite requests return an empty dictionary and preserve the last
pose. Reapplying the same request resets the entire source pose first, including
node transforms and morph weights, so changes never accumulate.

There are 274 model/preset combinations across 24 pose names. Eligibility uses
both the animal's anatomy and its particular rig, not just shared bone names:

- Detailed canines: custom sitting, lying down, play bow, stretch and looking
  back. The coarse legacy dog omits sitting; Gobkit's single-segment Corgi legs
  retain their authored poses rather than receiving folded-leg recipes.
- Felines: crouch, stretch and looking back; lying down on the legacy and Toon
  Cat rigs. Tuxedo Cat uses its authored sit. Lying down is withheld on Tuxedo Cat
  and the lion cub because their deep folds do not deform cleanly.
- Five equine meshes: a custom diagonal trot with continuous phase selection.
  Authored gallop, jump, landing and kick are exposed only where matching source
  clips exist. Airborne frames retain their source clearance above the floor.
- Other source actions include idle, alert, walk, run, graze, eat, head low and
  headbutt. Headbutts are restricted to bovines and cervids. Fish swim, bats fly
  and jellyfish drift.

Gobkit's published frame ranges are selected from its combined track. Toon Cat
exposes its unidentified combined track as `source`. All models offer `rest`;
the elephant samples an authored neutral frame because its imported bind pose
folds its head backward. Death and hit reactions are excluded. A pose remains
frozen when the scene advances. `pose_info(name)` reports its origin and clip.

## Custom targets and cameras

The named recipes coordinate body rotation, hip/shoulder articulation and foot
targets. Two-bone fits preserve segment lengths and bend planes, with explicit
elbow pole hints for deep folds. Sitting searches for a reachable configuration;
low poses back off their depth if needed. These folded-pose recipes reject
unreachable targets or skin penetration deeper than 2% of neutral height before
final floor alignment. Trot body height uses actual limb reach at each phase.

`pose_targets(definition, seed, amount, overrides)` provides the solver for manual
poses on meshes with four mapped multi-joint legs. Points are in the normalized
model's local Y-up space, before heading variation. Targets are explicit; the
solver does not move them to the floor. For example, after choosing a reachable
`desired_point` from the neutral pose:

```gdscript
var result := animal.pose_targets({
    "body": {"pitch": -5.0, "neck_pitch": 5.0},
    "feet": {"front_left": {"at": desired_point, "contact": true}}
})
```

The four keys are `front_left`, `front_right`, `hind_left`, `hind_right`.
Each foot entry requires `at: Vector3`, with optional `contact: bool` and
`pole: Vector3` bend hint. Unspecified feet keep their neutral targets. Optional
body fields are `pivot`, `translation` (Vector3), and angles in degrees:
`pitch`, `roll`, `yaw`, `hips_pitch`, `shoulders_pitch`, `neck_pitch`, `neck_yaw`,
`head_pitch`, `head_yaw`, `tail_pitch`. Angles must be finite and within ±85°.
This low-level API checks reachability, not balance or full body collision.
Failed requests restore the exact previous pose. Its saved record includes
`definition` for reproduction through `pose_targets()`.

`AnimalCameraPresets.available(animal)` offers two side views, two three-quarter
views and a full front view. Full front is withheld for locomotion, jumping,
kicking and looking back because overlapping limbs weaken those silhouettes.
Three additional presets crop the front of the head: `head_front`,
`head_front_close`, `head_front_high`. They follow the posed head and frame ears,
horns and trunk. `portrait_snapshot()` isolates the weighted head triangles and
preserves their UVs; the studio and CPU preview use that geometry so legs/torso
cannot appear behind the face. Fused Gobkit faces use their face-shell weights,
excluding limb and tail bones. The Labrador uses the shared head/jaw parent for
head gestures, so both halves of its mouth follow the pose.
Head crops require a usable quadruped/bird head region and are withheld when a
look-back pose obscures the face.

```gdscript
animal.pose("sit", 42, 0.5)
AnimalCameraPresets.apply(camera, animal, "three_quarter_left", viewport_aspect)
var head_mesh := animal.portrait_snapshot()
var projection := AnimalCameraPresets.frame(animal, "head_front_close")
```

`frame()` returns an orthographic transform, size, near/far planes and the head
region flag in model-local coordinates. `apply()` sets a Camera3D in world space;
when rendering a portrait, display the portrait subset returned above. Framing
fits the current geometry and viewport aspect rather than fixed bounds.

## Variations and constraints

- Heading: up to 6° around the ground's vertical axis.
- Head yaw/pitch/tilt, distributed neck turns and nods; smaller ranges for grazing
  and heavy animals. The largest head yaw offset is 16°.
- Tail sweep/lift, independent ear rotations, and elephant trunk sweep/curl.
- Small back bends, body pitch/roll, wider/narrower stances, and staggered feet.
  These use per-rig two-bone leg fits on the detailed quadrupeds. Independent
  weighted paw/controller bones move with their targets; actual limb segments
  keep their lengths and scales. Leg adjustments are limited to 20° per joint.
- Stance changes back off through smaller amplitudes if a target cannot be
  reached within 0.2% of neutral height or violates the joint adjustment limit.
  Sitting preserves the solved or authored stance. Rigs without suitable
  multi-joint legs retain their authored stance and use their other controls.

`supported_controls()` reports controls that affect the supplied geometry. For
example, an unused head bone in a simple rigid animal is not offered as a head
control. Every model supports heading/phase variation. Limb mappings cover the
Quaternius, Farm, legacy, Toon Cat, Tuxedo Cat, elephant and lion rigs. Bones that
carry shoulders are treated as spine, even when the exporter names them “neck”.

The last-pose record includes the source hash, version, preset, clip/time, seed,
amount, requested `overrides`, sampled controls, accepted stance factor and foot
errors. To reproduce it, pass the saved preset/seed/amount/overrides back to
`pose()`. The `controls` field contains strength-scaled values for inspection.

Seeded mutators are bounded offsets around the selected authored/custom pose.
Contact fitting uses foot bones/markers; full body self-collision, balance
simulation and soft paw contact remain outside this posing pass. New large
poses such as curling up still need a reviewed recipe or an authored clip.

## Inspect and verify

Run `tools/animal_pose_studio.tscn` in the editor, or:

```sh
godot --path . res://tools/animal_pose_studio.tscn
```

The viewer has animal/preset selection, seed, variation strength, head, tail,
stance and trunk controls, a pose phase slider, eight curated camera/crop choices
and manual orbit. Unsupported poses, cameras and controls are hidden or disabled.
“Reset controls to seed” restores the generated variation.

```sh
godot --headless --editor --import
godot --headless -s res://tests/run_animal_poses.gd -- --out=/tmp/animal-poses
godot --headless -s res://tests/run_animal_pose_views.gd -- --out=/tmp/animal-views
python3 experiments/animal_3d/check_pose_bind_space.py --input=/tmp/animal-poses/bind_checks
python3 experiments/animal_3d/preview_pose_variants.py \
  --input=/tmp/animal-poses --out=/tmp/animal-poses/comparison.png
python3 experiments/animal_3d/preview_pose_views.py \
  --input=/tmp/animal-views --out=/tmp/animal-views/gallery
```

The runtime checks cover all 37 models and every advertised preset: seeded mesh
variation at a fixed animation phase, exact repeatability after another seed,
zero-strength identity, no limb stretching/scaling, UV/topology preservation,
contact/joint limits, floor alignment, frozen poses across frames, morph handling
and invalid input. Independent NumPy glTF transform/inverse-bind calculations
check each neutral skin against the source file, allowing import quantization.
Comparison sheets use a fixed camera and shared framing across an animal's seeds.
The view suite also checks species/rig eligibility, custom target failure
rollback, all eight camera fits at multiple aspect ratios, portrait isolation,
diagonal trot contacts and 17 gait phases with/without variation on every equine.

`snapshot()` uses reference CPU skinning, including up to eight weights, morph
targets, and rigid bone attachments. Vertices and normals use this node's local
Y-up space; UVs stay attached to the imported skin. Sampling is useful for bounds,
tests and the next projection stage. Orthographic contour extraction and puzzle
line-art integration remain separate work.
