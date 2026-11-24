#!/usr/bin/env bash
# One line per suite log in DIR: PASS, FAIL (with its first failing checks)
# or RUNNING. Safe to call while run_suites.sh is still going.
#   summarize.sh DIR
dir="${1:?usage: summarize.sh DIR}"
for log in "$dir"/*.log; do
	s=$(basename "$log" .log)
	case "$s" in import|placement_baseline) continue ;; esac
	code=$(grep -o '^exit [0-9]*' "$log" | tail -1 | cut -d' ' -f2)
	last=$(grep -v '^$' "$log" | grep -iv '^exit \|previews in' | grep -i 'pass\|checks\|failures\|fail' | tail -1 | cut -c1-110)
	if [ -z "$code" ]; then
		echo "RUNNING $s"
	elif [ "$code" = 0 ]; then
		echo "PASS    $s: $last"
	else
		echo "FAIL    $s (exit $code): $last"
		grep -v '^$' "$log" | grep -E '^ *FAIL|SCRIPT ERROR|Parse Error|Run python3' | grep -v '^FAILED' | sort -u | head -8 | cut -c1-200 | sed 's/^/          /'
	fi
done
