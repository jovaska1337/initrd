# user.sh - utility functions for interacting with the user

# import library
. /lib/initrd/command

# spawn an emergency shell for the user to fix problems
function shell() {
	tab_push
	[[  "$1" ]] && msg "$1"
	msg "Dropping to shell (CTRL + D to exit)." 2
	getty 0 tty0 vt100 -n -l /bin/bash
	tab_pop
}

# we use stdout for the return value
# and stderr for the messages
# parameter 1 tells how ask_input()
# should handle the input echoing:
# 	0 -> echo enabled
#	1 -> echo disabled
# 	2 -> echo * for all chars
# parameter 2 contains an optional
# message displayed when asking input
function user_input() {
	# globals
	declare -g print_prefix

	# locals
	local char
	local input

	# disable echo
	[[ "$1" -gt 0 ]] && stty -echo

	# we want a non-empty input
	while [[ ! "$input" ]]; do
		echo -n "${print_prefix}${2}" >&2
		# echo *?
		if [[ "$1" == 2 ]]; then
			# read one character at atime
			while IFS= read -rn1 char; do
				# enter was pressed
				[[ "$char" ]] || break

				# backspace
				if [[ "$char" == $'\x7F' ]]; then
					# if the input is empty
					# we can't erase characters
					[[ "$input" ]] || continue

					# erase asterisk from terminal
					echo -ne '\b \b' >&2

					# remove last character from input
					input="${input%?}"
				else
					# echo asterisk
					echo -n \* >&2

					# append character to input
					input="${input}${char}"
				fi
			done
		# a single read will do
		else
			read input
		fi
		
		# add newline when echo is disabled
		[[ "$1" -gt 0 ]] && echo >&2
	done

	# enable echo
	[[ "$1" -gt 0 ]] && stty echo >&2

	echo "$input"
}
