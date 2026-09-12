#!/usr/bin/env bash
set -euo pipefail

repo=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin" "$work/runtime"
export XDG_RUNTIME_DIR="$work/runtime" WRAPPER_TEST_CALLS="$work/calls"
export PATH="$work/bin:$PATH"
unset LINE_LAUNCHER_DMENU_IN LINE_LAUNCHER_DMENU_OUT

# A fake Quickshell exercises the real wrapper without opening a window.
cat >"$work/bin/qs" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$WRAPPER_TEST_CALLS"
if [ "$1" = kill ]; then exit 1; fi
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
echo PASS
