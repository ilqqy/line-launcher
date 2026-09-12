#!/usr/bin/env bash
set -euo pipefail

# Headless test runner. Quickshell resolves shell types relative to the
# directory passed to `qs -p`, so each test file is staged next to the sources
# rather than run from tests/.

repo=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
xvfb_pid=
# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
	if [ -n "$xvfb_pid" ]; then
		kill "$xvfb_pid" 2>/dev/null || true
		wait "$xvfb_pid" 2>/dev/null || true
	fi
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
	if [[ "$name" =~ ^(detect|preview|glow|alpha|smooth)$ ]]; then
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
	Xvfb -displayfd 3 -screen 0 1024x768x24 +extension GLX 3>"$work/display" >"$work/xvfb.log" 2>&1 &
	xvfb_pid=$!
	# Give the server a moment to come up before anything connects to it.
	for _ in $(seq 1 40); do
		[ -s "$work/display" ] && break
		sleep 0.1
	done
	if [ ! -s "$work/display" ] || ! kill -0 "$xvfb_pid" 2>/dev/null; then
		cat "$work/xvfb.log" >&2
		exit 1
	fi

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
	# Isolate the dark legibility halo from the brighter coloured aura; their
	# combined brightness cannot prove whether the dark halo was rendered.
	sed 's/^{ /{ "auraOpacity": 0, /' "$work/preview-config.json" >"$work/halo-only.json"

	preview_out=${LINE_LAUNCHER_PREVIEW_DIR:-}
	if [ -n "$preview_out" ]; then mkdir -p -- "$preview_out"; fi

	# Switched over wholesale rather than per-run: a subshell would keep the
	# changes local, but it would also swallow the exit status the loop
	# below needs.
	export QT_QPA_PLATFORM=xcb
	DISPLAY=":"$(cat "$work/display")
	export DISPLAY
	export LINE_LAUNCHER_ITEMS=5

	shots=$work/shots
	mkdir -p "$shots"
	rects=
	export LINE_LAUNCHER_CONFIG="$work/preview-config.json"
	echo "== smooth (Xvfb)"
	run_suite "$repo/tests/smooth.qml" || status=1
	echo "== alpha (Xvfb)"
	if ! alpha_log=$(LINE_LAUNCHER_ALPHA_DIR="$shots" run_suite "$repo/tests/alpha.qml"); then
		status=1
	fi
	printf '%s\n' "$alpha_log"
	if [ -n "$preview_out" ]; then cp -- "$shots"/alpha-*.png "$preview_out/"; fi
	if command -v magick >/dev/null 2>&1; then
		zones=$(printf '%s\n' "$alpha_log" | sed -n 's/^ *ZONE //p')
		if [ -z "$zones" ]; then
			echo "FAIL alpha suite did not report any measurement regions"
			status=1
		fi
		while read -r state region x y w h minimum; do
			[ -n "$state" ] || continue
			if [ "$region" = box ]; then
				outside=$(magick "$shots/alpha-$state.png" -alpha extract \
					-fill black -draw "rectangle $x,$y $w,$h" -format '%[fx:maxima.r]' info:)
				if awk -v value="$outside" 'BEGIN { exit !(value == 0) }'; then
					echo "ok   $state surface is fully transparent outside the content"
				else
					echo "FAIL $state surface paints outside the content (alpha=$outside)"
					status=1
				fi
			else
				alpha=$(magick "$shots/alpha-$state.png" -alpha extract \
					-crop "${w}x${h}+${x}+${y}" +repage -format '%[fx:minima.r]' info:)
				if awk -v value="$alpha" -v minimum="$minimum" 'BEGIN { exit !(value >= minimum - 0.005) }'; then
					echo "ok   frame fill covers the entire input box"
				else
					echo "FAIL frame fill has transparent holes"
					status=1
				fi
			fi
		done <<<"$zones"
	fi

	for variant in glow halo plain; do
		if [ "$variant" = "glow" ]; then
			echo "== preview (Xvfb)"
			export LINE_LAUNCHER_CONFIG="$work/preview-config.json"
		elif [ "$variant" = "halo" ]; then
			echo "== preview, legibility halo only (Xvfb)"
			export LINE_LAUNCHER_CONFIG="$work/halo-only.json"
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
		if [ -z "$rects" ]; then
			echo "FAIL preview did not report any measurement regions"
			status=1
		fi
		while read -r name x y w h metric; do
			[ -n "$name" ] || continue
			crop="${w}x${h}+${x}+${y}"

			# "darker" reads overall shade, "warmer" reads red against
			# blue, which is where the accent shows and a neutral halo
			# does not.
			if [ "$metric" = "warmer" ]; then
				lit_image="$shots/glow.png"
				format='%[fx:mean.b-mean.r]'
				expected="carrying the accent"
				missing="has no accent aura"
			else
				lit_image="$shots/halo.png"
				format='%[fx:mean]'
				expected="sitting in its own halo"
				missing="has no halo"
			fi

			lit=$(magick "$lit_image" -background white -alpha remove \
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
	xvfb_pid=
else
	echo "== preview  SKIPPED (no Xvfb on PATH; nix develop provides one)"
fi

# The suites above cannot instantiate shell.qml: it is rooted in a PanelWindow,
# and there is no layer-shell backend under the offscreen platform. Loading it
# anyway still compiles every component and resolves every type and import in
# the file, so anything but that one expected error is a real failure.
echo "== shell.qml loads"
load_log=$(timeout 15s qs --no-color --path "$repo" 2>&1 || true)
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
