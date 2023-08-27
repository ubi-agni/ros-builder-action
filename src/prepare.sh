#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

# https://wiki.ubuntuusers.de/Apt-Pinning/#Einzelne-Pakete-aus-einem-Sammel-PPA-installieren
function gen_pin_entries {
  local src=$1
  local enable=$2

  # disable all packages from $src
  gen_pin_entry "$src" "*" -1

  # but allow updating of selected packages
  for pkg in $enable; do
    gen_pin_entry "$src" "$pkg" 500
  done
}

function gen_pin_entry {
  local src=$1
  local pkg=$2
  local priority
  priority="${3:-1}"

  cat <<- EOF

Package: $pkg
Pin: $src
Pin-Priority: $priority
EOF
}

function restrict_src_to_packages {
  gen_pin_entries "$@" | ici_asroot tee /etc/apt/preferences > /dev/null
}

REPOS_LIST_FILE="/etc/apt/sources.list.d/ros-builder-repos.list"
function configure_deb_repo {
  ici_asroot /bin/bash -c "echo \"$1\" >> \"$REPOS_LIST_FILE\""
}
function configure_extra_deb_sources {
  ici_asroot rm -f "$REPOS_LIST_FILE"
  echo "$EXTRA_DEB_SOURCES" | while IFS= read -r line; do
    ici_log "$line"
    _ici_guard configure_deb_repo "$line"
  done
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
    "deb $DISTRIBUTION_REPO $DEB_DISTRO main universe" \
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

function generate_readme {
	local branch=${GITHUB_REF}

	# shellcheck disable=SC2006,2086
  cat <<EOF > "$DEBS_PATH/README.md"
		# Instructions

		## Install

		```bash
		echo "deb [trusted=yes] @REPO_URL@ ./" | sudo tee /etc/apt/sources.list.d/$branch.list
		sudo apt update

		sudo apt install python3-rosdep
		echo "yaml @REPO_URL@/local.yaml debian" | sudo tee /etc/ros/rosdep/sources.list.d/1-$branch.list
		rosdep update
		```
EOF
}
