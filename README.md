# Paint With Gems

A cozy Android game in Godot 4.7 where you place sparkly gems to make pretty
pictures. There are no timers, no fail states and no ads. There are two modes:

- **Diamond Kit:** a picture becomes a numbered grid of round or square drills.
- **Gem Collage:** line art becomes regions packed with gem slots of mixed
  shapes, set in metal lines.

This first step is the **puzzle generators**: pure-logic GDScript in `gen/`
that turns a source picture into a playable puzzle for either mode.

## Picture sources → puzzles

| Source | Kit mode | Collage mode |
| --- | --- | --- |
| Seeded mandala | `PictureSources.mandala_image()` → `KitGenerator.generate()` | `PictureSources.mandala_collage()` |
| Photo | `KitGenerator.generate(photo)` | `PictureSources.photo_collage()` |
| Bundled line art | render with its colors → `KitGenerator.generate()` | `PictureSources.line_art_collage()` |

## Generators (`gen/`)

| Script | What it does |
| --- | --- |
| `mandala.gd` | Seeded symmetric line art as vector polylines: picks the generator for each variant (mandalas from `mandala_design.gd`, flowers from `flower.gd`), 6-fold snowflakes (from `snowflake.gd`), and mirror-only hearts (from `heart.gd`) and butterflies (from `butterfly.gd`). An optional *wobble* makes it look hand-drawn while every region stays closed. |
| `mandala_design.gd` | Mandalas: a center (rosette, star, nested, seeds), 3–6 **rings** and an outer **silhouette** (circle, scalloped, polygon, star, petal edge, sun rays, beaded rim), repeated 6–32 times around. Each ring is either one of 7 singular patterns (lattice, zigzag, weave, spokes, wave, bricks, chain) or a combination of layers: something rising from its inner circle (petals, arches, teeth, tulips), something hanging from its outer circle (scallops, drips, bells) and floating shapes (dots, diamonds, rings, teardrops), sized so they never collide or get too thin. 45% get **extras** outside (satellites, sparkles, corner fans, a frame, rays). 5% are **zoomed in**: drawn twice as big with the center near a corner and cropped to a frame, so the picture shows about a quarter of the mandala with the usual stone sizes. Pass `recent` to skip recent choices and favor the least used. |
| `flower.gd` | Flowers from 7 petal templates, each with its own petal-count range drawn uniformly: oval (daisy, 8–16), pointed (lily, 5–12), heart notch (cosmos, 5–8), wide fan (rose, 4–7), fringed tip (carnation, 6–10), thin ray (aster, 18–36) and spoon (gerbera, 8–14). Each flower has 1–4 rings, and each ring mixes 2 or 3 wobbled versions of its template (length, width, tip, curl and skew varied) in a symmetric ABAB, ABCABC or mirrored order. Inner rings are 0.55–0.8 the size of the ring outside, rotated half a petal, and sometimes use another template. Petals overlap like a pinwheel with hidden lines clipped, so every region stays closed. Centers are a seed spiral, stamens, nested circles or a star. Pass `recent` (the templates of the previous flowers) to skip the last 2 and favor the least used, so a run of flowers covers every template. |
| `heart.gd` | Hearts from three choices. **Shape:** 6 outline proportions (classic, plump, slim, sweetheart with a deep cleft, puffy, pointed), each varied slightly. **Collar:** a band just inside the outline, made by a true inward offset so it stays even: plain, rays, beads, scallops, petals, double or none. **Inside:** 1–3 combined patterns, from 4 center motifs (heart, double heart with spokes, flower, rosette) and 8 fills (stripes, chevrons, diamond lattice, rays, waves, dots, grid, echoes of the motif's outline). Two fills split the heart along a mirrored divider (straight, arc, wave or V); fills flow around the motif, so every region stays closed. Everything is mirror-symmetric. Pass `recent` (the previous hearts' choices) to skip recent ones and favor the least used. |
| `butterfly.gd` | Butterflies from: 7 **wing shapes** (classic, swallowtail with tail paddles, rounded, glider, scalloped edges, moth, fairy with big hindwings), 5 **borders** along the wing edges (band, spotted, scalloped, cells, none), and 1–3 **wing patterns** per wing, chosen separately for forewing and hindwing: holes (eyespot, window) and, flowing around them, veins, rings, stripes, scattered spots or a row of dots. Plus 3 **bodies** (slender, plump, segmented) and 3 **antennae** (clubbed, curled, feathered). The forewing overlaps the hindwing and the body both, with hidden lines clipped so every region stays closed. Built on the right and mirrored. Pass `recent` to skip recent choices and favor the least used. |
| `snowflake.gd` | Six-fold snowflakes from: 6 **centers** (hexagon, nested, star, rosette, spoked, flower), 7 **arm styles** (plain, branched, fern, plates, arrows, spear, crystal), 5 **tips** (point, plate, diamond, fork, ring), **content between the arms** (stellar plate, webs, spikes, petals, diamonds or dots; one or two kinds on all but about 8% of snowflakes) and 0–2 **details** (ribs, dots, inner outlines). Arms, branches, webs and plates merge into one clean silhouette; centers, plates, tips and petals keep their own outlines, so every region stays closed. Pass `recent` to skip recent choices and favor the least used. |
| `kit_generator.gd` | Kit pipeline: crop to the board aspect, area-average downscale (40×50 / 70×90 / 100×130), k-means in Lab, snap to the gem colors she owns (only those), clean up isolated cells, then build a legend with a symbol per color. |
| `color_quantizer.gd`, `lab_color.gd` | Weighted k-means++ in Lab over a color histogram, plus sRGB ↔ Lab conversion. |
| `line_raster.gd` | Polylines or line-art images → line masks; dilation to close gaps. |
| `region_map.gd` | Flood-fills closed regions, merges tiny ones into the lines, and computes a chamfer distance transform with per-region stats (area, centroid, elongation, principal axis, deepest point). |
| `slot_packer.gd` | Greedy capsule packing on a "free distance" field: the biggest stone that fits goes where the field peaks, until the region is about 80% covered. Fill styles are cabochon, pavé, petals, flow and mosaic, with an optional rhinestone outline. |
| `design_plan.gd` | Per-design variety, decided per symmetry group so symmetric copies match. **Fills:** some groups are made sparse on purpose (*scatter*: a few spaced-out stones; *accent*: one stone; *outline*: a rhinestone border only; *bare*: empty negative space). At most 60% of the area goes sparse and 30% bare, and something always stays fully packed. **Line styles:** *full*, *partial* (only some groups' borders), *outer* (silhouette only) or *none* (stones alone). Hidden lines still separate regions for packing; they just aren't drawn. Both are picked per seed unless `sparsity` (0..1) or `line_style` is passed. |
| `region_paint.gd` | Finds symmetric copies of regions so they share theme colors, samples region colors from photos, snaps to gems, and renders flat images. |
| `photo_line_art.gd` | Photo → closed line art: blur, quantize to 6–10 colors, majority filter, merge small areas, then trace the color boundaries. |
| `collage_generator.gd` | Turns a mask into the full collage puzzle (regions, groups, slots and target colors). |
| `picture_sources.gd` | Convenience entry points for each source. |
| `pattern_io.gd` | JSON save and load (colors as hex, grids as base64). |
| `gem_shapes.gd` | Outline polygons for slot shapes (round, oval, teardrop, marquise, baguette, square, hexagon, triangle). |
| `palettes.gd` | 24 starter gem colors and theme palettes, used until `GemDB` exists. |

The generators touch no nodes, so they can run on `WorkerThreadPool`.

### Puzzle formats

Kit: `{type: "kit", width, height, drill, palette: [{symbol, color, gem_color_id, count}], cells}`.
`cells` holds one palette index per cell, row-major.

Collage: `{type: "collage", width, height, symmetry, line_style, sparsity, source, lines, lines_visible, regions, slots}`.
`lines` is every region boundary and `lines_visible` is the part drawn as the
metal setting. Each region has a `fill` (full, scatter, accent, outline or
bare) and `outlined`.
Each slot is `{id, region, shape, x, y, rotation, size, width, target_color, target_gem}`,
in pixels of `width × height`. `size` is the length along `rotation`. Regions
that share a `group` are symmetric copies of each other.

## Trying it

- Open the project in Godot 4.7. The main scene, `scenes/dev/generator_lab.tscn`,
  is a dev screen. Pick a mandala shape, theme, seed and wobble, or load a
  photo. Then view it as a collage, a kit or plain line art, and save the JSON.
- Headless checks with preview PNGs. The checks cover 20 seeds across all
  shapes, contact sheets of 24 mandalas (every silhouette, center, extra and
  ring pattern, two zoomed in), 24 flowers in a row (every template, no repeats
  within 2, varied petal counts), 24 hearts (every shape, collar and
  pattern, mostly combined, mirror-symmetric) and 24 butterflies (every
  wing shape, border, pattern, body and antenna style, mirror-symmetric) and
  24 snowflakes (every center, arm, tip, in-between and detail, nearly all
  with content between the arms), overlaps, coverage, slots spilling onto
  lines, kits at every size (owned colors only), photo line art and a JSON
  round trip:

  ```sh
  godot --headless --import
  godot --headless -s res://tests/run_generators.gd -- --out=/tmp/previews --seeds=20
  ```

Lint with [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit): `gdlint gen scenes tests`.
