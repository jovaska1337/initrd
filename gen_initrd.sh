#!/bin/bash
# gen_initrd.sh - generated initrd image

# useful to have
set -o pipefail

# dynamic link dependencies
deps() {
	local line
	while read line; do
		# parse library path (ignores linux-vdso)
		line="${line% (*}"
		[[ "$line" == */* ]] || continue
		line="/${line#*/}"

		# output
		echo "$line"
	done < <(ldd "$1" 2>/dev/null)
}

# check if ${1} has ${2} by nameref
has() {
	local -n a="$1"
	local -n b="$2"

	local i
	local j

	i=0
	while [[ $i -lt ${#a[@]} ]]; do
		[[ "${a[$i]}" == "$b" ]] && return 0
		i=$(($i + 1))
	done

	return 1
}

# include executable ${1} (with deps) in target optionally at ${2}
include_exe() {
	if [[ ! -f "$1" ]]; then
		echo "Executable '${1}' doesn't exist."
		return 1
	fi

	# root filesystem
	declare -g initrd
	[[ -d "$initrd" ]] || return 1

	local temp
	local line
	local check=($(deps "$1")) # initial deps
	local known=()

	# recursive library dependencies
	while [[ "${#check[@]}" -gt 0 ]]; do
		# pop next library
		temp="${check[-1]}"
		unset check[-1]

		# dependencies of this library
		while read line; do
			has known line && continue

			# add to stack
			check+=("$line")
		done < <(deps "$temp")

		# don't add duplicates
		has known temp || known+=("$temp")
	done

	# copy dependencies
	local src
	local dst
	for src in "${known[@]}"; do
		# add as symlink
		if [[ -L "$src" ]]; then
			# real path
			temp="$(readlink -f "$src")"

			# file destination
			dst="/lib/$(basename "$temp")"

			# add real library
			include_file "$temp" "$dst" +x || return 1

			# add library symlink
			include_symlink "$dst" "/lib/$(basename "$src")" || return 1

		# add as file
		else
			# just add the file
			dst="/lib/$(basename "$src")"
			include_file "$src" "$dst" +x || return 1
		fi
	done

	# target path
	[[ "$2" ]] && dst="$2" || dst="$1"
	
	# add as symlink (saves quite a bit of space)
	if [[ -L "$1" ]]; then
		# real path
		temp="$(readlink -f "$1")"

		# add real executable
		include_file "$temp" "$temp" +x || return 1

		# add symlink
		include_symlink "$temp" "$dst" 1 || return 1

	# add as file
	else
		include_file "$1" "$dst" +x || return 1
	fi
}

# include relative symlink ${2} to ${1} in target
include_symlink() {
	if [[ ${1:0:1} != / || ${2:0:1} != / ]]; then
		echo "Symlink ${2} -> ${1} needs to be absolute."
		return 1
	fi 

	# root filesystem
	declare -g initrd
	[[ -d "$initrd" ]] || return 1

	local src="${initrd}${2}"
	local dst="$(realpath -sm --relative-to="$(dirname "$2")" "$1")"
	if [[ -L "$src" && ${3} != 1 ]]; then
		if [[ "$(readlink "$src")" != "$dst" ]]; then
			echo "Symlink '${src}' exists."
			return 1
		fi
	elif ! ln -sf "$dst" "$src"; then
		echo "Failed to symlink '${src}' -> '${dst}'."
		return 1
	fi
}

# include file ${1} in target optionally at ${2}
include_file() {
	if [[ ! -f "$1" || "${1:0:1}" != / ]]; then
		echo "Invalid file '${1}'."
		return 1
	fi

	# root filesystem
	declare -g initrd
	[[ -d "$initrd" ]] || return 1

	local file
	local dir

	# normalize path
	[[ "$2" ]] && file="$2" || file="$1"
	file="${initrd}$(realpath -sm "$file")"

	# create directory
	dir="$(dirname "$file")"
	if ! mkdir -p "$dir"; then
		echo "Failed to mkdir '${dir}'."
		return 1
	fi

	# remove if file exists
	if [[ -f "$file" ]]; then
		if cmp -s "$file" "$1"; then
			return 0
		else
			echo "Warning, removing '${file}'."
			rm "$file" || return 1
		fi
	fi

	# copy file
	if ! cp "$1" "$file"; then
		echo "Failed to copy '${1}' -> '${file}'."
		return 1
	fi

	# optional: change permissions
	if [[ "$3" ]]; then
		chmod "$3" "$file" || return 1
	fi
}

# include directory ${1} in target optionally at ${2}
include_dir() {
	if [[ ! -d "$1" || "${1:0:1}" != / ]]; then
		echo "Invalid directory '${1}'."
		return 1
	fi

	# root filesystem
	declare -g initrd
	[[ -d "$initrd" ]] || return 1

	local dir

	# normalize path
	[[ "$2" ]] && dir="$2" || dir="$1"
	dir="${initrd}$(realpath -sm "$dir")"

	# create directory
	if ! mkdir -p "$dir"; then
		echo "Failed to mkdir '${dir}'."
		return 1
	fi

	# copy items recursively
	local item
	while read item; do
		if ! cp -r "$item" "$dir"; then
			echo "Failed to copy '${item}' -> '${dir}'."
			return 1
		fi
	done < <(find "$1" -mindepth 1 -maxdepth 1)

	# optional: change permissions
	if [[ "$3" ]]; then
		chmod "$3" "$dir" || return 1
	fi
}

# add busybox (with symlinks) to target
include_busybox() {
	if [[ "$(basename "$1")" != busybox ]]; then
		echo "'${1}' is not busybox."
		return 1
	fi

	# include busybox
	include_exe "$1" /bin/busybox || return 1

	# symlink utils
	local util
	while read util; do
		[[ "$util" != *bin/* || "$util" == */busybox ]] && continue
		include_symlink /bin/busybox "/bin/$(basename "$util")" || return 1
	done < <("$1" --list-full)
}

# adds a task to the specified verb
# $1 = task program which is to be called
# $2 = task verb (default is boot)
include_task() {
	# task indecies
	declare -ga index

	# get index
	local i n
	case "${2,,}" in
		boot|'')
			n=boot
			i=0;;
		halt)
			n=halt
			i=1;;
		reboot) n=reboot
			i=2;;
		*      )
			echo "Unknown verb ${2}."
		   	return 1
		;;
	esac

	# add task to filesystem (include as executable, allows non-script tasks)
	include_exe "$1" "/etc/tasks.${n}/${index[$i]}-$(basename "$1")" || return 1

	# increment index
	index[$i]=$((${index[$i]} + 50))
}

# cleanup
clean() {
	declare -g initrd
	declare -g ucode

	# clean up temporary files
	local tmp
	for tmp in "$initrd" "$ucode"; do
		if [[ -d "$tmp" ]]; then
			echo "Cleaning up ${tmp}."
			rm -r "$tmp"
		fi
	done
}
trap clean EXIT

# entry point
main() {
	# location of initrd files
	local root="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

	# cmdline parameters given by user
	declare -g config="${1}"
	declare -g target="${2}"
	
	# check that configuration file exists
	if [[ ! -f "$config" ]]; then
		echo "Cannot read configuration from ${1}."
		return 1
	fi

	# we need the absolute path to the config
	config="$(realpath "$config")"

	# query GCC major version
	local gcc_major="$(gcc --version | head -n1 | cut -d\  -f4 | cut -d. -f1)"
	[[ "$gcc_major" ]] || return 1
	
	echo "GCC major version: ${gcc_major}"

	# temporary directory for initrd filesystem
	declare -g initrd="$(mktemp -d)"
	cd "$initrd" || return 1

	# temporary directory for microcode
	declare -g ucode="$(mktemp -d)"

	# prepare structure
	mkdir sys proc run dev etc usr var bin lib mnt new_root || return 1

	# add symlinks
	include_symlink /lib /lib64     || return 1
	include_symlink /lib /usr/lib   || return 1
	include_symlink /lib /usr/lib64 || return 1
	include_symlink /bin /usr/bin   || return 1

	# always include busybox for base utilities
	include_busybox /bin/busybox || return 1

	# busybox switch_root doesn't move mountpoints
	include_exe /bin/switch_root || return 1

	# add bash for shell
	include_exe /bin/bash || return 1

	# add init script + default environment
	include_file "${root}/init.sh"  /init      +x || return 1
	include_file "${root}/init.env" /etc/init.env || return 1

	# add init library
	local temp name
	while read temp; do
		# strip extension from name
		name="${temp##*/}"
		name="${name%.*}"
		include_file "$temp" "/lib/initrd/${name}" || return 1
	done < <(find "${root}/lib" -maxdepth 1 -mindepth 1 -type f)

	# add udev + rules (required by init)
	include_exe /bin/udevadm                          || return 1
	include_exe /lib/systemd/systemd-udevd /bin/udevd || return 1
	include_dir /etc/udev                             || return 1
	include_dir /lib/udev                             || return 1

	# add libgcc_s.so, not shown by ldd
	include_file "/usr/lib/gcc/x86_64-pc-linux-gnu/${gcc_major}/libgcc_s.so.1" \
		/lib/libgcc_s.so.1 +x || return 1

	# task indecies
	declare -ga index=(0 0 0)

	# source configuration (which is a bash script, this allows extra trickery)
	if ! . "$config"; then
		echo "Configuration failed."
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
		echo "Adding Intel microcode..."
		cat /lib/firmware/intel-ucode/* > kernel/x86/microcode/GenuineIntel.bin
	fi
	if [[ -d /lib/firmware/amd-ucode/microcode_amd ]]; then
		echo "Adding AMD microcode..."
		cat /lib/firmware/amd-ucode/microcode_amd/* > kernel/x86/microcode/AuthenticAMD.bin
	fi

	# lsinitrd compatability
	echo 1 > early_cpio

	# generate microcode cpio image (must be uncompressed)
	echo "Generating early cpio image..."
	find . ! -path . | cpio -ovH newc > "$target" || return 1

	# generate initrd and compress cpio image
	echo "Generating compressed initrd cpio image..."
	cd "$initrd" || return 1
	find . ! -path . | cpio -ovH newc | xz --check=crc32 --lzma2=dict=1MiB >> "$target" || return 1

	echo "Initrd image at ${target} created successfully."
	return 0
}

# call entry point
main "$@" || exit 1
