---
name: test-play-input
description: Reproduce and regression-test touch, pen and gesture behavior on the play screen (taps placing stones, strokes, double tap to fit, pinch and pan, carrying gems from the row, the stones limit, modal blocking) with a tiny made-up puzzle in tests/run_menu_ui.gd. Use when a player reports a gesture misbehaving (an unwanted zoom, a tap that doesn't place, a drag that pans instead of filling), before changing input code in scenes/game/play_screen.gd or render/gem_board_3d.gd, and to prove an input fix.
---

# Testing play-screen input

Touch handling is split between two places:

| Where | Handles |
| --- | --- |
| `render/gem_board_3d.gd` `_input` | Every touch on the board: pan, pinch, double tap to fit (`DOUBLE_TAP_MS`, `DOUBLE_TAP_SLOP`, `fit_filter`), and turning a touch into a stroke when `stroke_filter` says so |
| `scenes/game/play_screen.gd` | Strokes from the board (`_on_stroke_started`, `_on_stroke_moved`, `_fill_at`, slop `TAP_SLOP` / `DRAG_SLOP`), the gem row (`_input`: scroll, fling, tap to pick, drag up/down to carry), power-ups, the stones limit |
| `scenes/game/slot_overlay.gd` | Which slot is under a board point (`slot_at`, `slots_near`) |
| `scenes/game/app.gd` | Pen (S Pen) as touch: `Input.emulate_touch_from_mouse` |

Board touches work in the board control's px, and strokes and slots in
board units. `board.view_transform()` maps board units to control px, and
`screen_to_board()` does the reverse. The two slop sizes are screen px,
so at high zoom they cover fewer board units.

## Writing a test

Add a `_test_<name>()` to `tests/run_menu_ui.gd` and call it from `_run()`.
`_test_double_tap_fit` is a short model to copy:

1. Make a profile and a tiny puzzle by hand: a few `round` slots at known
   board points, two gem colors, `"type": "collage"`, a 100×100 board.
   Add it with `SaveStore.add_puzzle(profile, picture)`, then make a
   `PlayScreen`, set `profile` and `puzzle_id`, `root.add_child(play)` and
   `await _layout_frames()`.
2. Set up the state directly: `play._select(play._type_of[i])`,
   `board.reset_view()`, `board._zoom_at(board.size / 2.0, z)`.
3. Send real events with `_tap(at)`, `_pen(pressed, at)` and
   `_pen_move(at)`. They take a point in the stretched 1080×2400 canvas and
   convert it to window px with `root.get_final_transform()`. A slot's
   canvas point is
   `board.get_global_transform_with_canvas() * (board.view_transform() * Vector2(x, y))`.
4. Check what she would see: `play._overlay.placed[i]`, `play._filled`,
   `board._zoom`, `play._selected`, `play._carry`.
5. Clean up: `play.queue_free()`, `await process_frame`,
   `SaveStore.delete_puzzle(profile, meta["id"])`.

Traps:

- **Check that your points are on screen** after zooming. A slot outside
  the view gets no touch, and the test fails in a misleading way. Add a
  `_check` that the stones under test are inside `board.size`.
- **Stone sizes are in board units.** A "near miss" must be outside the
  outline (`size / 2 * board.scale_px()` px from the center) but within
  `TAP_SLOP`, or the tap simply places the stone.
- Each `_tap` press and release is one frame apart, so consecutive taps
  are well inside `DOUBLE_TAP_MS`. To test "slow" taps, `await
  create_timer(0.4).timeout` between them.
- Calling `play._input(event)` or `board._input(event)` directly skips
  the viewport's coordinate conversion. Use `Input.parse_input_event` (the
  helpers) unless the test is about one handler alone.
- Modal dialogs set `board.input_enabled = false`. Close them (`play.go_back()`)
  before testing board gestures.

## Proving the test

Make the test fail without the fix before trusting it. Disable just the fix
(for example, have the new filter return `true`), run the suite, see the
new checks fail, and restore the file. Don't check out the old version of a
whole file: other code may already depend on the new one.

Run it with the `run-tests` skill:

```bash
.claude/skills/run-tests/run_suites.sh --out <scratchpad>/tests-input menu_ui
```

`menu_ui` takes under a minute. Run `@ui` before committing.
