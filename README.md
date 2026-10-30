# Paint With Gems

A cozy Android game in Godot 4.7 where you place sparkly gems to make pretty
pictures. There are no timers, no fail states and no ads. There are two modes:

- **Diamond Kit:** a picture becomes a numbered grid of round or square drills.
- **Gem Collage:** line art becomes gem slots laid out in patterns. Most
  pictures turn the lines themselves into rows of slotted gems; some keep
  them as a metal setting. One line art makes many collages: change the
  `pattern_seed`.

So far there are the **puzzle generators**: pure-logic GDScript in `gen/`
that turns a source picture into a playable puzzle for either mode, the
**3D board** in `render/` that shows a puzzle as real faceted gems, and the
first playable **game** (`game/`, `scenes/game/`): Gem Collage puzzles made
only from the gems she has unlocked. The generator lab stays as a debug
mode for trying out new pattern generation.

## The game (`game/`, `scenes/game/`)

- **Unlocks.** Puzzles use only the gem colors, shapes and cuts, color
  themes and puzzle types she has unlocked. She starts with about half the
  shapes (round, oval, cushion, square, hexagon, heart, marquise, teardrop
  and baguette), each in one cut (its classic one), the primary colors
  (ruby, tangerine, sunflower, leaf, sapphire, indigo and amethyst, plus
  black onyx, white and clear diamond), six themes made of those colors
  (rainbow, sunset, ocean, garden, starry night, ember) and one puzzle type:
  mandala collages, with no frames or collars, placing gems with Pop or
  Fly and the Ripple finale. Everything else comes from packs.
- **Colors and themes.** 105 gem colors, at least 10 of each hue (red,
  orange, yellow, green, teal, blue, purple, pink, brown and neutrals; some,
  like pearl, ivory, jade and turquoise, are opaque stones), and 33 themes:
  one per hue, the starting rainbow ones and mixes like Tropical, Galaxy and
  Seaside. A theme is hers as soon as she has all its colors; themes don't
  come from packs. Collection shows a locked theme's colors she has found so far.
- **Photos.** *A photo* is a picture source for both kinds of puzzle in the
  New puzzle panel: *Choose photo…* picks one of her photos (the phone's own picker; turned upright by its EXIF orientation, see `game/photo_loader.gd`) and turns it into a collage
  or a kit of drills, in her unlocked colors. *Take photo…* takes a new
  photo instead (`scenes/game/camera_capture.gd`:
  a full-screen camera view through `CameraServer`, with Switch for the
  other camera and Turn for an extra quarter turn; Android asks for the camera
  permission, which the committed export preset includes). Android sends
  frames as a Y plane and a half-size CbCr plane (YUV_420_888, picked over
  RGBA formats); the preview converts them in a shader and stands them
  upright by the feed's own rotation, and the photo is converted on the CPU
  from the same planes (full-range BT.601), shrunk to 1024 px, not read back
  from the screen. Some phones hand over the CbCr plane as one channel
  twice as wide (Cb, Cr, Cb, Cr...) instead of two channels; read as two,
  that turns everything green and blue with no red. The panel reads the
  plane back once when the feed starts, picks the layout from its bytes per
  pixel, and decodes either. The shader gets its CbCr texture again
  whenever a camera starts: a material keeps the texture it was handed, and
  a CameraTexture with no feed yet is only a placeholder, which read as CbCr
  turns the preview green and blue. The line above the preview names the
  camera (*Back camera 1*, *Front camera*, ...). The main back camera (the
  lowest id, "0" on Android) opens first; higher ids are extra lenses. Photo puzzles can't be
  recolored: their colors come from the photo.
  - *Photo collages* find the photo's edges (`gen/photo_edges.gd`: an
    edge-preserving Kuwahara smoothing so fur and cloth flatten, a color
    edge detector over Lab, thin ridges, thresholds from the photo with a
    floor, short specks dropped, loose ends reaching on to close shapes),
    then become a collage like any line art, with every area filled. If the
    photo has a clear subject (boundary connectivity saliency: sky, ground
    and walls connect to the photo's border, a subject hardly does; it must
    be compact, stand out clearly and not run edge to edge), only the
    subject becomes line art, cropped around it, with the rest left as
    background. The panel's *Photo collage* choice can also ask for the
    subject only or the whole photo.
  - *Photo kits* keep the photo's own shape (about 6000 drills, nothing
    cropped) and map each cell straight to the nearest unlocked gem in Lab,
    carrying 85% of the leftover color on to its neighbors (Floyd-Steinberg,
    back and forth, capped), so neighboring gems blend into the colors in
    between. Against the photo, seen from a little way off, that cut the
    average color error by a half to two thirds (with the 10 starting colors
    on sample photos, 18-30 ΔE down to 8-21). The panel's *Photo kit colors*
    can instead use the photo's own 12, 20 or 30 colors (k-means in Lab,
    exact colors that aren't her gems, 50% carried on): 2-4 ΔE on the same
    photos with 12.
- **Collection & packs** (from the menu). *Packs*: each unlock pack (Color,
  Shape, Facet, Picture, Flourish, Sparkle) gives one thing she
  doesn't have yet from its category, never a repeat, and is sold out once
  she has it all; the Everything pack picks a category with something left
  (each as likely) and gives something from it; the Power-up pack gives
  charges. Every pack costs 30 coins (power-ups 10) or a free pick. She gets
  a free pick the first time she opens the game each day and another for
  her first finished puzzle each day; every finished puzzle pays 10 coins
  (once per puzzle, so restarting one doesn't pay again), so every 3
  puzzles buy a pack. Opening one pops up what came out, rendered. *Collection*: every
  gem color and every shape in every cut as real rendered gems, then
  themes, picture types (collages and Diamond kits), flourishes (frames,
  frame backgrounds, heart collars, close-ups, hand-drawn lines), ways to
  place gems (Pop, Fly, Drop, Spin, Twinkle, and ones that read even zoomed
  far out: Bounce, Comet, Firework, Beam, Halo), finales (Ripple, Spiral,
  Sweep, Shimmer) and power-up charges. Locked things stay a mystery: gems
  show only as flat silhouettes of their outline, and names, theme colors
  and descriptions stay hidden.
- **Power-ups**, spent from *Power-ups* while playing. For the whole puzzle:
  Big brush (fills every matching slot under a wide brush), Tidy up (gems
  with fewer than 10 slots left finish themselves), Free hand (tap any open
  slot to fill it with its own gem) and Double coins. Once per charge:
  Finish gem, Sweep (the picked gem's slots on screen), Finder (zooms to
  the picked gem's slots) and Sprinkle (40 gems anywhere). She starts with
  a Finish gem and two Finders.
- **Diamond kits**: a mandala painted with the theme, turned into a grid of
  round or square drills (whichever are unlocked), played like a collage.
  Drills fill 98% of their cell, so neighbors almost touch, like a real kit
  (square drills' slots are sized by `GemShapes.drill_length`, since a square
  draws at 75% of its slot to fit round collage slots).
  *Kit size* in the New puzzle panel (for photo kits too) sets the drills
  on the longer side: Small 50, Medium 90, Large 130 or X-large 250; the
  shorter side follows the picture's shape (an X-large kit can have 62,500
  drills). Kits save as their grid of colors (82 KB for an X-large one,
  where every drill as a slot would be 11 MB) and turn back into drills on
  loading; filling a drill only collapses its own outline, so big boards
  stay quick.
- **Menu.** *New puzzle* opens a panel that asks in steps and shows only
  what applies: the kind (*Gem collage* or *Diamond kit*), then the picture
  (her unlocked collage pictures, the mandala for kits once unlocked, or *A
  photo*), then that picture's options (*Colors* for generated pictures;
  *Photo* subject for photo collages; *Drill colors* for photo kits; *Kit
  size* for kits). It makes the puzzle on a worker thread.
  Recoloring opens the same panel with the kind and picture fixed and only
  *Colors* to choose. Every puzzle keeps its own save, so starting a
  new one never touches the others. Each saved puzzle shows a thumbnail and
  how far along it is, and can be continued, restarted (asks "Sure?"
  first), recolored (the same picture made again in another unlocked theme,
  saved as a new puzzle beside the original) or deleted. *Generator lab
  (debug)* at the bottom opens the lab; its *‹ Menu* button comes back.
- **Playing.** Every gem type (a shape in a cut and a color) gets a number,
  the most used first. Open slots show as thin outlines of their shape with
  the number inside, drawn at screen size so it grows as you zoom, and
  hidden where the slot is too small to hold it. The gems still to place
  run along the top as fully rendered, glinting gems with their number and
  how many are left; a gem leaves the row once all its slots are filled,
  and the next one is picked up. Picking one makes its open slots stand out
  (darker outlines over a tint of its color). The row scrolls with a drag
  (flinging on), and a tap picks a gem or lets it go; picking never scrolls it. Tap a slot, or drag
  across many: each gem flies from its card (even one scrolled out of view) into the slot with a
  trail of tiny sparkles and a little burst as it lands, or in another
  unlocked style chosen in *Settings* on the menu (where the finale is
  chosen too), always with a tiny buzz. A drag that doesn't start
  on the selected gem's slot pans instead, and two fingers pinch. When the
  last stone is in, a wave ripples out from the middle while the light
  sweeps over the gems, and the picture is left to look at, zoomed and
  panned at will, until *‹ Menu*. Progress saves every couple of seconds
  and whenever she leaves or the app goes to the background.

| File | What it does |
| --- | --- |
| `game/gem_catalog.gd` | `GemCatalog`: every unlockable (gem colors, shapes and cuts, themes as gem colors, puzzle types) and what she starts with. |
| `game/unlockables.gd` | `Unlockables`: the table of every kind of unlockable, its items, starting items, and granting and upgrading profiles. |
| `game/packs.gd` | `Packs`: what each pack can still give, opening packs with picks or coins, daily picks, puzzle rewards and power-up charges. |
| `game/puzzle_maker.gd` | `PuzzleMaker`: a puzzle request (type, seed, pattern seed, theme) → a collage made from her unlocks only. Safe on worker threads. |
| `game/save_store.gd` | `SaveStore`: her profile (unlocks, settings and puzzle list) and each puzzle's picture, progress (one bit per slot) and thumbnail under `user://saves`, written via a temporary file. |
| `game/thumbnail.gd` | Small flat pictures for the menu: placed stones in color, open slots as pale dots. |
| `scenes/game/app.tscn` | The main scene: shows the menu, a puzzle or the lab, and passes Android's back button on. |
| `scenes/game/main_menu.gd` | New puzzle, the saved puzzles and the way into the lab. |
| `scenes/game/play_screen.gd` | One puzzle: the gem row (cut from a small off-screen `GemBoard3D` of single stones, so the icons are real lit gems), tapping and dragging to place, buzzes, the finale and saving. |
| `scenes/game/collection_screen.gd` | Collection & packs: pack cards, opening and revealing, and everything unlocked or still hidden. |
| `scenes/game/drag_scroll.gd` | `DragScroll`: makes a list scroll (and fling) wherever a drag starts, buttons included, without pressing them. |
| `scenes/game/gem_icons.gd` | `GemIcons`: single gems laid out on an icon sheet, sized to stay inside their own cell. |
| `scenes/game/gem_flights.gd` | `GemFlights`: gems flying from the row into their slots (following the board if it moves), with their sparkle trails and landing bursts. |
| `scenes/game/slot_overlay.gd` | `SlotOverlay`, drawn over the board: outlines and numbers of open slots, the selected gem's highlight, and finding the open slot under a finger. |

### Adding unlockables

Every kind of unlockable (colors, shapes, cuts, themes, picture types,
flourishes, placement styles, finales, power-ups) is a row in
`Unlockables.KINDS`, and packs, Collection and profiles all work from that
table, so additions never touch old puzzles or what she has:

- **A new item:** add it to its catalog in `GemCatalog` (cuts go in
  `GemCuts.BY_SHAPE`, with a `GemCuts.SHADER_STYLE`). Packs offer it at once,
  and a sold-out pack comes back in stock. New placement styles, finales,
  flourishes and power-ups also need their code (and an entry in
  `PlayScreen.FILL_STYLES` / `POWER_EFFECTS`, `GemBoard3D.FINALES` or
  `PuzzleMaker.FEATURES`); new shapes need a `GemShapes` outline and a
  `GemVariety` family. The *Catalog complete* check fails until all of
  that is in place.
- **A new starting item:** add it to its `STARTING_` list. Existing players
  get it the next time the game starts. Starting power-up charges are given
  only once, ever, through the profile's `granted` ledger.
- **A new kind:** add a row to `Unlockables.KINDS` (its unlock list and its
  pack), its items to `Unlockables.items()`, and the pack to `Packs.PACKS`.
- **Ids are forever:** saves keep ids, never positions or names, so never
  rename or reuse one (map an old id to a new one in `Unlockables.RENAMED`
  if you must).

Saved puzzles keep their whole picture (every stone's shape, cut and color),
so they look and play the same whatever is added later. A profile from any
earlier version loads through `SaveStore.upgrade()`, which only adds things
and keeps anything it doesn't recognize; the *Old profiles* check covers
this.

Buzzes need the `VIBRATE` permission and taking photos the `CAMERA`
permission; both are on in the committed Android export preset
(`export_presets.cfg`).

## Picture sources → puzzles

| Source | Kit mode | Collage mode |
| --- | --- | --- |
| Seeded mandala | `PictureSources.mandala_image()` → `KitGenerator.generate()` | `PictureSources.mandala_collage()` |
| Photo (picked or from the camera) | `KitGenerator.generate(photo)` | `PictureSources.photo_collage()` |
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
| `gem_variety.gd` | Steers each collage to 25–30 **gem types** (a shape in one of its cuts in a gem color; sizes don't count) and gives every stone its `cut`: each shape in a color starts with its own seeded cut. It changes whole pattern parts (one row, one ring, the center stones, one symmetry class of lines) across symmetric copies, so every row and every line keeps a single type: first a sibling shape (round ↔ cushion ↔ octagon ↔ hexagon ↔ flower ↔ square ↔ pentagon ↔ heart ↔ trillion ↔ triangle ↔ star, oval ↔ marquise ↔ lozenge ↔ kite ↔ teardrop, which fit the same slot), then another cut of the same shape, then a color, choosing colors the picture already uses before harmonious new ones. Given the shapes and cuts she has unlocked (`shapes`), it first gives every other stone the nearest unlocked shape (its own family first, resized to fit when it comes from another) and only swaps among unlocked ones. Too many types fold into common ones. If a picture is still short, it is rebuilt with **spacer rows** (thin rows of small stones between the main rows) to give it more rows to vary. |
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
| `gem_board_3d.gd` | `GemBoard3D`, a `SubViewportContainer`: `show_collage(picture)` or `show_kit(pattern)` (each drill a round or square brilliant). For play, stones can start hidden, pop in when placed (`fill_slot`) and pulse in a wave when the picture is done (`celebrate`); a `stroke_filter` turns touches into strokes instead of pans, and `view_transform()` maps the board onto the screen for drawing over it. White stones are opaque, with a soft glaze, so they read apart from clear diamonds. Stones of one shape and cut share a mesh and draw as one `MultiMesh`, with their color, refractive index (pale stones read as diamonds, with more fire) and cut per instance. Moves the key and fill lights with time and with the phone's turn since the picture appeared, each sensor for one thing so they never pull against each other: gravity for tilting and rolling, the gyroscope for spinning about the vertical (both enabled in the project settings). The lights glide to new directions; glow blooms the glints. Zooms in up to 40×. `shadows` turns the shadows off (their caustic light stays). Pinch, drag, double-tap and the mouse wheel zoom and pan, like the 2D preview. |
| `gem_mesh.gd` | Builds a stone's crown in 3D from its outline: the girdle resampled so corners stay sharp, then rings of points pulled in and raised (every 1st, 2nd or 4th point, half a step apart for brilliants) zipped into flat triangular facets up to a table or a point. Cached per shape and cut. |
| `gem.gdshader` | Facets mirror a small studio (a key softbox with window bars, a fill, a ring of low lamps, the paper below); light also refracts in, bounces off two pavilion facets (sectors under a brilliant, nested rectangles under a step cut), comes back out tinted by the gem and split a little per color for fire, with soft light playing through the body (shifting as the light moves) and a darker rim. Cabochons glow smoothly toward the light. |
| `gem_shadow.gdshader` | Each stone's soft shadow on the paper (lighter under the tiniest stones), cast away from the light by how high it stands, with the colored caustic light it focuses inside it, shifting as the light moves; both fade out before the edge of their plane. |
| `gem_sparkle.gdshader` | Four-point star flares when one of a stone's two brightest facets turns a light straight up at the viewer; planes for unlit stones collapse to nothing. |
| `paper.gdshader` | The paper's faint grain, lit by the key; metal-setting lines as gold ridges that shine toward the light. |
| `gem_light.gdshaderinc` | The light and studio shared by all of them. |

## Trying it

- Open the project in Godot 4.7. The main scene, `scenes/game/app.tscn`, is
  the game; *Generator lab (debug)* in its menu opens the lab
  (`scenes/dev/generator_lab.tscn`, which also runs on its own), a dev screen. Pick a mandala shape, theme, seed and wobble, or load a
  photo (*Photo…*) or take one (*Camera…*). *Kit size* has the game's sizes,
  small to X-large (50-250 drills on the longer side), and *Drill colors*
  makes kits in the starter gem colors or in the picture's own colors (as
  many as *Kit colors*, mapped like the game's photo kits). *New pattern* (or the Pattern box) makes another collage of the same
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
  staying overhead however it's held, kits at every size (owned colors only), photo line art, a JSON
  round trip, game puzzles using only the starting unlocks (and keeping their lines when recolored),
  progress saves, packs (never a repeat, selling out, paying with picks or coins, daily picks and
  puzzle coins once each) and kit puzzles (only unlocked colors and drills):

  ```sh
  godot --headless --import
  godot --headless -s res://tests/run_generators.gd -- --out=/tmp/previews --seeds=20
  ```

- One line art under several pattern seeds, side by side:

  ```sh
  godot --headless -s res://tests/collage_sheet.gd -- --out=/tmp/sheet --seeds=1000,1003 --patterns=3
  ```

Lint with [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit): `gdlint gen game scenes tests`.

## Building an APK

`tools/build_apk.sh` builds a signed debug APK from the command line on
Linux x86_64, with nothing set up beforehand but a JDK 17+ (`java` and
`keytool`), `curl` and `unzip`:

```sh
tools/build_apk.sh           # build/paint-with-gems-debug.apk
```

It uses the committed `export_presets.cfg` (one *Android* preset: package
`com.squishter.paintwithgems`, arm64-v8a, no Gradle build, camera and vibrate
permissions, tests and tools left out) and keeps everything else in a cache
folder (`~/.cache/paint-with-gems-build`, or `BUILD_CACHE`), never touching
your own Godot settings:

- The Godot editor (`GODOT_VERSION`, default `4.7-stable`) from GitHub.
- Only the `android_*` templates out of the official export-templates bundle
  (the bundle itself is about 1 GB; it is deleted after).
- An Android SDK. A plain APK export only needs `apksigner` from build-tools
  and a `platform-tools` folder, so `ANDROID_SDK_SOURCE` picks where they
  come from: `google` (default; sdkmanager from `dl.google.com`), `apt`
  (Ubuntu/Debian's `apksigner`, `zipalign` and `adb` packages linked into a
  minimal SDK layout, for machines that can't reach `dl.google.com`, such
  as Claude's cloud sessions), or `existing` (your `ANDROID_HOME`).
- A debug keystore made with `keytool`, and Godot's editor settings (SDK,
  JDK and keystore paths), both in the cache. Godot runs with the
  `XDG_*_HOME` folders pointed there, which is how it finds them and its
  templates.

It imports the project first (so `class_name` scripts are registered) and
then runs `godot --headless --export-debug Android`. Install with
`adb install -r build/paint-with-gems-debug.apk`.

For a release APK, make a keystore (never commit it; `*.keystore` and
`*.jks` are ignored), set `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`,
`GODOT_ANDROID_KEYSTORE_RELEASE_USER` and
`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`, raise `version/code` in the
preset, and run `tools/build_apk.sh release`.
