---
name: run-tests
description: Run this project's Godot test suites (tests/run_*.gd) in parallel and get one pass/fail line per suite. Use before committing, pushing or merging any change to gen/, game/, scenes/ or render/, after merging main into a branch, or whenever the user asks to run or check the tests.
---

# Running the tests

All suites are headless Godot scripts in `tests/run_*.gd`. Run them with the
bundled runner instead of writing a loop each time:

```bash
.claude/skills/run-tests/run_suites.sh --out <scratchpad>/tests-<label> @plants @ui
```

- Arguments are suite names without `run_` and `.gd` (`generators`,
  `plant_pictures`), or groups (below). Pass `--import` after adding a new
  `class_name` script or on a fresh checkout (it imports anyway when
  `.godot/` is missing).
- Each suite gets its own `XDG_DATA_HOME` under `--out`, so the UI suites
  never touch a real profile. Logs land in `<out>/<suite>.log`, the
  summary in `<out>/summary.txt`. The exit status is 0 only if all passed.
- The runner prepares the placement baseline
  (`tests/prepare_placement_baseline.py`) itself when `placements` is asked for.
- Always put `--out` in the session scratchpad, never in the repo.

## Waiting for it

A full run takes 12 minutes or more: `generators` alone takes 10–12. Start it
with the Bash tool's `run_in_background: true`, keep working, and read the
summary when the task notification arrives. To peek before then:

```bash
.claude/skills/run-tests/summarize.sh <out>
```

It prints `PASS`, `FAIL` (with the failing checks and any parse errors) or
`RUNNING` per suite. Don't chain `sleep` calls; foreground `sleep` is blocked.
To block until done, use one `until grep -q '^exit' <out>/generators.log; do sleep 5; done`
with a timeout under 10 minutes, and repeat if it times out.

## Which suites to run

| Group | Suites | Covers |
| --- | --- | --- |
| `@plants` | plant_mesh, plant_pictures, source_recipe_io, generators | `gen/plant_3d/`, plant pictures, auras, plant colors |
| `@generators` | generators, gem_geometry, source_recipe_io | anything in `gen/` (collage, slots, patterns, frames, kits) |
| `@animals` | animal_coats, animal_pack, animal_poses, animal_pose_views | `gen/animal_3d/`, `assets/animals/` |
| `@ui` | menu_ui, color_stories_ui, completed_puzzles_ui, pack_bundles | `scenes/game/`, `game/` |
| `@gems` | gem_geometry, saved_gem_proportions, gem_normals | `gen/gem_*`, `render/` (gem_normals runs under xvfb) |
| `@placements` | placements | `scenes/game/gem_flights.gd`, `gem_placement_fx.gd` |
| `@all` | every `tests/run_*.gd` | before merging into main |

Rough times: generators 10–12 min, plant_pictures 4–6, animal_coats 3–4,
plant_mesh 1–2, UI suites 1–3 each, the rest under a minute.

Pick by what changed, and add `@generators` whenever `gen/collage_generator.gd`,
`gen/picture_sources.gd`, `gen/mandala.gd` or `gen/region_paint.gd` changed:
every picture type goes through them. Before a merge into main, run `@all`.

## When something fails

- Read the failing lines in the summary first; the full log is
  `<out>/<suite>.log`.
- `Parse Error: Cannot infer the type` or `Identifier "X" not declared`: see
  the GDScript notes in `CLAUDE.md` (explicit types; re-import after a new
  `class_name`).
- `run_generators` checks every picture variant, so a new variant's quirks
  (overlapping stones, empty regions) usually show up there first, under
  `test_collages` with the seed and variant in the message. Reproduce one seed
  with a small script rather than re-running the whole suite.
- Before blaming your change, check whether main fails the same way: run
  the suite in a worktree of `origin/main`
  (`git worktree add <scratchpad>/wt-main origin/main`, then
  `<scratchpad>/wt-main/.claude/skills/run-tests/run_suites.sh --import --out <scratchpad>/tests-main <suite>`;
  the runner works in the checkout it sits in). Report a failure that's already on main as
  such, with its count.
- Report failures with the exact failing lines; never skip or loosen a check
  to get green without saying so.
