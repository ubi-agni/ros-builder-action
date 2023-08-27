#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

function register_local_pkgs_with_rosdep {
  for pkg in $(colcon list --topological-order --names-only); do
    cat << EOF >> "$DEBS_PATH/local.yaml"
$pkg:
  $DISTRIBUTION:
    - ros-one-$(echo "$pkg" | tr '_' '-')
EOF
  done

  echo "yaml file://$DEBS_PATH/local.yaml $ROS_DISTRO" | \
    ici_asroot tee /etc/ros/rosdep/sources.list.d/01-local.list

  ici_cmd rosdep update
}

function prepare_ws {
  local ws_path=$1
  local src=$2

  rm -rf "$ws_path"
  mkdir -p "$ws_path"
  ici_step "Import ROS sources into workspace" vcs import --recursive --input "$src" "$ws_path"
}

function build_pkg {
  local pkg_path=$1
  local pkg_name

  test -f "$pkg_path/CATKIN_IGNORE" && echo "Skipped" && return
  test -f "$pkg_path/COLCON_IGNORE" && echo "Skipped" && return

  cd "$pkg_path" || return 1

  pkg_name="$(colcon list --topological-order --names-only)"

  if ! ici_cmd bloom-generate "${BLOOM_GEN_CMD}" --os-name="$DISTRIBUTION" --os-version="$DEB_DISTRO" --ros-distro="$ROS_DISTRO"; then
    gha_error "bloom-generate failed for ${pkg_name}"
    cd - || return 1
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

  SBUILD_OPTS="--chroot-mode=unshare --no-clean-source --no-run-lintian --nolog \
    --dpkg-source-opts=\"-Zgzip -z1 --format=1.0 -sn\" --build-dir=\"$DEBS_PATH\" \
    --extra-package=\"$DEBS_PATH\" \
    $EXTRA_SBUILD_OPTS"
  if ! ici_cmd eval sbuild "$SBUILD_OPTS"; then
    gha_error "sbuild failed for ${pkg_name}"
    cd - || return 1
    return 1
  fi

  ici_cmd ccache -sv
  cd - || return 1
}

function build_source {
  local old_path=$PWD
  local ws_path="$PWD/ws"

  ici_title "Build packages from $1"

  prepare_ws "$ws_path" "$1"
  cd "$ws_path" || exit 1
  ici_step "Register new packages with rosdep" register_local_pkgs_with_rosdep

  local pkg_paths
  pkg_paths="$(colcon list --topological-order --paths-only)"
  local count=1
  local total
  total="$(echo "$pkg_paths" | wc -l)"

  for pkg_path in $pkg_paths; do
    if ! ici_step "Building package $count/$total: $pkg_path" build_pkg "$pkg_path"; then
      test "$CONTINUE_ON_ERROR" = false && exit 1 || FAIL_EVENTUALLY=1
    fi
    count=$((count + 1))
  done

  cd "$old_path" || exit 1
}

function build_all_sources {
  for src in $ROS_SOURCES; do
    build_source "$src"
  done
}

FAIL_EVENTUALLY=0
build_all_sources
exit $FAIL_EVENTUALLY
