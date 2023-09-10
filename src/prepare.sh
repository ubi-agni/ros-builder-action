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
function configure_extra_host_sources {
  ici_asroot rm -f "$REPOS_LIST_FILE"
  while IFS= read -r line; do
    ici_log "$line"
    _ici_guard configure_deb_repo "$line"
  done <<< "$EXTRA_HOST_SOURCES"
}

function create_chroot {
  if [ -d /var/cache/sbuild-chroot ] && [ -f /etc/schroot/chroot.d/sbuild ]; then
    echo "chroot already exists"
    return
  fi

  # http://127.0.0.1:3142 should be quoted by double quotes, but this leads to three-fold nested quotes!
  # Using @ first and replacing them later with quotes via sed...
  local acng_config_cmd='echo \"Acquire::http::Proxy @http://127.0.0.1:3142@;\" | tee /etc/apt/apt.conf.d/01acng'

  local chroot_folder="/var/cache/sbuild-chroot"
  # shellcheck disable=SC2016
  ici_cmd ici_asroot mmdebstrap \
    --variant=buildd --include=apt,ccache,ca-certificates,curl,build-essential,debhelper,fakeroot,cmake,python3-rosdep,python3-catkin-pkg \
    --customize-hook='chroot "$1" curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg' \
    --customize-hook='chroot "$1" '"sh -c \"$acng_config_cmd\"" \
    --customize-hook='chroot "$1" sed -i "s#@#\"#g" /etc/apt/apt.conf.d/01acng' \
    "$DEB_DISTRO" "$chroot_folder" \
    "deb $DISTRIBUTION_REPO $DEB_DISTRO main universe" \
    "deb [signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu jammy main"

  ici_log
  ici_color_output "${ANSI_BOLD}" "Write schroot config"
  cat <<- EOF | ici_asroot tee /etc/schroot/chroot.d/sbuild
[sbuild]
groups=root,sbuild
root-groups=root,sbuild
profile=sbuild
type=directory
directory=$chroot_folder
union-type=overlay
EOF
  # sbuild-rw: writable sbuild
  sed -e 's#\(union-type\)=overlay#\1=none#' -e 's#\[sbuild\]#[sbuild-rw]#'\
    /etc/schroot/chroot.d/sbuild | ici_asroot tee /etc/schroot/chroot.d/sbuild-rw

  ici_log
  ici_color_output "${ANSI_BOLD}" "Add mount points to sbuild's fstab"
  cat <<- EOF | ici_asroot tee -a /etc/schroot/sbuild/fstab
$CCACHE_DIR  /build/ccache   none    rw,bind         0       0
$DEBS_PATH   /build/repo     none    rw,bind         0       0
EOF

  ici_log
  ici_color_output "${ANSI_BOLD}" "Add extra debian package sources"
  while IFS= read -r line; do
    echo "$line"
    cat <<- EOF | ici_pipe_into_schroot sbuild-rw
    echo "$line" >> "$REPOS_LIST_FILE"
EOF
  done <<< "$EXTRA_DEB_SOURCES"

  ici_log
  ici_color_output "${ANSI_BOLD}" "apt-get update in chroot"
  echo "apt-get update" | ici_pipe_into_schroot sbuild-rw
}

function configure_sbuildrc {
  # https://wiki.ubuntu.com/SimpleSbuild
  cat << EOF | tee ~/.sbuildrc
\$build_environment = { 'CCACHE_DIR' => '/build/ccache' };
\$path = '/usr/lib/ccache:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games';
\$dsc_dir = "package";
\$build_path = "/build/package/";
\$build_dir = "$DEBS_PATH";
\$dpkg_source_opts = ["-Zgzip", "-z1", "--format=1.0", "-sn"];
\$extra_repositories = ["deb [trusted=yes] file:///build/repo ./"];
$EXTRA_SBUILD_CONFIG
EOF
}

function create_ws {
  local src=$1; shift

  rm -rf src
  mkdir src
  vcs import --recursive --shallow --input "$src" src
}

function load_local_yaml {
  while IFS= read -r line; do
    url=$(echo "$line" | sed -n 's#deb\s\(\[[^]]*\]\)\?\s\([^ ]*\).*#\2#p')
    if curl -sfL "$url/local.yaml" -o /tmp/local.yaml ; then
      echo "$url/local.yaml"
      cat /tmp/local.yaml >> "$DEBS_PATH/local.yaml"
    fi
  done <<< "$EXTRA_DEB_SOURCES"
}

function declare_extra_rosdep_sources {
  for source in $EXTRA_ROSDEP_SOURCES; do
    [ ! -f "$GITHUB_WORKSPACE/$source" ] || source="file://$GITHUB_WORKSPACE/$source"
    echo "yaml $source $ROS_DISTRO"
  done | ici_asroot tee /etc/ros/rosdep/sources.list.d/02-remote.list
}
