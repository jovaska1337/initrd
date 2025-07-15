# command.sh - utility functions for running commands

# import library
. /lib/initrd/color

# run a task suppressing console output/input
function quiet() {
	"$@" &>/dev/null </dev/null
	return $?
}

# run a task with console output
function run() {
	# print prefix
	declare -g print_prefix

	# echo the message
	echo -n "${print_prefix}[${Y}....${O}] ${1}"

	# evaluate the command
	shift 1 && quiet eval "$@"; local ret="$?"

	# print some nice output
	if [[ $ret == 0 ]]; then
		echo -e "\r${print_prefix}[ ${G}OK${O} ]"
	else
		echo -e "\r${print_prefix}[${R}FAIL${O}]"
	fi

	return $ret
}

# print a message
function msg() {
	local level="$2"

	# use info as default
	[[ "$level" ]] || level=0

	# select color
	local color
	case "$level" in
		# info
		0) color="$C";;
		# success
		1) color="$G";;
		# warning
		2) color="$Y";;
		# error
		3) color="$R";;
		# unknown
		*) color="$P";;
	esac

	# use the portage message format
	# because it's quite neat
	echo "${print_prefix} ${color}*${O} ${1}"
}

# get configured tab width
declare -g tab_width="$([[ "$TAB_WIDTH" ]] && echo "$TAB_WIDTH" || echo 2)"

# increase and decrease print_prefix
function tab() {
	# globals
	declare -g print_prefix
	declare -g tab_width

	# get current length
	local cur=$(( ${#print_prefix} / ${tab_width} ))

	# get new length
	local new
	local op="${1:0:1}"
	case "$op" in
	# relative increment/decrement
	+|-) new=$(( (${cur} ${op} ${1:1} ) * ${tab_width} ));;
	# set
	\*) new=$(( ${1:1} * ${tab_width} ));;
	# reset
	*) new=0;;
	esac

	# set new prefix
	if [[ $new -lt 1 ]]; then
		print_prefix=""
	else
		print_prefix="$(printf '%*s' $new '')"
	fi
	export print_prefix
}

# tab level store
declare -ga tab_store=()

# push tab level
function tab_push() {
	# globals
	declare -g print_prefix
	declare -g tab_width
	declare -ga tab_store

	# store old tab width
	tab_store+=($(( ${#print_prefix} )))

	local new
	[[ "$1" ]] && new="$1" || new=0

	# set new print prefix
	print_prefix="$(printf '%*s' $new '')"
	export print_prefix
}

# pop tab level
function tab_pop() {
	# globals
	declare -g print_prefix
	declare -ga tab_store

	# no stored levels
	[[ ${#tab_store[@]} == 0 ]] && return

	# pop last prefix
	local new=${tab_store[$((${#tab_store[@]} - 1))]}
	unset tab_store[$((${#tab_store[@]} - 1))]

	# set new print prefix
	print_prefix="$(printf '%*s' $new '')"
	export print_prefix
}
