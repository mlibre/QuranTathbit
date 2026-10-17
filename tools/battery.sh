#!/usr/bin/env bash
## The full regression battery, twice over.
##
## Pass 1 runs every headless suite in the machine's current .godot state.
## Pass 2 empties .godot/global_script_class_cache.cfg first and restores it
## afterwards -- the state of any machine that pulled new classes but has not
## opened the editor since. A suite may only call itself green if it passes
## both ways, because the stale state is exactly what a player's machine
## carries.
##
## Per-suite logs land in .godot/battery_logs/.
set -u
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
CACHE=".godot/global_script_class_cache.cfg"
BACKUP=".godot/global_script_class_cache.battery.bak"
LOGS=".godot/battery_logs"
HAD_CACHE=0
if [ -f "$CACHE" ]; then HAD_CACHE=1; fi

restore() {
	if [ "$HAD_CACHE" = 1 ]; then
		mv -f "$BACKUP" "$CACHE" 2>/dev/null || true
	else
		rm -f "$BACKUP" "$CACHE" 2>/dev/null || true
	fi
}
trap restore EXIT

mkdir -p "$LOGS"

# The export presets ride with every CI workflow; a head_include value that
# broke at a stray quote, an APK that lost an ABI, or a version code that
# forgot to move must fail here, loudly, before any workflow ships it.
if ! "$GODOT" --headless --path . --script tools/check_presets.gd >"$LOGS/check_presets.log" 2>&1; then
	echo "  FAIL  check_presets -- see .godot/battery_logs/check_presets.log"
	exit 1
fi

run_pass() {
	local label="$1"
	local failed=0
	for suite in tests/regression_*.gd; do
		[ -e "$suite" ] || continue
		local name
		name="$(basename "$suite" .gd)"
		if "$GODOT" --headless --path . --script "$suite" >"$LOGS/$name.$label.log" 2>&1; then
			echo "  PASS  $name ($label)"
		else
			echo "  FAIL  $name ($label) -- see .godot/battery_logs/$name.$label.log"
			failed=$((failed + 1))
		fi
	done
	return $failed
}

echo "battery pass 1 (warm cache)"
run_pass warm
WARM=$?
if [ "$WARM" -ne 0 ]; then
	echo "battery: $WARM suite(s) failed on a warm cache"
	exit 1
fi

if [ "$HAD_CACHE" = 1 ]; then
	cp "$CACHE" "$BACKUP"
	rm -f "$CACHE"
fi

echo "battery pass 2 (stale machine, no class cache)"
run_pass cold
COLD=$?
if [ "$COLD" -ne 0 ]; then
	echo "battery: $COLD suite(s) failed on a cold cache"
	exit 1
fi

echo "battery: all suites green, warm and cold"
