#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2023, Robert Haschke

DIR_THIS="$(dirname "${BASH_SOURCE[0]}")"
SRC_PATH="$(realpath "$DIR_THIS/..")"

# shellcheck source=src/env.sh
source "$SRC_PATH/env.sh"

ici_start_fold "Variables"
cat <<EOF
ROS_DISTRO=$ROS_DISTRO
DEB_DISTRO=$DEB_DISTRO
ROS_SOURCES=$ROS_SOURCES

EXTRA_DEB_SOURCES=$EXTRA_DEB_SOURCES
EXTRA_ROSDEP_SOURCES=$EXTRA_ROSDEP_SOURCES
EXTRA_SBUILD_CONFIG=$EXTRA_SBUILD_CONFIG
CONTINUE_ON_ERROR=$CONTINUE_ON_ERROR

DEBS_PATH=$DEBS_PATH
REPO_PATH=$REPO_PATH

DEBUG_BASH=$DEBUG_BASH
EOF
ici_end_fold

# shellcheck source=main.sh
source "$1"
