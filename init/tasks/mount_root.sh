#!/bin/sh
# this tasks job is to mount the root filesystem at $ROOT

. "$INIT_LIB/command.sh"
. "$INIT_LIB/user.sh"

# temporarily hard coded, until we get GRUB
# to pass the root partition UUID here
ROOT_PART=/dev/sda2
CRYPT_NAME=crypt_luks_ADATA

case "$1" in
	'init')

	# if MAX_ATTEMPTS is undefined, use 5 as default.
	[ -z "$MAX_ATTEMPTS" ] && MAX_ATTEMPTS=5

	I=0 
	while true; do
		# are we out of attempts?
		if [ "$I" -ge "$MAX_ATTEMPTS" ]; then
			msg "Out of password attempts. Failed to unlock device." 3
			exit 1
		fi
		
		# increment attempt counter
		I=`expr $I + 1`

		# attempt to unlock
		if user_input 2 "password: " | \
			cryptsetup luksOpen "$ROOT_PART" "$CRYPT_NAME" -; then
			msg "Unlocked LUKS device" 1
			break
		else
			msg "Invalid password. ($I/$MAX_ATTEMPTS)" 2
		fi
	done

	# FIX THIS TO BE MORE GENERIC, THIS IS JUST TO GET THE SYSTEM TO BOOT
	run 'LVM scan' lvm pvscan || exit 1
	run 'LVM activation' lvm lvchange 'linux/root' -ay || exit 1
	run 'LVM /dev nodes' lvm vgscan --mknodes || exit 1
	run 'Mount root' mount "/dev/linux/root" "$ROOT" || exit 1

	;;

	# NOP, unmounting is handled separately
	'halt');;

	*)
	msg "Unknown verb '$1'" 3
	exit 1
	;;
esac
