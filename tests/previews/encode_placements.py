"""Package native Godot frames; never synthesize or paint over an effect."""

from pathlib import Path
import json
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFont


ROOT = Path("build/placement-previews")
STYLES = ["pop", "fly", "drop", "spin", "twinkle", "bounce", "comet", "firework", "halo"]
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def encode(name):
    folder = ROOT / name
    frames = sorted(folder.glob("*.png"))
    expected = 80 if name.startswith("beam-") else 50
    assert len(frames) == expected, (name, len(frames))
    assert all(Image.open(p).size == (1440, 1080) for p in frames)
    ffmpeg("-framerate", "30", "-i", str(folder / "%04d.png"), "-c:v", "libx264",
           "-crf", "19", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(ROOT / f"{name}.mp4"))
    # 30 ms / 40 ms GIF delays alternate to retain the 30 fps playback rate.
    images = []
    for p in frames:
        with Image.open(p) as src:
            images.append(src.resize((960, 720), Image.Resampling.LANCZOS).convert("RGB"))
    atlas = Image.new("RGB", (960 * 4, 720 * 3))
    for i, frame in enumerate(images[::max(1, len(images) // 12)][:12]):
        atlas.paste(frame, ((i % 4) * 960, (i // 4) * 720))
    palette = atlas.quantize(colors=192, method=Image.Quantize.MEDIANCUT)
    quantized = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in images]
    quantized[0].save(ROOT / f"{name}.gif", save_all=True, append_images=quantized[1:], loop=0,
                      duration=[30, 30, 40] * (len(quantized) // 3) + [30] * (len(quantized) % 3),
                      optimize=False, disposal=1)


def filmstrip():
    # Four actual captured instants, with timestamps derived from launch frame 7.
    picks = [9, 12, 16, 21]
    strip = Image.new("RGB", (1440, len(picks) * 445 + 90), "#151a2a")
    draw = ImageDraw.Draw(strip)
    title = ImageFont.truetype(FONT_PATH, 29)
    small = ImageFont.truetype(FONT_PATH, 21)
    draw.text((28, 20), "Beam / the same 0.42 s placement, four instants", fill="#f3d286", font=title)
    for row, index in enumerate(picks):
        with Image.open(ROOT / "beam-close" / f"{index:04d}.png") as frame:
            # Keep all three column labels and their light-to-gem contact area.
            crop = frame.crop((0, 140, 1440, 750)).resize((1200, 508), Image.Resampling.LANCZOS)
            # Preserve aspect ratio, showing the upper 445 px where the effect lands.
            strip.paste(crop.crop((0, 0, 1200, 425)), (220, 90 + row * 445))
        elapsed = (index - 7 + 1) / 30
        draw.text((28, 130 + row * 445), f"{elapsed:.2f} s", fill="#f3d286", font=title)
        draw.text((28, 178 + row * 445), "of 0.42 s", fill="#bdc7d8", font=small)
    strip.save(ROOT / "beam-filmstrip.png")


def gallery():
    tiles = []
    for name in ["beam-fit", "beam-close", *STYLES]:
        label = name.replace("-", " ").title()
        tiles.append(f'''<article><h2>{label}</h2><img loading="lazy" src="{name}.gif" alt="{label}: current and proposed native renders">
<p><a href="{name}.mp4">MP4 at original speed</a></p></article>''')
    (ROOT / "index.html").write_text('''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Gem placement studies</title>
<style>body{margin:24px auto;max-width:1100px;padding:0 20px;background:#151a2a;color:#dbe3ee;font:17px/1.6 system-ui}
h1,h2,a{color:#f3d286}article{margin:40px 0}img{width:100%;height:auto;border-radius:16px}
code{color:#b6e6d3}p{max-width:900px}a:focus{outline:2px solid #b6e6d3}</style>
<h1>Gem placement / motion studies</h1><p>Native Godot renders of the current animations beside render-only prototypes.
Beam compares Current, A (soft column) and B (prismatic column). Other styles compare Current and Proposed.
All keep their original placement timings and flight paths. First a single placement, then a short brush stroke.
Playback loops at original speed. No production animation code was changed.</p>''' + "\n".join(tiles) + "</html>")


for name in ["beam-fit", "beam-close", *STYLES]:
    encode(name)
filmstrip()
gallery()
shutil.copyfile(ROOT / "beam-fit" / "0012.png", ROOT / "beam-comparison.png")
shutil.copyfile(ROOT / "beam-close" / "0012.png", ROOT / "beam-close-comparison.png")
shutil.copyfile(ROOT / "comet" / "0013.png", ROOT / "comet-comparison.png")
shutil.copyfile(ROOT / "halo" / "0011.png", ROOT / "halo-comparison.png")
shutil.copyfile(ROOT / "firework" / "0022.png", ROOT / "firework-comparison.png")
(ROOT / "render-info.json").write_text(json.dumps({
    "renderer": "Godot 4.7.2 / Mobile Vulkan / native frames",
    "frames": 610, "fps": 30, "production_gem_flights_blob": "5fadf388edb676e9c1f2c9859bab5fd37768ef00",
    "beam_duration_seconds": 0.42, "production_changes": False,
    "styles": ["beam", *STYLES], "landing_validation": "all single and stroke placements land exactly once"
}, indent=2) + "\n")
print("Encoded native comparisons:", ", ".join(["beam-fit", "beam-close", *STYLES]))
