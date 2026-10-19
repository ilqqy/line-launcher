#!/usr/bin/env bash
set -euo pipefail

repo=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin" "$work/runtime"
export XDG_RUNTIME_DIR="$work/runtime" WRAPPER_TEST_CALLS="$work/calls"
export PATH="$work/bin:$PATH"
unset LINE_LAUNCHER_DMENU_IN LINE_LAUNCHER_DMENU_OUT LINE_LAUNCHER_QML_DIR LINE_LAUNCHER_RESIDENT

# A fake Quickshell exercises the real wrapper without opening a window.
cat >"$work/bin/qs" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$WRAPPER_TEST_CALLS"
if [ "$1" = kill ]; then exit 1; fi
if [ "$1" = ipc ]; then [ "${WRAPPER_TEST_RESIDENT:-}" = yes ]; exit; fi
printf 'resident=%s\n' "${LINE_LAUNCHER_RESIDENT:-}" >>"$WRAPPER_TEST_CALLS"
echo 'quickshell log output'
if [ "${WRAPPER_TEST_SELECT:-}" = yes ]; then
    head -n 1 "$LINE_LAUNCHER_DMENU_IN" >"$LINE_LAUNCHER_DMENU_OUT"
fi
SH
chmod +x "$work/bin/qs"

for value in '' 0 000 -1 1.5 nope 2147483648 999999999999999999999999999; do
    status=0
    "$repo/launcher.sh" --toggle --items="$value" </dev/null >"$work/out" 2>"$work/err" || status=$?
    [ "$status" -eq 2 ] || { echo "FAIL invalid --items=$value accepted"; exit 1; }
    [ ! -e "$work/calls" ] || { echo 'FAIL validation invoked Quickshell'; exit 1; }
done
echo 'ok   invalid arguments fail before toggle side effects'

printf 'id\tclipboard text\nsecond\n' | WRAPPER_TEST_SELECT=yes "$repo/launcher.sh" >"$work/out" 2>"$work/err"
printf 'id\tclipboard text\n' >"$work/expected"
cmp "$work/expected" "$work/out"
echo 'ok   dmenu returns the original line without log pollution'

status=0
printf 'one\n' | "$repo/launcher.sh" >"$work/out" 2>"$work/err" || status=$?
[ "$status" -eq 1 ] && [ ! -s "$work/out" ]
[ -z "$(ls -A "$work/runtime")" ]
echo 'ok   cancellation returns 1 and removes temporary files'

# --- resident launcher -------------------------------------------------------
resident=$repo/resident.qml
pid_file=$XDG_RUNTIME_DIR/line-launcher-$UID-resident.pid
reset_calls() { rm -f -- "$WRAPPER_TEST_CALLS"; }

reset_calls
status=0
"$repo/launcher.sh" --toggle --daemon </dev/null >"$work/out" 2>"$work/err" || status=$?
[ "$status" -eq 2 ] && [ ! -e "$WRAPPER_TEST_CALLS" ] || { echo 'FAIL --toggle --daemon accepted'; exit 1; }
echo 'ok   --toggle and --daemon are exclusive'

reset_calls
LINE_LAUNCHER_DMENU_IN=/dev/null "$repo/launcher.sh" --daemon </dev/null >"$work/out" 2>"$work/err"
grep -qxF -- "--path $resident --no-duplicate" "$WRAPPER_TEST_CALLS" || { echo 'FAIL --daemon did not start resident.qml'; cat "$WRAPPER_TEST_CALLS"; exit 1; }
grep -qx 'resident=1' "$WRAPPER_TEST_CALLS" || { echo 'FAIL --daemon did not set resident mode'; exit 1; }
[ -s "$pid_file" ] || { echo 'FAIL --daemon wrote no pid file'; exit 1; }
[ ! -s "$work/out" ] || { echo 'FAIL --daemon wrote to stdout'; exit 1; }
echo 'ok   --daemon runs resident.qml in resident mode and records its pid'

# The recorded pid is gone now (the fake exits at once): no IPC attempt.
reset_calls
"$repo/launcher.sh" --toggle </dev/null >"$work/out" 2>"$work/err"
! grep -q '^ipc' "$WRAPPER_TEST_CALLS" || { echo 'FAIL IPC tried with no resident running'; exit 1; }
grep -qxF -- "--path $repo --no-duplicate" "$WRAPPER_TEST_CALLS" || { echo 'FAIL no cold start'; exit 1; }
echo 'ok   --toggle skips IPC when the resident pid is not alive'

# A live process stands in for the resident launcher.
sleep 60 &
stand_in=$!
printf '%s\n' "$stand_in" >"$pid_file"

reset_calls
WRAPPER_TEST_RESIDENT=yes "$repo/launcher.sh" --toggle </dev/null >"$work/out" 2>"$work/err"
printf 'ipc --path %s call launcher toggle\n' "$resident" >"$work/expected"
cmp -s "$work/expected" "$WRAPPER_TEST_CALLS" || { echo 'FAIL --toggle did not go (only) to the resident'; cat "$WRAPPER_TEST_CALLS"; kill "$stand_in"; exit 1; }
echo 'ok   --toggle goes to the resident launcher and spawns nothing else'

reset_calls
"$repo/launcher.sh" --toggle </dev/null >"$work/out" 2>"$work/err"
grep -q '^ipc ' "$WRAPPER_TEST_CALLS" && grep -qxF -- "--path $repo --no-duplicate" "$WRAPPER_TEST_CALLS" \
	|| { echo 'FAIL no cold fallback when the resident does not answer'; cat "$WRAPPER_TEST_CALLS"; kill "$stand_in"; exit 1; }
echo 'ok   a resident that does not answer falls back to a cold start'

reset_calls
WRAPPER_TEST_RESIDENT=yes "$repo/launcher.sh" --toggle --items 3 </dev/null >"$work/out" 2>"$work/err"
! grep -q '^ipc' "$WRAPPER_TEST_CALLS" && grep -qxF -- "--path $repo --no-duplicate" "$WRAPPER_TEST_CALLS" \
	|| { echo 'FAIL per-invocation options reached the resident'; cat "$WRAPPER_TEST_CALLS"; kill "$stand_in"; exit 1; }
echo 'ok   per-invocation options open a one-off launcher'

reset_calls
printf 'one\n' | WRAPPER_TEST_RESIDENT=yes WRAPPER_TEST_SELECT=yes "$repo/launcher.sh" >"$work/out" 2>"$work/err"
! grep -q '^ipc' "$WRAPPER_TEST_CALLS" && [ "$(cat "$work/out")" = one ] \
	|| { echo 'FAIL a piped menu went to the resident'; kill "$stand_in"; exit 1; }
echo 'ok   piped menus stay one-off processes'

reset_calls
LINE_LAUNCHER_RESIDENT=1 "$repo/launcher.sh" --toggle --prompt x </dev/null >"$work/out" 2>"$work/err"
grep -qx 'resident=' "$WRAPPER_TEST_CALLS" || { echo 'FAIL an inherited resident flag leaked'; kill "$stand_in"; exit 1; }
echo 'ok   an inherited resident flag does not reach a one-off launcher'

kill "$stand_in"
rm -f -- "$pid_file"
echo PASS
