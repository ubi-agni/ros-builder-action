#!/bin/bash

DIR_THIS="$(dirname "${BASH_SOURCE[0]}")"
SRC_PATH="$(realpath "$DIR_THIS/../src")"

# shellcheck source=src/util.sh
source "$SRC_PATH/util.sh"
ici_setup

if [ -r ~/.reprepro.env ]; then
	# shellcheck disable=SC1090
	. ~/.reprepro.env
fi

# Sanity checks
[ -z "$DISTRO" ] && DISTRO=(jammy noble)
[ -z "$ARCH" ] && ARCH=(amd64 arm64)

FAILURE=0
FILTER="Exporting indices|Deleting files no longer referenced|replacing .* with equal version"

for d in "${DISTRO[@]}"; do
	for a in "${ARCH[@]}"; do
		ici_log
		ici_log "Moving packages from $d-testing -> $d ($a)"
		# Move deb packages from testing to production stage
		pkgs=$(reprepro -A "$a" -T deb list "$d-testing" | cut -s -d " " -f 2)
		# shellcheck disable=SC2086
		ici_filter_out "$FILTER" reprepro -A "$a" copy "$d" "$d-testing" $pkgs || FAILURE=1

		# Move dsc packages from testing to production stage
		if [ "$a" == "amd64" ]; then
			pkgs=$(reprepro -T dsc list "$d-testing" | cut -s -d " " -f 2)
			for pkg in $pkgs; do
				printf "."
				ici_filter_out "$FILTER" reprepro -T dsc copysrc "$d" "$d-testing" "$pkg" || FAILURE=1
			done
		fi
	done
done

# reprepro -A $ARCH remove "$DISTRO-testing" $pkgs

ici_exit "$FAILURE"
