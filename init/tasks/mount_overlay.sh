# mount_overlay.sh - task to mount squashfs overlay

# import library
. /lib/initrd/command

do_unmount=1

# unmounts boot device when necessary
clean() {
	if [[ "$do_unmount" == 1 ]]; then
		msg "Unmounting boot device..."
		quiet umount /run/bootdev || return 1
		quiet rmdir /run/bootdev  || return 1
	fi
}
trap clean EXIT

# check for boot device
if [[ ! -L "$BOOT_DEVICE" ]]; then
	msg "Boot device '${BOOT_DEVICE}' not found!" 3
	exit 1
fi

# mount boot device
run "Create mountpoint" quiet mkdir /run/bootdev || exit 1
run "Mount boot device" quiet mount -o ro "$BOOT_DEVICE" /run/bootdev || exit 1

# image path
image="/run/bootdev/${ROOT_IMAGE}"

# check for root image
if [[ ! -f "$image" ]]; then
	msg "Root filesystem image '${ROOT_IMAGE}' not found !" 3
	exit 1
fi

# unpack squashfs image to ram?
if [[ "$initrd_toram" == 1 ]]; then
	msg "Mode ${R}copy to ram${O}."
	run "Mount tmpfs" quiet mount -t tmpfs none "$ROOT" || exit 1
	msg "Unpacking squashfs image..."
	if unsquashfs -dest "$ROOT" "$image"; then
		msg "Successfully unpacked image" 1
	else
		msg "Failed to unpack image." 3
		exit 1
	fi

# mount tmpfs overlay on top of squashfs image
else
	msg "Mode ${R}image overlay${O}."
	run "Create mountpoint" quiet mkdir /run/rootfs || exit 1
	run "Mount root tmpfs" quiet mount -t tmpfs none /run/rootfs || exit 1
	run "Create mountpoints" quiet mkdir \
		/run/rootfs/upper \
		/run/rootfs/lower \
		/run/rootfs/work || exit 1
	run "Mount image" quiet mount -t squashfs -o ro "$image" /run/rootfs/lower || exit 1
	do_unmount=0
	run "Mount overlay" quiet mount -t overlay -o \
		lowerdir=/run/rootfs/lower,upperdir=/run/rootfs/upper,workdir=/run/rootfs/work none \
		"$ROOT" || exit 1
fi

# move /run/bootdev to $ROOT/boot
run "Move boot device mount" quiet mount --move /run/bootdev "${ROOT}/boot" || exit 1
run "Remove old mountpoint"   quiet rmdir /run/bootdev || exit 1
