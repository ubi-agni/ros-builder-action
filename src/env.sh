#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2023, Robert Haschke

set -euo pipefail # exit script on errors

## target names
export ROS_DISTRO=${INPUT_ROS_DISTRO:-one}
export DEB_DISTRO=${INPUT_DEB_DISTRO:-$(lsb_release -cs)}

## package repository options
export EXTRA_DEB_SOURCES=${INPUT_EXTRA_DEB_SOURCES:-${EXTRA_DEB_SOURCES:-}}
export EXTRA_ROSDEP_SOURCES=${INPUT_EXTRA_ROSDEP_SOURCES:-${EXTRA_ROSDEP_SOURCES:-}}

## build options
export ROS_SOURCES=${INPUT_ROS_SOURCES:-${ROS_SOURCES:-*.repos}}
export EXTRA_SBUILD_CONFIG=${INPUT_EXTRA_SBUILD_CONFIG:-${EXTRA_SBUILD_CONFIG:-}}
export CONTINUE_ON_ERROR=${INPUT_CONTINUE_ON_ERROR:-false}
EXTRA_SBUILD_OPTS="${EXTRA_SBUILD_OPTS:-} $(echo "$EXTRA_DEB_SOURCES" | sed -n '/^ *$/ T; s/.*/--extra-repository="\0"/; p' | tr '\n' ' ')"
export DEB_BUILD_OPTIONS=nocheck  # don't build/run tests

## deploy options
export REPO_PATH
REPO_PATH=$(eval echo "${REPO_PATH:-$HOME/debs}")
export BRANCH=${INPUT_BRANCH:-${BRANCH:-${DEB_DISTRO}-${ROS_DISTRO}}}
export GITHUB_TOKEN=${INPUT_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}
export SQUASH_HISTORY=${INPUT_SQUASH_HISTORY:-${SQUASH_HISTORY:-true}}
export PUSH_ON_ERROR=${INPUT_PUSH_ON_ERROR:-${PUSH_ON_ERROR:-false}}

case $ROS_DISTRO in
  debian)
    export BLOOM_GEN_CMD=debian
    ;;
  boxturtle|cturtle|diamondback|electric|fuerte|groovy|hydro|indigo|jade|kinetic|lunar)
    echo "EOL ROS 1 version: $ROS_DISTRO"
    exit 1
    ;;
  *)
    export BLOOM_GEN_CMD=rosdebian
    ;;
esac

# sanity checks
if debian-distro-info --all | grep -q "$DEB_DISTRO"; then
  export DISTRIBUTION=debian
elif ubuntu-distro-info --all | grep -q "$DEB_DISTRO"; then
  export DISTRIBUTION=ubuntu
else
  echo "Unknown DEB_DISTRO: $DEB_DISTRO"
  exit 1
fi

# configure shell debugging
export DEBUG_BASH=${DEBUG_BASH:-false}
if [ "${DEBUG_BASH:-}" ] && [ "$DEBUG_BASH" == true ]; then
	set -x;
fi
