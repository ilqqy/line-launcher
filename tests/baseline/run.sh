#!/usr/bin/env bash
set -euo pipefail

# Search-layer baseline.
#
# Runs every query in queries.json through the real search layer -- shell.qml
# up to its window section, the providers, rofi-search.js, the real
# DesktopEntries index -- and dumps the ordered results as JSON.
#
#   tests/baseline/run.sh            compare against baseline.json (exit 1 on any difference)
#   tests/baseline/run.sh --record   (re)write baseline.json
#
# History is read from fixtures/ (snapshots of config.json, the druncache and
# command history), never from the live files, so launching apps between runs
# does not move the baseline. The application set is the live system's; it is
# recorded in the output as `catalog`, so input drift shows up as a catalog
# diff rather than as an unexplained ranking change.

here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(CDPATH='' cd -- "$here/../.." && pwd)

mode=compare
case ${1:-} in
'') ;;
--record) mode=record ;;
*)
	echo "usage: $0 [--record]" >&2
	exit 2
	;;
esac

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

cp -r -- "$repo"/*.qml "$repo"/*.js "$repo"/qmldir "$work/"
cp -r -- "$repo/providers" "$work/"

# shell.qml verbatim up to the window section, then the harness in its place.
marker='^    // -+ window$'
if ! grep -qE "$marker" "$repo/shell.qml"; then
	echo "FAIL shell.qml has no window section marker" >&2
	exit 1
fi
awk -v marker="$marker" '$0 ~ marker { exit } { print }' "$repo/shell.qml" >"$work/shell.qml"
cat -- "$here/harness.qml" >>"$work/shell.qml"

mkdir -p "$work/runtime" "$work/config" "$work/cache" "$work/state/line-launcher"
chmod 700 "$work/runtime"
cp -- "$here/fixtures/config.json" "$work/config.json"
cp -- "$here/fixtures/druncache" "$work/cache/line-launcher.druncache"
cp -- "$here/fixtures/history.json" "$work/state/line-launcher/history.json"

export XDG_RUNTIME_DIR="$work/runtime"
export XDG_CONFIG_HOME="$work/config"
export XDG_CACHE_HOME="$work/cache"
export XDG_STATE_HOME="$work/state"
export LINE_LAUNCHER_CONFIG="$work/config.json"
export BASELINE_QUERIES="$here/queries.json"
export BASELINE_OUT="$work/current.json"
export QT_QPA_PLATFORM=offscreen
unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
unset LINE_LAUNCHER_DMENU_IN LINE_LAUNCHER_DMENU_OUT LINE_LAUNCHER_ITEMS
unset LINE_LAUNCHER_PROMPT LINE_LAUNCHER_NAMESPACE

status=0
timeout 60s qs --no-color --path "$work" >"$work/qs.log" 2>&1 || status=$?
if [ ! -s "$work/current.json" ]; then
	echo "FAIL harness produced no output (qs exit $status):" >&2
	cat -- "$work/qs.log" >&2
	exit 1
fi
grep -E 'BASELINE|ERROR|WARN' "$work/qs.log" | sed 's/^.*qml: //' >&2 || true

if [ "$mode" = record ]; then
	cp -- "$work/current.json" "$here/baseline.json"
	echo "RECORDED $here/baseline.json"
	exit 0
fi

if diff -u --label baseline.json --label current.json \
	"$here/baseline.json" "$work/current.json"; then
	echo "BASELINE: IDENTICAL"
else
	echo "BASELINE: DIFFERS"
	exit 1
fi
