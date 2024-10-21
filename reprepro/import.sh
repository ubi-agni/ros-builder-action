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

# Operate on the -testing distro
DISTRO="${DISTRO}-testing"

if [ -n "$RUN_ID" ] ; then
	echo "Fetching artifact"
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
if [ "$ARCH" == "amd64" ]; then
	printf "\nImporting source packages\n"
	for f in "$INCOMING_DIR"/*.dsc; do
		[ -f "$f" ] || break  # Handle case of no files found
		echo "${f#"$INCOMING_DIR/"}"
		reprepro includedsc "$DISTRO" "$f" | filter
	done
fi

# Import packages
printf "\nImporting binary packages\n"
for f in "$INCOMING_DIR"/*.deb; do
	[ -f "$f" ] || break  # Handle case of no files found
	echo "${f#"$INCOMING_DIR/"}"
	reprepro -A "$ARCH" includedeb "$DISTRO" "$f" | filter
done

# Cleanup files
(cd "$INCOMING_DIR" || exit 1; rm -f ./*.log ./*.deb ./*.dsc ./*.tar.gz ./*.tar.xz ./*.changes ./*.buildinfo)

# Rename, Import, and Cleanup ddeb files (if existing)
printf "\nImporting debug packages\n"
for f in "$INCOMING_DIR"/*.ddeb; do
	[ -f "$f" ] || break  # Handle case of no files found
	echo "${f#"$INCOMING_DIR/"}"
	# remove .ddeb suffix
	f=${f%.ddeb}
	mv "${f}.ddeb" "${f}.deb"
	reprepro -A "$ARCH" -C main-dbg includedeb "$DISTRO" "${f}.deb" | filter
done
(cd "$INCOMING_DIR" || exit 1; rm ./*.deb)

printf "\nExporting\n"
reprepro export "$DISTRO"

# Merge local.yaml into ros-one.yaml
cat "$INCOMING_DIR/local.yaml" >> "ros-one.yaml"
"$(dirname "${BASH_SOURCE[0]}")/../src/scripts/yaml_remove_duplicates.py" ros-one.yaml

# Remove remaining files
(cd "$INCOMING_DIR" || exit 1; rm -f ./Packages ./Release ./README.md.in ./local.yaml)
