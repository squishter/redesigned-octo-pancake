---
name: triage-player-report
description: Turn a player's report of a problem or wish (often relayed second-hand, voice-typed, in the game's own words, like "drills", "the row", "the finale", "it zooms out") into the code that does it, a likely cause, a check against which build they have, and a plan. Use whenever the user passes on what the player saw or wants, for bugs, slowness, confusing behavior or feature requests, before changing code.
---

# Triaging a player's report

Reports come second-hand and are often voice-typed ("anim a lions" means
animations; "drills" is a real word here). Work out what the player
actually did and saw, find the code that does it, and say what you found
in the player's terms.

## 1. Translate the words

| Player says | Means | Code |
| --- | --- | --- |
| drills, kit, diamond kit, the grid | A kit puzzle: one round or square drill per grid cell, Small to X-large (13k drills Large, ~48k X-large) | `gen/kit_generator.gd`, `GemBoard3D.show_kit`, `PuzzleMaker` |
| gems, stones, the picture | A collage puzzle's stones in slots | `gen/collage_generator.gd`, `GemBoard3D.show_collage` |
| the row, tray, cards up top, numbers | The gem row: one card per gem type with how many are left | `play_screen.gd` (`_palette`, `_row`, `_input`) |
| the numbers / circles on the board | Open slots of the picked gem, with their numbers | `scenes/game/slot_overlay.gd` |
| tapping / dragging in gems | Strokes: tap or drag places the picked gem | `play_screen.gd` `_on_stroke_*`, `_fill_at`; `GemBoard3D._input` |
| zoom, pinch, it zooms out, Fit | Pinch and pan, double tap to fit, the Fit button, hint glides | `GemBoard3D._input`, `reset_view`, `glide_to`, `focus_on` |
| how gems go in, animations, sparkles | Placement styles (pop, fly, comet, beam, …) | `GemCatalog.ANIMATIONS`, `gem_flights.gd`, `gem_placement_fx.gd` |
| the ending, the wave, celebration | The finale | `GemCatalog.FINALES`, `GemBoard3D.celebrate` |
| lines, outlines, paint | Kept lines painted like gems | `game/line_paint.gd`, `paper.gdshader` |
| power-ups, brush, finder, sprinkle | Power-ups | `GemCatalog.POWERS`, `play_screen.gd` `_use_power` |
| hint, the light bulb | Hint | `game/hints.gd`, `hint_button.gd` |
| packs, coins, picks, the shop | Packs and rewards | `game/packs.gd`, `pack_opening.gd`, `completion_rewards.gd` |
| color stories, themes, my colors | Themes and their own color stories | `GemCatalog.THEMES`, `game/custom_themes.gd`, `color_story_*.gd` |
| collection, gallery, finished ones | Collection screen; completed puzzles | `collection_screen.gd`, `completed_puzzles.gd` |
| lab, generator | The developer Gem Lab | `scenes/dev/generator_lab.gd` |
| it's slow, laggy, choppy | Board rendering per frame | the `measure-board-performance` skill |

`README.md` covers every file and has a section for each screen. Search
it for the player's word before searching the code.

## 2. Pin down what happened

From the report, write down:

- **Puzzle**: kit or collage, and its size.
- **View**: zoomed in or fitted.
- **How far along**: early or mostly filled. Placed stones cost more to
  draw than hidden ones.
- **The gesture or moment**: tap, drag, pinch, during a placement
  animation, during the finale.
- **Where on screen**, if they say so ("near the bottom"). That points at
  safe areas (`safe_area.gd`), Android's gesture edge, or controls laid
  over the board.
- **How often**: always, or sometimes. "Sometimes" usually means timing
  (double-tap windows, `BUZZ_GAP_MS`, flights still in the air) or a
  boundary (slop distances, the impostor switch).

If something that matters is missing and the code can't settle it, ask the
user one short question. Otherwise go with the likeliest reading and say
which one you took.

## 3. Which build do they have?

APKs from `tools/build_apk.sh` carry a build stamp (`BuildInfo`). The bottom
of Settings reads "Build 657adc2 · 27 Nov 2026 14:05 UTC", with "+ changes"
when the build had uncommitted work. Ask the user for that line. Builds
made before the stamp existed show no line: place them by the date they
were built or installed instead (`git rev-list -1 --before="<date>" origin/main`).

```bash
git fetch origin main
base=<commit from Settings>                            # or the dated rev-list above
git log --oneline "$base"..origin/main                 # everything since their build
git log --oneline "$base"..origin/main -- <files you found in step 1>
```

"+ changes" means some of what was built was never committed, so the
commit is only a close match. The `version/name` in `export_presets.cfg`
stays `0.1.0` and tells you nothing.

Tell the user whether something since then already addresses the report.
If nothing does, say so plainly, so they know updating alone won't help.

## 4. Find the cause before fixing

- Read the handler for the gesture end to end. Write down each condition
  that leads to the bad outcome and check it against step 2.
- Reproduce it:
  - gestures: `test-play-input`, a failing check in `tests/run_menu_ui.gd`
  - slowness: `measure-board-performance`, counts before and after
  - looks: `render-sheets`
- Fix the cause, not the symptom. Keep the behavior other players rely
  on (for example, double tap to fit still works off the stones, and the
  Fit button always works).

## 5. Report back

Write for someone passing it on to the player: what was happening in their
terms ("two quick taps that didn't place a drill counted as a double tap"),
what changes for them, and anything they could try or check on the phone.
Debug builds have the performance readout (hold the progress line) and
Settings → *Testing* → *Board test*. Add the branch and commit, and what
was tested and what wasn't.
