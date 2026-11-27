#!/usr/bin/env bash
# Board benchmark under xvfb + software OpenGL.
#   bench.sh [--ref <git-ref>] [--project <dir>] -- <bench_board.gd options>
# With --ref, runs against a worktree of that ref (made under $SCRATCH or /tmp),
# so "before" and "after" can be printed one after the other.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
project="$(git -C "$here" rev-parse --show-toplevel)"
ref=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--ref) ref="$2"; shift 2 ;;
		--project) project="$2"; shift 2 ;;
		--) shift; break ;;
		*) break ;;
	esac
done
if [[ -n "$ref" ]]; then
	base="${SCRATCH:-${TMPDIR:-/tmp}}"
	wt="$base/bench-wt-$(git -C "$project" rev-parse --short "$ref")"
	if [[ ! -d "$wt" ]]; then
		git -C "$project" worktree add -q --detach "$wt" "$ref"
	fi
	project="$wt"
	if [[ ! -d "$project/.godot" ]]; then
		godot --headless --path "$project" --editor --import --quit >/dev/null 2>&1 || true
	fi
	echo "== $ref ($project)"
else
	echo "== working tree ($project)"
fi
timeout 600 xvfb-run -a godot --rendering-driver opengl3 --resolution 1080x1600 --path "$project" \
	-s "$here/bench_board.gd" -- "$@" 2>&1 | grep -Ev '^(ALSA|ERROR: Condition "status < 0"|   at: |WARNING: All audio|     at: )' \
	| grep -v '^$' || true
