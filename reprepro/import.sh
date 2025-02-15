#!/bin/bash

if [ -r ~/.reprepro.env ]; then
	# shellcheck disable=SC1090
	. ~/.reprepro.env
fi

# Sanity checks
[ ! -d "$INCOMING_DIR" ] && echo "Invalid incoming directory" && exit 1
[ -z "$REPO" ] && echo "github repo undefined" && exit 1

function filter {
	grep -vE "Exporting indices...|Deleting files no longer referenced..."
}

function import {
	[ -z "$1" ] && echo "DISTRO undefined" && exit 1
	[ -z "$2" ] && echo "ARCH undefined" && exit 1

	local distro="$1-testing" # operate on -testing distro
	local arch="$2"

	# Translate arch x64 -> amd64
	[ "$arch" == "x64" ] && arch="amd64"

	# Import sources
	if [ "$arch" == "amd64" ]; then
		printf "\nImporting source packages\n"
		for f in "$INCOMING_DIR"/*.dsc; do
			[ -f "$f" ] || break  # Handle case of no files found
			echo "${f#"$INCOMING_DIR/"}"
			reprepro includedsc "$distro" "$f" | filter
		done
	fi

	# Import packages
	printf "\nImporting binary packages\n"
	for f in "$INCOMING_DIR"/*.deb; do
		[ -f "$f" ] || break  # Handle case of no files found
		echo "${f#"$INCOMING_DIR/"}"
		reprepro -A "$arch" includedeb "$distro" "$f" | filter
	done

	# Save log files
	mkdir -p "log/${distro%-testing}.$arch"
	mv "$INCOMING_DIR"/*.log "log/${distro%-testing}.$arch"

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
		reprepro -A "$arch" -C main-dbg includedeb "$distro" "${f}.deb" | filter
	done
	(cd "$INCOMING_DIR" || exit 1; rm ./*.deb)

	printf "\nExporting\n"
	reprepro export "$distro"

	# Merge local.yaml into ros-one.yaml
	cat "$INCOMING_DIR/local.yaml" >> "ros-one.yaml"
	"$(dirname "${BASH_SOURCE[0]}")/../src/scripts/yaml_remove_duplicates.py" ros-one.yaml

	# Remove remaining files
	rm -rf "${INCOMING_DIR:?}"/*
}

# Download debs artifact(s)
if [ "$(ls -A "$INCOMING_DIR")" ]; then
	echo "Importing existing files from incoming directory"
	# shellcheck disable=SC2153 # DISTRO and ARCH might be unset
	import "$DISTRO" "$ARCH"
else
	if [ -z "$RUN_ID" ] ; then
		# Retrieve RUN_ID of latest workflow run
		RUN_ID=$(gh api -X GET "/repos/$REPO/actions/runs" | jq ".workflow_runs[0] | .id")
	fi
	# Retrieve names of artifacts in that workflow run
	artifacts=$(gh api -X GET "/repos/$REPO/actions/artifacts" | jq --raw-output ".artifacts[] | select(.workflow_run.id == $RUN_ID) | .name")
	for a in $artifacts; do
		echo "Fetching artifact \"$a\" from https://github.com/$REPO/actions/runs/$RUN_ID"
		gh --repo "$REPO" run download --name "$a" --dir "$INCOMING_DIR" "$RUN_ID" || continue

		# parse distro and arch from artifact name <distro>-<arch>-debs
		if [[ $a =~ ([^-]+)-([^-]+)(-debs)? ]]; then
			distro=${BASH_REMATCH[1]}
			arch=${BASH_REMATCH[2]}
		else
			distro=$DISTRO
			arch=$ARCH
		fi
		import "$distro" "$arch"
	done
fi
