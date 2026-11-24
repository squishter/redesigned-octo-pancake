#!/usr/bin/env bash
# Renders the same plant seeds under several option sets in parallel and
# stitches them into one image, a row per option set.
#
#   compare.sh --out DIR [--seeds FIRST,COUNT] [--cell 512] [--take collage|lines|both] \
#       "NAME: --opt=value ..." "NAME2: --opt=value ..." ...
#
# Each "NAME: args" runs tests/plant_sheet.gd with those args into DIR/NAME;
# the stitched result is DIR/compare.png (and DIR/compare_small.png to view).
# Any plant_sheet / picture option works: --collar=halo --theme=garden
# --layout=fine --flower=rose --plant_min_region=0 ...
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/../../.." || exit 2
out=""
seeds="1,4"
cell=512
take=collage
sets=()
while [ $# -gt 0 ]; do
	case "$1" in
		--out) out="$2"; shift 2 ;;
		--seeds) seeds="$2"; shift 2 ;;
		--cell) cell="$2"; shift 2 ;;
		--take) take="$2"; shift 2 ;;
		*) sets+=("$1"); shift ;;
	esac
done
[ -n "$out" ] && [ ${#sets[@]} -gt 0 ] || { sed -n 2,12p "$0"; exit 2; }
first="${seeds%%,*}"
sheets=()
for set in "${sets[@]}"; do
	name="${set%%:*}"
	read -r -a opts <<< "${set#*:}"
	sheets+=("$out/$name/plants_$first.png")
	mkdir -p "$out/$name"
	(
		timeout 600 godot --headless -s res://tests/plant_sheet.gd -- --out="$out/$name" --seeds="$seeds" \
			--cell="$cell" "${opts[@]}" > "$out/$name.log" 2>&1
		grep -E '^seed|ERROR|Error' "$out/$name.log" | cut -c1-160 | sed "s/^/$name: /"
	) &
done
wait
python3 "$here/stitch.py" --out "$out/compare.png" --cell "$cell" --take "$take" "${sheets[@]}"
