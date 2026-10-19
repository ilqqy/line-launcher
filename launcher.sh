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
  --daemon          run the resident launcher: start hidden and stay running,
                    shown and hidden by --toggle over IPC (see README)
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

With a resident launcher running (--daemon), --toggle, and a plain invocation
from a terminal, go to it over IPC. --items, --prompt, --config and
--namespace cannot be applied to an already running process: with any of
them the call opens a one-off launcher, as it does when no resident is
running. Pass them to --daemon to configure the resident launcher itself.
USAGE
}

qml_dir=${LINE_LAUNCHER_QML_DIR:-}
if [ -z "$qml_dir" ]; then
	qml_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fi

items=
items_set=
prompt=
config=
namespace=
toggle=
daemon=
# Set by any option that only a freshly started process can apply.
one_off_options=

# Only --daemon may put a process in resident mode; an inherited value (a
# terminal launched from the resident launcher, say) must not.
unset LINE_LAUNCHER_RESIDENT

while [ $# -gt 0 ]; do
	case $1 in
	--toggle)
		toggle=1
		shift
		;;
	--daemon)
		daemon=1
		shift
		;;
	--items)
		[ $# -ge 2 ] || { echo "line-launcher: --items needs a value" >&2; exit 2; }
		items=$2
		items_set=1
		shift 2
		;;
	--items=*)
		items=${1#*=}
		items_set=1
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

if [ -n "$toggle" ] && [ -n "$daemon" ]; then
	echo "line-launcher: --toggle and --daemon cannot be combined" >&2
	exit 2
fi

if [ -n "$items_set" ]; then
	one_off_options=1
	case $items in
	'' | *[!0-9]*)
		echo "line-launcher: --items expects a positive integer, got: $items" >&2
		exit 2
		;;
	esac
	# Strip leading zeroes without shell arithmetic (which treats them as octal).
	items=${items#"${items%%[!0]*}"}
	if [ -z "$items" ] || [ "${#items}" -gt 10 ] || { [ "${#items}" -eq 10 ] && [ "$items" -gt 2147483647 ]; }; then
		echo "line-launcher: --items must be between 1 and 2147483647" >&2
		exit 2
	fi
	export LINE_LAUNCHER_ITEMS=$items
fi

if [ -n "$prompt" ]; then
	one_off_options=1
	export LINE_LAUNCHER_PROMPT=$prompt
fi

if [ -n "$namespace" ]; then
	one_off_options=1
	export LINE_LAUNCHER_NAMESPACE=$namespace
fi

if [ -n "$config" ]; then
	if [ ! -r "$config" ]; then
		echo "line-launcher: cannot read config: $config" >&2
		exit 2
	fi
	config_abs=$(CDPATH='' cd -- "$(dirname -- "$config")" && printf '%s/%s' "$PWD" "$(basename -- "$config")")
	one_off_options=1
	export LINE_LAUNCHER_CONFIG=$config_abs
fi

# The resident launcher runs resident.qml, a symlink to shell.qml. Quickshell
# keys instances on the path they were started with, so the resident instance
# is a config of its own: one-off launchers and piped menus (started with the
# directory) never answer its IPC, and `qs kill`/--no-duplicate on them never
# touch it.
resident_path=$qml_dir/resident.qml
# The resident launcher's pid; exec keeps it the pid of Quickshell. Only a
# hint: it saves the IPC round trip (a whole Quickshell process) on every
# --toggle when no resident launcher is running.
resident_pid_file=${XDG_RUNTIME_DIR:-/tmp}/line-launcher-$UID-resident.pid

if [ -n "$daemon" ]; then
	unset LINE_LAUNCHER_DMENU_IN LINE_LAUNCHER_DMENU_OUT
	export LINE_LAUNCHER_RESIDENT=1
	printf '%s\n' "$$" >"$resident_pid_file"
	# exec, so a service manager supervises Quickshell itself. Logs go to
	# stderr like everywhere else; stdin is never a menu here.
	exec qs --path "$resident_path" --no-duplicate </dev/null >&2
fi

resident_alive() {
	local pid
	[ -r "$resident_pid_file" ] || return 1
	read -r pid <"$resident_pid_file" || return 1
	case $pid in '' | *[!0-9]*) return 1 ;; esac
	kill -0 "$pid" 2>/dev/null
}

# Piped stdin is a menu, unless this is --toggle.
dmenu=
if [ -z "$toggle" ] && [ ! -t 0 ]; then
	dmenu=1
fi

# A running resident launcher answers first; nothing else is spawned. If none
# answers -- not running, mid-restart after a crash, too old to know the
# call -- fall through to the one-off launcher below.
if [ -z "$dmenu" ] && [ -z "$one_off_options" ] && resident_alive; then
	call=show
	if [ -n "$toggle" ]; then call=toggle; fi
	if qs ipc --path "$resident_path" call launcher "$call" >/dev/null 2>&1; then
		exit 0
	fi
fi

# Validate options before closing an existing instance.
if [ -n "$toggle" ] && qs kill --path "$qml_dir" >/dev/null 2>&1; then
	exit 0
fi

runtime_dir=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/line-launcher.XXXXXX")
trap 'rm -rf -- "$runtime_dir"' EXIT INT TERM

if [ -n "$dmenu" ]; then
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
