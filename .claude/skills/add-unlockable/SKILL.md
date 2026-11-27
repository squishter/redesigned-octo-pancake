---
name: add-unlockable
description: Checklist for adding an unlockable item to the game (a gem color or shimmer stone, a color theme, a placement animation, a finale, a line finish, a power-up, a picture feature or flourish), or a whole new kind of unlockable, so packs, Collection, Settings, saves and tests all pick it up. Use whenever adding to GemCatalog's lists or Unlockables, or when the user asks for a new animation, finale, finish, power-up, color or theme. New picture types use add-picture-source instead.
---

# Adding an unlockable

`game/unlockables.gd` explains the rules at the top. Its `KINDS` table
connects each kind to its profile list and its pack. Most kinds need two
things: a catalog entry in `game/gem_catalog.gd`, and the code that makes
the item do something. Once it's in the catalog, packs offer it,
Collection lists it and Settings shows it, with no further wiring.

Rules that protect players' saves (see CLAUDE.md):

- **Never rename or reuse an id.** Profiles store ids. To rename, map
  `"kind:old": "new"` in `Unlockables.RENAMED`.
- To make an item a starting item, add it to the kind's `STARTING_` list.
  Existing players get it on their next start (`normalize()`).
- Saved puzzles keep every stone's shape, cut and color, so new items never
  change old puzzles. Changing an existing item's look or color does change
  them, so add a new item instead.

## Per kind

| Kind | Catalog entry | Also wire up |
| --- | --- | --- |
| Gem color | `EXTRA_COLORS`: `{id, name, color, hue}` with hue in `HUE_ORDER` | Opaque stone: add to `GemBoard3D.OPAQUE_GEMS` (only ever add). Shimmer stone: `"hue": "shimmer", "finish": <finish>`, with the finish in `GemBoard3D.FINISH_ALPHA` and its look in `render/gem_body.gdshaderinc` (a new finish is shader work, so render it) |
| Color theme | `THEMES`: `{name, gems}`, 3–8 existing color ids, neighbors that look good together | Nothing: a theme unlocks once she has all its colors |
| Placement animation | `ANIMATIONS`: `{name, about}` | `PlayScreen.FILL_STYLES` and the `match` in `_fill`. The motion goes in `scenes/game/gem_flights.gd` (flights; `FX_STYLES` and `SHOWN_AT_END` for effect-only styles), and effects in `gem_placement_fx.gd`. Add it to `STYLES` in `tests/run_placements.gd` |
| Finale | `FINALES`: `{name, about}`; light versions are `light_<base>` | `GemBoard3D.FINALES`. A new wave shape needs `WAVE_KINDS` (its index goes to the shaders as `wave_kind`) plus the wave code in `render/paper.gdshader` and the gem shaders. `run_menu_ui` checks every base has a light version |
| Line finish | `LINE_FINISHES`: `{name, about}` | `GemBoard3D.LINE_FINISHES`, **same order as the catalog** (the index is `line_finish` in `render/paper.gdshader`; add the `if (line_finish == N)` branch there). `run_menu_ui` checks the order |
| Power-up | `POWERS`: `{name, kind: "puzzle" or "now", about}` | `PlayScreen.POWER_EFFECTS`. `"puzzle"` ones are checked with `_has_power(id)` where they act; `"now"` ones get a branch in `_use_power`'s `match`. Charges come from `Unlockables.NOW_CHARGES` / `PUZZLE_CHARGES` |
| Feature (flourish) | `FEATURES`: `{name, about}` | `PuzzleMaker.FEATURES` and where `make()` uses it |
| Shape or cut | `ALL_SHAPES`, `GemCuts.BY_SHAPE` | Outline in `gen/gem_shapes.gd`, a `GemVariety` family, `GemCuts.SHADER_STYLE` for a cut. This is geometry work: run `@gems` and render stones |
| New kind | A row in `Unlockables.KINDS` and its items in `items()` / `starting()` | A pack in `Packs.PACKS` if a pack gives it; how it's chosen and used in Settings (`settings_dialog.gd` `_setting(...)`) or play |

`tests/run_generators.gd` has a "Catalog complete" check that fails when
any catalog item isn't handled by the game (`handled` lists the code-side
arrays above), lacks a name or about text, or is a starting item missing
from its catalog. Starting the full suite takes 10–12 minutes, so for a
quick catalog-only check, run the catalog block alone (copy it into a
scratch script) or run `generators` in the background while you work.

## Names and wording

`name` is short and title-case ("Light sweep"). `about` is one plain
sentence saying what she will see ("A band of light crosses from one side to
the other, and every gem it passes flashes."). Pack reveals use
`KINDS[kind]["found"]`.

## Checking it

1. Run `godot --headless --check-only -s <changed script>` on each
   changed script.
2. Run the suites with `run-tests`: `@ui` and `generators` for any catalog
   change, plus `placements` for an animation and `@gems` for colors,
   finishes or shapes.
3. If it changes how anything looks (a color, finish, line finish,
   animation or finale), render it with `render-sheets` and look before
   calling it done. `tests/render_menu_ui.gd` captures the real screens
   (Collection, packs, power-ups) under
   `xvfb-run -a godot --path . --resolution 1080x2400 -s res://tests/render_menu_ui.gd`.
   For line finishes, render a picture with kept lines.
4. To try it in the game, debug builds have *Unlock everything* in
   Settings (README, "Unlock everything"; `run_menu_ui`'s `_test_unlock_all`).
