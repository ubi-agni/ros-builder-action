#!/bin/bash

if [ -r ~/.reprepro.env ]; then
	# shellcheck disable=SC1090
	. ~/.reprepro.env
fi

LOG="$(mktemp /tmp/reprepro-import-XXXXXX)"

# Sanity checks
[ ! -d "$INCOMING_DIR" ] && echo "Invalid incoming directory" && exit 1
[ -z "$DISTRO" ] && echo "Distribution undefined" && exit 1
[ -z "$REPO" ] && echo "github repo undefined" && exit 1

# Fetch last debs artifact from github
if [ -n "$GH_TOKEN" ]; then
	echo "$GH_TOKEN" | gh auth login --with-token
	gh --repo "$REPO" run download --name debs --dir "$INCOMING_DIR"
fi

# Import sources
for f in "$INCOMING_DIR"/*.dsc; do
	reprepro includedsc "$DISTRO" "$f";
done

# Import packages
for f in "$DISTRO" "$INCOMING_DIR"/*.deb; do
	reprepro includedeb "$DISTRO" "$f" && echo "$f" >> "$LOG"
done

# Cleanup files
(cd "$INCOMING_DIR" || exit 1; rm ./*.log ./*.deb ./*.dsc ./*.tar.gz ./*.changes ./*.buildinfo)

# Rename, Import, and Cleanup ddeb files
mmv "$INCOMING_DIR/*.ddeb" "$INCOMING_DIR/#1.deb"
reprepro -C main-dbg includedeb "$DISTRO" "$INCOMING_DIR"/*.deb
(cd "$INCOMING_DIR" || exit 1; rm ./*.deb)

# Merge local.yaml into ros-one.yaml
cat "$INCOMING_DIR/local.yaml" >> "ros-one.yaml"
"$(dirname "${BASH_SOURCE[0]}")/src/scripts/yaml_remove_duplicates.py" ros-one.yaml

# Remove remaining files
(cd "$INCOMING_DIR" || exit 1; rm ./Packages ./Release ./README.md.in ./local.yaml)

echo "Imported: "
cat "$LOG"
rm "$LOG"
