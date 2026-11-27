---
name: measure-board-performance
description: Measure what the 3D gem board (render/gem_board_3d.gd) draws per frame (triangles, draw calls, objects) for kits or mixed-shape boards at chosen zooms and fill levels, before and after a change. Use when a player reports lag, stutter or slow animations, before and after any change to the board, its shaders or its MultiMesh batching, and when choosing between rendering options.
---

# Measuring the board

There is no phone here, but Godot can render for real under `xvfb-run` with
Mesa's software OpenGL (`--rendering-driver opengl3`). The play screen's
board is a `SubViewport`, and the rendering server counts what each of its
renders draws. Those counts are what you compare. The milliseconds come
from a CPU rasterizer and mean nothing for a phone.

```bash
S=<scratchpad>
SCRATCH=$S .claude/skills/measure-board-performance/bench.sh -- --kit=large --zooms=1,6,20
SCRATCH=$S .claude/skills/measure-board-performance/bench.sh --ref origin/main -- --kit=large --zooms=1,6,20
```

The second line runs the same options against a worktree of `origin/main`
(made once under `$SCRATCH`, imported on first use). Print before and after
one after the other and compare the lines. Each run takes 10–60 s,
depending on the board size and `--frames`.

Options (all after `--`):

| Option | Meaning |
| --- | --- |
| `--kit=small\|medium\|large\|xlarge` | Kit grid, about the sizes `KitGenerator` makes (Large 100×130 = 13k drills, X-large 192×250 = 48k) |
| `--cols=N --rows=N` | Any grid instead |
| `--drill=round\|square` | Kit drill shape |
| `--shapes=round,oval,heart` | Mixed-shape stones on a grid, drawn with `show_collage`, standing in for a collage's many batches |
| `--zooms=1,6,20` | 1 is the whole picture, `MAX_ZOOM` is 40 |
| `--placed=0.5` | Share of stones shown; the rest are hidden the way unplaced stones are |
| `--debug_test="no shadows"` | One of `GemBoard3D.DEBUG_TESTS`, to see what a part costs |
| `--size=1080x1600`, `--frames=20` | Board size in px; renders averaged per zoom |

## Reading the numbers

- **Triangles** track vertex work, and **draw calls / objects** track CPU
  and driver overhead per render. Each `MultiMeshInstance3D` is one object
  and one draw call per pass. Since tiling (`_tiles`, `TILE_STONES`), a kit
  is about 30 objects per layer kind, and zoomed in only the tiles in view
  are counted.
- Whole-picture zoom on a big kit should stay low on triangles because tiny
  stones become impostors (`IMPOSTOR_PX`). If zoom 1 jumps, impostors
  stopped switching on.
- Zoomed in, triangles should fall with the view. If they don't, something
  draws off-screen stones (one big MultiMesh, or an AABB that's too big).
- Fragment cost (big stones filling the screen, shadows and sparkles
  overdrawing) doesn't show in these counts. Use `--debug_test` variants
  to see the effect, then confirm on a phone.
- The phone uses the Mobile (Vulkan) renderer and this uses Compatibility
  (OpenGL). Draw counts agree; shading cost doesn't.

## On her phone

Debug builds have a readout and switches for this (README, "performance
readout"):

- Hold the progress line ("12 / 340 gems") on the play screen to show
  frames per second, frame time, the board's renders a second, GPU time
  per render, triangles and draw calls.
- Settings → *Testing* → *Board test* draws puzzles opened after that
  with one part left out (no shadows, no sparkles, flat gems, MSAA 2×/off,
  half resolution, no impostors).

When she reports lag, ask for the readout's numbers in the situation she
describes (which puzzle size, zoomed in or out, during which animation),
and for one *Board test* that removes the part you suspect.

## When the board renders at all

The board only renders when a frame is due (`_schedule`): every frame while
anything moves (touches, pops, flights, glides, finale, the phone turning),
and `IDLE_FPS` times a second otherwise. "Slow while animating" usually
means the per-render cost is high, since every animated frame pays it. It
rarely means the animation code itself is slow. Check `_step_anims` and
`GemFlights` only if the counts look fine.

Put any output you keep in the scratchpad, never in the repo.
