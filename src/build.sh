#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

function deb_pkg_name {
  local version=${2:-}
  [ -n "$version" ] && version="_$version" # prepend _
  echo "ros-$ROS_DISTRO-$(echo "$1" | tr '_' '-')$version"
}

function register_local_pkgs_with_rosdep {
  #shellcheck disable=SC2086
  local total="${#PKG_NAMES[@]}"
  local idx

  for (( idx=0; idx < total; idx++ )); do
    if [ ! -f "${PKG_FOLDERS[$idx]}/package.xml" ]; then # only consider ROS packages
      continue
    fi
    local pkg="${PKG_NAMES[$idx]}"
    cat << EOF >> "$DEBS_PATH/local.yaml"
$pkg:
  ubuntu: [$(deb_pkg_name "$pkg")]
  debian: [$(deb_pkg_name "$pkg")]
EOF
  done

  if [ -f "$DEBS_PATH/local.yaml" ]; then
    "$SRC_PATH/scripts/yaml_remove_duplicates.py" "$DEBS_PATH/local.yaml"

    echo "yaml file://$DEBS_PATH/local.yaml $ROS_DISTRO" | \
      ici_asroot tee /etc/ros/rosdep/sources.list.d/01-local.list

    ici_cmd rosdep update
  fi
}

function ici_vcs_import {
  ici_guard vcs import --recursive --force --treeless "$@"
}

function ici_import_repository {
  local ws_path=$1

  if ! ici_parse_url "$2"; then
    gha_error "URL '$2' does not match the pattern: <scheme>:<resource>[#<fragment>]"
  fi

  local name="${URL_RESOURCE%.git}"
  local url
  case "$URL_SCHEME" in
    bitbucket | bb)   url="https://bitbucket.org/$URL_RESOURCE" ;;
    github | gh)      url="https://github.com/$URL_RESOURCE" ;;
    gitlab | gl)      url="https://gitlab.com/$URL_RESOURCE" ;;
    'git+file'*|'git+http'*|'git+ssh'*)
                      url="${URL_SCHEME#git+}:$URL_RESOURCE" ;;
    git+*)            url="$URL_SCHEME:$URL_RESOURCE" ;;
    *)                url="$URL_SCHEME:$URL_RESOURCE" ;;
  esac

  if [ -z "$URL_FRAGMENT" ] || [ "$URL_FRAGMENT" = "HEAD" ]; then
    ici_vcs_import "$ws_path" <<< "{repositories: {'$name': {type: 'git', url: '$url'}}}"
    WS_SOURCE="${url%.git}"
  else
    ici_vcs_import "$ws_path" <<< "{repositories: {'$name': {type: 'git', url: '$url', version: '$URL_FRAGMENT'}}}"
    WS_SOURCE="${url%.git}/commit/$URL_FRAGMENT"
  fi
}

function ici_import {
  local type=$1; shift
  local ws_path=$1; shift
  local src=$1; shift
  local importer
  local processor

  if [ "$type" = "url" ]; then
    importer=(curl -sSL)
  elif [ "$type" = "file" ]; then
    importer=(cat)
  else
    return 1
  fi

  case "$src" in
    *.zip|*.tar|*.tar.*|*.tgz|*.tbz2)
      processor=(bsdtar -C "$ws_path" -xf-)
      ;;
    *)
      processor=(ici_vcs_import "$ws_path")
      ;;
  esac
  WS_SOURCE=$(realpath "$src")
  ici_guard "${importer[@]}" "$src" | ici_guard "${processor[@]}"
}

function prepare_ws {
  local ws_path=$1
  local src=$2

  rm -rf "$ws_path"
  mkdir -p "$ws_path"

  case "$src" in
    git* | bitbucket:* | bb:* | gh:* | gl:*)
      ici_import_repository "$ws_path" "$src"
      ;;
    http://* | https://*)
      ici_import url "$ws_path" "$src"
      ;;
    *)
      ici_import file "$ws_path" "$src"
      ;;
  esac
}

function source_link {
  local version=$1
  local url

  if git rev-parse --is-inside-work-tree &> /dev/null; then
    url="$(git config --get remote.origin.url)"
    url="${url%.git}/commit/$(git rev-parse HEAD)"
  elif [ -f "$WS_SOURCE" ]; then
    local repo; repo=$(realpath "$PWD")
    repo=${repo#*/ws/}  # strip everyting before /ws/
    repo=${repo%%/*}    # strip everything after next /
    url=$(yq ".repositories.\"$repo\".url" "$WS_SOURCE")
  else
    url="$WS_SOURCE"
  fi
  echo "[$version]($url)"
}

function get_release_version {
  local version
  local offset="0"

  # version from package.xml
  version="$(xmllint --xpath "/package/version/text()" package.xml)"

  if git rev-parse --is-inside-work-tree &> /dev/null; then
    # commit offset from latest version update in package.xml
    offset="$(git rev-list --count "$(git log -n 1 --pretty=format:'%H' -G"<version>" package.xml)"..HEAD)"
  fi

  echo "$version-$offset$DEB_DISTRO"
}

function pkg_exists {
  local pkg_version="${2%"$DEB_DISTRO"}"
  local candidate; candidate=$(LANG=C apt-cache policy "$1" | sed -n "s#^\s*Candidate:\s\(.*\)#\1#p")
  [ "$candidate" = "(none)" ] && candidate=""
  local available="${candidate%"$DEB_DISTRO"*}"  # extract version number

  if [ -n "$candidate" ] && ! dpkg --compare-versions "$available" "<=" "$pkg_version" ; then
    gha_warning "$1: existing version newer: $available > $pkg_version"
  fi
  if [ "$SKIP_EXISTING" == "true" ] && [ -n "$candidate" ] && \
     dpkg --compare-versions "$available" ">=" "$pkg_version" && ! "$SRC_PATH/scripts/upstream_rebuilds.py"; then
    echo "Skipped (existing version $candidate >= $pkg_version)"
    return 0
  fi
  echo "Building version $pkg_version (old: $candidate)"
  return 1
}

function build_pkg {
  local old_path=$PWD
  local pkg_name=$1
  local pkg_path=$2
  local opts
  local version
  local version_stamped

  cd "$pkg_path" || return 1
  trap 'trap - RETURN; cd "$old_path"' RETURN # cleanup on return

  test -f "./CATKIN_IGNORE" && echo "Skipped (CATKIN_IGNORE)" && return
  test -f "./COLCON_IGNORE" && echo "Skipped (COLCON_IGNORE)" && return

  # Get + Check release version
  # <release version>-<git offset><debian distro>
  version="$(get_release_version)" || return 5

  pkg_exists "$(deb_pkg_name "$pkg_name")" "$version" && return

  # Check availability of all required packages (bloom-generate waits for input on rosdep issues)
  rosdep install --os="$DISTRIBUTION:$DEB_DISTRO" --simulate --from-paths . > /dev/null || return 2
  ici_label "${BLOOM_QUIET[@]}" bloom-generate "${BLOOM_GEN_CMD}" --os-name="$DISTRIBUTION" --os-version="$DEB_DISTRO" --ros-distro="$ROS_DISTRO" || return 2

  # Enable CATKIN_INSTALL_INTO_PREFIX_ROOT for catkin package
  if [ "$pkg_name" = "catkin" ]; then
    sed -i 's@-DCATKIN_BUILD_BINARY_PACKAGE="1"@-DCATKIN_INSTALL_INTO_PREFIX_ROOT="1"@' debian/rules
  fi
  # Configure ament python packages to install into lib/python3/dist-packages (instead of lib/python3.x/site-packages)
  sed -i 's@lib/{interpreter}/site-packages@lib/python3/dist-packages@' debian/rules

  # https://github.com/ros-infrastructure/bloom/pull/643
  echo 11 > debian/compat

  # Update release version (with appended timestamp)
  version_stamped="$version.$(date +%Y%m%d.%H%M)" # append build timestamp (following ROS scheme)
  debchange -v "$version_stamped" \
    --preserve --force-distribution "$DEB_DISTRO" \
    --urgency high -m "Append timestamp when binarydeb was built." || return 3

  local version_link; version_link=$(source_link "${version%"$DEB_DISTRO"}") || true
  rm -rf .git

  # Fetch sbuild options from .repos yaml file
  [ -f "$WS_SOURCE" ] && opts=$(yq ".sbuild_options.\"$pkg_name\"" "$WS_SOURCE") || opts=""
  [ "$opts" != "null" ] || opts=""
  [ -z "$opts" ] || opts="$EXTRA_SBUILD_OPTS $opts"

  SBUILD_OPTS="--verbose --chroot=sbuild --no-clean-source --no-run-lintian --dist=$DEB_DISTRO $opts"
  ici_label "${SBUILD_QUIET[@]}" sg sbuild -c "sbuild $SBUILD_OPTS" || return 4

  "${CCACHE_QUIET[@]}" ici_label ccache -sv || return 1
  BUILT_PACKAGES+=("$(deb_pkg_name "$pkg_name"): $version_link")

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
  log=$(ls -1t "$DEBS_PATH/$(deb_pkg_name "${pkg_name}" "$version_stamped")_"*.build | grep -P '(?<!Z)\.build' | head -1)
  mv "$(readlink -f "$log")" "${log/.build/.log}" # rename actual log file
  rm "$log" # remove symlink

  ici_label update_repo
}

function get_python_release_version {
  local version
  local offset="0"

  # version from setup.py
  version="$(python3 setup.py --version)"

  if git rev-parse --is-inside-work-tree &> /dev/null; then
    # commit sha from latest version update in setup.py
    sha=$(git log -n 1 --pretty=format:'%H' -G"version *=" setup.py)
    # alternatively, commit sha from latest commit with $version in commit message
    test -z "$sha" && sha=$(git log -n 1 --pretty=format:'%H' --grep="${version}$")
    offset="$(git rev-list --count "$sha..HEAD")"
  fi

  echo "$version-$offset"
}

function build_python_pkg {
  local old_path=$PWD
  local pkg_name=$1
  local pkg_path=$2
  local version
  local version_stamped

  cd "$pkg_path" || return 1
  trap 'trap - RETURN; cd "$old_path"' RETURN # cleanup on return

  test -f "./CATKIN_IGNORE" && echo "Skipped (CATKIN_IGNORE)" && return
  test -f "./COLCON_IGNORE" && echo "Skipped (COLCON_IGNORE)" && return

  # Get + Check release version
  version="$(get_python_release_version)" || return 5
  local debian_version="${version#*-}"
  local deb_pkg_name; deb_pkg_name="python3-$(python3 setup.py --name)"
  pkg_exists "$deb_pkg_name" "$version" && return

  local version_link; version_link=$(source_link "${version%"$DEB_DISTRO"}") || true
  rm -rf .git

  ici_label "${SBUILD_QUIET[@]}" python3 setup.py --command-packages=stdeb.command sdist_dsc --debian-version "$debian_version" bdist_deb || return 4

  BUILT_PACKAGES+=("$deb_pkg_name: $version_link")

  # Move created files to $DEBS_PATH for deployment
  mv deb_dist/*.dsc deb_dist/*.tar.?z deb_dist/*.deb deb_dist/*.changes deb_dist/*.buildinfo "$DEBS_PATH"

  ici_label update_repo
}

function build_source {
  local old_path=$PWD
  local ws_path="$PWD/ws"

  ici_timed "$(ici_colorize BLUE BOLD "Setup workspace for $1")" prepare_ws "$ws_path" "$1"
  cd "$ws_path" || ici_exit 1

  # determine list of packages (names + folders)
  PKG_NAMES=()
  PKG_FOLDERS=()
  #shellcheck disable=SC2034,SC2086
  while read -r name folder unused; do
    PKG_NAMES+=("$name")
    PKG_FOLDERS+=("$folder")
  done < <(colcon list --topological-order $COLCON_PKG_SELECTION)

  ici_timed "Register new packages with rosdep" register_local_pkgs_with_rosdep
  ici_timed update_repo

  local msg_prefix=""
  local total="${#PKG_NAMES[@]}"
  local idx
  for (( idx=0; idx < total; idx++ )); do
    gha_report_result "LATEST_PACKAGE" "${PKG_NAMES[$idx]}"

    local pkg_desc="package $((idx+1))/$total: ${PKG_NAMES[$idx]} (${PKG_FOLDERS[$idx]})"
    ici_time_start "$(ici_colorize CYAN BOLD "Building $pkg_desc")"

    local exit_code=0
    if [ -f "${PKG_FOLDERS[$idx]}/package.xml" ]; then
      build_pkg "${PKG_NAMES[$idx]}" "${PKG_FOLDERS[$idx]}" || exit_code=$?
    elif [ -f "${PKG_FOLDERS[$idx]}/setup.py" ]; then
      build_python_pkg "${PKG_NAMES[$idx]}" "${PKG_FOLDERS[$idx]}" || exit_code=$?
    else
      ici_warn "No package.xml or setup.py found"
      exit_code=0
    fi

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
        ici_exit "$exit_code" gha_error "$msg_prefix on $pkg_desc."
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
export WS_SOURCE # current workspace source
