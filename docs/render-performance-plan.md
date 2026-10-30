# Render performance plan

The 3D board (`render/gem_board_3d.gd` and its shaders) costs too much on
phones. This plan cuts that cost **without changing how anything looks**, in
small steps that are each verified before the next. Do the steps in order and
commit each one on its own.

Phase 1 (steps 1–5) is approved to implement. Phase 2 (steps 6–8) needs
measurements from a phone first: finish phase 1, report, and ask before
starting phase 2.

## Background: where the cost is

Read `render/gem_board_3d.gd`, `render/gem.gdshader`,
`render/gem_shadow.gdshader`, `render/gem_sparkle.gdshader`,
`render/paper.gdshader` and `render/gem_light.gdshaderinc` first.

1. **No frame cap, and the board never rests.** `project.godot` sets no
   max fps, so a 90/120 Hz phone draws the full 3D board 90–120 times a
   second. The light drifts every frame (`GemBoard3D._process` →
   `light_time`, `update_light`), so every frame really is a full redraw,
   even when nobody touches anything.
2. **Shadow/caustic overdraw.** `_add_layer(..., "shadow")` gives every stone
   a plane `SHADOW_SPAN` (2.6) stone half-sizes each way, centered on the
   stone: about 8× the stone's area. On a packed board every paper pixel runs
   `gem_shadow.gdshader` about 7 times. The shadow only ever lies toward one
   side (`off`, away from the key light), so most of that plane is discarded
   work.
3. **The gem fragment shader calls `studio()` 4 times per pixel** (the
   reflection plus r, g, b through the stone for fire), each with
   atan/asin/sin and many smoothsteps.
4. **Triangles on big kits.** A brilliant round drill is about 64 triangles;
   an X-large kit (62,500 drills) is about 4M triangles per frame at MSAA 4×.
   MultiMesh culling is per MultiMesh, not per instance, so zooming in
   doesn't help.
5. **Off-screen boards that always render:** the play screen's gem-row icons
   (`scenes/game/play_screen.gd`, `_icons.set_always_render()`) and the
   Collection sheet (`scenes/game/collection_screen.gd`,
   `_sheet.set_always_render()`) redraw every frame.
6. **Smaller costs:** `paper.gdshader` recomputes three value-noise octaves
   per pixel every frame, though the grain never changes. Glow runs several
   full-screen passes.

## Phase 1 (implement)

### Step 1: frame cap and idle rate

- Cap the game at **45 fps**: `application/run/max_fps=45` in
  `project.godot`. The user also mentioned 30, so keep the number easy to
  change and mention it in the report.
- In `GemBoard3D`, render the SubViewport at **full rate (45) only while
  something moves**, and at **30 fps when idle**. "Moving": a touch, a pan or
  pinch (`_touches` not empty), a glide (`_glide`), stone animations
  (`_anims` not empty), the finale sweep (`_clock < _sweep_until`), the
  phone turning (the light's change since the last frame above a small
  threshold), or a `view_changed`. Idle: only the slow time drift.
- Mechanism: keep `render_target_update_mode` at `UPDATE_DISABLED` while the
  board is visible, and set `UPDATE_ONCE` whenever a frame is due (time since
  the last render ≥ 1/rate, or something changed this frame). Keep advancing
  `light_time` every frame, so the drift speed doesn't change. Respect the
  existing visibility handling (`visibility_changed` sets `UPDATE_WHEN_VISIBLE`
  / `UPDATE_DISABLED`; replace it with the new scheduling) and
  `set_always_render()` (used by off-screen boards, see step 4).
- Pans and zooms move the camera (`_apply_view`), so they must render the
  same frame: mark "changed" in `_apply_view` and in the stroke and anim
  paths.
- Add constants such as `ACTIVE_FPS := 45.0`, `IDLE_FPS := 30.0`, with a short
  comment, matching the file's style.
- Done when: idle, the board renders ~30 times a second (count renders in a
  debug readout or log); while panning or placing it renders every frame;
  nothing looks different.

### Step 2: shadow planes that fit their shadow

- In `gem_shadow.gdshader`'s `vertex()`, move the plane toward where the
  shadow and focus actually fall: shift `VERTEX.xz` by the local offset
  (`off`, already computed there in the stone's local units), and keep
  `lp` = the fragment position relative to the **stone**, so `fragment()` is
  unchanged.
- Then shrink `SHADOW_SPAN` in `gem_board_3d.gd` to the smallest plane that
  still contains everything. The shade fades out by `d = 1.3` around
  `off * 0.8`. The focus fades by 0.85 around `focus_off * 1.25` (which
  includes the stone's up-to-15° tilt, `TILT_MAX_DEG`). The `edge` fade uses
  `span`. Work out the bound (expected about 1.5 instead of 2.6) and keep a
  small margin. Mind that the `span` uniform drives the `edge` fade, so
  update it consistently.
- Done when: renders before and after are pixel-identical, or differ only in
  invisible noise, at several light positions (`animate = false`, set
  `light_time` and `turn` as tests do). Include a zoomed-in close-up of
  shadows and caustics.

### Step 3: bake the paper grain

- Compute the grain (`noise(...)` mix in `paper.gdshader`) once per board
  into a texture when the board is built (`_build`), at the board's size in
  board units (cap the size, e.g. 2048, and use linear filtering). Sample it
  in the shader. Keep `lit` and the gold lines' sheen live, since they depend
  on the light.
- Generating the texture can be done in GDScript, with the same hash/noise
  maths, or by a one-off render. It must not slow down puzzle loading
  noticeably (measure; an X-large kit board is 2500×1900 board units, so
  generate at a reduced size and let filtering stretch it, since the grain is
  very soft).
- Done when: the paper looks the same as before (side by side, zoomed in and
  out) and the paper shader no longer calls `noise()`.

### Step 4: slow down off-screen boards

- The gem-row icon board (`play_screen.gd`, `_build_icons`) and the
  Collection sheet (`collection_screen.gd`) call `set_always_render()`. Give
  `GemBoard3D` an optional rate for that mode (e.g.
  `set_always_render(fps := 0.0)`, 0 meaning the normal scheduling) and use
  about **10 fps** for both. Their glints only change with the slow light
  drift.
- Done when: icons still glint, and those boards render about 10 times a
  second.

### Step 5: a performance readout

- Add a small toggleable readout, off by default, to the play screen (e.g.
  a long-press on the progress label, or a setting) and to the generator lab.
  Show fps, the board's renders per second, frame time, and
  `RenderingServer.get_rendering_info(RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)`
  and draw calls. The user tests on a real phone and needs these numbers to
  judge phase 2.
- Done when: the readout shows sensible numbers in a local run.

Then build the APK (see Verification), send it, and ask the user to compare
on their phone: an X-large kit and a big collage, idle and while panning, and
the readout's numbers.

## Phase 2 (ask before starting)

### Step 6: studio lighting from a lookup texture

`studio(d)` depends only on the direction and the light uniforms. Render it
once per board frame into a small octahedral-mapped texture (256×256, HDR,
since highlights go well above 1), via a tiny SubViewport with a 2D or quad
shader, updated only when the lights change. In `gem.gdshader`, replace the 4
`studio()` calls with texture lookups. Keep the analytic path behind a
uniform switch for A/B. The risk is that the sharpest key highlight
(`smoothstep(0.988, 0.996, k)`) and the window bars soften. Compare at
`MAX_ZOOM` and only keep it if they're indistinguishable; raise the texture
size if needed.

### Step 7: simpler meshes for tiny stones (big kits)

Add low-poly versions of each shape/cut in `render/gem_mesh.gd` (e.g. 8–16
girdle points, one crown ring), and swap each MultiMesh's mesh by on-screen
stone size (switch when a stone is under about 10–12 px across, using
`_scale_px()`). Facets that small are sub-pixel anyway. Check that the switch
doesn't visibly pop: compare at the switch zoom.

### Step 8 (if still needed): facet-normal impostors

The user's idea of "prerender gems once": the final gem image can't be
prerendered, because the glints come from the moving light. Its **shape**
can be. On load, render each shape/cut once into an atlas storing facet
normal, local position and coverage. Then draw each stone as a 2-triangle
quad that reads the atlas and runs the same lighting as `gem.gdshader`. That
takes an X-large kit from about 4M triangles to about 125k. Needs:
- alpha-to-coverage or analytic edges, so quad edges stay anti-aliased;
- a switch back to real meshes when zoomed in close, where atlas resolution
  would blur big facets;
- the cabochon cut (smooth normals).

Consider step 7 first; step 8 only if kits are still slow.

### Trade-offs to offer only as switches (don't change defaults)

MSAA 4× → 2×, fewer glow levels, a 3D render scale under 1. Show the user
side-by-side renders before changing any default.

## Verification (in a Claude cloud session)

- **Godot:** `tools/build_apk.sh` downloads Godot 4.7 into
  `~/.cache/paint-with-gems-build` (or `BUILD_CACHE`). The editor binary is
  `godot-4.7-stable/Godot_v4.7-stable_linux.x86_64` in there. Run Godot with
  `XDG_CONFIG_HOME`, `XDG_DATA_HOME` and `XDG_CACHE_HOME` pointed under that
  cache, as the script does.
- **APK:** `ANDROID_SDK_SOURCE=apt tools/build_apk.sh` (dl.google.com is
  blocked in cloud sessions; see the README's "Building an APK"). The script
  checks that every script compiles (`tools/check_scripts.gd`) before
  exporting.
- **New `class_name` scripts:** run `godot --headless --import --path .` once
  before using them from a test script.
- **Rendering checks:** install `xvfb` and `mesa-vulkan-drivers` (apt works),
  then
  `xvfb-run -a godot --path . --rendering-method mobile --rendering-driver vulkan --resolution 540x1200 -s <script>`.
  That uses the real mobile renderer on the CPU (lavapipe). Frame times there
  say nothing about a phone; use it for **pixel comparisons** and renders per
  second only. Freeze the light for comparisons (`animate = false`, set
  `light_time`, `turn = Basis.IDENTITY`, `use_sensor = false`) and save
  `get_view_texture().get_image()` before and after (e.g. `git stash` the
  change to render "before"). Put throwaway scripts at the repo root as
  `zz_*.gd`, and delete them (and their `.uid` files) before committing.
- **Tests:** `godot --headless -s res://tests/run_generators.gd -- --out=/tmp/previews --seeds=2`
  takes 15–20 minutes, so run it in the background. One failure is known and
  unrelated: `seed 6009: only 3 regions` (snowflakes).
- **Lint:** `gdlint gen game scenes tests tools render` (`pip install gdtoolkit`).
  Existing warnings: `class-definitions-order` in `render/gem_board_3d.gd`,
  `game/gem_catalog.gd`, `scenes/dev/generator_lab.gd` and
  `scenes/game/gem_flights.gd`; `function-arguments-number` in
  `gem_flights.gd`; `max-public-methods`, `max-file-lines` and
  `duplicated-load` in `tests/run_generators.gd`. Add no new ones.
- **Docs:** update the README's rendering section (and any comment the change
  makes wrong) in the same commit as the change.
- Work on `main`, commit each step separately, push, and send the APK at the
  end of phase 1.
