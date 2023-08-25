#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

function add_pin_entry {
  local src="$1"; shift
  local pkg="$1"; shift
  local priority
  priority="${1:-1}"; shift

  cat << EOF | ici_asroot tee /etc/apt/preferences > /dev/null

Package: $pkg
Pin: $src
Pin-Priority: $priority
EOF
}

# https://wiki.ubuntuusers.de/Apt-Pinning/#Einzelne-Pakete-aus-einem-Sammel-PPA-installieren
function restrict_src_to_packages {
  local src
  local enable
  src=$1; shift
  enable=$1; shift

  # disable all packages from $src
  add_pin_entry "$src" "*" -1

  # but allow updating of selected packages
  for pkg in $enable; do
    add_pin_entry "$src" "$pkg" 500
  done
}

function install_host_packages {
  local ros_key_file="/usr/share/keyrings/ros-archive-keyring.gpg"
  local arch
  arch="arch=$(dpkg --print-architecture)"

  ici_start_fold "Define new packages sources"
  ici_cmd ici_asroot add-apt-repository -y --no-update ppa:v-launchpad-jochen-sprickerhof-de/sbuild
  ici_cmd restrict_src_to_packages "release o=v-launchpad-jochen-sprickerhof-de" "mmdebstrap sbuild"

  ici_cmd ici_asroot curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o "$ros_key_file"
  echo "deb [$arch signed-by=$ros_key_file] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" | ici_cmd ici_asroot tee /etc/apt/sources.list.d/ros2-latest.list

  echo "$EXTRA_DEB_SOURCES" | ici_asroot tee /etc/apt/sources.list.d/1-custom-ros-deb-builder-repositories.list
  ici_end_fold

  echo apt-cacher-ng apt-cacher-ng/tunnelenable boolean true | ici_asroot debconf-set-selections

  ici_step "Update apt package list" ici_asroot apt-get update -q

  DEBIAN_FRONTEND=noninteractive ici_step "Install packages" \
    ici_asroot apt-get install -yq \
    mmdebstrap sbuild devscripts ccache curl apt-cacher-ng \
    python3-pip python3-rosdep python3-vcstool python3-colcon-common-extensions

  # Install patched bloom to handle ROS "one" distro key when resolving python and ROS version
  ici_step "Install bloom" ici_asroot pip install -U git+https://github.com/rhaschke/bloom.git@ros-one
  ici_step "rosdep init" ici_asroot rosdep init
}

function create_chroot {
  # http://127.0.0.1:3142 should be quoted by double quotes, but this leads to three-fold nested quotes!
  # Using @ first and replacing them later with quotes via sed...
  local acng_config_cmd='echo \"Acquire::http::Proxy @http://127.0.0.1:3142@;\" | tee /etc/apt/apt.conf.d/01acng'

  mkdir -p ~/.cache/sbuild
  # shellcheck disable=SC2016
  ici_cmd mmdebstrap \
    --variant=buildd --include=apt,ccache,ca-certificates,curl,python3-rosdep,python3-catkin-pkg \
    --customize-hook='chroot "$1" update-ccache-symlinks' \
    --customize-hook='chroot "$1" curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg' \
    --customize-hook='chroot "$1" '"sh -c \"$acng_config_cmd\"" \
    --customize-hook='chroot "$1" sed -i "s#@#\"#g" /etc/apt/apt.conf.d/01acng' \
    "$DEB_DISTRO" "$HOME/.cache/sbuild/$DEB_DISTRO-amd64.tar" \
    "deb http://azure.archive.ubuntu.com/ubuntu $DEB_DISTRO main universe" \
    "deb [arch=amd64 signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu jammy main"
}

function configure_sbuildrc {
  # https://wiki.ubuntu.com/SimpleSbuild
  cat << EOF | tee ~/.sbuildrc
\$build_environment = { 'CCACHE_DIR' => '/build/ccache' };
\$path = '/usr/lib/ccache:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games';
\$build_path = "/build/package/";
\$dsc_dir = "package";
\$unshare_bind_mounts = [ { directory => "$HOME/.cache/ccache", mountpoint => '/build/ccache' } ];
$EXTRA_SBUILD_CONFIG
EOF
}

function create_ws {
  local src=$1; shift

  rm -rf src
  mkdir src
  vcs import --recursive --input "$src" src
}

function declare_extra_rosdep_sources {
  for source in $EXTRA_ROSDEP_SOURCES; do
    [ ! -f "$GITHUB_WORKSPACE/$source" ] || source="file://$GITHUB_WORKSPACE/$source"
    echo "yaml $source $ROS_DISTRO"
  done | ici_asroot tee /etc/ros/rosdep/sources.list.d/02-remote.list
}

ici_title "Install required packages on host system"
install_host_packages
ici_step "check apt-cacher-ng" service apt-cacher-ng status

ici_step "Declare EXTRA_ROSDEP_SOURCES" declare_extra_rosdep_sources

ici_title "Prepare build environment"
ici_step "Create sbuild chroot" create_chroot

ici_step "Configure ccache" ccache --zero-stats --max-size=10.0G
# allow ccache access from sbuild
chmod a+rX ~
chmod -R a+rwX ~/.cache/ccache

ici_step "Configure ~/.sbuildrc" configure_sbuildrc

ici_step "Create \$REPO_PATH=$REPO_PATH" mkdir -p "$REPO_PATH"
