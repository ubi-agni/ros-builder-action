#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

# Adapted from https://github.com/ros-industrial/industrial_ci/blob/master/industrial_ci/src/util.sh
# Copyright 2016-2023, Isaac I. Y. Saito, Mathias Lüdtke, Robert Haschke

export ANSI_RED=31
export ANSI_GREEN=32
export ANSI_YELLOW=33
export ANSI_BLUE=34
export ANSI_MAGENTA=35
export ANSI_CYAN=36
export ANSI_BOLD=1
export ANSI_THIN=22
export ANSI_RESET=0

export TRACE=${TRACE:-false}
export ICI_FOLD_NAME=${ICI_FOLD_NAME:-}
export ICI_START_TIME=${ICI_START_TIME:-}
_CLEANUP_FILES=""
declare -a _CLEANUP_CMDS

__ici_log_fd=1
__ici_err_fd=2
__ici_top_level=0
__ici_setup_called=false

function ici_setup {
    # shellcheck disable=SC2064
    trap "ici_trap_exit $((128 + $(kill -l INT)))" INT # install interrupt handler
    # shellcheck disable=SC2064
    trap "ici_trap_exit $((128 + $(kill -l TERM)))" TERM # install interrupt handler

    trap "ici_trap_exit" EXIT # install exit handler

    exec {__ici_log_fd}>&1
    exec {__ici_err_fd}>&2
    __ici_top_level=$BASH_SUBSHELL
    __ici_setup_called=true
}

function ici_redirect {
    1>&"$__ici_log_fd" 2>&"$__ici_err_fd" "$@"
}

function ici_log {
    ici_redirect echo "$@"
}

function ici_ansi {
  local var="ANSI_$1"
  echo "\e[${!var}m"
}

function ici_colorize() {
   local color reset
   while true ; do # process all color arguments
      case "${1:-}" in
         RED|GREEN|YELLOW|BLUE|MAGENTA|CYAN)
            color="$(ici_ansi "$1")"; reset="$(ici_ansi RESET)" ;;
         THIN)
            color="${color:-}$(ici_ansi THIN)" ;;
         BOLD)
            color="${color:-}$(ici_ansi BOLD)"; reset="${reset:-$(ici_ansi THIN)}" ;;
         *) break ;;
      esac
      shift
   done
   echo -e "${color:-}$*${reset:-}"
}

function ici_color_output {
  ici_log "$(ici_colorize "$@")"
}

function ici_title {
  ici_log
  ici_color_output BLUE "$@"
}

function ici_ansi_cleared_line {
  ici_log -en "$*\r\e[0K"
}

function ici_backtrace {
  if [ "$TRACE" = true ]; then
    ici_log
    ici_color_output MAGENTA "TRACE: ${BASH_SOURCE[2]#$SRC_PATH/}:${BASH_LINENO[1]} ${FUNCNAME[1]} $*"
    for ((i=3;i<${#BASH_SOURCE[@]};i++)); do
        ici_color_output MAGENTA " from: ${BASH_SOURCE[$i]#$SRC_PATH/}:${BASH_LINENO[$((i-1))]} ${FUNCNAME[$((i-1))]}"
    done
  fi
}

function ici_trace {
  if [ "$TRACE" = true ]; then
    ici_log
    ici_color_output MAGENTA "TRACE:${BASH_SOURCE[2]#$SRC_PATH/}:${BASH_LINENO[1]} ${FUNCNAME[1]} $*"
  fi
}

function ici_set_u {
  [[ "${BASH_VERSINFO[0]}_${BASH_VERSINFO[1]}" < "4_4" ]] || set -u
}

function ici_with_unset_variables {
  local err=0
  set +u
  "$@" || err=$?
  ici_set_u
  return "$err"
}

function _sub_shell() (
  # shellcheck disable=SC2317
  function rosenv() {
    # if current_ws not set, use an invalid path to skip it
    for e in $(ici_extend_space "${current_ws:-/dev/null}") $(ici_extend_space "$BASEDIR/${PREFIX}downstream_ws") $(ici_extend_space "$BASEDIR/${PREFIX}target_ws") $(ici_extend_space "$BASEDIR/${PREFIX}base_ws") $(ici_extend_space "$BASEDIR/${PREFIX}upstream_ws") "$UNDERLAY"; do
    if [ -f "$e/setup.bash" ]; then
      ici_source_setup "$e"
      if [ -n "$*" ]; then
        (exec "$@") || return
      fi
      return 0
    fi
    done
    return 1
  }
  eval "$*" || ici_exit
)

# usage echo "$*" | ici_pipe_into_schroot <schroot name>
function ici_pipe_into_schroot {
  cat -- | ici_asroot schroot -c "$1" --directory / /bin/bash -- || ici_exit
}

function _label_hook() {
      ici_log
      # shellcheck disable=SC2001
      ici_color_output BOLD "$(sed -e 's/^/$ /' <<< "$1")"
}

function ici_hook() {
  local name=${1^^} # uppercase hook name
  if [ -z "${name#*_}" ]; then return 0; fi

  ici_trace "$@"
  name=${name//[^A-Z0-9_]/_}
  local name_embed="${name}_EMBED"

  local script=${!name:-}
  local script_embed=${!name_embed:-}

  if [ -n "$script" ] || [ -n "$script_embed" ] ; then
    ici_time_start "$1"

    if [ -n "$script" ]; then
      _label_hook "( $script; )"
      _sub_shell "$script" || ici_exit
    fi

    if [ -n "$script_embed" ]; then
      _label_hook "eval \"$script_embed\""
      eval "$script_embed" || ici_exit
      ici_set_u
    fi

    ici_time_end
  fi
}

#######################################
# Starts a timer section in a folding section
# based on https://github.com/travis-ci/travis-build/blob/master/lib/travis/build/bash/travis_time_start.bash
#      and https://github.com/travis-ci/travis-build/blob/master/lib/travis/build/bash/travis_fold.bash
#
# Globals:
#   DEBUG_BASH (read-only)
#   ICI_FOLD_NAME (write-only)
#   ICI_START_TIME (write-only)
# Arguments:
#   color_wrap (default: 32): Color code for the section delimitter text.
#   exit_code (default: $?): Exit code for display
# Returns:
#   (None)
#######################################

function ici_time_start {
    if [ "$DEBUG_BASH" ] && [ "$DEBUG_BASH" == true ]; then set +x; fi
    ICI_START_TIME=$(date -u +%s%N)
    ici_start_fold "$1"
    if [ "$DEBUG_BASH" ] && [ "$DEBUG_BASH" == true ]; then set -x; fi
}

#######################################
# Wraps up the timer section that was started by ici_time_start function
# based on https://github.com/travis-ci/travis-build/blob/master/lib/travis/build/bash/travis_time_finish.bash
#
# Globals:
#   DEBUG_BASH (read-only)
#   ICI_FOLD_NAME (from ici_time_start, read-write)
#   ICI_START_TIME (from ici_time_start, read-only)
# Arguments:
#   color_wrap (default: 32): Color code for the section delimitter text.
#   exit_code (default: $?): Exit code for display
# Returns:
#   (None)
#######################################
function ici_time_end {
    local exit_code=${1:-0}
    if [ "$DEBUG_BASH" ] && [ "$DEBUG_BASH" == true ]; then set +x; fi

    local name=$ICI_FOLD_NAME
    local color_wrap="GREEN"
    if [ "$exit_code" -ne "0" ]; then color_wrap="RED"; fi  # Red color for errors

    if [ -z "$ICI_START_TIME" ]; then ici_warn "[ici_time_end] var ICI_START_TIME is not set. You need to call ici_time_start in advance. Returning."; return; fi
    local end_time; end_time=$(date -u +%s%N)
    local elapsed_seconds; elapsed_seconds=$(( (end_time - ICI_START_TIME)/1000000000 ))

    ici_color_output "$color_wrap" "'$name' returned with code '${exit_code}' after $(( elapsed_seconds / 60 )) min $(( elapsed_seconds % 60 )) sec"
    ici_end_fold "$name"

    ICI_START_TIME=
    if [ "$DEBUG_BASH" ] && [ "$DEBUG_BASH" == true ]; then set -x; fi
}

# Execute command via ici_timed, running BEFORE_* and AFTER_* hooks and reporting the result
function ici_step {
    local id=$1
    local exit_code=0
    ici_hook "before_$id" || ici_exit
    ici_timed "$id" "$@" || exit_code=$?
    gha_report_result "$id" "${exit_code}"
    [ "$exit_code" -ne 0 ] && ici_exit "$exit_code"
    ici_hook "after_$id" || ici_exit
}

# Execute command folding and timing it
function ici_timed {
    local title=$1; shift
    ici_time_start "$title"
    "$@" || ici_exit
    ici_time_end
}

# Register command to be executed on teardown
function ici_on_teardown {
    _CLEANUP_CMDS+=("$@")
}

function ici_teardown {
    local exit_code=${1:-$?}; shift || true

    # don't run teardown code within subshells, but only at top level
    if [  "$BASH_SUBSHELL" -le "$__ici_top_level" ]; then
        # Reset signal handler since the shell is about to exit.
        [ "$__ici_setup_called" == true ] && trap - EXIT

        local cleanup=()
        # shellcheck disable=SC2016
        IFS=: command eval 'cleanup=(${_CLEANUP_FILES})'
        for c in "${cleanup[@]}"; do
          rm -rf "${c/#\~/$HOME}"
        done

        if [ "$exit_code" -ne 0 ]; then
            local addon=""
            [ -n "$ICI_FOLD_NAME" ] && addon="(in '$ICI_FOLD_NAME')"

            if [ -n "$*" ]; then # issue custom error message
              "$@" "$addon" || true
            else # issue default error message
              gha_error "Failure with exit code: $exit_code" "$addon"
            fi
        fi

        # end fold/timing if needed
        if [ -n "$ICI_FOLD_NAME" ]; then
            if [ -n "$ICI_START_TIME" ]; then
              ici_time_end "$exit_code" # close timed fold
            else
              ici_end_fold "$ICI_FOLD_NAME" # close untimed fold
            fi
        fi

        for c in "${_CLEANUP_CMDS[@]}"; do
          $c
        done

        if [ "$__ici_setup_called" = true ]; then
            # These will fail if ici_setup was not called
            exec {__ici_log_fd}>&-
            exec {__ici_err_fd}>&-
        fi
        __ici_setup_called=false
    fi
}

function ici_trap_exit {
    local exit_code=${1:-$?}
    local cmd=gha_error
    local msg
    if [ "$exit_code" -gt "128" ]; then
        msg="Terminating on signal $(kill -l $((exit_code - 128)))"
        # simple message instead of error for SIGINT
        [ "$exit_code" -eq "130" ] && cmd="ici_log"
    else
        msg="Unexpected failure with exit code '$exit_code'"
        TRACE=true
    fi

    ici_backtrace "$@"
    ici_teardown "$exit_code" "$cmd" "$msg"
    exit "$exit_code"
}

#######################################
# exit function with handling for EXPECT_EXIT_CODE, ends the current fold if necessary
#
# Globals:
#   EXPECT_EXIT_CODE (read-only)
#   ICI_FOLD_NAME (from ici_time_start, read-only)
# Arguments:
#   exit_code (default: $?)
#   command args ... (optional command, passed to ici_teardown, to generate custom error message)
# Returns:
#   (None)
#######################################
function ici_exit {
    local exit_code=${1:-$?}
    ici_backtrace "$@"
    shift || true
    ici_teardown "$exit_code" "$@"

    if [ "$exit_code" == "${EXPECT_EXIT_CODE:-0}" ] ; then
        exit_code=0
    elif [ "$exit_code" == "0" ]; then # 0 was not expected
        exit_code=1
    fi

    exit "$exit_code"
}

function ici_warn {
    ici_color_output YELLOW "$*"
}

function ici_mark_deprecated {
  local e=$1
  shift
  if [ "${!e:-}" ]; then
    ici_warn "'$e' is deprecated. $*"
  fi
}

#######################################
# Print an error message and calls "exit"
#
# * exit_code is taken from second argument or from the previous command.
# * If the final exit_code is 0, this function will exit 1 instead to enforce a test failure
#
# Globals:
#   (None)
# Arguments:
#   message (optional)
#   exit_code (default: $?)
# Returns:
#   (None)
#######################################
function ici_error {
    local exit_code=${2:-$?} #
    if [ -n "$1" ]; then
        __ici_log_fd=$__ici_err_fd ici_color_output RED "$1"
    fi
    if [ "$exit_code" == "0" ]; then # 0 is not error
        exit_code=1
    fi
    ici_exit "$exit_code"
}

function ici_enforce_deprecated {
    local e=$1
    shift
    if [ "${!e:-}" ]; then
      ici_error "'$e' is not used anymore. $*"
    fi
}

function ici_rename_deprecated() {
  local old=$1
  shift
  local new=$1
  shift
  if [ "${!old:-}" ]; then
      local value=${!old}
      ici_warn "'$old' is deprecated. Use '$new=$value' instead"
      export "$new"="$value"
  fi
}

function ici_migrate_hook() {
  local oldname=${1^^}
  oldname=${oldname//[^A-Z0-9_]/_}
  local newname=${2^^}
  newname=${newname//[^A-Z0-9_]/_}

  mapfile -t envs < <(env | grep -oE "(BEFORE_|AFTER_)+$oldname(_EMBED)?")

  for oldhook in "${envs[@]}"; do
    local newhook=${oldhook/$oldname/$newname}
    ici_warn "hook '$oldhook' was renamed to '$newhook'."
    eval "export $newhook=\$$oldhook"
  done
}

function ici_removed_hook() {
  local oldname=${1^^}
  shift
  oldname=${oldname//[^A-Z0-9_]/_}

  mapfile -t envs < <(env | grep -oE "(BEFORE_|AFTER_)+$oldname(_EMBED)?")

  for oldhook in "${envs[@]}"; do
    ici_enforce_deprecated "$oldhook" "$@"
  done
}

function ici_retry {
  ici_trace "$@"
  local tries=$1; shift
  local ret=0

  for ((i=1;i<=tries;i++)); do
    "$@" && return 0
    ret=$?
    sleep 1;
  done

  ici_color_output RED "'$*' failed $tries times"
  return "$ret"
}

function ici_get_log_cmd {
    local post=""
    while true; do
        case "$1" in
            ici_asroot)
                echo -n "sudo "
                ;;
            ici_filter)
                post=" | grep -E '$2' "
                shift 1
                ;;
            ici_quiet)
                post=" > /dev/null "
                ;;
            ici_cmd|ici_guard|ici_label)
                ;;
            *)
              echo "$*$post"
              return
        esac
        shift
    done
}

# only show output on failure, otherwise be quiet
function ici_quiet {
    local out; out=$(mktemp)
    local err=0
    "$@" &> "$out" || err=$?
    if [ "$err" -ne 0 ]; then
        ici_redirect cat "$out"
    fi
    rm -f "$out"
    return "$err"
}

# show full output on failure, otherwise filtered stdout
function ici_filter {
    local filter=$1; shift
    local out; out=$(mktemp)
    "$@" | grep -E "$filter" | ici_redirect cat || true
    local err=${PIPESTATUS[0]}
    if [ "$err" -ne 0 ]; then
        ici_redirect cat "$out"
    fi
    rm -f "$out"
    return "$err"
}

# append new line(s) to a variable
function ici_append {
  local -n var=$1; shift
  var=$(echo -e "${var:+${var}\n}$*")
}

function _ici_guard {
    local err=0
    "$@" || err=$?
    if [ "$err" -ne 0 ]; then
        ici_error "'$(ici_get_log_cmd "$@")' returned with $err" "$err"
    fi
}

function ici_guard {
    ici_trace "$@"
    _ici_guard "$@"
}

function ici_label {
    local cmd; cmd=$(ici_get_log_cmd "$@")
    ici_color_output BOLD "$ $cmd"
    "$@"
}

function ici_cmd {
     _ici_guard ici_label "$@"
}

function ici_asroot {
  if [ "$EUID" -ne 0 ] && command -v sudo > /dev/null; then
      sudo -E "$@"
  else
      "$@"
  fi
}

function ici_exec_for_command {
  ici_trace "$@"
  local command=$1; shift
  if ! command -v "$command" > /dev/null; then
    "$@"
  fi
}

function ici_split_array {
    # shellcheck disable=SC2034
    IFS=" " read -r -a "$1" <<< "$*"
}

function ici_parse_env_array {
    # shellcheck disable=SC2034
    eval "$1=(${!2:-})"
}

function ici_parse_jobs {
  local -n _ici_parse_jobs_res=$1
  # shellcheck disable=SC2034
  _ici_parse_jobs_res=${!2:-}

  case "$_ici_parse_jobs_res" in
  "")
      _ici_parse_jobs_res="$3";;
  "true")
      _ici_parse_jobs_res="0";;
  "false")
      _ici_parse_jobs_res="1";;
  *)
      if ! [[ "$_ici_parse_jobs_res" =~ ^[0-9]+$ ]]; then
          ici_error "cannot parse $2=$_ici_parse_jobs_res as a number"
      fi
      ;;
  esac
}

function ici_find_nonhidden {
  ici_trace "$@"
  local path=$1; shift
  local args=()
  if [ $# -gt 0 ]; then
    args=(-a \( "$@" \))
  fi
  find "$path" \( \! \( -path "${path}*/.*" -prune \) \) "${args[@]}"
}

function ici_resolve_component {
  local label=$1
  local group=$2
  for file in "${SRC_PATH}/${!label}" "${SRC_PATH}/$group/${!label}.sh"; do
    if [ -f "$file" ]; then
      echo "$file"
      return
    fi
  done
  ici_error "$label '${!label}' not found"
}

function ici_source_component {
  local script
  script=$(ici_resolve_component "$@")
  ici_guard source "$script"
}

function ici_join_array {
  local sep=$1
  shift
  local res=""
  for elem in "$@"; do
    if [ -n "$elem" ]; then
      res+="$sep$elem"
    fi
  done
  echo "${res#"$sep"}"
}

function ici_cleanup_later {
  ici_trace "$@"
  _CLEANUP_FILES=$(ici_join_array : "$_CLEANUP_FILES" "$@")
}

function ici_make_temp_dir {
  ici_trace "$@"
  local -n ici_make_temp_dir_res=$1;
  ici_make_temp_dir_res=$(mktemp -d)
  ici_log "ici_make_temp_dir: $1 -> $ici_make_temp_dir_res"
  ici_cleanup_later "$ici_make_temp_dir_res"
}

# parse a URL of the form <scheme>:<resource>[#<fragment>]
function ici_parse_url {
    if [[ $1 =~ ([^:]+):([^#]+)(#.+)? ]]; then
        export URL_SCHEME=${BASH_REMATCH[1]}
        export URL_RESOURCE=${BASH_REMATCH[2]}
        export URL_FRAGMENT="${BASH_REMATCH[3]#"#"}"
    else
        return 1
    fi
}

# define defaults to disable verbose output for individual build steps
# format: filter:variable:default
export DEFAULT_QUIET_CONFIG=( \
	"bloom:BLOOM_QUIET:ici_quiet" \
	"sbuild:SBUILD_QUIET:ici_quiet" \
	"ccache:CCACHE_QUIET:ici_quiet" \
	"apt:APT_QUIET:ici_filter \"Setting up\"" \
)
function ici_setup_vars {
  local filters=$1; shift
  for spec in "$@"; do
    IFS=: read -r filter variable default <<< "$spec"
    if [ "$filters" = true ] || [[ "$filters" == *"$filter"* ]]; then
      default=""
    fi
    eval "export ${variable}=($default)"
  done
}

function ici_apt_install {
    ici_asroot apt-get -qq install -y --no-upgrade --no-install-recommends "$@"
}

function gha_cmd {
    local cmd=$1; shift
    # turn newlines into %0A, carriage returns into %0D, and % into %25
    echo -e "::$cmd::$*" | sed -e 's/%/%25/g' -e 's/\r/%0D/g' -e 's/\n/%0A/g'
}

function gha_error {
    gha_cmd error "$*"
}

function gha_warning {
    gha_cmd warning "$*"
}

function  ici_start_fold() {
    if [ -n "$ICI_FOLD_NAME" ]; then
        # report error _within_ the previous fold
        ici_warn "ici_start_fold: nested folds are not supported (still open: '$ICI_FOLD_NAME')"
        ici_end_fold
    fi
    # shellcheck disable=SC2001
    ICI_FOLD_NAME="$(sed -e 's/\x1b\[[0-9;]*m//g' <<< "$1")" # store name w/o color codes
    gha_cmd group "$1"
}

function  ici_end_fold() {
    if [ -z "$ICI_FOLD_NAME" ]; then
        ici_warn "spurious call to ici_end_fold"
    else
        gha_cmd endgroup
        ICI_FOLD_NAME=
    fi
}

function gha_report_result() {
    echo "$1=$2" >> "${GITHUB_OUTPUT:-/dev/null}"
}

# Remove suffix _disabled to skip sudo stuff during development
function ici_asroot_disabled {
    echo "Skipping $*"
    # allow processing of stdin within pipes
    read -t 0.1 -r || true
}
