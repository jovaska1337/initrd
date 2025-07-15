# unpack_and_remove.sh - task to unpack squashfs contained in the initrd

# import library
. /lib/initrd/command

# remove root password
run "Remove root password" quiet chroot "$ROOT" passwd -d root || exit 1
