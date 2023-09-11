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

  ici_label "${BLOOM_QUIET[@]}" bloom-generate "${BLOOM_GEN_CMD}" --os-name="$DISTRIBUTION" --os-version="$DEB_DISTRO" --ros-distro="$ROS_DISTRO" || return 2

  if [ "$pkg_name" = "catkin" ]; then
    # Enable CATKIN_INSTALL_INTO_PREFIX_ROOT for catkin package
    sed -i 's@-DCATKIN_BUILD_BINARY_PACKAGE="1"@-DCATKIN_INSTALL_INTO_PREFIX_ROOT="1"@' debian/rules
  fi

  # https://github.com/ros-infrastructure/bloom/pull/643
  echo 11 > debian/compat

  # Set version based on last changelog entry and append build timestamp (following official ROS scheme)
  # <changelog version>-<increment><debian distro>.date.time
  # This way, we cannot yet distinguish different, not-yet-released versions (which git describe would do)
  # However, git describe relied on tags being available, which is often not the case!
  # TODO: Increase the increment on each build
  version=$(dpkg-parsechangelog --show-field Version)
  debchange -v "$version.$(date +%Y%m%d.%H%M)" \
    --preserve --force-distribution "$DEB_DISTRO" \
    --urgency high -m "Append timestamp when binarydeb was built." || return 3

  ici_label update_repo || return 1
  SBUILD_OPTS="--chroot=sbuild --no-clean-source --no-run-lintian --nolog $EXTRA_SBUILD_OPTS"
  ici_label "${SBUILD_QUIET[@]}" sg sbuild -c "sbuild $SBUILD_OPTS" || return 4

  "${CCACHE_QUIET[@]}" ici_label ccache -sv || return 1
  gha_report_result "LATEST_PACKAGE" "$pkg_name"

  if [ "$INSTALL_TO_CHROOT" == "true" ]; then
    ici_color_output "${ANSI_BOLD}" "Install package within chroot"
    # shellcheck disable=SC2012
    cat <<- EOF | "${APT_QUIET[@]}" ici_pipe_into_schroot sbuild-rw
      DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -q -y \$(ls -1 -t /build/repo/"$(deb_pkg_name "$pkg_name")"*.deb | head -1)
EOF
  fi
}

function build_source {
  local old_path=$PWD
  local ws_path="$PWD/ws"

  ici_title "Build packages from $1"

  prepare_ws "$ws_path" "$1"
  cd "$ws_path" || ici_exit 1

  # determine list of packages (names + folders)
  PKG_NAMES=()
  PKG_FOLDERS=()
  #shellcheck disable=SC2034,SC2086
  while read -r name folder dummy; do
    PKG_NAMES+=("$name")
    PKG_FOLDERS+=("$folder")
  done < <(colcon list --topological-order $COLCON_PKG_SELECTION)

  ici_timed "Register new packages with rosdep" register_local_pkgs_with_rosdep

  local msg_prefix=""
  local total="${#PKG_NAMES[@]}"
  for (( idx=0; idx < total; idx++ )); do
    local pkg_desc="package $((idx+1))/$total: ${PKG_NAMES[$idx]} (${PKG_FOLDERS[$idx]})"
    ici_time_start "Building $pkg_desc"

    local exit_code=0
    build_pkg "${PKG_NAMES[$idx]}" "${PKG_FOLDERS[$idx]}" || exit_code=$?

    if [ "$exit_code" != 0 ] ; then
      case "$exit_code" in
        2) msg_prefix="bloom-generate failed" ;;
        3) msg_prefix="debchange failed" ;;
        4) msg_prefix="sbuild failed" ;;
        *) msg_prefix="unnamed step failed ($exit_code)" ;;
      esac

      if [ "$CONTINUE_ON_ERROR" = false ]; then
        # exit with custom error message
        ici_exit "$exit_code" gha_error "$msg_prefix on $pkg_desc. Continue with: --packages-start ${PKG_NAMES[$idx]}"
      else
        # fail later
        FAIL_EVENTUALLY=1
        gha_error "$msg_prefix on $pkg_desc."
      fi
    fi
    ici_time_end
  done

  cd "$old_path" || ici_exit 1
}

function build_all_sources {
  for src in $ROS_SOURCES; do
    build_source "$src"
  done
}

export FAIL_EVENTUALLY
