# Sourced animal posing

The 37 sourced GLBs are bundled under `assets/animals/`, with their licenses and
source hashes. This is the runtime posing stage for the forthcoming 3D-to-2D
generator. The existing puzzle catalog still uses its current line-art generator.

## Use in Godot

Call on the main thread with a parent already in the scene tree:

```gdscript
var animal := AnimalPoseLibrary.spawn(self, "ultimate_fox")
var choices := animal.available_poses()  # rest, graze, idle, walk for this model
var info := animal.pose("idle", 42, 0.75)
var mesh := animal.snapshot()  # posed vertices/normals, UVs, colors and triangles

# Same authored frame, with explicit normalized control overrides:
animal.pose("idle", 42, 0.75, {"phase": 0.25, "look_yaw": -0.6, "tail_sweep": 0.8})
```

`model_ids()` lists stable catalog IDs; `model_info(id)` includes a display name,
rig family, source hash and whether the second UV channel carries CoatFlow.
`spawn(parent, id, height)` normalizes the neutral model's height to one scene unit
by default. It returns null for unknown models, invalid heights or missing parents.

`pose(preset, seed, amount, overrides)` freezes an authored animation sample and
adds deterministic variations. Amount is clamped to 0–1; zero disables variations
and uses a fixed phase. Supported overrides use -1–1, except `phase`, which uses
0–1. Invalid/nonfinite requests return an empty dictionary and preserve the last
pose. Reapplying the same request resets the entire source pose first, including
node transforms and morph weights, so changes never accumulate.

Available presets come from the actual source clips. All models offer `rest`;
others expose authored idle, walking, grazing or sitting where present. Gobkit's
published idle/walk frame ranges are selected from its combined track. Toon Cat
exposes its unidentified combined track as `source`, rather than inventing pose
names. Labrador and lion cub still have only idle/rest. The Tuxedo Cat has a
sitting preset. A pose remains frozen when the scene advances.

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
  Sitting preserves the authored stance. Rigs without suitable multi-joint legs
  retain their authored stance and use their other available controls.

`supported_controls()` reports controls that affect the supplied geometry. For
example, an unused head bone in a simple rigid animal is not offered as a head
control. Every model supports heading/phase variation. Limb mappings cover the
Quaternius, Farm, legacy, Toon Cat, Tuxedo Cat, elephant and lion rigs. Bones that
carry shoulders are treated as spine, even when the exporter names them “neck”.

The last-pose record includes the source hash, version, preset, clip/time, seed,
amount, requested `overrides`, sampled controls, accepted stance factor and foot
errors. To reproduce it, pass the saved preset/seed/amount/overrides back to
`pose()`. The `controls` field contains strength-scaled values for inspection.

This is bounded variation around authored poses. Contact fitting uses foot
bones/markers; full body self-collision, balance simulation and soft paw contact
are outside this posing pass. A large new pose such as curling up needs its own
authored pose or additional rig work.

## Inspect and verify

Run `tools/animal_pose_studio.tscn` in the editor, or:

```sh
godot --path . res://tools/animal_pose_studio.tscn
```

The viewer has animal/preset selection, seed, variation strength, head, tail,
stance and trunk controls, plus a view-angle slider. Unsupported controls are
disabled. “Reset controls to seed” restores the generated variation.

```sh
godot --headless --editor --import
godot --headless -s res://tests/run_animal_poses.gd -- --out=/tmp/animal-poses
python3 experiments/animal_3d/check_pose_bind_space.py --input=/tmp/animal-poses/bind_checks
python3 experiments/animal_3d/preview_pose_variants.py \
  --input=/tmp/animal-poses --out=/tmp/animal-poses/comparison.png
```

The runtime checks cover all 37 models and every advertised preset: seeded mesh
variation at a fixed animation phase, exact repeatability after another seed,
zero-strength identity, no limb stretching/scaling, UV/topology preservation,
contact/joint limits, floor alignment, frozen poses across frames, morph handling
and invalid input. Independent NumPy glTF transform/inverse-bind calculations
check each neutral skin against the source file, allowing import quantization.
Comparison sheets use a fixed camera and shared framing across an animal's seeds.

`snapshot()` uses reference CPU skinning, including up to eight weights, morph
targets, and rigid bone attachments. Vertices and normals use this node's local
Y-up space; UVs stay attached to the imported skin. Sampling is useful for bounds,
tests and the next projection stage. Orthographic contour extraction and puzzle
line-art integration remain separate work.
