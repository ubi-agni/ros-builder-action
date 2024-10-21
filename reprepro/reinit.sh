#!/bin/bash

function process {
	local f=$1
	echo "$f"
	local args=""
	local distros=""

	case "$f" in
		*_arm64.deb) args="-A arm64" ;;
		*_amd64.deb) args="-A amd64" ;;
		*_all.deb) distros="jammy noble";;
		*)
			echo "Unknown arch"
			exit 1
			;;
	esac

	if [[ $f == *-dbgsym_* ]]; then
		args="$args -C main-dbg"
	fi

	case $f in
		*jammy.*) distros="jammy" ;;
		*noble.*) distros="noble" ;;
		*)
			if [ -z "$distros" ]; then
				echo "Unknown distro"
				exit 1
			fi
			;;
	esac

	# shellcheck disable=SC2086
	for distro in $distros; do
		reprepro $args includedeb "$distro"-testing "$f"
	done
}

while IFS= read -r -d '' file
do
  process "$file"
done <   <(find /var/www/repos -iname "*.deb" -print0)
