#!/bin/bash

if [ -r ~/.reprepro.env ]; then
	# shellcheck disable=SC1090
	. ~/.reprepro.env
fi

# Sanity checks
[ -z "$DISTRO" ] && DISTRO=(jammy noble)
[ -z "$ARCH" ] && ARCH=(amd64 arm64)

for d in "${DISTRO[@]}"; do
	for a in "${ARCH[@]}"; do
		echo
		echo "Moving packages from $d-testing -> $d ($a)"
		# Move deb packages from testing to production stage
		pkgs=$(reprepro -A "$a" -T deb list "$d-testing" | cut -s -d " " -f 2)
		# shellcheck disable=SC2086
		reprepro -A "$a" copy "$d" "$d-testing" $pkgs

		# Move dsc packages from testing to production stage
		if [ "$a" == "amd64" ]; then
			pkgs=$(reprepro -T dsc list "$d-testing" | cut -s -d " " -f 2)
			for pkg in $pkgs; do
				reprepro -T dsc copysrc "$d" "$d-testing" "$pkg"
			done
		fi
	done
done

# reprepro -A $ARCH remove "$DISTRO-testing" $pkgs
