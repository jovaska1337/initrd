# init.sh - utility functions for top level init script

# import library
. /lib/initrd/command

# print greeting message
function init_greet() {
	local act
	case "$INIT_VERB" in
		boot)   act="booting up";;
		halt)   act="shutting down";;
		reboot) act="rebooting";;
		*)      act="in an unknown state..";;
	esac
	msg "Hello from the initial ramdisk, the system is ${act}."
}

# run init tasks for current verb
function init_tasks() {
	# locals
	local path

	# path to tasks for this verb
	path="/etc/tasks.${INIT_VERB}"
	if [[ ! -d "$path" ]]; then
		msg "No tasks defined for ${INIT_VERB}." 2
		return 0
	fi

	# we use file descriptor 3 here to preserve
	# stdin for child processes (mainly for user_input())
	msg "Executing tasks..."
	tab +1
	while read -u3 path; do
		# get index and name for display
		local name="${path##*/}"
		local n=${name%%-*}
		name="${name#*-}"
		name="${name%.*}"

		# check if file is executable
		if [[ ! -x "$path" ]]; then
			msg "Task ${Y}${name}${O} is not executable!" 2
			continue
		fi

		# execute file
		msg "Executing task ${Y}${name}${O} (${B}$(( $n ))${O})..."
		tab +1
		if "$path" "$INIT_VERB" <&0; then
			tab -1
			msg "Task ${Y}${name}${O} finished." 1
		else
			tab -1
			msg "Task ${Y}${name}${O} failed." 3
			tab -1
			return 1
		fi
	done 3< <(find "$path" -mindepth 1 -maxdepth 1 -type f | sort)
	tab -1

	return 0
}

# export initrd.* parameters into environment from kernel cmdline
function parse_cmdline() {
	# parse kernel command line (procfs needs to be mounted)
	for arg in $(grep -o 'initrd\.[^[:space:]=]\+=[^[:space:]]\+' /proc/cmdline); do
		# extract key and value
		local key="${arg%%=*}"
		local val="${arg#*=}"
		
		# substitute '.' with '_' in key
		key="${key//./_}"

		# make key lowercase
		key="${key,,}"
		
		# export the argument to it can be used anywhere
		export "${key}=${val}"
	done
}

# check that a filesystem is mounted on $ROOT
function check_root() {
	local line
	while read line; do
		line="${line#* }"
		line="${line%% *}"
		[[ "$line" == "$ROOT" ]] && return 0
	done < /etc/mtab
	return 1
}

# create temporary filesystem that init will pivot to on shutdown/reboot
function mkpivot() {
	# this can only be called when booting
	if [[ "$INIT_VERB" != boot ]]; then
		msg "mkpivot() should only be called during boot!" 3
		return 1
	fi

	# root filesystem must be mounted
	if ! check_root; then
		msg "Root filesystem is not mounted!" 3
		return 1
	fi

	# where to copy the initramfs (/run is moved to new root by switch_root!)
	local target=/run/initramfs

	# these directories should not be
	# copied recursively
	local ignore=(/early_cpio /kernel /run /tmp /mnt /sys /dev /proc "$ROOT")

	# create $ROOT/run/initramfs
	run "Create ${target}" quiet mkdir "$target" || return 1

	# create rootfs layout
	quiet pushd "$target"
	run "Create layout" quiet mkdir sys proc run dev etc usr var bin lib mnt old_root || return 1
	quiet popd

	# copy the contents of the initramfs
	msg "Copying initramfs..."
	tab +1
	local path
	find / -mindepth 1 -maxdepth 1 | while read path; do
		# directory should be ignored
		local i=0 flag=0
		while [[ $i -lt ${#ignore[@]} ]]; do
			if [[ "$path" == "${ignore[$i]}" ]]; then
				msg "Ignored ${path}."
				flag=1
				break
			fi
			i=$(($i + 1))
		done
		[[ "$flag" == 1 ]] && continue

		# copy the directory over
	run "Copy ${path} to ${target}" cp -Ra "$path" "$target" || return 1
	done
	tab -1

	# systemd calls /run/initramfs/shutdown on shutdown
	run "Rename init to shutdown" mv "${target}/init" "${target}/shutdown" || return 1
}
