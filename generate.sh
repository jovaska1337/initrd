#!/bin/bash
# gen_initrd.sh - generated initrd image

# useful to have
set -o pipefail

# location of initrd files
declare -g root="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

# import library
. "${root}/lib/utils.sh"  || exit 1
. "${root}/lib/config.sh" || exit 1

# use color library from init side
. "${root}/init/lib/color.sh" || exit 1

# automatic cleanup
clean() {
	declare -g initrd
	declare -g ucode

	# clean up temporary files
	local tmp
	for tmp in "$initrd" "$ucode"; do
		if [[ -d "$tmp" ]]; then
			echo "Cleaning up ${B}${tmp}${O}."
			rm -rf "$tmp"
		fi
	done
}
trap clean EXIT

# entry point
main() {
	# location of initrd files
	local root="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

	# cmdline parameters given by user
	declare -g config="$(realpath "${1}")"
	declare -g target="$(realpath "${2}")"
	
	# check that configuration file exists
	if [[ ! -f "$config" ]]; then
		echo "Cannot read configuration from ${1}."
		return 1
	fi

	# we need the absolute path to the config
	config="$(realpath "$config")"

	# temporary directory for initrd filesystem
	declare -g initrd="$(mktemp -d)"
	cd "$initrd" || return 1

	# temporary directory for microcode
	declare -g ucode="$(mktemp -d)"

	# prepare structure
	mkdir sys proc run dev etc usr var bin lib mnt new_root || return 1

	# add symlinks
	config_add include_symlink /lib /lib64
	config_add include_symlink /lib /usr/lib
	config_add include_symlink /lib /usr/lib64
	config_add include_symlink /bin /usr/bin
	config_add include_symlink /bin /usr/sbin
	config_add include_symlink /sbin /bin

	# always include busybox for base utilities
	config_add include_busybox busybox

	# busybox switch_root doesn't move mountpoints
	# (if this isn't util-linux switch_root we're SOL)
	config_add include_exe switch_root

	# add bash for shell
	config_add include_exe bash

	# add init script
	config_add include_file "${root}/init/init.sh" /bin/init +x
	config_add include_symlink /bin/init /init

	# source default environment block
	config_add source_env "${root}/default.env"

	# add init library
	local temp name
	while read temp; do
		# strip extension from name
		name="${temp##*/}"
		name="${name%.*}"
		config_add include_file "$temp" "/lib/initrd/${name}"
	done < <(find "${root}/init/lib" -maxdepth 1 -mindepth 1 -type f)

	# add udev + rules (required by init)
	config_add include_exe udevadm
	config_add include_exe /lib/systemd/systemd-udevd /bin/udevd
	config_add include_dir /etc/udev
	config_add include_dir /lib/udev

	# add libgcc_s.so, not shown by ldd
	config_add include_file "$(gcc -print-file-name=libgcc_s.so.1)" /lib/libgcc_s.so.1 +x

	# task indecies
	declare -ga index=(0 0 0)

	# source configuration
	if ! config_source "$config"; then
		echo "Failed to source user configuration '${config}'."
		return 1
	fi

	# evaluate configuration
	if ! config_eval; then
		echo "Failed to evaluate configuration."
		return 1
	fi

	# dump environment file
	if ! dump_env "${initrd}/etc/init.env"; then
		echo "Failed to save environment block."
		return 1
	fi

	# check that at least one task is defined for boot
	if [[ "${index[0]}" == 0 ]]; then
		echo "Configuration doesn't define boot tasks!"
		return 1
	fi

	# message about pivot
	if [[ "${index[1]}" != 0 || "${index[2]}" != 0 ]]; then
		echo "Initrd will create pivot filesystem!"
	fi

	# fix task numbers (add padding if required)
	local tmp
	for tmp in boot halt; do
		# check if any tasks exist
		tmp="${initrd}/etc/tasks.${tmp}"
		[[ -d "$tmp" ]] || continue

		# get largest index
		local task i=0
		while read task; do
			# extract task index
			task=${task##*/}
			task=${task%%-*}

			# save largest index
			[[ "$i" -lt "$task" ]] && i="$task"
		done < <(find "$tmp" -maxdepth 1 -mindepth 1 -type f)

		# calculate length of largest index
		local pad
		if [[ "$i" -lt 1 ]]; then
			pad=1
		else
			pad="$(bc -l -s <<< "(l(${i})/l(10)+1)/1")"
			pad="${pad%%.*}"
		fi

		# pad all indecies
		local x y z
		while read task; do
			# separate directory and filename
			x="$(dirname "$task")"	
			y="$(basename "$task")"

			# extract task index
			z="${y%%-*}"

			# no need for padding
			[[ "${#z}" -eq "$pad" ]] && continue

			# remove index from name
			y="${y#*-}"

			# pad index
			z="${x}/$(printf '%0*d' "$pad" "$z")-${y}"

			# move file
			mv "$task" "$z" || return 1
		done < <(find "$tmp" -maxdepth 1 -mindepth 1 -type f)
	done

	# save old initrd (if it exists)
	#if [[ -f "$target" ]]; then
	#	echo "Saving old initrd as: ${target}.old"
	#	mv "$target" "${target}.old" || return 1
	#fi

	# copy microcode
	cd "$ucode"|| return 1
	mkdir -p kernel/x86/microcode || return 1
	if [[ -d /lib/firmware/intel-ucode ]]; then
		echo "Adding ${R}Intel microcode${O}..."
		cat /lib/firmware/intel-ucode/* > kernel/x86/microcode/GenuineIntel.bin
	fi
	if [[ -d /lib/firmware/amd-ucode/microcode_amd ]]; then
		echo "Adding ${R}AMD microcode${O}..."
		cat /lib/firmware/amd-ucode/microcode_amd/* > kernel/x86/microcode/AuthenticAMD.bin
	fi

	# lsinitrd compatability
	echo 1 > early_cpio

	# generate microcode cpio image (must be uncompressed)
	echo "Generating ${R}early cpio image${O}..."
	find . ! -path . | cpio -ovH newc > "$target" || return 1

	# generate initrd and compress cpio image
	echo "Generating ${R}compressed initrd cpio image${O}..."
	cd "$initrd" || return 1
	find . ! -path . | cpio -ovH newc | xz --check=crc32 --lzma2=dict=1MiB >> "$target" || return 1

	echo "Initrd image at ${Y}${target}${O} created successfully."
	return 0
}

# call entry point
main "$@" || exit 1
