# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2023, Robert Haschke

# Employing the shell unit testing framework: https://bats-core.readthedocs.io

function setup {
	load 'test_helper/bats-support/load'
	load 'test_helper/bats-assert/load'
	bats_require_minimum_version 1.10.0

	# Get the containing directory of this file ($BATS_TEST_FILENAME)
	# Use that instead of ${BASH_SOURCE[0]} as the latter points to the bats executable!
	DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
	SRC_PATH=$(realpath "$DIR/../src")
	DEBS_PATH=${DEBS_PATH:-~/debs}

	# shellcheck source=src/env.sh
	source "${SRC_PATH}/env.sh"
}

# wrapper around bats' run() to increment __ici_top_level beforehand
# This is needed for all functions that eventually call ici_teardown,
# i.e. ici_step, ici_hook, ici_exit, etc.
function ici_run {
	__ici_top_level=$((__ici_top_level+1))
	run "$@"
	__ici_top_level=$((__ici_top_level-1))
}

function sub_shell {
	eval "$*"
}

@test "ici_append" {
	local VAR=""

	ici_append VAR "first line"
	run echo "$VAR"
	assert_output "first line"

	local TWO_LINE_VAR="second line\nthird line\n"
	ici_append VAR "$TWO_LINE_VAR"
	run echo "$VAR"

	local expected; expected=$(cat <<-EOF
	first line
	second line
	third line
EOF
)
	assert_output "$expected"
}

# shellcheck disable=SC2030
@test "ici_hook_on_appended_var" {
	function ici_time_start() { true; }
	function ici_time_end() { true; }
	function _label_hook() { true; }

	# shellcheck disable=SC2034
	local HOOK="echo 1st line"
	ici_append HOOK "echo 2nd line"
	ici_append HOOK "echo 3rd line"
	ici_run ici_hook HOOK

	local expected; expected=$(cat <<-EOF
	1st line
	2nd line
	3rd line
EOF
)
	assert_output "$expected"
}

function test_filtering_helper {
	local exit_code=$1
	local expected_components=$2
	local filter=${4:-xxx}
	shift 2

	local all; all=$(cat <<- EOF
	good
	bad
EOF
)
	# shellcheck disable=SC2034,SC2155
	local passed=$(echo "$all" | grep -E "$filter")
	# shellcheck disable=SC2034
	local error="stderr"
	local expected=""
	for var in $expected_components; do
		ici_append expected "${!var}"
	done

	# shellcheck disable=SC2016
	local cmd='echo "$all"; echo "stderr" 1>&2; return $exit_code'
	run "-$exit_code" "$@" sub_shell "$cmd"
	assert_output "$expected"
}
@test "ici_quiet_true" {
	test_filtering_helper 0 "" ici_quiet
}
@test "ici_quiet_false" {
	test_filtering_helper 1 "all error" ici_quiet
}
@test "ici_filter_true" {
	skip
	# stderr is dropped on success
	test_filtering_helper 0 "passed" ici_filter "good"
}
@test "ici_filter_false" {
	skip
	# order of stdout and stderr might change due to extra filter step
	test_filtering_helper 1 "all error" ici_filter "good" || \
	test_filtering_helper 1 "error all" ici_filter "good"
}

# bats test_tags=folding
@test "folding_success" {
	# shellcheck disable=SC2034
	local HOOK="echo successful"
	local expected; expected=$(cat <<EOF
::group::HOOK

[1m$ ( echo successful; )[22m
successful
[32m'HOOK' returned with code '0' after 0 min 0 sec[0m
::endgroup::
EOF
)
	ici_run ici_hook HOOK
	assert_output "$expected"
}

# bats test_tags=folding
@test "folding_failure" {
	local HOOK="echo failure; false;"
	local expected; expected=$(cat <<EOF
::group::HOOK

[1m$ ( echo failure; false;; )[22m
failure
::error::Failure with exit code: 1 (in 'HOOK')
[31m'HOOK' returned with code '1' after 0 min 0 sec[0m
::endgroup::
EOF
)
	ici_run -1 ici_hook HOOK
	assert_output "$expected"

	# exit yields same result as false
	local sed_cmd='s/false/exit 1; echo "never reached"/'
	HOOK=$(echo "$HOOK" | sed "$sed_cmd")
	expected=$(echo "$expected" | sed "$sed_cmd")

	ici_run -1 ici_hook HOOK
	assert_output "$expected"
}

# bats test_tags=folding
@test "folding_cleanup" {
	local tmps=()
	for i in 1 2 3; do
		local tmp; tmp=$(mktemp)
		[ -f "$tmp" ]             # file should exist
		ici_cleanup_later "$tmp"  # register file for removal during ici_teardown
		tmps+=("$tmp")
	done

	local HOOK="false"
	ici_run -1 ici_hook HOOK

	for tmp in "${tmps[@]}"; do
		[ ! -f "$tmp" ]           # file should be deleted by now
	done
}

# bats test_tags=folding
@test folding_double_start_fold {
	local HOOK; HOOK="ici_start_fold test; ici_start_fold test; ici_end_fold"
	local expected; expected=$(cat <<EOF
::group::test
[33mici_start_fold: nested folds are not supported (still open: 'test')[0m
::endgroup::
::group::test
::endgroup::
EOF
)
	run eval "$HOOK"
	assert_output "$expected"
}
# bats test_tags=folding
@test folding_double_end_fold {
	local HOOK; HOOK="ici_start_fold test; ici_end_fold; ici_end_fold"
	run eval "$HOOK"
	echo "$output" | grep -q "spurious call to ici_end_fold"
}

@test "ici_parse_url" {
	run -1 ici_parse_url invalid

	ici_parse_url git@github.com:user/repo#branch
	output=$URL_SCHEME; assert_output "git@github.com"
	output=$URL_RESOURCE; assert_output "user/repo"
	output=$URL_FRAGMENT; assert_output "branch"
}

@test "ici_setup_vars_quiet" {
	ici_setup_vars "" "${DEFAULT_QUIET_CONFIG[@]}"
	[ "${#BLOOM_QUIET[@]}" = 1 ] && [ "${BLOOM_QUIET[0]}" = ici_quiet ]
	[ "${#SBUILD_QUIET[@]}" = 1 ] && [ "${SBUILD_QUIET[0]}" = ici_quiet ]
	[ "${#CCACHE_QUIET[@]}" = 1 ] && [ "${CCACHE_QUIET[0]}" = ici_quiet ]
	[ "${#APT_QUIET[@]}" = 2 ] && [ "${APT_QUIET[0]}" = ici_filter ] && [ "${APT_QUIET[1]}" = "Setting up" ]
}
@test "ici_setup_vars_verbose" {
	ici_setup_vars "true" "${DEFAULT_QUIET_CONFIG[@]}"
	[ "${#BLOOM_QUIET[@]}" = 0 ]
	[ "${#SBUILD_QUIET[@]}" = 0 ]
	[ "${#CCACHE_QUIET[@]}" = 0 ]
	[ "${#APT_QUIET[@]}" = 0 ]
}
@test "ici_setup_vars_selected" {
	ici_setup_vars "bloom sbuild ccache apt" "${DEFAULT_QUIET_CONFIG[@]}"
	[ "${#BLOOM_QUIET[@]}" = 0 ]
	[ "${#SBUILD_QUIET[@]}" = 0 ]
	[ "${#CCACHE_QUIET[@]}" = 0 ]
	[ "${#APT_QUIET[@]}" = 0 ]
}
