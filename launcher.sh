#!/usr/bin/env bash
set -euo pipefail

# line-launcher wrapper.
#
# Quickshell has no way to hand argv or stdin to QML, so this script does the
# translation: CLI flags become environment variables, piped stdin becomes a
# file, and the dmenu selection comes back through another file.
#
# LINE_LAUNCHER_QML_DIR is exported by the Nix wrapper. When unset (running
# straight from a checkout) it defaults to the directory holding this script.

usage() {
	cat <<'USAGE'
line-launcher - a Wayland application launcher

Usage:
  line-launcher [OPTIONS]
  <command> | line-launcher [OPTIONS]      # dmenu mode

Options:
  --toggle          close the running launcher, or open it if it is not running
  --items N         show N result rows for this invocation
  --prompt TEXT     placeholder text for the input field
  --config PATH     use an alternate config.json
  -n, --namespace NAME
                    layer-shell namespace for the surface, used verbatim
                    (default: line-launcher). Compositor rules that match on
                    the namespace key off this.
  -h, --help        show this help

When stdin is not a terminal, line-launcher lists the piped lines instead of
applications, prints the chosen line to stdout, and exits 1 with no output if
cancelled.
USAGE
}

qml_dir=${LINE_LAUNCHER_QML_DIR:-}
if [ -z "$qml_dir" ]; then
	qml_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fi

items=
prompt=
config=
namespace=
toggle=

while [ $# -gt 0 ]; do
	case $1 in
	--toggle)
		toggle=1
		shift
		;;
	--items)
		[ $# -ge 2 ] || { echo "line-launcher: --items needs a value" >&2; exit 2; }
		items=$2
		shift 2
		;;
	--items=*)
		items=${1#*=}
		shift
		;;
	--prompt)
		[ $# -ge 2 ] || { echo "line-launcher: --prompt needs a value" >&2; exit 2; }
		prompt=$2
		shift 2
		;;
	--prompt=*)
		prompt=${1#*=}
		shift
		;;
	--config)
		[ $# -ge 2 ] || { echo "line-launcher: --config needs a value" >&2; exit 2; }
		config=$2
		shift 2
		;;
	--config=*)
		config=${1#*=}
		shift
		;;
	-n | --namespace)
		[ $# -ge 2 ] || { echo "line-launcher: --namespace needs a value" >&2; exit 2; }
		namespace=$2
		shift 2
		;;
	--namespace=* | -n=*)
		namespace=${1#*=}
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "line-launcher: unknown option: $1" >&2
		usage >&2
		exit 2
		;;
	esac
done

# A compositor hotkey needs toggle semantics: invoking the same command a
# second time closes this exact Quickshell configuration.  `qs kill` exits
# non-zero when no matching instance exists, in which case we continue and
# launch one below.
if [ -n "$toggle" ] && qs kill --path "$qml_dir" >/dev/null 2>&1; then
	exit 0
fi

if [ -n "$items" ]; then
	case $items in
	'' | *[!0-9]*)
		echo "line-launcher: --items expects a positive integer, got: $items" >&2
		exit 2
		;;
	esac
	export LINE_LAUNCHER_ITEMS=$items
fi

if [ -n "$prompt" ]; then
	export LINE_LAUNCHER_PROMPT=$prompt
fi

if [ -n "$namespace" ]; then
	export LINE_LAUNCHER_NAMESPACE=$namespace
fi

if [ -n "$config" ]; then
	if [ ! -r "$config" ]; then
		echo "line-launcher: cannot read config: $config" >&2
		exit 2
	fi
	config_abs=$(CDPATH='' cd -- "$(dirname -- "$config")" && printf '%s/%s' "$PWD" "$(basename -- "$config")")
	export LINE_LAUNCHER_CONFIG=$config_abs
fi

runtime_dir=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/line-launcher.XXXXXX")
trap 'rm -rf -- "$runtime_dir"' EXIT INT TERM

dmenu=
if [ -z "$toggle" ] && [ ! -t 0 ]; then
	dmenu=1
	cat >"$runtime_dir/stdin"
	export LINE_LAUNCHER_DMENU_IN="$runtime_dir/stdin"
	export LINE_LAUNCHER_DMENU_OUT="$runtime_dir/selection"
fi

qs_args=(--path "$qml_dir")
if [ -z "$dmenu" ]; then
	# A launcher bound to a hotkey should not stack overlays if the key is
	# hit twice. Piped invocations are independent, so they skip this.
	qs_args+=(--no-duplicate)
fi

# Quickshell logs to stdout. In dmenu mode stdout is the caller's pipe and must
# carry nothing but the chosen line, so the logs go to stderr in both modes.
status=0
qs "${qs_args[@]}" </dev/null >&2 || status=$?

if [ -n "$dmenu" ]; then
	if [ -s "$runtime_dir/selection" ]; then
		cat -- "$runtime_dir/selection"
		exit 0
	fi
	exit 1
fi

exit "$status"
