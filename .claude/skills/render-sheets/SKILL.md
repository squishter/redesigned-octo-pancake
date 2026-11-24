---
name: render-sheets
description: Render pictures from this project's generators and stitch them into one comparison image to look at. Use whenever a change affects how pictures look (plants, auras, colors, layouts, patterns, frames), to compare options or before/after, or when the user asks for renders, previews or examples.
---

# Rendering pictures to look at

Changes to how pictures look are judged by eye. Render a handful of seeds,
look at them with the Read tool, and send the user the result with
SendUserFile. Keep all output in the session scratchpad.

## Plants: compare option sets side by side

```bash
.claude/skills/render-sheets/compare.sh --out <scratchpad>/cmp-<label> --seeds 31,4 --cell 512 \
    "halo: --collar=halo --theme=garden" \
    "streams: --collar=streams --theme=garden"
```

- One row per `"NAME: options"` set, the same seeds in each. Sets render in
  parallel; four seeds take about 30 seconds.
- Options are anything `tests/plant_sheet.gd` or the picture takes:
  `--collar=streams|veil|halo|none`, `--theme=<Palettes theme>`,
  `--layout=cluster|fine|dense|classic`, `--flower=rose`, `--leaf=fern`,
  `--camera=front`, `--plant_min_region=0`, `--plant_natural=true`.
- `--take collage` (default) keeps the collage cells, `lines` the painted line
  art, `both` the pairs.
- Output: `<out>/compare.png`, plus `compare_small.png` (2000 px wide) when the
  full one is wider. Read the small one; send the full one to the user.
- Good seeds to start from: 1–4 (camellia, lotus, lavender, sunflower) and
  31–34 (calla, hydrangea, anemone, orchid). Thin plants like lavender are the
  hardest case; hydrangeas test small-patch folding.

## Before and after a code change

Render the "before" first, at the commit before the change, into its own
folder: either before editing, or from a worktree of `main`:

```bash
git worktree add <scratchpad>/wt-main origin/main
(cd <scratchpad>/wt-main && godot --headless --editor --import --quit >/dev/null 2>&1 &&
 godot --headless -s res://tests/plant_sheet.gd -- --out=<scratchpad>/before --seeds=31,4 --cell=512)
```

Then render "after" in the repo and stitch both sheets, a row each:

```bash
python3 .claude/skills/render-sheets/stitch.py --out <scratchpad>/before-after.png --cell 512 \
    <scratchpad>/before/plants_31.png <scratchpad>/cmp-x/after/plants_31.png
```

Remove the worktree afterwards with `git worktree remove`.

## Other pictures

- Collages of any variant, several pattern seeds each:
  `godot --headless -s res://tests/collage_sheet.gd -- --out=DIR --seeds=1000,1003 --patterns=3 [--layout=both]`
  writes one PNG per collage; pass several to `stitch.py` to put them in a row each.
- Animals' or plants' painted line art:
  `godot --headless -s res://tests/animal_sheet.gd -- --out=DIR --seeds=1,12 [--variant=animal_mesh|plant_mesh] [--cell=320]`
- `stitch.py` takes any PNGs: plant sheets are cut into cells, anything else is
  used whole.

## Looking at the result

- The Read tool shows images scaled down to about 2000 px wide. For detail,
  render fewer seeds at a bigger `--cell` rather than zooming a big sheet.
- Collage renders use the game's warm paper for plants (`plant_sheet.gd`) and
  a dark velvet for `collage_sheet.gd`; the real game draws gems in 3D, so
  check proportions and colors, not shading.
- Say what you see (and what still looks weak) when you send renders, and
  caption which row is which.
