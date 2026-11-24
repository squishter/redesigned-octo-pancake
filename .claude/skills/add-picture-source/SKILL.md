---
name: add-picture-source
description: Checklist for wiring a new picture source (a new generator or MandalaGenerator variant, like posed animals or posed plants) into this game's collages, kits, puzzle types, lab, saves and exports. Use when adding a picture type or source, or when finishing a generator that exists but isn't wired into the game or the lab.
---

# Adding a picture source

A picture source is line art (polylines in unit space) that the game turns
into collages and kits. The posed plants (`plant_mesh`) are the most complete
example; follow them. Grep for `plant_mesh` to see every place below.

## 1. The generator

- Returns the same shape as the others: `polylines`
  (`Array[PackedVector2Array]` in -1..1, y down), `closed`, and for free-form
  pictures `families` (one per polyline), `family_names` and `marks`
  (`[{at, family}]` inside areas). See `MandalaGenerator.generate`'s doc.
- Needs no nodes, so it runs on a `WorkerThreadPool` job.
- Has a JSON-safe replay token (a `recipe`) if it has many hidden choices, so
  saved puzzles regrow exactly. `PatternIO` keeps `source` values at full
  precision.

## 2. `gen/mandala.gd` (MandalaGenerator)

- Add the variant to `VARIANTS` and a `match` branch that calls the generator,
  sets `symmetry` and lists the `keys` saved as the picture's choices.
- Handle a generator that returns `{}` (bad options): return empty lines, never crash.
- Framing: decide whether it is framed by default (posed pictures aren't; see
  the `animal_mesh`/`plant_mesh` check before `FrameDesign.apply`).
- Narrow seed-picked choices to what reads well as gems (see `PLANT_PICTURE`
  and `_plant_options`): explicit options always win, unknown values are
  ignored rather than failing.
- An unframed free-form picture can take its own shape: set `aspect`
  (see `_fit_plant`); `PictureSources.mandala_lines` rasterizes to it.
- Document the variant's choices in `generate`'s doc comment.

## 3. `gen/picture_sources.gd`

- `mandala_collage`: add the variant to the list of keys copied into
  `opts["source"]` (this is what saves keep).
- Set the collage options the picture needs (setting, sparsity, aura,
  `separate_lines`...) only when the caller didn't, as the plant block does.
- If areas have roles (bold flowers vs quiet leaves), mark them in
  `mandala_lines` (`motifs["bold"]`) so both `mandala_collage` and
  `mandala_image` (kits) color by them.

## 4. The game

- `game/gem_catalog.gd`: an entry in `PUZZLES` (`name`, `source`, `variant`,
  `about`). Its id is saved in profiles: never rename it later (or add it to
  `Unlockables.RENAMED`). It becomes findable in packs automatically.
- `game/puzzle_maker.gd`: add posed/recipe sources to `POSED_VARIANTS` so kits
  keep the recipe in `picture["source"]`.
- Picture features (`PuzzleMaker.FEATURES`, `GemCatalog.FEATURES`): if the
  source has a flourish (like the plants' aura via `collar`), gate it on an
  existing feature and update that feature's `about` text.

## 5. The lab (`scenes/dev/generator_lab.gd`)

- The Shape dropdown lists `MandalaGenerator.VARIANTS` automatically; give it a
  readable label in `_options`.
- Add dropdowns for the source's main choices (pass them through `job` and
  `_run_job`'s `opts`) and a summary line under `"Collage"` in `_process`.

## 6. Exports and assets

- `export_presets.cfg`: both presets' `include_filter` must list the source's
  raw data files (`.dat`, credits). Resources reached by `preload` are
  exported anyway.

## 7. Tests, renders and docs

- A `tests/run_<source>_pictures.gd` like `run_plant_pictures.gd`: line art is
  deterministic, saved recipes replay through `PatternIO`, collages have
  stones and no overlaps, kits keep the recipe, the game's puzzle type and
  lab work, and the look rules you rely on (no sparse areas, colors by role...).
- Run `run-tests` with `@generators` (every variant is exercised there) plus the
  new suite, and fix what `test_collages` finds for the new variant.
- Render a sheet with `render-sheets` and look at it before calling it done.
- README: the file table row for the generator, the picture types list, the
  Diamond kits list, and the test/sheet commands.
