# unpack_and_remove.sh - task to unpack squashfs contained in the initrd

# import library
. /lib/initrd/command

# check for root image
if [[ ! -f "$ROOT_IMAGE" ]]; then
	msg "Root filesystem image '${ROOT_IMAGE}' not found !" 3
	exit 1
fi

# unpack and copy
msg "Mode ${R}copy to ram${O}."
run "Mount tmpfs" quiet mount -t tmpfs none "$ROOT" || exit 1
msg "Unpacking squashfs image..."
if unsquashfs -dest "$ROOT" "$ROOT_IMAGE"; then
	msg "Successfully unpacked image" 1
else
	msg "Failed to unpack image." 3
	exit 1
fi
