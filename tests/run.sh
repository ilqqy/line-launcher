#!/usr/bin/env bash
set -euo pipefail

# Headless test runner. Quickshell resolves shell types relative to the
# directory passed to `qs -p`, so each test file is staged next to the sources
# rather than run from tests/.

repo=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT INT TERM

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
export XDG_STATE_HOME="$work/state"
export XDG_CACHE_HOME="$work/cache"
export QT_QPA_PLATFORM=offscreen

run_suite() {
	cp -- "$1" "$work/shell.qml"
	qs --path "$work" 2>&1 | sed -n 's/^.*qml\x1b\[0m: //p'
}

status=0
for test_file in "$repo"/tests/*.qml; do
	name=$(basename -- "$test_file" .qml)
	# Needs a different environment; run separately below.
	if [ "$name" = "detect" ] || [ "$name" = "preview" ] || [ "$name" = "glow" ]; then
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

# The glow suite wants a font size away from the default, so that "the radii
# scale with fontSize" is a measurement and not an identity that holds at 1x.
echo "== glow"
sed 's/^{$/{ "fontSize": 28,/' "$work/config.json" >"$work/glow-config.json"
if ! LINE_LAUNCHER_CONFIG="$work/glow-config.json" run_suite "$repo/tests/glow.qml"; then
	status=1
fi

echo "== glow, disabled"
sed 's/^{$/{ "glowEnabled": false,/' "$work/config.json" >"$work/glow-off-config.json"
if ! LINE_LAUNCHER_CONFIG="$work/glow-off-config.json" run_suite "$repo/tests/glow.qml"; then
	status=1
fi

# The scene-graph suite. Every suite above runs under QT_QPA_PLATFORM=offscreen,
# which reports no OpenGL capability and so falls back to the software
# renderer -- and under the software renderer every ShaderEffect draws nothing,
# which makes both MultiEffect and RectangularShadow silent no-ops. Testing the
# glow there would prove nothing, so this one wants a real X server. Any will
# do; Xvfb is the one that needs no display.
if command -v Xvfb >/dev/null 2>&1; then
	Xvfb :99 -screen 0 1024x768x24 +extension GLX >"$work/xvfb.log" 2>&1 &
	xvfb_pid=$!
	# Give the server a moment to come up before anything connects to it.
	for _ in $(seq 1 40); do
		[ -e /tmp/.X11-unix/X99 ] && break
		sleep 0.1
	done

	# A realistic palette rather than the primary colours the assertion
	# suites use, since the point of this one is to be looked at.
	cat >"$work/preview-colors.json" <<'JSON'
{
  "special": { "foreground": "#c4c5c6", "background": "#13171b" },
  "colors": {
    "color0": "#13171b", "color1": "#DEB2A6", "color2": "#F4C9B6",
    "color3": "#ACC2CC", "color4": "#DCD2D5", "color5": "#FDECD7",
    "color6": "#D3D9E6", "color7": "#c4c5c6"
  }
}
JSON

	cat >"$work/preview-config.json" <<JSON
{ "colorsFile": "$work/preview-colors.json", "colorsFormat": "pywal" }
JSON

	# The same configuration, with the glow switched off -- so the two
	# previews differ in exactly one setting.
	sed 's/^{ /{ "glowEnabled": false, /' "$work/preview-config.json" >"$work/glow-off.json"

	preview_out=${LINE_LAUNCHER_PREVIEW_DIR:-}

	# Switched over wholesale rather than per-run: a subshell would keep the
	# changes local, but it would also swallow the exit status the loop
	# below needs.
	export QT_QPA_PLATFORM=xcb
	export DISPLAY=:99
	export LINE_LAUNCHER_ITEMS=5

	shots=$work/shots
	mkdir -p "$shots"
	rects=

	for variant in glow plain; do
		if [ "$variant" = "glow" ]; then
			echo "== preview (Xvfb)"
			export LINE_LAUNCHER_CONFIG="$work/preview-config.json"
		else
			echo "== preview, glow disabled (Xvfb)"
			export LINE_LAUNCHER_CONFIG="$work/glow-off.json"
		fi

		export LINE_LAUNCHER_PREVIEW_OUT="$shots/$variant.png"
		if ! out=$(run_suite "$repo/tests/preview.qml"); then
			status=1
		fi
		printf '%s\n' "$out"

		# The suite reports the rectangles off its own live items, so these
		# survive any change to the layout.
		if [ "$variant" = "glow" ]; then
			rects=$(printf '%s\n' "$out" | sed -n 's/^ *RECT //p')
		fi

		if [ -n "$preview_out" ]; then
			cp -- "$shots/$variant.png" "$preview_out/preview-$variant.png"
		fi
	done

	# Whether the halo is actually on the glass, region by region.
	#
	# Structural assertions cannot see this: an effect can be constructed,
	# sized and handed the right source and still draw nothing. The only
	# proof is that the pixels moved, so each region is compared between the
	# two renders and has to have got darker.
	if command -v magick >/dev/null 2>&1; then
		echo "== preview pixels (Xvfb)"
		while read -r name x y w h metric; do
			[ -n "$name" ] || continue
			crop="${w}x${h}+${x}+${y}"

			# "darker" reads overall shade, "warmer" reads red against
			# blue, which is where the accent shows and a neutral halo
			# does not.
			if [ "$metric" = "warmer" ]; then
				format='%[fx:mean.b-mean.r]'
				expected="carrying the accent"
				missing="has no accent aura"
			else
				format='%[fx:mean]'
				expected="sitting in its own halo"
				missing="has no halo"
			fi

			lit=$(magick "$shots/glow.png" -background white -alpha remove \
				-crop "$crop" +repage -format "$format" info:)
			bare=$(magick "$shots/plain.png" -background white -alpha remove \
				-crop "$crop" +repage -format "$format" info:)
			if awk -v a="$lit" -v b="$bare" 'BEGIN { exit !(b - a > 0.002) }'; then
				printf 'ok   the %s is %s  (%s lit vs %s bare)\n' \
					"$name" "$expected" "$lit" "$bare"
			else
				printf 'FAIL the %s %s  %s lit vs %s bare\n' \
					"$name" "$missing" "$lit" "$bare"
				status=1
			fi
		done <<EOF
$rects
EOF
	else
		echo "== preview pixels  SKIPPED (no magick on PATH; nix develop provides one)"
	fi

	unset DISPLAY LINE_LAUNCHER_PREVIEW_OUT
	export QT_QPA_PLATFORM=offscreen
	export LINE_LAUNCHER_ITEMS=9
	export LINE_LAUNCHER_CONFIG="$work/config.json"

	kill "$xvfb_pid" 2>/dev/null || true
	wait "$xvfb_pid" 2>/dev/null || true
else
	echo "== preview  SKIPPED (no Xvfb on PATH; nix develop provides one)"
fi

# The suites above cannot instantiate shell.qml: it is rooted in a PanelWindow,
# and there is no layer-shell backend under the offscreen platform. Loading it
# anyway still compiles every component and resolves every type and import in
# the file, so anything but that one expected error is a real failure.
echo "== shell.qml loads"
load_log=$(qs --path "$repo" 2>&1 || true)
if printf '%s' "$load_log" | grep -q "No PanelWindow backend loaded"; then
	unexpected=$(printf '%s' "$load_log" | grep -E "ERROR|WARN.*scene" | grep -v "No PanelWindow backend loaded" | grep -v "Failed to load configuration" || true)
	if [ -n "$unexpected" ]; then
		echo "FAIL unexpected diagnostics while loading shell.qml:"
		printf '%s\n' "$unexpected"
		status=1
	else
		echo "ok   shell.qml compiled; only the expected offscreen backend error"
	fi
else
	echo "FAIL shell.qml did not reach the PanelWindow stage:"
	printf '%s\n' "$load_log" | tail -5
	status=1
fi

exit "$status"
