#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2023, Robert Haschke

set -euo pipefail # exit script on errors

## target names
export ROS_DISTRO=${INPUT_ROS_DISTRO:-one}
export DEB_DISTRO=${INPUT_DEB_DISTRO:-$(lsb_release -cs)}

## package repository options
export INSTALL_GPG_KEYS=${INSTALL_GPG_KEYS:-} # hook to install GPG keys
export EXTRA_DEB_SOURCES=${INPUT_EXTRA_DEB_SOURCES:-${EXTRA_DEB_SOURCES:-}}
export EXTRA_ROSDEP_SOURCES=${INPUT_EXTRA_ROSDEP_SOURCES:-${EXTRA_ROSDEP_SOURCES:-}}

## build options
export ROS_SOURCES=${INPUT_ROS_SOURCES:-${ROS_SOURCES:-*.repos}}
export EXTRA_SBUILD_CONFIG=${INPUT_EXTRA_SBUILD_CONFIG:-${EXTRA_SBUILD_CONFIG:-}}
export CONTINUE_ON_ERROR=${INPUT_CONTINUE_ON_ERROR:-false}
EXTRA_SBUILD_OPTS="${EXTRA_SBUILD_OPTS:-} $(echo "$EXTRA_DEB_SOURCES" | sed -n '/^ *$/ T; s/.*/--extra-repository="\0"/; p' | tr '\n' ' ')"
export DEB_BUILD_OPTIONS=nocheck  # don't build/run tests

## deploy options
export DEBS_PATH
DEBS_PATH=$(eval echo "${DEBS_PATH:-$HOME/debs}")
export REPO_PATH
REPO_PATH=$(eval echo "${REPO_PATH:-$HOME/repo}")

export GITHUB_TOKEN=${INPUT_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}

# configure shell debugging
export DEBUG_BASH=${DEBUG_BASH:-false}
if [ "${DEBUG_BASH:-}" ] && [ "$DEBUG_BASH" == true ]; then
	set -x;
fi


# sanity checks

# shellcheck source=src/util.sh
source "$SRC_PATH/util.sh"

case $ROS_DISTRO in
	debian)
		export BLOOM_GEN_CMD=debian
		;;
	boxturtle|cturtle|diamondback|electric|fuerte|groovy|hydro|indigo|jade|kinetic|lunar|melodic)
		gha_error "ROS_DISTRO=$ROS_DISTRO is EOL"
		ici_exit 1
		;;
	*)
		export BLOOM_GEN_CMD=rosdebian
		;;
esac

if debian-distro-info --all | grep -q "$DEB_DISTRO"; then
	export DISTRIBUTION=debian
	export DISTRIBUTION_REPO=http://deb.debian.org/debian
	ici_append INSTALL_GPG_KEYS "sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0E98404D386FA1D9 6ED0E7B82643E131 F8D2585B8783D481"

elif ubuntu-distro-info --all | grep -q "$DEB_DISTRO"; then
	export DISTRIBUTION=ubuntu
	export DISTRIBUTION_REPO=http://azure.archive.ubuntu.com/ubuntu
else
	gha_error "Unknown DEB_DISTRO: $DEB_DISTRO"
	ici_exit 1
fi
