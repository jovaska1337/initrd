# color.sh - simple ANSI color sequence generator

# FIXME: this might have bugs...

# this order matches the color suffix in ANSI codes,
# so the result of indexof() can be directly used
# as the color suffix.
cols=(BLACK RED GREEN YELLOW BLUE PURPLE CYAN WHITE)

# the order here is important, as the index of HINT
# added to the index of REG, BOLD or BGRN results
# in the index of the high intensity version in
# MOD_CODES. we also use the fact that indexof()
# will return the lowest index of HINT so we can
# use it to pad the indecies of RESET and ULINE
# to match those in MOD_CODES.
mods=(REG BOLD BGRN ULINE HINT HINT HINT HINT RESET)

# we drop the m suffix here as it is added by color()
# and we have to add a color before some of these codes
code=('\e[0;3' '\e[1;3' '\e[4' '\e[4;3' '\e[0;9' '\e[1;9' '\e[0;10' '\e[4;3' '\e[0')

# returns the index of item in array
function indexof() {
	local -n arr="$1"

	# loop through array
	local i
	while [[ $i -lt ${#arr[@]} ]]; do
		if [[ "${arr[$i]}" == "$2" ]]; then
			echo $i
			return
		fi
		i=$(($i + 1))
	done
}

# generates a series of ANSI color codes
function color() {
	# HINT causes the modifiers to be offset to the high intensity versions
	local off=0
	local col
	local seq
	local out

	# iterate over all arguments
	local arg
	for arg in "$@"; do
		# convert to uppercase
		arg="${arg^^}"

		# is the arugment a color? 
		local i=$(indexof cols "$arg")
		if [[ "$i" ]]; then
			# if no sequence was generated for the
			# current color, generate REGULAR implicitly
			[[ ! "$seq" && "$col" ]] && seq="${seq}${code[$off]}${col}m"

			# append the current sequence to the output
			out="${out}${seq}"
			seq=""

			# HINT only applies to the current color
			off=0

			# switch to the new color
			col="$i"
			continue
		fi

		# if the argument isn't a color or a
		# modifier we silently ignore it
		i=$(indexof mods "$arg")
		[[ "$i" ]] || continue

		# RESET means we just emit the reset code
		if [[ "$arg" == RESET ]]; then
			out="${code[$i]}m"
			break

		# HINT needs special treatment
		elif [[ "$arg" == HINT ]]; then
			off="$i"
		else
			seq="${seq}${code[$(($i + $off))]}${col}m"
		fi
	done

	# this simply needs to be repeated after
	# the last parameter
	[[ ! "$seq" && "$col" ]] && seq="${seq}${code[$off]}${col}m"

	# output code sequence
	echo -e "${out}${seq}"
}

# define some common colors
R="$(color RED HINT)"
G="$(color GREEN HINT)"
B="$(color BLUE HINT)"
C="$(color CYAN HINT)"
Y="$(color YELLOW HINT)"
P="$(color PURPLE HINT)"
O="$(color RESET)"
