#!/usr/bin/env bash
set -euo pipefail

# launch-app.sh, the wrapper every launch goes through. A fake systemd-run
# records its arguments and then does what the real one does in --scope mode
# once the scope exists: exec the command. A real socket stands in for the
# user manager's.

repo=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
wrapper=$repo/launch-app.sh
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/runtime/systemd" "$work/cwd dir"
export XDG_RUNTIME_DIR="$work/runtime"
unset LINE_LAUNCHER_SCOPE

cat >"$work/bin/systemd-run" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FAKE_SYSTEMD_RUN_ARGS"
while [ $# -gt 0 ] && [ "$1" != -- ]; do shift; done
shift
exec "$@"
SH
chmod +x "$work/bin/systemd-run"
export FAKE_SYSTEMD_RUN_ARGS="$work/systemd-run.args"

# What the launched program saw: its argv, cwd, an inherited variable, its pid.
cat >"$work/record" <<'SH'
#!/usr/bin/env bash
{
	printf 'arg=%s\n' "$@"
	printf 'cwd=%s\n' "$PWD"
	printf 'env=%s\n' "${LAUNCH_TEST_VAR:-}"
	printf 'pid=%s\n' "$$"
} >"$RECORD_OUT"
SH
chmod +x "$work/record"
export RECORD_OUT="$work/record.out" LAUNCH_TEST_VAR="from the launcher"

fail() {
	echo "FAIL $1"
	[ -e "$FAKE_SYSTEMD_RUN_ARGS" ] && sed 's/^/     systemd-run: /' "$FAKE_SYSTEMD_RUN_ARGS"
	[ -e "$RECORD_OUT" ] && sed 's/^/     program: /' "$RECORD_OUT"
	exit 1
}
reset() { rm -f -- "$FAKE_SYSTEMD_RUN_ARGS" "$RECORD_OUT"; }
launch() { (cd "$work/cwd dir" && "$@"); }

# A user manager: its private socket exists.
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' \
	"$work/runtime/systemd/private"

# --- with a user manager -----------------------------------------------------
reset
launch env PATH="$work/bin:$PATH" sh "$wrapper" --id org.example.App-1 --name 'Example App' \
	-- "$work/record" plain 'two words' "it's" ''
[ -e "$FAKE_SYSTEMD_RUN_ARGS" ] || fail 'systemd-run was not used with a user manager running'
pid=$(sed -n 's/^pid=//p' "$RECORD_OUT")
{
	printf '%s\n' --user --scope --collect --quiet --slice=app.slice
	printf '%s\n' "--unit=app-line\\x2dlauncher-org.example.App\\x2d1-$pid.scope"
	printf '%s\n' '--description=Example App' -- "$work/record" plain 'two words' "it's" ''
} >"$work/expected"
cmp -s "$work/expected" "$FAKE_SYSTEMD_RUN_ARGS" || fail 'unexpected systemd-run arguments'
echo 'ok   runs in app.slice/app-line\x2dlauncher-<id>-<pid>.scope, named after the app'

printf '%s\n' 'arg=plain' 'arg=two words' "arg=it's" 'arg=' >"$work/expected"
grep '^arg=' "$RECORD_OUT" | cmp -s "$work/expected" - || fail 'arguments not passed through verbatim'
echo 'ok   arguments arrive verbatim (spaces, quotes, empty)'

grep -qxF "cwd=$work/cwd dir" "$RECORD_OUT" || fail 'working directory not kept'
grep -qxF 'env=from the launcher' "$RECORD_OUT" || fail 'environment not kept'
echo 'ok   working directory and environment are the launcher'"'"'s'

reset
launch env PATH="$work/bin:$PATH" sh "$wrapper" -- "$work/record" no-id
grep -qxF -- "--unit=app-line\\x2dlauncher-record-$(sed -n 's/^pid=//p' "$RECORD_OUT").scope" "$FAKE_SYSTEMD_RUN_ARGS" \
	|| fail 'no --id: the scope is not named after the program'
grep -qxF -- '--description=record' "$FAKE_SYSTEMD_RUN_ARGS" || fail 'no --name: no fallback description'
echo 'ok   without --id/--name the scope is named after the program'

# --- fallbacks ---------------------------------------------------------------
reset
launch env PATH="$work/bin:$PATH" LINE_LAUNCHER_SCOPE=0 sh "$wrapper" --id x -- "$work/record" opted-out
[ ! -e "$FAKE_SYSTEMD_RUN_ARGS" ] && grep -qxF 'arg=opted-out' "$RECORD_OUT" || fail 'LINE_LAUNCHER_SCOPE=0 still used a scope'
echo 'ok   LINE_LAUNCHER_SCOPE=0 runs the program directly'

reset
rm -f -- "$work/runtime/systemd/private"
launch env PATH="$work/bin:$PATH" sh "$wrapper" --id x -- "$work/record" no-manager
[ ! -e "$FAKE_SYSTEMD_RUN_ARGS" ] && grep -qxF 'arg=no-manager' "$RECORD_OUT" || fail 'no user manager: program not run directly'
grep -qxF "cwd=$work/cwd dir" "$RECORD_OUT" && grep -qxF 'env=from the launcher' "$RECORD_OUT" \
	|| fail 'fallback lost cwd or environment'
echo 'ok   without a user manager it runs the program directly, cwd and env kept'

reset
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' \
	"$work/runtime/systemd/private"
mkdir "$work/nosystemd"
for tool in sh env bash basename id; do ln -s "$(command -v "$tool")" "$work/nosystemd/$tool"; done
launch env PATH="$work/nosystemd" "$work/nosystemd/sh" "$wrapper" --id x -- "$work/record" no-systemd-run
[ ! -e "$FAKE_SYSTEMD_RUN_ARGS" ] && grep -qxF 'arg=no-systemd-run' "$RECORD_OUT" || fail 'no systemd-run: program not run directly'
echo 'ok   without systemd-run it runs the program directly'

status=0
sh "$wrapper" --id x -- 2>"$work/err" || status=$?
[ "$status" -eq 2 ] && grep -q 'no command' "$work/err" || fail 'a missing command is not an error'
echo 'ok   no command is an error (exit 2)'
echo PASS
