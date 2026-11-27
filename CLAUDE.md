# Paint With Gems: notes for Claude

A Godot 4.7.2 (GDScript) gem-art puzzle game for Android. `README.md` has the
full tour: what each file in `gen/`, `game/` and `scenes/` does, and every
test and render command.

## Skills in this repo

- `run-tests`: which suites cover what, and a runner that runs them in parallel.
- `render-sheets`: render and stitch pictures to look at; use for any visual change.
- `add-picture-source`: the checklist for wiring a new picture type.
- `branch-and-merge`: start branches, merge main before testing, commit, merge.
- `triage-player-report`: turn what the player saw (in their words) into code, a cause and a plan.
- `test-play-input`: reproduce and regression-test taps, strokes, zoom and other play gestures.
- `measure-board-performance`: count what the 3D board draws per frame, before and after a change.
- `add-unlockable`: the checklist for a new color, theme, animation, finale, finish or power-up.

## Godot

- Godot is `/usr/local/bin/godot`, 4.7.2. Run everything headless:
  `godot --headless -s res://tests/<script>.gd -- --key=value`.
- After adding a script with a new `class_name`, or on a fresh checkout, run
  `godot --headless --editor --import --quit` first. Otherwise other scripts
  fail with `Identifier "X" not declared in the current scope`.
- Quick parse check of one script (catches the type errors below without
  running anything): `godot --headless --check-only -s <path>`.
- `gdlint`/`gdformat` are not installed here. `gdlintrc` sets lines to at most
  130 columns; the code itself uses tabs and typed variables throughout.

## GDScript traps that cost retries

- `:=` can't infer a type from `Array.filter()`, `.map()`, values read out of
  a `Dictionary`, or other untyped expressions. Write the type:
  `var stones: Array = slots.filter(...)`, `var r: float = d["width"] / 2.0`.
  A parse error like this stops the whole test script from loading.
- In a `for` loop over an untyped array, type the loop variable when you use
  it as a typed value (`for s: Dictionary in slots`).
- Don't name a variable `range` or other built-in function names in new code
  (some old code does; it works but shadows the builtin).

## Working here

- Generated pictures are judged by eye: render them (`render-sheets`) and look
  before reporting a visual change as done. Put renders and test output in the
  session scratchpad, never in the repo.
- Foreground `sleep` is blocked. Run long suites with `run_in_background` and
  wait for the notification, or poll with one `until ...; do sleep 5; done`
  loop under the tool's timeout.
- `run_generators.gd` takes 10–12 minutes and exercises every picture variant;
  start it first when running several suites.
- Saved puzzles keep their `source` (seeds, recipes); changes to a generator's
  random streams change old puzzles when they regrow. Keep replay stable or
  version it (see `gen/plant_3d/README.md`).
- Puzzle-type, feature and unlock ids are stored in player profiles: don't
  rename them (map old ids in `Unlockables.RENAMED` if you must).
