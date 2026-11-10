# Plant component provenance

All shipped `.dat` plant components are original procedural geometry authored
in this repository. They are generated from
`experiments/plant_3d/plant_components.py` and `mesh_geometry.py`; they do not
contain downloaded third-party meshes, textures, rigs, or sampled photographs.
The repository's own licensing terms apply to these authored assets.

The library contains 24 leaf families, 32 flower families and five bud families,
with four variants per family and closed/open endpoints for 19 flower families.
`catalog.json` records the source SHA-256, asset revision, individual compressed
and raw hashes, geometry counts and measured morph-endpoint approximation error.
Rebuild with `python3 experiments/plant_3d/bake_runtime.py` (NumPy, offline only).

The separately researched online source is documented in
[`experiments/plant_3d/SOURCE_AUDIT.md`](../../experiments/plant_3d/SOURCE_AUDIT.md).
It is not part of these runtime assets or their counts.

See [`gen/plant_3d/README.md`](../../gen/plant_3d/README.md) for the native Godot
API, replay contract, binary format reader and required export include filter.
