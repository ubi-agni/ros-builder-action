#!/bin/bash

if [ -r ~/.reprepro.env ]; then
	# shellcheck disable=SC1090
	. ~/.reprepro.env
fi

# Sanity checks
[ ! -d "$INCOMING_DIR" ] && echo "Invalid incoming directory" && exit 1
[ -z "$DISTRO" ] && echo "Distribution undefined" && exit 1
[ -z "$ARCH" ] && echo "ARCH undefined" && exit 1
[ -z "$REPO" ] && echo "github repo undefined" && exit 1

# Move packages from build to production stage
pkgs=$(reprepro -A "$ARCH" list "$DISTRO-build" | grep -v "|source" | cut -s -d " " -f 2)
# shellcheck disable=SC2086
reprepro -A "$ARCH" copy "$DISTRO" "$DISTRO-build" $pkgs

# reprepro remove "$DISTRO-build" "$pkgs"
