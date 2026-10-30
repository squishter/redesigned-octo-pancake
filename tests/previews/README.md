# Placement animation studies

Render-only proposals on `preview/placement-animations`, based on `c98d795`.
The production `GemFlights` source also matches current main (blob
`5fadf388edb676e9c1f2c9859bab5fd37768ef00`). No production scripts are changed.

Beam currently fades three nested rectangular columns in/out over 0.42 s.
Its hard edges, simultaneous fade along the whole column and flat contact
circle make the light feel less physical. The gem lands when that column
vanishes, so there is little continuity between the two.

- **A / Soft column:** feathered, gently tapered light; a fine bright core;
  a downward leading edge and a small pool of light on the paper.
- **B / Prismatic column:** the same overhead beam with fine refracted
  filaments and sparse light fragments travelling downward.

Both retain the 0.42 s placement, gem color and top-to-slot direction.
They compare against the unmodified current effect at fit and close zoom,
first placing one gem, then four during a short stroke. Neither becomes a
projectile, explosion or closing ring.

The suite also compares all nine other placements. The prototype inherits
the production flight paths, size/rotation easing, timing and landing event:

| Style | Preserved intent | Proposed polish |
| --- | --- | --- |
| Pop | Grow in place with a bounce | Small contact glint; same bounce |
| Fly | Swoop from its palette card | Lighter trail and precise landing glints |
| Drop | Fall from directly above | Cleaner trail and restrained landing |
| Spin | Grow while twirling | Precise landing accent; same turn |
| Twinkle | Appear in a sparkle burst | More deliberate, fewer diamond glints |
| Bounce | Leap from its card in a high arc | Lighter trail and precise landing |
| Comet | Streak from the sky | Tapered continuous core under the sparkle tail |
| Firework | Rise from below and burst into a gem | Fine ignition trail and coherent radial burst |
| Halo | Ring closes onto the slot | Slim light rim, restrained orbiting glints and fade |

The fixture uses the real `GemBoard3D`, gem icon renderer and `SlotOverlay`.
Baseline columns instantiate unmodified `GemFlights`; proposed columns use
the subclass in this directory. Each panel has its own viewport (so Comet's
off-screen start uses the panel's dimensions). Seeds match between columns. Native capture
checks that every single/stroke placement lands exactly once. These are visual
studies, not a mobile performance measurement or a production integration.

Run with Godot 4.7.2 and a real Vulkan display:

```sh
godot --headless --editor --import --quit --path .
xvfb-run -a -s '-screen 0 1440x1080x24' godot --path . \
  --resolution 1440x1080 --audio-driver Dummy --fixed-fps 30 \
  --rendering-method mobile --rendering-driver vulkan \
  -s res://tests/previews/render_placements.gd
python3 tests/previews/encode_placements.py
```

Open `build/placement-previews/index.html` for the complete gallery. GIFs and
MP4s use original timing; PNG comparisons and the filmstrip show actual
captured frames. Encoding only resizes/assembles screenshots, never paints
or synthesizes the proposed effects.
