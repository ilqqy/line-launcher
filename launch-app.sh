#!/bin/sh
# Start an application in a systemd scope of its own.
#
#   launch-app.sh [--id ID] [--name NAME] [--] COMMAND [ARGS...]
#
# Everything the launcher starts -- applications, terminal applications,
# actions, ">" commands -- goes through here. Started straight from the
# launcher, a program lands in the launcher's own cgroup: for the resident
# launcher that is line-launcher.service, and with the default
# KillMode=control-group a restart or a crash of the service takes every
# application started from it down too.
#
# With a systemd user manager running, the command runs in a transient scope,
# app-line\x2dlauncher-<ID>-<PID>.scope in app.slice (the naming the systemd
# desktop-environment conventions use), and outlives the launcher. A scope,
# not a service: systemd-run --scope moves its own process into the new scope
# and then execs COMMAND, so the environment, the working directory and the
# file descriptors are this process's own, exactly as without the scope.
#
# Without systemd-run or a user manager, or with LINE_LAUNCHER_SCOPE=0,
# COMMAND is exec'd directly: the behaviour from before scopes.

app_id=
name=
while [ $# -gt 0 ]; do
	case $1 in
	--id)
		app_id=$2
		shift 2
		;;
	--name)
		name=$2
		shift 2
		;;
	--)
		shift
		break
		;;
	*) break ;;
	esac
done

if [ $# -eq 0 ]; then
	echo "launch-app.sh: no command given" >&2
	exit 2
fi

# The user manager's own socket: present exactly when one runs for this user.
# Checked up front because systemd-run cannot be retried once it has exec'd
# the command, and if it fails before that, nothing would start at all.
runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
if [ "${LINE_LAUNCHER_SCOPE:-1}" != 0 ] \
	&& [ -S "$runtime_dir/systemd/private" ] \
	&& command -v systemd-run >/dev/null 2>&1; then
	[ -n "$app_id" ] || app_id=$(basename -- "$1")
	[ -n "$name" ] || name=$app_id
	# The PID is the application's own once systemd-run has exec'd it, and
	# keeps concurrent launches of one application apart.
	unit="app-line\\x2dlauncher-$(systemd-escape -- "$app_id")-$$.scope"
	exec systemd-run --user --scope --collect --quiet --slice=app.slice \
		--unit="$unit" --description="$name" -- "$@"
fi

exec "$@"
