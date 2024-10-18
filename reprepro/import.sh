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

# Translate ARCH x64 -> amd64
[ "$ARCH" == "x64" ] && ARCH="amd64"

# Operate on the -build distro
DISTRO="${DISTRO}-build"

if [ -n "$RUN_ID" ] ; then
	echo "Fetching debs artifact from https://github.com/$REPO/actions/runs/$RUN_ID"
	gh --repo "$REPO" run download --name debs --dir "$INCOMING_DIR" "$RUN_ID"
elif [ "$(ls -A "$INCOMING_DIR")" ]; then
	echo "Importing existing files from incoming directory"
elif [ -n "$GH_TOKEN" ]; then
   echo "Fetching last debs artifact from https://github.com/$REPO"
	gh --repo "$REPO" run download --name debs --dir "$INCOMING_DIR"
fi

function filter {
	grep -vE "Exporting indices...|Deleting files no longer referenced..."
}

# Import sources
printf "\nImporting source packages"
if [ "$ARCH" == "amd64" ]; then
	for f in "$INCOMING_DIR"/*.dsc; do
		echo "$f"
		reprepro includedsc "$DISTRO" "$f" | filter
	done
fi

# Import packages
printf "\nImporting binary packages"
reprepro -A "$ARCH" includedeb "$DISTRO" "$INCOMING_DIR"/*.deb | filter

# Cleanup files
(cd "$INCOMING_DIR" || exit 1; rm -f ./*.log ./*.deb ./*.dsc ./*.tar.gz ./*.tar.xz ./*.changes ./*.buildinfo)

# Rename, Import, and Cleanup ddeb files (if existing)
printf "\nImporting debug packages"
if [ -n "$(ls -A "$INCOMING_DIR"/*.ddeb 2>/dev/null)" ]; then
	mmv "$INCOMING_DIR/*.ddeb" "$INCOMING_DIR/#1.deb"
	reprepro -A "$ARCH" -C main-dbg includedeb "$DISTRO" "$INCOMING_DIR"/*.deb | filter
	(cd "$INCOMING_DIR" || exit 1; rm ./*.deb)
fi

printf "\nExporting"
reprepro export "$DISTRO"

# Merge local.yaml into ros-one.yaml
cat "$INCOMING_DIR/local.yaml" >> "ros-one.yaml"
"$(dirname "${BASH_SOURCE[0]}")/../src/scripts/yaml_remove_duplicates.py" ros-one.yaml

# Remove remaining files
(cd "$INCOMING_DIR" || exit 1; rm -f ./Packages ./Release ./README.md.in ./local.yaml)
