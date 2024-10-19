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

function url_from_deb_source {
  # parse url from "deb [[option=value ...]] uri suite [component ...]"
  local re; re="deb\s+(\[[^]]*\]\s+)?(https?://[^ ]+)\s([^ ]+)"
  if [[ $1 =~ $re ]]; then
    local uri;
    # shellcheck disable=SC2001
    uri=$(echo "${BASH_REMATCH[2]}" | sed 's#/\+$##g') # remove trailing slashes
    local suite=${BASH_REMATCH[3]}
    if [ "$suite" = "./" ]; then
      echo "$uri"
    else
      echo "$uri/dists/$suite"
    fi
  else
    return 1 # invalid source spec
  fi
}

function validate_deb_sources {
  local -n var=$1
  local filtered=""
  while IFS= read -r line; do
    local url;
    test -z "$line" && continue
    if ! url=$(url_from_deb_source "$line"); then
      gha_error "Invalid deb source spec: '$line'\nExpected scheme: deb [option=value ...] uri suite [component ...]\nhttps://manpages.ubuntu.com/manpages/jammy/man5/sources.list.5.html#the%20deb%20and%20deb-src%20types:%20general%20format"
    else
      local http_result; http_result=$(curl -o /dev/null --silent -Iw '%{http_code}' "$url/Release")
      if [ "$http_result" = 200 ]; then
        ici_append filtered "$line"
      else
        gha_warning "deb repository $url is missing Release file"
      fi
    fi
  done <<< "$var"
  var="$filtered"
}

REPOS_LIST_FILE="/etc/apt/sources.list.d/ros-builder-repos.list"
DEBS_LIST_FILE="/etc/apt/sources.list.d/ros-builder-debs.list"
function configure_extra_host_sources {
  ici_asroot rm -f "$REPOS_LIST_FILE"
  while IFS= read -r line; do
    eval echo "$line" | ici_asroot tee -a "$REPOS_LIST_FILE"
  done <<< "$EXTRA_HOST_SOURCES"
}

function create_chroot {
  if [ -d /var/cache/sbuild-chroot ] && [ -f /etc/schroot/chroot.d/sbuild ]; then
    echo "chroot already exists"
    return
  fi


  local tmp; tmp=$(mktemp "/tmp/ros-builder-XXXXXX.sh")
  cat <<- EOF > "$tmp"
  mkdir -p /etc/apt/keyrings
  curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /etc/apt/keyrings/ros-archive-keyring.gpg
  $INSTALL_GPG_KEYS
  echo "Acquire::http::Proxy \"http://127.0.0.1:3142\";" > tee /etc/apt/apt.conf.d/01acng
EOF

  ici_color_output BOLD "Add extra debian package sources"
  while IFS= read -r line; do
    eval echo "$line"
    echo "echo \"$line\" >> \"$REPOS_LIST_FILE\"" >> "$tmp"
  done <<< "$EXTRA_DEB_SOURCES"

  local chroot_folder="/var/cache/sbuild-chroot"
  # shellcheck disable=SC2016
  ici_cmd ici_asroot mmdebstrap \
    --variant=buildd --include=apt,apt-utils,ccache,ca-certificates,curl,build-essential,debhelper,fakeroot,cmake,git,python3-rosdep,python3-catkin-pkg \
    --customize-hook="upload $tmp $tmp" \
    --customize-hook="chroot \$1 chmod 755 $tmp" \
    --customize-hook="chroot \$1 sh -c $tmp" \
    "$DEB_DISTRO" "$chroot_folder" \
    "deb $DISTRIBUTION_REPO $DEB_DISTRO main universe" \
    "deb [signed-by=/etc/apt/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $DEB_DISTRO main"

  ici_log
  ici_color_output BOLD "Write schroot config"
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
  ici_color_output BOLD "Add mount points to sbuild's fstab"
  cat <<- EOF | ici_asroot tee -a /etc/schroot/sbuild/fstab
$CCACHE_DIR  /build/ccache   none    rw,bind         0       0
$DEBS_PATH   /build/repo     none    rw,bind         0       0
EOF

  ici_log
  ici_color_output BOLD "apt-get update -q in chroot"
  echo "apt-get update -q" | ici_pipe_into_schroot sbuild-rw
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

function load_local_yaml {
  while IFS= read -r line; do
    local url; url=$(url_from_deb_source "$line")
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

function update_repo {
  local old_path=$PWD
  cd "$DEBS_PATH" || return 1
  apt-ftparchive packages . > Packages
  apt-ftparchive release  . > Release
  cd "$old_path" || return 1

  ici_asroot apt-get update -qq -o Dir::Etc::sourcelist="$DEBS_LIST_FILE" \
        -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
}
