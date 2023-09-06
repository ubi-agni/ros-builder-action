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
  if [ -d /var/cache/sbuild-chroot ] && [ -f /etc/schroot/chroot.d/sbuild ]; then
    echo "chroot already exists"
    return
  fi

  # http://127.0.0.1:3142 should be quoted by double quotes, but this leads to three-fold nested quotes!
  # Using @ first and replacing them later with quotes via sed...
  local acng_config_cmd='echo \"Acquire::http::Proxy @http://127.0.0.1:3142@;\" | tee /etc/apt/apt.conf.d/01acng'

  # shellcheck disable=SC2016
  ici_cmd ici_asroot mmdebstrap \
    --variant=buildd --include=apt,ccache,ca-certificates,curl,build-essential,debhelper,fakeroot,cmake,python3-rosdep,python3-catkin-pkg \
    --customize-hook='chroot "$1" curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg' \
    --customize-hook='chroot "$1" '"sh -c \"$acng_config_cmd\"" \
    --customize-hook='chroot "$1" sed -i "s#@#\"#g" /etc/apt/apt.conf.d/01acng' \
    "$DEB_DISTRO" "/var/cache/sbuild-chroot" \
    "deb $DISTRIBUTION_REPO $DEB_DISTRO main universe" \
    "deb [signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu jammy main"

  # Write schroot config
  cat <<- EOF | ici_asroot tee /etc/schroot/chroot.d/sbuild
[sbuild]
groups=root,sbuild
root-groups=root,sbuild
profile=sbuild
type=directory
directory=/var/cache/sbuild-chroot
union-type=overlay
EOF

  # Add mount points to sbuild's fstab
  cat <<- EOF | ici_asroot tee -a /etc/schroot/sbuild/fstab
$CCACHE_DIR  /build/ccache   none    rw,bind         0       0
$DEBS_PATH   /build/repo     none    rw,bind         0       0
EOF
}

function configure_sbuildrc {
  # https://wiki.ubuntu.com/SimpleSbuild
  cat << EOF | tee ~/.sbuildrc
\$build_environment = { 'CCACHE_DIR' => '/build/ccache' };
\$path = '/usr/lib/ccache:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games';
\$dsc_dir = "package";
\$build_path = "/build/package/";
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

function repository_url {
  local url=$1
  local branch=$2

  [ "$url" == "self" ] && url="https://github.com/$GITHUB_REPOSITORY"
  if [[ $url =~ ([^:]+):([^#]+) ]]; then
    local repo=${BASH_REMATCH[2]}
    local scheme=${BASH_REMATCH[1]}

    # strip off trailing .git from $repo
    repo=${repo%.git}
    case "$scheme" in
      github | gh | git@github.com)
        echo "https://raw.githubusercontent.com/$repo/$branch"
        ;;
      'git+file'*|'git+http'*|'git+ssh'*|'https'*|'http'*)
        # ensure that $repo starts with github.com
        if [[ $repo =~ ^//github.com/ ]]; then
          echo "https://raw.githubusercontent.com/${repo#//github.com/}/$branch"
        else
          gha_error "Only github.com repositories are supported."
        fi
        ;;
      *)
        gha_error "Unsupported scheme '$scheme' in URL '$url'."
        ;;
    esac
  else
    gha_error "Could not parse URL '$url'. It does not match the expected pattern: <scheme>:<resource>#<version>."
  fi
}

function generate_readme {
  local url
  if [ -n "$1" ] && [ -n "$2" ]; then
    url=$(repository_url "$1" "$2")
  else
    url="@REPO_URL@"
  fi

  sed -e "s|@REPO_URL@|$url|g" \
      -e "s|@DISTRO_NAME@|$DEB_DISTRO-$ROS_DISTRO|g" \
      "$SRC_PATH/README.md.in"
}
