#!/bin/sh
# this task mounts /run as a tmpfs
# and bind mounts /tmp to /run/tmp

. "$INIT_LIB/command.sh"

case "$1" in
	'init')
	# make sure /run and /tmp are empty
	for dir in "$ROOT/run" "$ROOT/tmp"; do
		if [ ! -d "$dir" ]; then
			# files need to be removed
			[ -f "$dir" ] && run "Removing file $Y$dir$O" rm "$dir"

			run "Creating directory $C$dir$O" mkdir "$dir"
		elif [ "`ls "$dir"`" ]; then
			run "Emptying directory $C$dir$O" rm -r "$dir/*"
		fi
	done

	# systemd wants these options for /run
	run "Mounting $C/run$O as tmpfs" \
		mount -t tmpfs -o mode=755,nodev,nosuid,strictatime tmpfs "$ROOT/run"

	# make /tmp a bind mount to /run/tmp
	run "Mounting $C/tmp$O on $C/run/tmp$O" mkdir "$ROOT/run/tmp" \
		\&\& mount -o rbind "$ROOT/run/tmp" "$ROOT/tmp"
	;;

	# NOP, unmounting is handled separately
	'halt');;

	*)
	echo "Unknown verb '$1'"
	exit 1
	;;
esac
