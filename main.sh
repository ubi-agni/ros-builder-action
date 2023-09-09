#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2023, Robert Haschke

ici_start_fold "Variables"
cat <<EOF
ROS_DISTRO=$ROS_DISTRO
DEB_DISTRO=$DEB_DISTRO
ROS_SOURCES=$ROS_SOURCES
COLCON_PKG_SELECTION=$COLCON_PKG_SELECTION

EXTRA_DEB_SOURCES=$EXTRA_DEB_SOURCES
EXTRA_ROSDEP_SOURCES=$EXTRA_ROSDEP_SOURCES
EXTRA_SBUILD_CONFIG=$EXTRA_SBUILD_CONFIG
CONTINUE_ON_ERROR=$CONTINUE_ON_ERROR

DEBS_PATH=$DEBS_PATH

DEBUG_BASH=$DEBUG_BASH
EOF
ici_end_fold

# shellcheck source=src/scripts/prepare.sh
source "${SRC_PATH}/scripts/prepare.sh"

# shellcheck source=src/scripts/build.sh
source "${SRC_PATH}/scripts/build.sh"
