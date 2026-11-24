#!/usr/bin/env bash
# Runs Godot test suites in parallel, each with its own save folder, and
# prints one pass/fail line per suite. See SKILL.md for which to pick.
#
#   run_suites.sh [--out DIR] [--import] SUITE|@GROUP ...
#
# SUITE is a tests/run_*.gd name without the prefix or suffix ("generators",
# "plant_pictures"). GROUPs: @plants @generators @animals @ui @gems
# @placements @all. Logs go to DIR/<suite>.log (default:
# ${TMPDIR:-/tmp}/pwg-tests/<time>); DIR/summary.txt holds the summary.
# Exit status: 0 when every suite passed.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 2

out="${TMPDIR:-/tmp}/pwg-tests/$(date +%Y%m%d-%H%M%S)"
import=0
want=()
while [ $# -gt 0 ]; do
	case "$1" in
		--out) out="$2"; shift 2 ;;
		--out=*) out="${1#--out=}"; shift ;;
		--import) import=1; shift ;;
		*) want+=("$1"); shift ;;
	esac
done
[ ${#want[@]} -gt 0 ] || { sed -n 2,12p "$0"; exit 2; }

group() {
	case "$1" in
		@plants) echo plant_mesh plant_pictures source_recipe_io generators ;;
		@generators) echo generators gem_geometry source_recipe_io ;;
		@animals) echo animal_coats animal_pack animal_poses animal_pose_views ;;
		@ui) echo menu_ui color_stories_ui completed_puzzles_ui pack_bundles ;;
		@gems) echo gem_geometry saved_gem_proportions gem_normals ;;
		@placements) echo placements ;;
		@all) ls tests/run_*.gd | sed 's#tests/run_##; s#\.gd$##' ;;
		*) echo "${1#run_}" | sed 's#\.gd$##' ;;
	esac
}

suites=()
for w in "${want[@]}"; do
	for s in $(group "$w"); do
		[ -f "tests/run_$s.gd" ] || { echo "no such suite: tests/run_$s.gd" >&2; exit 2; }
		[[ " ${suites[*]-} " == *" $s "* ]] || suites+=("$s")
	done
done
# The slowest first, so it isn't the one everything waits on.
sorted=()
for s in generators animal_pose_views animal_coats; do
	[[ " ${suites[*]} " == *" $s "* ]] && sorted+=("$s")
done
for s in "${suites[@]}"; do
	[[ " ${sorted[*]-} " == *" $s "* ]] || sorted+=("$s")
done

mkdir -p "$out"
if [ "$import" = 1 ] || [ ! -d .godot ]; then
	echo "importing the project..."
	timeout 600 godot --headless --editor --import --quit > "$out/import.log" 2>&1
fi
if [[ " ${sorted[*]} " == *" placements "* ]] && [ ! -f build/placement-checks/legacy_gem_flights.gd ]; then
	python3 tests/prepare_placement_baseline.py > "$out/placement_baseline.log" 2>&1
fi

echo "running ${sorted[*]} -> $out"
start=$(date +%s)
for s in "${sorted[@]}"; do
	(
		cmd=(godot --headless -s "res://tests/run_$s.gd")
		[ "$s" = gem_normals ] && cmd=(xvfb-run -a godot --rendering-method mobile -s "res://tests/run_$s.gd")
		XDG_DATA_HOME="$out/data_$s" timeout 1700 "${cmd[@]}" > "$out/$s.log" 2>&1
		echo "exit $?" >> "$out/$s.log"
	) &
done
wait

"$(dirname "$0")/summarize.sh" "$out" | tee "$out/summary.txt"
echo "took $(( ($(date +%s) - start) / 60 )) min"
! grep -q '^FAIL\|^RUNNING' "$out/summary.txt"
