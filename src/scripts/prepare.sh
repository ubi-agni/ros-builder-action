#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=src/prepare.sh
source "${SRC_PATH}/prepare.sh"

ici_title "Install required packages on host system"

ici_cmd validate_deb_sources EXTRA_DEB_SOURCES

## Add required apt gpg keys and sources
# Jochen's ppa for mmdebstrap, sbuild
ici_append INSTALL_HOST_GPG_KEYS "sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys D8A3751519274DEF"
ici_append EXTRA_HOST_SOURCES "deb http://ppa.launchpad.net/v-launchpad-jochen-sprickerhof-de/sbuild/ubuntu jammy main"
ici_cmd restrict_src_to_packages "release o=v-launchpad-jochen-sprickerhof-de" "mmdebstrap sbuild"

# Configure sources
ici_hook INSTALL_HOST_GPG_KEYS
ici_timed "Configure EXTRA_HOST_SOURCES" configure_extra_host_sources

ici_timed "Update apt package list" ici_asroot apt-get update

# Configure apt-cacher-ng
echo apt-cacher-ng apt-cacher-ng/tunnelenable boolean true | ici_asroot debconf-set-selections

# Install packages on host
DEBIAN_FRONTEND=noninteractive ici_timed "Install build packages" ici_cmd "${APT_QUIET[@]}" ici_apt_install \
	mmdebstrap sbuild schroot devscripts ccache apt-cacher-ng python3-pip libxml2-utils libarchive-tools \
	python3-stdeb python3-all dh-python build-essential

export PIP_BREAK_SYSTEM_PACKAGES=1
# Install patched bloom to handle ROS "one" distro key when resolving python and ROS version
ici_timed "Install bloom" ici_asroot pip install -U git+https://github.com/rhaschke/bloom.git@ros-one
# Install patched vcstool to allow for treeless clones
ici_timed "Install vcstool" ici_asroot pip install -U git+https://github.com/rhaschke/vcstool.git@master
# Install colcon and rosdep from pypi
ici_timed "Install rosdep and colcon" ici_asroot pip install -U rosdep colcon-package-information colcon-package-selection colcon-ros colcon-cmake

# remove existing rosdep config to avoid conflicts with rosdep init
ici_asroot rm -f /etc/ros/rosdep/sources.list.d/20-default.list
ici_timed "rosdep init" ici_asroot rosdep init

# Start apt-cacher-ng if not yet running (for example in docker)
ici_start_fold "Check apt-cacher-ng"
service apt-cacher-ng status || ici_asroot service apt-cacher-ng start
ici_end_fold

ici_title "Prepare build environment"

# Configure DEBS_PATH as deb sources
ici_time_start "Configure $DEBS_PATH as deb sources"
echo "deb [trusted=yes] file://$(realpath "$DEBS_PATH") ./" | ici_asroot tee -a "$DEBS_LIST_FILE"
ici_label mkdir -p "$DEBS_PATH"
ici_label update_repo
ici_time_end

ici_timed "Declare rosdep sources" declare_rosdep_sources

export CCACHE_DIR="${CCACHE_DIR:-$HOME/ccache}"
ici_timed "Configure ccache" ccache --zero-stats --max-size=10.0G

ici_timed "Create sbuild chroot" create_chroot

ici_timed "Configure ~/.sbuildrc" configure_sbuildrc

ici_cmd cp "$SRC_PATH/README.md.in" "$DEBS_PATH"

# Add user to group sbuild
ici_asroot usermod -a -G sbuild "$USER"
