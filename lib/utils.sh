#!/bin/bash
# utils.sh - initrd generator utility functions

# trim whitespace from input
# $1 = input string
trim() {
	local out
	out="$1"
	out="${out#"${out%%[![:space:]]*}"}"
	out="${out%"${out##*[![:space:]]}"}"
	echo "$out"
}

# list dynamic link dependencies
# $1 = input file
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

# list currently defined functions
# $1 = target dict (nameref)
key_funcs() {
	local -n target="$1"
	local line
	while read line; do
		target[${line##*-f }]="1"
	done < <(declare -F)
}

# get a difference between dictionary keys (A - B)
# $1 = output (nameref)
# $2 = dict A (nameref)
# $3 = dict B (nameref)
key_diff() {
	local -n A="$2"
	local -n B="$3"
	local -n C="$1"
	local key
	for key in "${!A[@]}"; do
		[[ ! -v B[${key}] ]] && C[${key}]=""
	done
}

# parse environment variable key-value pair
# $1 = key (nameref)
# $2 = val (nameref)
# $3 = input
parse_kv() {
	local -n K="$1"
	local -n V="$2"

	# split key and value
	K="${3%%=*}"
	V="${3:${#K}}"

	# unquote value
	V="$(xargs -n1 <<< "${V:1}")"
}

# convert relative paths to absolute paths from to initrd generator
# $1 = path
path_check() {
	[[ "${1:0:1}" == / ]] && echo "$1" || echo "${root}/${1}"
}
