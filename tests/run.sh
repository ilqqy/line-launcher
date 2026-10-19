#!/usr/bin/env bash
set -euo pipefail

# Headless test runner. Quickshell resolves shell types relative to the
# directory passed to `qs -p`, so each test file is staged next to the sources
# rather than run from tests/.

repo=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
	rm -rf -- "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Tests must not share Quickshell IPC/runtime state with the desktop session.
export XDG_RUNTIME_DIR="$work/runtime"
mkdir -m 700 "$XDG_RUNTIME_DIR"
export XDG_CONFIG_HOME="$work/config"
unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE

cp -r -- "$repo"/*.qml "$repo"/*.js "$repo"/qmldir "$work/"
if [ -d "$repo/providers" ]; then
	cp -r -- "$repo/providers" "$work/"
fi
rm -f -- "$work/shell.qml"

cat >"$work/colors.json" <<'JSON'
{
  "special": { "foreground": "#00ff00" },
  "colors": { "color0": "#101010", "color1": "#ff0000", "color6": "#0000ff" }
}
JSON

cat >"$work/config.json" <<JSON
{
  "colorsFile": "$work/colors.json",
  "colorsFormat": "pywal",
  "accentKey": "color6",
  "frameWidth": 300,
  "drunCache": "$work/druncache",
  "actions": [
    { "name": "Power off", "exec": "systemctl poweroff", "confirm": true },
    { "name": "Lock", "exec": "hyprlock" }
  ]
}
JSON

export LINE_LAUNCHER_CONFIG="$work/config.json"
export LINE_LAUNCHER_ITEMS=9
export LINE_LAUNCHER_PROMPT="run:"
printf 'alpha\nbeta\tsecond column\n' >"$work/piped"
export LINE_LAUNCHER_DMENU_IN="$work/piped"
export LINE_LAUNCHER_DMENU_OUT="$work/selection"
# Every suite runs in dmenu mode, which must win over a resident flag leaked
# into the environment (tests/frame.qml checks it).
export LINE_LAUNCHER_RESIDENT=1
export XDG_STATE_HOME="$work/state"
export XDG_CACHE_HOME="$work/cache"
export QT_QPA_PLATFORM=offscreen

run_suite() {
	cp -- "$1" "$work/shell.qml"
	local log="$work/suite.log" result=0
	timeout 30s qs --no-color --path "$work" >"$log" 2>&1 || result=$?
	# Keep errors and warnings visible as well as QML assertions.
	sed 's/^.*qml: //' "$log"
	if [ "$result" -ne 0 ]; then
		return "$result"
	fi
	# A clean process exit without reaching the assertions is not a pass.
	grep -qE 'qml: PASS$' "$log"
}

status=0
echo "== wrapper"
bash "$repo/tests/wrapper.sh" || status=1
for test_file in "$repo"/tests/*.qml; do
	name=$(basename -- "$test_file" .qml)
	# Needs a different environment; run separately below.
	if [[ "$name" == detect || "$name" == desktop-entries ]]; then
		continue
	fi
	echo "== $name"
	if ! run_suite "$test_file"; then
		status=1
	fi
done

# Colours-file auto-detection needs the opposite setup from every other suite:
# no colorsFile configured, and a palette sitting where pywal would leave it.
echo "== detect"
mkdir -p "$work/cache/wal"
cat >"$work/cache/wal/colors.json" <<'JSON'
{
  "special": { "foreground": "#c4c5c6", "background": "#13171b" },
  "colors": {
    "color0": "#13171b", "color1": "#DEB2A6", "color2": "#F4C9B6",
    "color3": "#ACC2CC", "color4": "#DCD2D5", "color5": "#FDECD7",
    "color6": "#D3D9E6", "color7": "#c4c5c6"
  }
}
JSON
cat >"$work/detect-config.json" <<'JSON'
{ "frameWidth": 300 }
JSON
if ! LINE_LAUNCHER_CONFIG="$work/detect-config.json" run_suite "$repo/tests/detect.qml"; then
	status=1
fi
rm -rf -- "$work/cache/wal"

# Application-list refresh on its own data dirs, so the system's applications
# stay out of it: one plain dir, and one reached through a Nix-style profile
# symlink that the suite switches to a new generation.
echo "== desktop-entries"
xdg=$work/xdg
mkdir -p "$xdg/home" "$xdg/plain/applications" "$xdg/gen1/share/applications"
printf '[Desktop Entry]\nType=Application\nName=One\nExec=true\n' >"$xdg/plain/applications/one.desktop"
printf '[Desktop Entry]\nType=Application\nName=Two\nExec=true\n' >"$xdg/gen1/share/applications/two.desktop"
ln -s gen1 "$xdg/profile"
if ! XDG_DATA_HOME="$xdg/home" XDG_DATA_DIRS="$xdg/plain:$xdg/profile/share" \
	LINE_LAUNCHER_TEST_XDG="$xdg" run_suite "$repo/tests/desktop-entries.qml"; then
	status=1
fi

# The resident lifecycle (show, hide, toggle, the reset on every show) is in
# shell.qml's logic section, which only runs with the window stubbed out:
# built the same way as tests/baseline/run.sh builds the search baseline.
echo "== resident"
awk '/^    \/\/ -+ window$/ { exit } { print }' "$repo/shell.qml" >"$work/resident-suite.qml"
cat -- "$repo/tests/resident/harness.qml" >>"$work/resident-suite.qml"
if ! (
	unset LINE_LAUNCHER_DMENU_IN LINE_LAUNCHER_DMENU_OUT
	export LINE_LAUNCHER_RESIDENT=1
	run_suite "$work/resident-suite.qml"
); then
	status=1
fi

# The suites above cannot instantiate shell.qml: it is rooted in a PanelWindow,
# and there is no layer-shell backend under the offscreen platform. Loading it
# anyway still compiles every component and resolves every type and import in
# the file, so anything but that one expected error is a real failure.
check_loads() {
	local label=$1 path=$2 load_log unexpected
	echo "== $label loads"
	load_log=$(timeout 15s qs --no-color --path "$path" 2>&1 || true)
	if printf '%s' "$load_log" | grep -q "No PanelWindow backend loaded"; then
		unexpected=$(printf '%s' "$load_log" | grep -E "ERROR|WARN.*scene" | grep -v "No PanelWindow backend loaded" | grep -v "Failed to load configuration" || true)
		if [ -n "$unexpected" ]; then
			echo "FAIL unexpected diagnostics while loading $label:"
			printf '%s\n' "$unexpected"
			return 1
		fi
		echo "ok   $label compiled; only the expected offscreen backend error"
	else
		echo "FAIL $label did not reach the PanelWindow stage:"
		printf '%s\n' "$load_log" | tail -5
		return 1
	fi
}

check_loads shell.qml "$repo" || status=1
# The resident entry point is a symlink to shell.qml; it must load under its
# own path (that is what keeps its IPC apart from one-off instances).
(
	unset LINE_LAUNCHER_DMENU_IN LINE_LAUNCHER_DMENU_OUT
	export LINE_LAUNCHER_RESIDENT=1
	check_loads resident.qml "$repo/resident.qml"
) || status=1

exit "$status"
