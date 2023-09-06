#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=src/prepare.sh
source "${SRC_PATH}/prepare.sh"

ici_title "Install required packages on host system"

## Add required apt gpg keys and sources
# Jochen's ppa for mmdebstrap, sbuild
ici_append INSTALL_GPG_KEYS "sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys D8A3751519274DEF"
ici_append EXTRA_DEB_SOURCES "deb http://ppa.launchpad.net/v-launchpad-jochen-sprickerhof-de/sbuild/ubuntu jammy main"
ici_cmd restrict_src_to_packages "release o=v-launchpad-jochen-sprickerhof-de" "mmdebstrap sbuild"

# ROS for python3-rosdep, python3-vcstool, python3-colcon-*
ros_key_file="/usr/share/keyrings/ros-archive-keyring.gpg"
ici_append INSTALL_GPG_KEYS "sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o $ros_key_file"
ici_append EXTRA_DEB_SOURCES "deb [signed-by=$ros_key_file] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main"

# Configure sources
ici_hook INSTALL_GPG_KEYS
ici_timed "Configure EXTRA_DEB_SOURCES" configure_extra_deb_sources

ici_timed "Update apt package list" ici_asroot apt-get -qq update

# Configure apt-cacher-ng
echo apt-cacher-ng apt-cacher-ng/tunnelenable boolean true | ici_asroot debconf-set-selections

# Install packages on host
DEBIAN_FRONTEND=noninteractive ici_timed "Install packages" ici_apt_install \
	mmdebstrap sbuild schroot devscripts libdistro-info-perl ccache curl apt-cacher-ng \
	python3-pip python3-rosdep python3-vcstool python3-colcon-common-extensions

# Install patched bloom to handle ROS "one" distro key when resolving python and ROS version
ici_timed "Install bloom" ici_asroot pip install -U git+https://github.com/rhaschke/bloom.git@ros-one
ici_timed "rosdep init" ici_asroot rosdep init

ici_timed "check apt-cacher-ng" service apt-cacher-ng status

ici_timed "Declare EXTRA_ROSDEP_SOURCES" declare_extra_rosdep_sources


ici_title "Prepare build environment"

export CCACHE_DIR="${CCACHE_DIR:-$HOME/ccache}"
ici_timed "Configure ccache" ccache --zero-stats --max-size=10.0G
# allow ccache access from sbuild
chmod a+rX ~
chmod -R a+rwX "$CCACHE_DIR"

ici_timed "Create sbuild chroot" create_chroot

ici_timed "Configure ~/.sbuildrc" configure_sbuildrc

ici_timed "Create \$DEBS_PATH=$DEBS_PATH" mkdir -p "$DEBS_PATH"

ici_timed "Generate README.md" generate_readme "${DEPLOY_URL:-}" "${BRANCH:-}" > README.md
