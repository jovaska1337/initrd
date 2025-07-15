#!/bin/bash
# config.sh - initrd generator configuration directives

# get defined functions before directives
declare -gA __funcs_pre && key_funcs __funcs_pre

# environment block
declare -gA __env_block

###############################################################################
#                            BEGIN DIRECTIVES                               ###
###############################################################################

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

	# TODO: implement this everywhere!
	local path="$(path_check "$1")"

	# add task to filesystem (include as executable, allows non-script tasks)
	include_exe "$path" "/etc/tasks.${n}/${index[$i]}-$(basename "$1")" || return 1

	# increment index
	index[$i]=$((${index[$i]} + 50))
}

# adds environment variable to the environment block
# $1 = key
# $2 = value
include_env() {
	__env_block["${1}"]="${2}"
}

# source environment variables from file and add them to the environment block
# $2 = file
source_env() {
	# check if file can be accessed
	[[ ! -f "$1" || ! -r "$1" ]] && return 1

	local line
	while read line; do
		# trim whitespace
		line="$(trim "$line")"

		# comment or empty
		[[ ${#line} == 0 || ${line:0:1} == "#" ]] && continue
	
		# environment variable assignment
		if [[ "${line}" =~ ^[A-Za-z][A-Za-z0-9_]*= ]]; then
			local key
			local val
			parse_kv key val "$line" || return 1
			config_add include_env "${key}" "${val}"

		# malformed line
		else
			echo "Malformed line in environment block '${1}'"
			return 1
		fi
	done < "$1"
}

###############################################################################
#                             END DIRECTIVES                                ###
###############################################################################

# get defined functions after directives
declare -gA __funcs_post && key_funcs __funcs_post

# get directive names
declare -gA __directives && key_diff __directives __funcs_post __funcs_pre
unset __funcs_pre __funcs_post

# current configuration
declare -g __config=()

# add configuration directive
# $1 = directive
# $. = args
config_add() {
	# convert directive to lowercase
	local args=("${1,,}")
	shift 1
	args+=("${@}")

	# stringify array so it can be evaluated later
	local args=$(declare -ap args)
	args="${args#declare -a }"

	# add to configuration
	__config+=("$args")
}

# source configuration from file
# $1 = file
config_source() {
	# check if file can be accessed
	[[ ! -f "$1" || ! -r "$1" ]] && return 1

	local line
	while read line; do
		# trim whitespace
		line="$(trim "$line")"

		# comment or empty
		[[ ${#line} == 0 || ${line:0:1} == "#" ]] && continue
	
		# environment variable assignment
		if [[ "${line}" =~ ^[A-Za-z][A-Za-z0-9_]*= ]]; then
			local key
			local val
			parse_kv key val "$line" || return 1
			config_add include_env "${key}" "${val}"

		# configuration directive
		else
			local args
			readarray -t args < <(xargs printf '%s\n' <<< "$line")
			config_add "${args[@]}"
		fi
	done < "$1"
}

# evaluate current configuration
config_eval() {
	local item
	local args
	for item in "${__config[@]}"; do
		eval "$item" || return 1
		if [[ ! -v __directives[${args[0]}] ]]; then
			echo "Unknown directive '${args[0]}'"
			return 1
		fi
		if ! "${args[@]}"; then
			echo "Failed to evaluate directive '${args[@]}'"
			return 1
		fi
	done
}

# dump environment block
# $1 = target file
dump_env() {
	echo "# initrd environment block" > "$1" || return 1
	for key in "${!__env_block[@]}"; do
		echo "${key}=${__env_block[${key}]}" >> "$1" || return 1
	done
}
