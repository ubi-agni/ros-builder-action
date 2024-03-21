#!/bin/bash

if [ -r ~/.reprepro.env ]; then
	# shellcheck disable=SC1090
	. ~/.reprepro.env
fi

# Sanity checks
[ ! -d "$INCOMING_DIR" ] && echo "Invalid incoming directory" && exit 1
[ -z "$DISTRO" ] && echo "Distribution undefined" && exit 1
[ -z "$REPO" ] && echo "github repo undefined" && exit 1

# Move packages from build to production stage
for pkg in $(reprepro list "$DISTRO-build" | cut -s -d " " -f 2); do
	echo "$pkg"
	reprepro copy "$DISTRO" "$DISTRO-build" "$pkg"
	reprepro remove "$DISTRO-build" "$pkg"
done
