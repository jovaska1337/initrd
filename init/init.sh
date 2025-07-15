#!/bin/bash
# init.sh - /sbin/init for simple initramfs

# called when exiting abnormally
on_exit() {
	echo "${R}init exited abnormally.${O}"
	while true; do
		# prefer to use proper shell with tty, fallback to bash
		shell "Emergency shell, use poweroff/reboot to exit." \
		|| ( echo "Emergency shell, use poweroff/reboot to exit." \
			&& bash )
		sleep 1
	done
}
trap on_exit EXIT

# export init environment
while read line; do
	# ignore empty lines
	[[ $line ]] || continue
	
	# ignore commented lines
	temp=$line
	[[ ${temp:0:1} == \# ]] && continue
	unset temp

	# extract key value pair
	key="${line%%=*}"
	val="${line#*=}"
	[[ "$key" && "$val" ]] || continue

	# trim whitespace
	key="${key#"${key%%[![:space:]]*}"}"
	key="${key%"${key##*[![:space:]]}"}"
	val="${val#"${val%%[![:space:]]*}"}"
	val="${val%"${val##*[![:space:]]}"}"

	# check that key is a valid identifier
	[[ "$key" =~ ^[[:alpha:]][[:alnum:]_]*$ ]] || continue

	# export value
	eval "export ${key}=${val}" || exit 1

done < /etc/init.env

# import init library
. /lib/initrd/command || exit 1
. /lib/initrd/user    || exit 1
. /lib/initrd/init    || exit 1

# determine action
case "${1,,}" in
	# when init pivot_roots to this script
	poweroff|reboot|halt)

	# export correct verb (halt and poweroff are the same thing)
	if [[ "${1,,}" == reboot ]]; then
		export INIT_VERB=reboot
	else
		export INIT_VERB=halt
	fi

	# verb specific environment
	export ROOT=/old_root

	# greet the user
	init_greet

	# start udev
	msg "Initializing ${R}udev daemon${O}..."
	tab +1
	run "Start ${R}udev${O}" quiet udevd -d
	run "Trigger ${R}udev${O} events" quiet udevadm trigger
	run "Wait for ${R}udev${O} to settle" quiet udevadm settle
	tab -1

	# parse kernel command line
	parse_cmdline

	# execute halt tasks
	init_tasks || shell

	# debug shell activated via kernel cmdline
	[[ "$initrd_break" == 1 ]] && shell "Breakpoint ${P}initrd.break${O} before ${R}${INIT_VERB}${O}."

	# stop udev
	msg "Stopping ${R}udev daemon${O}..."
	tab +1
	run "Ask ${R}udev${O} to stop" quiet udevadm control -e
	tab -1

	# we need -f on busybox to skip service manager
	msg "System will ${INIT_VERB} now."
	[[ "$INIT_VERB" == reboot ]] && reboot -f || poweroff -f
	trap - EXIT
	;;

	# called by kernel (command line can be used to put anything here)
	*)
	# verb specific environment
	export INIT_VERB=boot
	export ROOT=/new_root

	# greet the user
	init_greet

	# mount virtual filesystems
	msg "Mounting ${C}virtual filesystems${O}..."
	tab +1
	run "Mount   ${C}/dev${O}"     quiet mount -t devtmpfs none /dev
	run "Create  ${C}/dev/pts${O}" quiet mkdir /dev/pts
	run "Mount   ${C}/dev/pts${O}" quiet mount -t devpts   none /dev/pts
	run "Mount   ${C}/sys${O}"     quiet mount -t sysfs    none /sys
	run "Mount   ${C}/proc${O}"    quiet mount -t proc     none /proc
	# systemd wants these options for /run
	run "Mount   ${C}/run${O}"     quiet mount -t tmpfs \
		-o mode=755,nodev,nosuid,strictatime none /run
	# add necessary symlinks
	run "Symlink ${C}/proc/mounts${O}  -> ${C}/etc/mtab${O}" \
		ln -sf /proc/mounts /etc/mtab
	run "Symlink ${C}/proc/self/fd${O} -> ${C}/dev/fd${O}" \
		ln -sf /proc/self/fd /dev/fd
	tab -1

	# start udev
	msg "Initializing ${R}udev daemon${O}..."
	tab +1
	run "Start ${R}udev${O}" quiet udevd -d
	run "Trigger ${R}udev${O} events" quiet udevadm trigger
	run "Wait for ${R}udev${O} to settle" quiet udevadm settle
	tab -1

	# parse kernel command line
	parse_cmdline

	# execute init tasks
	init_tasks || shell

	# we can't proceed until the root filesystem is mounted
	while ! check_root; do
		shell "Mount the root filesystem at ${R}${ROOT}${O}." 3
	done

	# create pivot filesystem if there are halt tasks
	if [[ -d /etc/tasks.halt || -d /etc/tasks.reboot ]]; then
		msg "Creating pivot filesystem..."
		tab +1
		if mkpivot; then
			msg "Pivot filesystem created." 1
		else
			msg "Failed to create pivot filesystem!" 3
		fi
		tab -1
	fi

	# debug shell activated via kernel cmdline
	[[ "$initrd_break" == 1 ]] && shell "Breakpoint ${P}initrd.break${O} before ${R}${INIT_VERB}${O}."

	# stop udev
	msg "Stopping ${R}udev daemon${O}..."
	tab +1
	run "Ask ${R}udev${O} to stop" quiet udevadm control -e
	tab -1

	# switch to the new root
	msg "Switching root to ${C}${ROOT}${O} and executing ${Y}${INIT}${O}..."
	trap - EXIT
	exec switch_root "$ROOT" "$INIT"
	;;
esac
