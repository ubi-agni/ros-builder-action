#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

function deb_pkg_name {
  echo "ros-$ROS_DISTRO-$(echo "$1" | tr '_' '-')"
}

function register_local_pkgs_with_rosdep {
  #shellcheck disable=SC2086
  for pkg in "${PKG_NAMES[@]}"; do
    cat << EOF >> "$DEBS_PATH/local.yaml"
$pkg:
  $DISTRIBUTION:
    - $(deb_pkg_name "$pkg")
EOF
  done
  "$SRC_PATH/scripts/yaml_remove_duplicates.py" "$DEBS_PATH/local.yaml"

  echo "yaml file://$DEBS_PATH/local.yaml $ROS_DISTRO" | \
    ici_asroot tee /etc/ros/rosdep/sources.list.d/01-local.list

  ici_cmd rosdep update
}

function prepare_ws {
  local ws_path=$1
  local src=$2

  rm -rf "$ws_path"
  mkdir -p "$ws_path"
  ici_timed "Import ROS sources into workspace" vcs import --recursive --input "$src" "$ws_path"
}

function update_repo {
  local old_path=$PWD
  cd "$DEBS_PATH" || return 1
  apt-ftparchive packages . > Packages
  apt-ftparchive release  . > Release
  cd "$old_path" || return 1
}

function pkg_exists {
  local version; version=$(apt-cache policy "$(deb_pkg_name "$1")" | sed -n 's#^\s*Candidate:\s\(.*\)#\1#p')
  if [ "$SKIP_EXISTING" == "true" ] && [ -n "$version" ] && [ "$version" != "(none)" ]; then
    return 0
  else
    return 1
  fi
}

function build_pkg {
  local old_path=$PWD
  local pkg_name=$1
  local pkg_path=$2

  test -f "$pkg_path/CATKIN_IGNORE" && echo "Skipped (CATKIN_IGNORE)" && return
  test -f "$pkg_path/COLCON_IGNORE" && echo "Skipped (COLCON_IGNORE)" && return
  pkg_exists "$pkg_name" && echo "Skipped (already built)" && return

  cd "$pkg_path" || return 1
  trap 'trap - RETURN; cd "$old_path"' RETURN # cleanup on return

  if ! ici_label bloom-generate "${BLOOM_GEN_CMD}" --os-name="$DISTRIBUTION" --os-version="$DEB_DISTRO" --ros-distro="$ROS_DISTRO"; then
    gha_error "bloom-generate failed for ${pkg_name}"
    return 1
  fi

  if [ "$pkg_name" = "catkin" ]; then
    # Enable CATKIN_INSTALL_INTO_PREFIX_ROOT for catkin package
    sed -i 's@-DCATKIN_BUILD_BINARY_PACKAGE="1"@-DCATKIN_INSTALL_INTO_PREFIX_ROOT="1"@' debian/rules
  fi

  # https://github.com/ros-infrastructure/bloom/pull/643
  echo 11 > debian/compat

  # Set the version based on the checked out tag that contain at least on digit
  # strip any leading non digits as they are not part of the version number
  # strip a potential trailing -g<sha>
  version=$( ( git describe --tag --match "*[0-9]*" 2>/dev/null || echo 0 ) | sed 's@^[^0-9]*@@;s@-g[0-9a-f]*$@@')
  debchange -v "$version-$(date +%Y%m%d.%H%M)" -p -D "$DEB_DISTRO" -u high -m "Append timestamp when binarydeb was built."

  ici_label update_repo || return 2
  SBUILD_OPTS="--chroot=sbuild --no-clean-source --no-run-lintian --nolog $EXTRA_SBUILD_OPTS"
  if ! ici_label sg sbuild -c "sbuild $SBUILD_OPTS"; then # run with sbuild group permissions
    gha_error "sbuild failed for ${pkg_name}"
    return 1
  fi

  ici_label ccache -sv || return 2
  gha_report_result "LATEST_PACKAGE" "$pkg_name"

  if [ "$INSTALL_TO_CHROOT" == "true" ]; then
    ici_color_output "${ANSI_BOLD}" "Install package within chroot"
    # shellcheck disable=SC2012
    cat <<- EOF | ici_pipe_into_schroot sbuild-rw
      apt install --no-install-recommends -q -y \$(ls -1 -t /build/repo/"$(deb_pkg_name "$pkg_name")"*.deb | head -1)
EOF
  fi
}

function build_source {
  local old_path=$PWD
  local ws_path="$PWD/ws"

  ici_title "Build packages from $1"

  prepare_ws "$ws_path" "$1"
  cd "$ws_path" || exit 1

  # determine list of packages (names + folders)
  PKG_NAMES=()
  PKG_FOLDERS=()
  #shellcheck disable=SC2034,SC2086
  while read -r name folder dummy; do
    PKG_NAMES+=("$name")
    PKG_FOLDERS+=("$folder")
  done < <(colcon list --topological-order $COLCON_PKG_SELECTION)

  ici_timed "Register new packages with rosdep" register_local_pkgs_with_rosdep

  local total="${#PKG_NAMES[@]}"
  for (( idx=0; idx < total; idx++ )); do
    ici_time_start "Building package $((idx+1))/$total: ${PKG_NAMES[$idx]}"
    if ! build_pkg "${PKG_NAMES[$idx]}" "${PKG_FOLDERS[$idx]}"; then
      # exit code 2 indicates not-yet handled failure
      test "$?" = 2 && gha_error "Unknown failure building package ${PKG_NAMES[$idx]}"
      test "$CONTINUE_ON_ERROR" = false && ici_exit 1 || FAIL_EVENTUALLY=1
    fi
    ici_time_end
  done

  cd "$old_path" || exit 1
}

function build_all_sources {
  for src in $ROS_SOURCES; do
    build_source "$src"
  done
}

export FAIL_EVENTUALLY
