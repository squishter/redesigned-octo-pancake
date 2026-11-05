#!/usr/bin/env python3
"""Builds the prototype web line-art catalog from museum open-access images.

Two steps, run together by default:

1. fetch  (this script): searches The Met and the Art Institute of Chicago for
   public-domain (CC0) artworks matching a list of themes, downloads a
   ~1000 px image of each, cuts out the subject with a segmentation model
   (IS-Net / DIS, the model rembg calls "isnet-general-use", run with
   onnxruntime) and writes, per artwork, an RGBA cutout and its metadata
   to the work directory.
2. trace  (tools/web_art/trace_catalog.gd, run by Godot headless): turns
   each cutout into line art with the game's own PhotoEdges (subject from the
   cutout's alpha), drops pictures that won't make a good collage, and writes
   the catalog: line art, thumbnails, color crops and index.json.

Usage:
  python3 tools/web_art/build_catalog.py --godot /path/to/godot
  python3 tools/web_art/build_catalog.py --per-query 3 --themes flower,bird
  python3 tools/web_art/build_catalog.py --local-dir ~/pics   # no network
  python3 tools/web_art/build_catalog.py --skip-fetch --godot godot  # retrace

Needs: numpy, pillow, requests, onnxruntime (pip install -r
tools/web_art/requirements.txt). The model (~175 MB) is downloaded once to
~/.cache/web_art/.

Only CC0 / public-domain works are kept: The Met's isPublicDomain and the
AIC's is_public_domain flags. Both museums release those images under CC0.
"""

from __future__ import annotations

import argparse
import io
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import requests
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_WORK = ROOT / "build" / "web_art"
DEFAULT_OUT = ROOT / "assets" / "web_art"
CACHE = Path.home() / ".cache" / "web_art"
MODEL_URL = "https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx"
USER_AGENT = "PaintWithGems-catalog-builder/0.1 (prototype; github.com/squishter/redesigned-octo-pancake)"

# Themes that tend to have one clear subject and read well as gem collages.
THEMES = [
    "flower", "rose", "tulip", "butterfly", "bird", "owl", "cat", "dog", "horse",
    "fish", "shell", "teapot", "vase", "leaf", "fruit", "dragonfly", "peacock",
    "crane", "rabbit", "lion",
]
# Classifications that are usually one object on a plain ground, or already
# drawn: preferred over paintings of whole scenes.
GOOD_CLASSES = re.compile(
    r"print|drawing|ceramic|porcelain|glass|metal|jewel|textile|sculpture|vessel|"
    r"woodblock|botanical|illustrat|book|enamel|lacquer|silver|bronze", re.I)

IMAGE_SIDE = 1024  # longest side of the downloaded image
SEG_SIZE = 1024  # IS-Net input
# A clear subject: this share of the picture, touching at most this share of
# the border (more is scenery or a cropped detail).
SUBJECT_SHARE = (0.04, 0.85)
MAX_BORDER_TOUCH = 0.25


def log(msg: str) -> None:
    print(msg, flush=True)


class Http:
    """requests with a User-Agent, a polite delay and a few retries."""

    def __init__(self, delay: float = 0.15):
        self.s = requests.Session()
        self.s.headers["User-Agent"] = USER_AGENT
        self.s.headers["AIC-User-Agent"] = USER_AGENT  # the AIC asks for this
        self.delay = delay

    def get(self, url: str, **kw) -> requests.Response:
        for attempt in range(4):
            time.sleep(self.delay)
            try:
                r = self.s.get(url, timeout=30, **kw)
            except requests.RequestException as e:
                err = e
            else:
                if r.status_code == 200:
                    return r
                if r.status_code not in (429, 500, 502, 503, 504):
                    r.raise_for_status()
                err = RuntimeError(f"HTTP {r.status_code}")
            time.sleep(2 ** (attempt + 1))
        raise RuntimeError(f"{url}: {err}")


# ---------------------------------------------------------------- sources

def _tags(*groups) -> list[str]:
    out: list[str] = []
    for g in groups:
        for t in g or []:
            t = str(t).strip().lower()
            if t and t not in out and len(t) < 40:
                out.append(t)
    return out[:24]


def met_search(http: Http, theme: str, want: int) -> list[dict]:
    """Public-domain Met objects with images for `theme`, best first."""
    base = "https://collectionapi.metmuseum.org/public/collection/v1"
    # v1/search was retired on 2026-10-01; v1.1 is paged by offset and limit.
    ids = http.get(f"{base}.1/search", params={"q": theme, "hasImages": "true", "limit": want * 12,
                                               "offset": 0}).json().get("objectIDs") or []
    found, good = [], []
    for oid in ids[: want * 12]:
        if len(good) >= want:
            break
        try:
            o = http.get(f"{base}/objects/{oid}").json()
        except (RuntimeError, requests.RequestException) as e:
            log(f"  met {oid}: {e}")
            continue
        if not o.get("isPublicDomain") or not o.get("primaryImageSmall"):
            continue
        item = {
            "id": f"met-{oid}",
            "title": o.get("title") or "Untitled",
            "artist": o.get("artistDisplayName") or o.get("culture") or "",
            "date": o.get("objectDate") or "",
            "medium": o.get("medium") or "",
            "classification": o.get("classification") or o.get("objectName") or "",
            "source": "The Metropolitan Museum of Art",
            "license": "CC0",
            "url": o.get("objectURL") or f"https://www.metmuseum.org/art/collection/search/{oid}",
            "image_url": o["primaryImageSmall"],
            "tags": _tags([theme], [t.get("term") for t in (o.get("tags") or [])],
                          [o.get("objectName"), o.get("classification"), o.get("culture")]),
        }
        (good if GOOD_CLASSES.search(item["classification"] + " " + item["medium"]) else found).append(item)
    return (good + found)[:want]


def aic_search(http: Http, theme: str, want: int) -> list[dict]:
    """Public-domain AIC artworks with images for `theme`, best first."""
    fields = ("id,title,image_id,artist_title,date_display,medium_display,classification_title,"
              "subject_titles,term_titles,is_public_domain")
    r = http.get("https://api.artic.edu/api/v1/artworks/search", params={
        "q": theme, "limit": want * 6, "fields": fields,
        "query[term][is_public_domain]": "true",
    }).json()
    iiif = (r.get("config") or {}).get("iiif_url") or "https://www.artic.edu/iiif/2"
    found, good = [], []
    for a in r.get("data") or []:
        if not a.get("is_public_domain") or not a.get("image_id"):
            continue
        item = {
            "id": f"aic-{a['id']}",
            "title": a.get("title") or "Untitled",
            "artist": a.get("artist_title") or "",
            "date": a.get("date_display") or "",
            "medium": a.get("medium_display") or "",
            "classification": a.get("classification_title") or "",
            "source": "Art Institute of Chicago",
            "license": "CC0",
            "url": f"https://www.artic.edu/artworks/{a['id']}",
            # 843 px wide is the size the AIC recommends and caches.
            "image_url": f"{iiif}/{a['image_id']}/full/843,/0/default.jpg",
            "tags": _tags([theme], a.get("subject_titles"), a.get("term_titles"), [a.get("classification_title")]),
        }
        (good if GOOD_CLASSES.search(item["classification"] + " " + item["medium"]) else found).append(item)
    return (good + found)[:want]


def local_items(folder: Path) -> list[dict]:
    """Images in a folder as catalog items (tags from the file name)."""
    items = []
    for p in sorted(folder.iterdir()):
        if p.suffix.lower() not in (".jpg", ".jpeg", ".png", ".webp"):
            continue
        words = [w for w in re.split(r"[^a-z]+", p.stem.lower()) if len(w) > 1]
        items.append({
            "id": "local-" + re.sub(r"[^a-z0-9]+", "-", p.stem.lower()).strip("-"),
            "title": " ".join(words).capitalize() or p.stem,
            "artist": "", "date": "", "medium": "", "classification": "",
            "source": "Local file", "license": "unknown", "url": "",
            "image_path": str(p), "tags": _tags(words),
        })
    return items


# ---------------------------------------------------------------- cutout

class Segmenter:
    """IS-Net (DIS) foreground segmentation, as rembg's isnet-general-use."""

    def __init__(self, model: Path):
        import onnxruntime as ort
        self.sess = ort.InferenceSession(str(model), providers=["CPUExecutionProvider"])
        self.input = self.sess.get_inputs()[0].name

    def mask(self, img: Image.Image) -> np.ndarray:
        """Foreground probability 0..1 at the image's size."""
        x = np.asarray(img.convert("RGB").resize((SEG_SIZE, SEG_SIZE), Image.LANCZOS), dtype=np.float32)
        x = x / max(float(x.max()), 1e-6) - 0.5
        x = x.transpose(2, 0, 1)[None]
        pred = self.sess.run(None, {self.input: x})[0][0, 0]
        lo, hi = float(pred.min()), float(pred.max())
        pred = (pred - lo) / max(hi - lo, 1e-6)
        m = Image.fromarray((pred * 255).astype(np.uint8)).resize(img.size, Image.LANCZOS)
        return np.asarray(m, dtype=np.float32) / 255.0


def subject_scores(prob: np.ndarray) -> dict:
    fg = prob >= 0.5
    h, w = fg.shape
    border = np.concatenate([fg[0], fg[-1], fg[:, 0], fg[:, -1]])
    return {"share": round(float(fg.mean()), 3), "border": round(float(border.mean()), 3),
            "clear": bool(SUBJECT_SHARE[0] <= fg.mean() <= SUBJECT_SHARE[1] and border.mean() <= MAX_BORDER_TOUCH)}


def ensure_model() -> Path:
    path = CACHE / "isnet-general-use.onnx"
    if path.exists():
        return path
    CACHE.mkdir(parents=True, exist_ok=True)
    log(f"Downloading segmentation model to {path} …")
    tmp = path.with_suffix(".part")
    with requests.get(MODEL_URL, stream=True, timeout=60, headers={"User-Agent": USER_AGENT}) as r:
        r.raise_for_status()
        with open(tmp, "wb") as f:
            shutil.copyfileobj(r.raw, f)
    tmp.rename(path)
    return path


def load_image(http: Http, item: dict) -> Image.Image:
    if "image_path" in item:
        img = Image.open(item["image_path"])
    else:
        img = Image.open(io.BytesIO(http.get(item["image_url"]).content))
    img = img.convert("RGB")
    img.thumbnail((IMAGE_SIDE, IMAGE_SIDE), Image.LANCZOS)
    return img


def fetch(args, work: Path) -> None:
    cut_dir = work / "cutouts"
    cut_dir.mkdir(parents=True, exist_ok=True)
    http = Http()
    seg = Segmenter(Path(args.model) if args.model else ensure_model())

    items: list[dict] = []
    if args.local_dir:
        items = local_items(Path(args.local_dir))
    else:
        themes = args.themes.split(",") if args.themes else THEMES
        for theme in themes:
            for name, search in (("met", met_search), ("aic", aic_search)):
                if name not in args.sources:
                    continue
                try:
                    got = search(http, theme.strip(), args.per_query)
                except (RuntimeError, requests.RequestException) as e:
                    log(f"{name} '{theme}': {e}")
                    continue
                log(f"{name} '{theme}': {len(got)}")
                items += got
    seen: set[str] = set()
    items = [i for i in items if not (i["id"] in seen or seen.add(i["id"]))]
    if args.limit:
        items = items[: args.limit]

    for n, item in enumerate(items, 1):
        meta_path = cut_dir / f"{item['id']}.json"
        if meta_path.exists() and not args.refresh:
            continue
        try:
            img = load_image(http, item)
        except (RuntimeError, OSError, requests.RequestException) as e:
            log(f"[{n}/{len(items)}] {item['id']}: download failed: {e}")
            continue
        prob = seg.mask(img)
        scores = subject_scores(prob)
        rgba = img.copy()
        # A clear subject keeps its soft mask as alpha; otherwise the whole
        # picture is used and PhotoEdges looks for a subject itself.
        alpha = (prob * 255).astype(np.uint8) if scores["clear"] else np.full(prob.shape, 255, np.uint8)
        rgba.putalpha(Image.fromarray(alpha))
        rgba.save(cut_dir / f"{item['id']}.png", optimize=True)
        item["cutout"] = scores
        item.pop("image_path", None)
        meta_path.write_text(json.dumps(item, indent=1, ensure_ascii=False))
        log(f"[{n}/{len(items)}] {item['id']}: {item['title'][:50]!r} subject={scores}")


def trace(args, work: Path, out: Path) -> None:
    godot = args.godot or shutil.which("godot") or shutil.which("godot4")
    if not godot:
        log("No Godot found (pass --godot): cutouts are in %s; trace them with\n"
            "  godot --headless --path . -s res://tools/web_art/trace_catalog.gd -- %s %s" % (work, work, out))
        return
    cmd = [godot, "--headless", "--path", str(ROOT), "-s", "res://tools/web_art/trace_catalog.gd",
           "--", str(work), str(out), str(args.detail)] + (["strict"] if args.strict_inside else [])
    log(" ".join(cmd))
    subprocess.run(cmd, check=True)
    review_sheet(work, out)


def review_sheet(work: Path, out: Path, tile: int = 220) -> None:
    """work/review.jpg: each picture's cutout beside its line art, rejected
    ones marked, for judging by eye what the numbers can't."""
    from PIL import ImageDraw
    index = json.loads((out / "index.json").read_text())["items"]
    rejected = json.loads((work / "rejected.json").read_text())
    rows = [(i["id"], out / i["art"], "") for i in index]
    rows += [(r["id"], work / "rejected" / f"{r['id']}.png", r["why"]) for r in rejected]
    if not rows:
        return
    cols = 4  # pairs per row
    sheet = Image.new("RGB", (cols * tile * 2, -(-len(rows) // cols) * (tile + 18)), "white")
    draw = ImageDraw.Draw(sheet)
    for k, (id_, art, why) in enumerate(rows):
        x, y = (k % cols) * tile * 2, (k // cols) * (tile + 18)
        for j, path in enumerate((work / "cutouts" / f"{id_}.png", art)):
            if not path.exists():
                continue
            im = Image.open(path).convert("RGBA")
            bg = Image.new("RGBA", im.size, (235, 225, 245, 255))
            bg.alpha_composite(im)
            bg.thumbnail((tile - 6, tile - 6))
            sheet.paste(bg.convert("RGB"), (x + j * tile + 3, y + 3))
        draw.text((x + 4, y + tile), (id_ + ("  ✗ " + why if why else ""))[:60], fill="red" if why else "black")
    sheet.save(work / "review.jpg", quality=85)
    log(f"Review sheet: {work / 'review.jpg'}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--work", default=str(DEFAULT_WORK), help="cutouts and metadata (default build/web_art)")
    ap.add_argument("--out", default=str(DEFAULT_OUT), help="the catalog (default assets/web_art)")
    ap.add_argument("--themes", help="comma-separated search terms (default: a built-in list of %d)" % len(THEMES))
    ap.add_argument("--sources", default="met,aic", help="met, aic or both (default)")
    ap.add_argument("--per-query", type=int, default=2, help="artworks per theme per museum (default 2)")
    ap.add_argument("--limit", type=int, default=0, help="stop after this many artworks")
    ap.add_argument("--local-dir", help="use the images in this folder instead of the museums")
    ap.add_argument("--model", help="path to isnet-general-use.onnx (downloaded if omitted)")
    ap.add_argument("--godot", help="Godot 4.7 binary for the trace step")
    ap.add_argument("--detail", type=float, default=0.5, help="PhotoEdges detail 0..1 (default 0.5)")
    ap.add_argument("--strict-inside", action="store_true",
                    help="inside a cut-out subject keep only sharp, strong edges (PhotoEdges strict_inside)")
    ap.add_argument("--refresh", action="store_true", help="redo artworks already fetched")
    ap.add_argument("--skip-fetch", action="store_true", help="only trace existing cutouts")
    ap.add_argument("--skip-trace", action="store_true", help="only fetch and cut out")
    args = ap.parse_args()
    work, out = Path(args.work).resolve(), Path(args.out).resolve()
    if not args.skip_fetch:
        fetch(args, work)
    if not args.skip_trace:
        trace(args, work, out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
