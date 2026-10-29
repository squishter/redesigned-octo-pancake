# Paint With Gems

A cozy Android game in Godot 4.7 where you place sparkly gems to make pretty
pictures. There are no timers, no fail states and no ads. There are two modes:

- **Diamond Kit:** a picture becomes a numbered grid of round or square drills.
- **Gem Collage:** line art becomes gem slots laid out in patterns. Most
  pictures turn the lines themselves into rows of slotted gems; some keep
  them as a metal setting. One line art makes many collages: change the
  `pattern_seed`.

So far there are the **puzzle generators**: pure-logic GDScript in `gen/`
that turns a source picture into a playable puzzle for either mode, and the
**3D board** in `render/` that shows a puzzle as real faceted gems.

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
| `frame_design.gd` | Frames and backgrounds for any generated picture; about 3 in 4 are framed (zoomed-in mandalas and ones with their own frame or corner fans aren't). A frame combines a **shape** (square, rounded, circle, octagon, arch, hexagon, oval), a **band** (plain, double, beaded, rope, segments, scallops, braid, weave) and **corners** (none, block, circle, diamond, rosette): 280 frames. A **background** can fill the space between frame and picture (plain, stripes, grid, lattice, rays, rings, waves, polka, sparkles); backgrounds are spaced wider than the pictures' own patterns so they stay calmer. A halo outline around the picture stops the background, so every region stays closed. Everything mirrors across the vertical and shares the shape's turns: outlines start on the vertical axis, beads, ticks and zigzags come in even multiples of the shape's folds (4 for square, rounded, octagon and circle; 6 for hexagon; 2 for oval; 1 for arch), stripes run across or along the vertical and dots sit on a grid centered on the picture. Options: `frame` (true/false), `frame_shape`, `frame_band`, `frame_corner`, `background`, `frame_recent`. |
| `mandala_design.gd` | Mandalas: a center (rosette, star, nested, seeds), 3–6 **rings** and an outer **silhouette** (circle, scalloped, polygon, star, petal edge, sun rays, beaded rim), repeated 6–32 times around. Each ring is either one of 7 singular patterns (lattice, zigzag, weave, spokes, wave, bricks, chain) or a combination of layers: something rising from its inner circle (petals, arches, teeth, tulips), something hanging from its outer circle (scallops, drips, bells) and floating shapes (dots, diamonds, rings, teardrops), sized so they never collide or get too thin. 45% get **extras** outside (satellites, sparkles, corner fans, a frame, rays). 5% are **zoomed in**: drawn twice as big with the center near a corner and cropped to a frame, so the picture shows about a quarter of the mandala with the usual stone sizes. Pass `recent` to skip recent choices and favor the least used. |
| `flower.gd` | Flowers from 7 petal templates, each with its own petal-count range drawn uniformly: oval (daisy, 8–16), pointed (lily, 5–12), heart notch (cosmos, 5–8), wide fan (rose, 4–7), fringed tip (carnation, 6–10), thin ray (aster, 18–36) and spoon (gerbera, 8–14). Each flower has 1–4 rings, 0.55–0.8 the size of the ring outside, rotated half a petal, and sometimes using another template. About 4 in 5 flowers **repeat around**: a ring of 6 or more (an even count) alternates 2 wobbled versions of its template (length, width, tip, curl and skew varied, ABAB), others repeat one, and inner rings' petal counts keep the turns of the first ring (all of them where a count fits, else at least 4), as does the center. The rest are **free-form**: each ring mixes 2 or 3 versions (ABAB, ABCABC or a mirrored order for odd counts) and picks its own petal count. `symmetric` (true/false) forces either. Petals overlap like a pinwheel with hidden lines clipped, so every region stays closed. Centers are seed dots (two staggered rings, or a spiral on free-form flowers), stamens, nested circles or a star. Pass `recent` (the templates of the previous flowers) to skip the last 2 and favor the least used, so a run of flowers covers every template. |
| `heart.gd` | Hearts from three choices. **Shape:** 6 outline proportions (classic, plump, slim, sweetheart with a deep cleft, puffy, pointed), each varied slightly. **Collar:** a band just inside the outline, made by a true inward offset so it stays even: plain, rays, beads, scallops, petals, double or none. **Inside:** 1–3 combined patterns, from 4 center motifs (heart, double heart with spokes, flower, rosette) and 8 fills (stripes, chevrons, diamond lattice, rays, waves, dots, grid, echoes of the motif's outline). Two fills split the heart along a mirrored divider (straight, arc, wave or V); fills flow around the motif, so every region stays closed. Everything is mirror-symmetric. Pass `recent` (the previous hearts' choices) to skip recent ones and favor the least used. |
| `butterfly.gd` | Butterflies from: 7 **wing shapes** (classic, swallowtail with tail paddles, rounded, glider, scalloped edges, moth, fairy with big hindwings), 5 **borders** along the wing edges (band, spotted, scalloped, cells, none), and 1–3 **wing patterns** per wing, chosen separately for forewing and hindwing: holes (eyespot, window) and, flowing around them, veins, rings, stripes, scattered spots or a row of dots. Plus 3 **bodies** (slender, plump, segmented) and 3 **antennae** (clubbed, curled, feathered). The forewing overlaps the hindwing and the body both, with hidden lines clipped so every region stays closed. Built on the right and mirrored. Pass `recent` to skip recent choices and favor the least used. |
| `snowflake.gd` | Six-fold snowflakes from: 6 **centers** (hexagon, nested, star, rosette, spoked, flower), 7 **arm styles** (plain, branched, fern, plates, arrows, spear, crystal), 5 **tips** (point, plate, diamond, fork, ring), **content between the arms** (stellar plate, webs, spikes, petals, diamonds or dots; one or two kinds on all but about 8% of snowflakes) and 0–2 **details** (ribs, dots, inner outlines). Arms, branches, webs and plates merge into one clean silhouette; centers, plates, tips and petals keep their own outlines, so every region stays closed. Pass `recent` to skip recent choices and favor the least used. |
| `kit_generator.gd` | Kit pipeline: crop to the board aspect, area-average downscale (40×50 / 70×90 / 100×130), k-means in Lab, snap to the gem colors she owns (only those), clean up isolated cells, then build a legend with a symbol per color. |
| `color_quantizer.gd`, `lab_color.gd` | Weighted k-means++ in Lab over a color histogram, plus sRGB ↔ Lab conversion. |
| `line_raster.gd` | Polylines or line-art images → line masks; dilation to close gaps; carving channels around line stones. |
| `contours.gd` | Vector paths from rasters: iso-lines of a region's edge distance (marching squares) and centerlines of a line mask (thinning, spur pruning, split at junctions). |
| `gem_variety.gd` | Steers each collage to 25–30 **gem types** (a shape in one of its cuts in a gem color; sizes don't count) and gives every stone its `cut`: each shape in a color starts with its own seeded cut. It changes whole pattern parts (one row, one ring, the center stones, one symmetry class of lines) across symmetric copies, so every row and every line keeps a single type: first a sibling shape (round ↔ cushion ↔ octagon ↔ hexagon ↔ flower ↔ square ↔ pentagon ↔ heart ↔ trillion ↔ triangle ↔ star, oval ↔ marquise ↔ lozenge ↔ kite ↔ teardrop, which fit the same slot), then another cut of the same shape, then a color, choosing colors the picture already uses before harmonious new ones. Too many types fold into common ones. If a picture is still short, it is rebuilt with **spacer rows** (thin rows of small stones between the main rows) to give it more rows to vary. |
| `gem_lines.gd` | Gem lines: stones slotted along every line's centerline, one on each junction, evenly spaced between, narrowing toward loose ends. 12 styles: beads, pearls (big/small), marquise, baguette, emerald (clipped-corner step cuts), lozenge, taper (swells mid-stroke), pulse (grows and shrinks in waves from the middle of each line), ramp (grows outward along some classes of lines and inward along others; lines that run around the center swell or pinch instead), radial (shrinks toward the picture's center) and hub (shrinks toward the nearest hub where 4+ lines meet). Lines carry on through junctions where they continue nearly straight (**strokes**), and sizes change along a whole stroke; in the styles of one size, 60% of longer strokes grow, shrink or swell too (0.35× to 1.45× the line stone), so runs of stones change size as they go. Each line's stones are sized to the room beside it (down to 0.35× the line stone), so short lines in fine details carry stones too, and junction stones are no bigger than their smallest line's; a last pass adds a stone wherever one still fits along a line. The channel around the stones is carved to their sizes, so a line is as wide as its stones at every point. Lines that are symmetric copies (same distance from the center and length) form one class, so a ring of lines can take its own gem type. About 1 in 5 classes of longer lines (10+ stones) instead repeat a short **sequence** of gem types: 1-2, 1-2-2, 1-1-2, 1-1-2-2, 1-2-2-2, 1-2-3, 1-2-3-2, 1-2-1-3 or the wave 1-2-2-3-3-2-2-1 (never more than 3 types), counted from both ends toward the middle so it reads the same either way (loops only alternate 1-2). Each step gets its own color, and the variety pass never merges steps. 2 or 3 classes of **bold lines** through the middle of the picture (spread from the center outward, where the areas beside have room; a little further out when the middle has too few) take medium or large stones (1.7× or 2.3×) in the line's accent color, to break up the run of small stones there. A line is laid out once and its symmetric copies copy its stones (by the rotation or reflection that carries it onto them), junctions included (each set of matching junctions snapped to one radius and angle), so copies match stone for stone; loops around the center take a multiple of the symmetry around them, starting on a mirror axis. Finally `line_mirror.gd` makes all line stones exactly as symmetric as the line art: band by band around the center, each band's folds and mirror axis are read from the line art, one wedge's stones are kept and repeated around (mirrored across the vertical axis for hearts and butterflies). |
| `region_map.gd` | Flood-fills closed regions, merges tiny ones into the lines (except one holding a given point: collages keep a symmetric picture's center), and computes a chamfer distance transform with per-region stats (area, centroid, elongation, principal axis, deepest point). |
| `slot_packer.gd` | Patterned fills, chosen per symmetry group so copies match. **echo**: rows of stones following the outline inward (round, hexagon, square, cushion, octagon, flower, heart, marquise, lozenge or oval; optionally alternating big/small rows, or graded smaller or bigger row by row); **halo**: 1–2 outline rows around a big center stone shaped to the region (round, cushion, octagon, heart, flower, star, trillion or pentagon; marquise, oval, lozenge or kite when the region is long); **rosette**: center stone, ring of teardrops (or kites or marquises), outline rows; **honeycomb**: an even lattice (round, hexagon, flower or cushion stones) lined up with the region's axis, optionally graded smaller toward the rim; **stripes**: straight parallel rows, optionally graded from the middle; **sunburst**: a center stone with spokes of stones growing outward; **spine**: a chain along the region's medial axis, each stone as wide as the region there, so petals taper; **solitaire**: one shaped stone; **pave**: the old free-form packing, kept for some variety. Patterns can use the region's accent color (alternate rows, outer row or center stone), and a picture can shrink all its stones toward its center. Every stone shrinks to the room left where it lands (a "free distance" field), down to a quarter of a stone unit in thin places, or is left out. **Symmetry** (see `slot_mirror.gd`): a region is packed once and its symmetric copies get the same stones; a region that mirrors onto itself gets a mirror-symmetric pattern, with single stones (accents, centers, big tier stones) on its axis; a region around the picture's center repeats one wedge all the way round, and its rows take a multiple of its folds; the region holding the center, when at most 3 stone units deep, gets one centerpiece stone of any center shape, standing upright (a heart point down, a star or pentagon point up; hearts elsewhere follow their pattern). Some groups get **spacer rows** between their main rows. Some pattern seeds are **tiered**: groups first get one large stone in a feature color, then a few medium ones (round, hexagon, square, cushion, octagon, heart, star, flower, oval, marquise or kite), and their pattern fills around them. |
| `line_mirror.gd` | Makes gem-line stones as symmetric as the line art: thinning traces small curly shapes a pixel or two differently on each copy, so in bands around the center it keeps one wedge's stones and repeats them by the band's own symmetry (read from the line art), snapping stones on a mirror axis onto it. Symmetric line channels let the areas between them copy cleanly too. |
| `symmetry.gd` | Symmetry geometry shared by the packer and gem lines: the rotation or reflection about the picture's center that carries one region or line onto another (or a region onto itself), how a stone turns under it, and the folds and mirror axis of a ring around the center. |
| `slot_mirror.gd` | Keeps `SlotPacker`'s patterns symmetric: each group's middle-sized region is packed and its stones copied onto its symmetric copies (copies a little bigger or smaller still take them), and a region that maps onto itself is made as symmetric as it is: a region around the center takes its folds and mirror axis from the line art around it (looking further out while those lines are only circles), as its own edge may be carved a pixel off by gem lines (falling back to the pattern as packed where the region is only roughly symmetric). |
| `slot_patterns.gd` | Two of `SlotPacker`'s patterns (stripes and sunburst), kept in their own file to keep the packer's short. |
| `design_plan.gd` | Per-design variety, decided per symmetry group so symmetric copies match. **Fills:** some groups are made sparse on purpose (*scatter*: a few spaced-out stones; *accent*: one stone that nearly fills a compact region; *outline*: a rhinestone border only; *bare*: empty negative space). At most 60% of the area goes sparse and 30% bare (only regions at least 2 stone units deep, so bare reads as negative space rather than a gap), and something always stays fully packed. **Line styles:** *full*, *partial* (only some groups' borders), *outer* (silhouette only) or *none* (stones alone). Hidden lines still separate regions for packing; they just aren't drawn. Both are picked per seed unless `sparsity` (0..1) or `line_style` is passed. |
| `region_paint.gd` | Finds symmetric copies of regions so they share theme colors, samples region colors from photos, snaps to gems, and renders flat images. |
| `photo_line_art.gd` | Photo → closed line art: blur, quantize to 6–10 colors, majority filter, merge small areas, then trace the color boundaries. |
| `collage_generator.gd` | Turns a mask into the full collage puzzle (regions, groups, slots and target colors). Picks the **setting** per pattern seed: *gems* (about 3 in 4; lines become gem lines, sized to how roomy the areas are, colored in one or two sparkly neutrals or each in the accent color of the area it borders; area stones sit as close to them as to each other) or *metal* (lines drawn as before). `pattern_seed` reseeds everything but the lines. The stone unit (a base stone's radius) is 0.75% of the picture's shorter side, so the line art's details are bigger than its stones, with 0.3 of a unit between stones. Collages land at 300–6000 stones. Over that, the element with the most stones (a class of gem lines or a group of areas, with all its symmetric copies) is left out as a symmetric gap, up to 6 times, before the stone unit is rescaled; under 300 the unit shrinks. |
| `picture_sources.gd` | Convenience entry points for each source. |
| `pattern_io.gd` | JSON save and load (colors as hex, grids as base64). |
| `gem_cuts.gd` | The 3D **cuts** each shape comes in, so one outline makes several gem types: *brilliant* (a table ringed by kite and star facets), *step* (flat steps like an emerald cut), *rose* (a dome of triangles to a point), *checker* (a low dome of many small facets) and *cabochon* (a smooth dome). Each shape lists its classic cut first; a gem type takes it half the time. |
| `gem_shapes.gd` | Outline polygons for slot shapes. Fit a circle: round, square, hexagon, triangle, cushion, octagon (asscher), pentagon, heart, trillion, star, flower (rose cut). Fit a capsule: oval, teardrop (pear), marquise, kite, lozenge. Fill their box (gem lines only): baguette, emerald. |
| `palettes.gd` | 24 starter gem colors and theme palettes, used until `GemDB` exists. |

The generators touch no nodes, so they can run on `WorkerThreadPool`.

### Puzzle formats

Kit: `{type: "kit", width, height, drill, palette: [{symbol, color, gem_color_id, count}], cells}`.
`cells` holds one palette index per cell, row-major.

Collage: `{type: "collage", version: 2, width, height, symmetry, setting, pattern_seed, line_gems, line_colors, bold_lines, dropped, radial_size, tiers, unit, gem_types, gem_kinds, line_style, sparsity, source, lines, lines_visible, regions, slots}`.
`lines` is every region boundary (with gem lines, the channel the line stones
sit in) and `lines_visible` is the part drawn as the metal setting (none with
gem lines). Each region has a `kind` (`area`, or `line` for gem-line stones),
a `fill` (full, scatter, accent, outline, bare; `line` for line regions),
`style` (its pattern), `color`, `accent_color` and `feature_color`, and `outlined`.
Each slot is `{id, region, shape, cut, x, y, rotation, size, width, tone, part, target_color, target_gem}`
(line stones also carry `seq`: their step in a line sequence, or -1),
in pixels of `width × height`. `size` is the length along `rotation`; `tone`
says which region color the pattern meant (0 main, 1 accent, 2 feature) and
`part` which pattern step placed it, but `target_color`/`target_gem` are the
final word (the variety pass may change them, and sets `cut`). `gem_kinds`
lists every gem type (shape, cut and color) with its stone count. Regions that share a `group` are symmetric
copies of each other.

## Rendering (`render/`)

The board in 3D: real faceted gems on white paper, under a fixed camera
looking straight down. The light drifts slowly over time and hangs still in
the room while the phone moves: tilting, rolling or turning it (in any pose,
upright too) moves the light across the stones, so facets catch it, glint
and flare into star sparkles. Turns count twice over, so tilting the phone
about 30° (flat, side to side) or turning it about 30° (upright) swings the
light over the stones from one side to the other, while it always stays
generally overhead (at least 40° above the paper). The camera never moves. Caustics depend on the light's direction only, so they
hold still when it does.

| File | What it does |
| --- | --- |
| `gem_board_3d.gd` | `GemBoard3D`, a `SubViewportContainer`: `show_collage(picture)` or `show_kit(pattern)` (each drill a round or square brilliant). Stones of one shape and cut share a mesh and draw as one `MultiMesh`, with their color, refractive index (pale stones read as diamonds, with more fire) and cut per instance. Moves the key and fill lights with time and with the phone's turn since the picture appeared, each sensor for one thing so they never pull against each other: gravity for tilting and rolling, the gyroscope for spinning about the vertical (both enabled in the project settings). The lights glide to new directions; glow blooms the glints. Zooms in up to 40×. `shadows` turns the shadows off (their caustic light stays). Pinch, drag, double-tap and the mouse wheel zoom and pan, like the 2D preview. |
| `gem_mesh.gd` | Builds a stone's crown in 3D from its outline: the girdle resampled so corners stay sharp, then rings of points pulled in and raised (every 1st, 2nd or 4th point, half a step apart for brilliants) zipped into flat triangular facets up to a table or a point. Cached per shape and cut. |
| `gem.gdshader` | Facets mirror a small studio (a key softbox with window bars, a fill, a ring of low lamps, the paper below); light also refracts in, bounces off two pavilion facets (sectors under a brilliant, nested rectangles under a step cut), comes back out tinted by the gem and split a little per color for fire, with soft light playing through the body (shifting as the light moves) and a darker rim. Cabochons glow smoothly toward the light. |
| `gem_shadow.gdshader` | Each stone's soft shadow on the paper (lighter under the tiniest stones), cast away from the light by how high it stands, with the colored caustic light it focuses inside it, shifting as the light moves; both fade out before the edge of their plane. |
| `gem_sparkle.gdshader` | Four-point star flares when one of a stone's two brightest facets turns a light straight up at the viewer; planes for unlit stones collapse to nothing. |
| `paper.gdshader` | The paper's faint grain, lit by the key; metal-setting lines as gold ridges that shine toward the light. |
| `gem_light.gdshaderinc` | The light and studio shared by all of them. |

## Trying it

- Open the project in Godot 4.7. The main scene, `scenes/dev/generator_lab.tscn`,
  is a dev screen. Pick a mandala shape, theme, seed and wobble, or load a
  photo. *New pattern* (or the Pattern box) makes another collage of the same
  lines; Setting and Line gems force a choice. Then view it as a collage, a kit or plain line art, and save the JSON.
  The **Lines** box above the picture flips between the collage (or kit) and
  the line art it was made from, without regenerating and keeping the zoom,
  to tell problems in the line art from problems in the gem patterns. The
  **3D** box (on by default) shows collages and kits as real gems on paper
  (`GemBoard3D`); off, they are flat shapes. *Shadows* in the Options panel
  turns the gems' shadows on the paper off and on.
  It is laid out for phones: *New seed*, *New pattern* and *Options* sit in a
  bar at the bottom, every setting is in the Options panel, and the picture
  zooms with a pinch (or the mouse wheel), pans with a drag and fits again
  with a double-tap or *Fit*.
- Headless checks with preview PNGs. The checks cover 20 seeds across all
  shapes, contact sheets of 24 framed pictures (every frame shape, band,
  corner and background; about 3 in 4 framed by default), 24 mandalas (every silhouette, center, extra and
  ring pattern, two zoomed in), 24 flowers in a row (every template, no repeats
  within 2, varied petal counts), 24 hearts (every shape, collar and
  pattern, mostly combined, mirror-symmetric) and 24 butterflies (every
  wing shape, border, pattern, body and antenna style, mirror-symmetric) and
  24 snowflakes (every center, arm, tip, in-between and detail, nearly all
  with content between the arms), overlaps, coverage, slots spilling onto
  lines, symmetric stones (unframed mandalas turned by one repeat), bold
  lines, bead lines changing size along strokes, elements left out over the
  stone limit, gem cuts (every shape's mesh in every cut covers its outline
  with facets facing up; stones of one part share a cut), the board's light
  following a phone held still or tilted, crossing over the stones when it
  is tilted 30° either way flat or turned 30° either way upright, and
  staying overhead however it's held, kits at every size (owned colors only), photo line art and a JSON
  round trip:

  ```sh
  godot --headless --import
  godot --headless -s res://tests/run_generators.gd -- --out=/tmp/previews --seeds=20
  ```

- One line art under several pattern seeds, side by side:

  ```sh
  godot --headless -s res://tests/collage_sheet.gd -- --out=/tmp/sheet --seeds=1000,1003 --patterns=3
  ```

Lint with [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit): `gdlint gen scenes tests`.
