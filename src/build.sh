#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

function deb_pkg_name {
  local version=${2:-}
  [ -n "$version" ] && version="_$version" # prepend _
  echo "ros-$ROS_DISTRO-$(echo "$1" | tr '_' '-')$version"
}

function register_local_pkgs_with_rosdep {
  #shellcheck disable=SC2086
  for pkg in "${PKG_NAMES[@]}"; do
    cat << EOF >> "$DEBS_PATH/local.yaml"
$pkg:
  ubuntu: [$(deb_pkg_name "$pkg")]
  debian: [$(deb_pkg_name "$pkg")]
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

function get_release_version {
  local deb_version
  local git_version=""
  local sha

  # version from last changelog entry: <changelog version>-<increment><debian distro>
  deb_version="$(dpkg-parsechangelog --show-field Version)"

  if [ "$(git rev-parse --show-toplevel)" == "$PWD" ]; then
    # version from last (numeric) git release tag: <release version>-<git offset>
    # - stripping any leading non digits as they are not part of the version number
    # - stripping trailing -g<sha>
    git_version="$(git describe --tag --long --match "*[0-9]*" 2>/dev/null | sed 's@^[^0-9]*@@;s@-g[0-9a-f]*$@@')"

    if [ -z "$git_version" ] || [ "$git_version$DEB_DISTRO" \< "$deb_version" ]; then
      # latest tag not defined
      # extract version from latest version-like commit message instead
      read -r sha git_version <<< "$(git log --pretty=format:'%h %s' | grep -E "^[^ ]+[^0-9]{0,3}[0-9.]+\.[0-9]+$" | head -n 1)"
      git_version="${git_version}-$(git rev-list --count "$sha"..HEAD)" # append commit offset from found tag
    fi
  fi

  if [ -z "$git_version" ] || [ "$git_version" == "-0" ] ; then
    git_version="$deb_version" # fallback to deb_version if git version could not be determined
  else
    git_version="$git_version$DEB_DISTRO" # append debian distro (as done by bloom)
  fi
  echo "$git_version"
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

  # Check availability of all required packages (bloom-generated waits for input on rosdep issues)
  rosdep install --simulate --from-paths . > /dev/null || return 2
  ici_label "${BLOOM_QUIET[@]}" bloom-generate "${BLOOM_GEN_CMD}" --os-name="$DISTRIBUTION" --os-version="$DEB_DISTRO" --ros-distro="$ROS_DISTRO" || return 2

  # Enable CATKIN_INSTALL_INTO_PREFIX_ROOT for catkin package
  if [ "$pkg_name" = "catkin" ]; then
    sed -i 's@-DCATKIN_BUILD_BINARY_PACKAGE="1"@-DCATKIN_INSTALL_INTO_PREFIX_ROOT="1"@' debian/rules
  fi
  # Configure ament python packages to install into lib/python3/dist-packages (instead of lib/python3.x/site-packages)
  sed -i 's@lib/{interpreter}/site-packages@lib/python3/dist-packages@' debian/rules

  # https://github.com/ros-infrastructure/bloom/pull/643
  echo 11 > debian/compat

  # Get + Check release version and append build timestamp (following ROS scheme)
  # <release version>-<git offset><debian distro>.date.time
  version="$(get_release_version).$(date +%Y%m%d.%H%M)" || return 5
  # Update release version (with appended timestamp)
  debchange -v "$version" \
    --preserve --force-distribution "$DEB_DISTRO" \
    --urgency high -m "Append timestamp when binarydeb was built." || return 3

  rm -rf .git

  ici_label update_repo || return 1
  SBUILD_OPTS="--chroot=sbuild --no-clean-source --no-run-lintian --dist=$DEB_DISTRO $EXTRA_SBUILD_OPTS"
  ici_label "${SBUILD_QUIET[@]}" sg sbuild -c "sbuild $SBUILD_OPTS" || return 4

  "${CCACHE_QUIET[@]}" ici_label ccache -sv || return 1
  gha_report_result "LATEST_PACKAGE" "$pkg_name"

  if [ "$INSTALL_TO_CHROOT" == "true" ]; then
    ici_color_output BOLD "Install package within chroot"
    # shellcheck disable=SC2012
    cat <<- EOF | "${APT_QUIET[@]}" ici_pipe_into_schroot sbuild-rw
      DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -q -y \$(ls -1 -t /build/repo/"$(deb_pkg_name "$pkg_name")"*.deb | head -1)
EOF
  fi
  # Move .dsc + .tar.gz files from workspace folder to $DEBS_PATH for deployment
  mv ../*.dsc ../*.tar.gz "$DEBS_PATH"

  ## Rename .build log file, which has invalid characters (:) for artifact upload
  local log;
  # shellcheck disable=SC2010
  log=$(ls -1t "$DEBS_PATH/$(deb_pkg_name "${pkg_name}" "${version}")_"*.build | grep -P '(?<!Z)\.build' | head -1)
  mv "$(readlink -f "$log")" "${log/.build/.log}" # rename actual log file
  rm "$log" # remove symlink
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
    ici_time_start "$(ici_colorize CYAN BOLD "Building $pkg_desc")"

    local exit_code=0
    build_pkg "${PKG_NAMES[$idx]}" "${PKG_FOLDERS[$idx]}" || exit_code=$?

    if [ "$exit_code" != 0 ] ; then
      case "$exit_code" in
        2) msg_prefix="bloom-generate failed" ;;
        3) msg_prefix="debchange failed" ;;
        4) msg_prefix="sbuild failed" ;;
        5) msg_prefix="missing release tag for latest version" ;;
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
