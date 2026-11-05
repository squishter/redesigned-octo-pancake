# Web imagery → line art for collages: options

Goal: a scrollable, searchable list of line art drawn from images on the web
(the isolated subject when there is one), each of which can become a Gem
Collage.

> **Status (prototype built):** architecture B exists as `tools/web_art/`
> with a 57-picture Met catalog in `assets/web_art/` and a searchable
> browser in the generator lab; see the README's *Web line-art catalog*.
> Findings so far: IS-Net cutouts are clean on museum object photos; the
> remaining weakness is busy patterns (painted porcelain, engraving)
> tracing into dense black masses at 640 px, which edge sharpness can't
> fix because those edges really are sharp. The Met retired `v1/search`
> on 2026-10-01 (use `v1.1/search`, paged); the AIC answers cloud IPs with
> a Cloudflare challenge.

## What we already have

The hard half is done. `PictureSources` already turns any picture into a
collage:

- `PhotoEdges.line_art(photo, {detail, subject})` (`gen/photo_edges.gd`):
  Kuwahara smoothing → Lab edges → gap closing → **subject isolation** by
  boundary-connectivity saliency, cropped around the subject. Pure GDScript,
  offline, no dependencies.
- `PictureSources.line_art_collage(img)` (`gen/picture_sources.gd`): any
  dark-lines-on-light image (or transparent PNG) → collage directly.
- `PhotoLoader.from_bytes()` (`game/photo_loader.gd`): JPEG/PNG/WebP bytes →
  upright `Image`, which is exactly what an `HTTPRequest` body gives us.

So the new work is: **finding images, licensing, a list UI with caching, and
optionally better isolation/line quality than the saliency heuristic.**

## 1. Where the images come from

Rule out general image search (Google/Bing scraping): unknown copyright, and
it breaks their terms. Use sources whose licenses allow modification.

| Source | Key? | License of results | Fit for line art | Notes |
| --- | --- | --- | --- | --- |
| **Openverse** (api.openverse.org) | Yes now (OAuth2 client_credentials; anonymous search was cut off for abuse) | CC0 / PD / CC BY / BY-SA; filter `license_type=commercial,modification` | Good. Aggregates Wikimedia, Flickr, museums. Has a `category` filter (photograph / illustration / digitized_artwork) | One API, many sources, attribution fields returned per image. Best single choice for live search. |
| **Wikimedia Commons** (MediaWiki API) | No (send a descriptive User-Agent) | Mostly CC / PD, per file | Good; huge archive of engravings, diagrams, botanical plates that are *already* line art | `generator=search&gsrnamespace=6&prop=imageinfo&iiprop=url|extmetadata&iiurlwidth=320` gives thumbs + license in one call. |
| **Pixabay** | Yes (free) | Pixabay Content License (modify, commercial, no attribution required) | Very good: `image_type=vector` / `illustration` returns clean flat art that traces into tidy regions | Must not hotlink permanently: download and cache; cache responses 24 h; link to Pixabay; no bulk scraping. |
| **Museum open access** (Met, Art Institute of Chicago, Smithsonian, Cleveland) | Met/AIC/Cleveland: no; Smithsonian: api.data.gov key | CC0 for the open-access subset | Excellent for prints, etchings, botanical and natural-history illustration | Narrower, but beautiful and legally clean. Great for a curated catalog. |
| **Openclipart / CC0 SVG sets** | No | CC0 | Best possible: already vector line art | `Image.load_svg_from_buffer()` rasterizes, then `line_art_collage()`. No edge detection needed. |
| Unsplash / Pexels | Yes | Free licenses, photos only | Photos (need conversion) | **Unsplash requires hotlinking its URLs and attribution**, which fits poorly with showing a derived drawing. Pexels is looser but still photos only. Lower priority. |

API keys inside an APK are extractable. Fine for Pixabay/Openverse at hobby
scale; at scale put a tiny proxy (Cloudflare Worker or similar) in front that
holds the keys and caches responses.

## 2. Isolating the subject

| Option | Where it runs | Quality | Cost |
| --- | --- | --- | --- |
| **Existing saliency** in `photo_edges.gd` (`subject: "auto"/"on"`) | On device, GDScript | OK on clean product-style shots, weak on busy scenes | Zero; works today |
| **ML Kit Subject Segmentation** (`play-services-mlkit-subject-segmentation`) | On device, Android 7+ (API 24), model via Play services (~200 KB in APK) | Very good, multi-subject, gives a foreground confidence mask | Needs a Godot v2 Android plugin (Kotlin) to pass bytes in and a mask out. Android only, beta, needs Play services |
| **MediaPipe Interactive Segmenter** | On device (LiteRT) | Good; user taps the thing they want | Plugin work as above; nice UX for "pick the cat, not the sofa" |
| **rembg / BiRefNet / U²-Net** | Server or offline tool (Python) | Very good to excellent | Not practical inside Godot without a native runtime; ideal in a batch pipeline |

Whichever mask we get, it slots into the existing step: AND the edge map with
a slightly dilated mask, add the mask outline as a line, crop. That's what
`photo_edges.gd` already does with its saliency mask, so an external mask can
be passed in as an option (`subject_mask`) without touching the rest.

Also cheap: many illustration/vector results already have **transparent
backgrounds** (Pixabay vectors, SVGs, PNG clip art). Alpha *is* the subject
mask; use it before trying anything else.

## 3. Turning the image into line art

| Option | Notes |
| --- | --- |
| **Existing `PhotoEdges`** | Good enough for most photos, tuned for gems (closed regions, specks dropped). Default. |
| **`line_art_collage()` directly** | For SVG/clip art/engravings that are already lines: threshold + dilate. Detect with a quick check (few colors, mostly near-white, high-contrast strokes). |
| **informative-drawings** (Chan et al., CVPR 2022, MIT code) | ML photo → artistic line drawing. ONNX conversions exist (~8.6 MB fp16; input RGB 0..1, output white background, dark lines). Much more "drawn" look than edge detection. Its output then goes through `line_art_collage()` with gap closing. Needs a native runtime (ONNX Runtime / LiteRT) via plugin, or run it offline. Check weight licenses before shipping. |
| TEED / PiDiNet / Anime2Sketch | Smaller edge/sketch models; similar trade-off. |

ML outputs aren't guaranteed to form closed regions, so the existing
gap-closing (`REACH`) and speck removal still matter; route ML output through
the same cleanup.

## 4. Two architectures

### A. Live search on device

Search box → API (Openverse/Pixabay/Commons) → thumbnails (~320 px) →
`PhotoEdges.line_art()` on each visible card → line-art preview in a grid.

- Pros: unlimited content, no backend.
- Cons: `PhotoEdges` runs in GDScript at 640 px working size; doing it for
  every card while scrolling will stutter. Needs a `WorkerThreadPool` queue,
  lazy conversion of only visible cards, and caching in `user://`. Results
  are hit-and-miss: some photos make poor line art, and the user only finds
  out after conversion. Needs the `INTERNET` permission (the Android preset
  only has camera and vibrate today).

### B. Curated catalog built offline (recommended as the main list)

A Python tool in `tools/` pulls from CC0/PD sources (museum open access,
Openclipart, Commons, Pixabay vectors) → rembg/BiRefNet isolates the subject
→ informative-drawings or our own edge pass → cleanup and a "makes a good
collage" check (region count, closed areas, not too dense) → line-art PNG
plus a JSON index entry:

```json
{"id": "met-436121", "title": "Peony", "tags": ["flower", "peony", "botanical"],
 "file": "met-436121.png", "thumb": "met-436121_t.webp",
 "source": "The Met", "license": "CC0", "url": "https://..."}
```

Host the index and PNGs statically (GitHub Pages/Releases or a bucket). The
app downloads the index (a few hundred KB for thousands of entries), searches
**locally** over title + tags (instant, works offline once cached), and lazily
fetches thumbnails as cards scroll in. Picking one feeds the PNG straight into
`line_art_collage()`.

- Pros: every item is known to make a good collage; best isolation and line
  quality (Python ML, no on-device runtime); licenses vetted once; no API keys
  in the APK; fast scrolling; tags can be enriched (e.g. auto-tagging).
- Cons: content is limited to what we've processed; needs a hosting spot and
  a rebuild script.

### Hybrid

Ship B as the list. Add a "Search the web" row at the end of results that
falls back to A (Openverse, `category=illustration` first, then photos) using
`PhotoEdges`, clearly labelled as "may vary". Later, an ML Kit plugin can
upgrade A's subject isolation without changing the UI.

## 5. App-side pieces (either architecture)

- **List UI:** `ScrollContainer` + `HFlowContainer`/`GridContainer` of cards,
  or `ItemList` in icon mode (cheap for hundreds of items). Load thumbnails
  only for cards near the viewport; cap concurrent `HTTPRequest`s (~4).
- **Search:** `LineEdit` with a short debounce; local filter over the index
  (catalog) or an API request (live). Show attribution under each card or in
  the detail view (required for CC BY results).
- **Cache:** `user://web_art/<id>.png` + index with timestamps; honor
  Pixabay's 24 h rule for its search responses; downloaded images we've
  converted are ours to keep under its license.
- **Saved puzzles** should record the source id, URL and license in the
  request's `source` dict (already a pattern: `{"kind": "photo", ...}`), so the
  completed gallery can credit it.
- **Export preset:** add `permissions/internet=true`.

## Suggested first step

Prototype B small: a `tools/web_art/build_catalog.py` that pulls ~50 CC0
items from The Met / Art Institute of Chicago open access (no keys needed),
runs rembg + a simple edge pass, writes PNGs and `index.json`. Load that
index from `res://` in the generator lab with a searchable grid, to judge how
many web images actually make good collages before building hosting or the
live-search path.
