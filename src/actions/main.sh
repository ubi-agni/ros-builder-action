#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2023, Robert Haschke

DIR_THIS="$(dirname "${BASH_SOURCE[0]}")"
ICI_SRC_PATH="$(realpath "$DIR_THIS/..")"

# shellcheck source=src/env.sh
source "$ICI_SRC_PATH/env.sh"

# shellcheck source=src/util.sh
source "${ICI_SRC_PATH}/util.sh"

ici_start_fold "Variables"
echo "ROS_DISTRO=$ROS_DISTRO"
echo "DEB_DISTRO=$DEB_DISTRO"
echo "EXTRA_DEB_SOURCES=$EXTRA_DEB_SOURCES"
echo "EXTRA_ROSDEP_SOURCES=$EXTRA_ROSDEP_SOURCES"
echo "ROS_SOURCES=$ROS_SOURCES"
echo "EXTRA_SBUILD_CONFIG=$EXTRA_SBUILD_CONFIG"
echo "CONTINUE_ON_ERROR=$CONTINUE_ON_ERROR"
echo "REPO_PATH=$REPO_PATH"
echo "DEBUG_BASH=$DEBUG_BASH"
ici_end_fold

# shellcheck source=src/prepare.sh
source "${ICI_SRC_PATH}/prepare.sh"

# shellcheck source=src/build.sh
source "${ICI_SRC_PATH}/build.sh"
