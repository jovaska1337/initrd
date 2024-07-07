#!/bin/sh
# this tasks job is to recursively unmount $ROOT

. "$INITLIB"

case "$1" in
	# NOP mounting filesystems is handled
	# by separate tasks on init.
	'init');;

	'halt')
	# get everything mounted under $ROOT
	# in the order that they should be unmounted
	MOUNTS=`cat /etc/mtab | cut -d\  -f2 | awk '{print length($0),$0}' \
		| sort -rn | cut -d\  -f2 | grep "^$ROOT."`

	# recursively unmount all mount points inside $ROOT
	msg "Recursively unmounting $ROOT..."
	tab +1
	for point in $MOUNTS; do
		run "Unmounting $point" umount "$point"
	done
	tab -1
	;;

	*)
	echo "Unknown verb '$1'"
	exit 1
	;;
esac
