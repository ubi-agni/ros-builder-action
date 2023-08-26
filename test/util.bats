# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2023, Robert Haschke

# Employing the shell unit testing framework: https://bats-core.readthedocs.io

function setup {
	load 'test_helper/bats-support/load'
	load 'test_helper/bats-assert/load'

	# Get the containing directory of this file ($BATS_TEST_FILENAME)
	# Use that instead of ${BASH_SOURCE[0]} as the latter points to the bats executable!
	DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
	SRC_PATH=$(realpath "$DIR/../src")

	# shellcheck source=src/env.sh
	source "${SRC_PATH}/env.sh"
}

@test "ici_append" {
	local VAR=""

	ici_append VAR "first line"
	run echo "$VAR"
	assert_output "first line"

	local TWO_LINE_VAR="second line\nthird line\n"
	ici_append VAR "$TWO_LINE_VAR"
	run echo "$VAR"

	local expected
	expected=$(cat <<-EOF
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
	run ici_hook HOOK

	local expected
	expected=$(cat <<-EOF
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

	function sub_shell {
		eval "$*"
	}

	run "$@" sub_shell "echo \"$all\"; echo \"stderr\" 1>&2; return $exit_code"
	assert_output "$expected"
	# shellcheck disable=SC2031
	[ "$status" -eq "$exit_code" ]
}
@test "ici_quiet_true" {
	test_filtering_helper 0 "" ici_quiet
}
@test "ici_quiet_false" {
	test_filtering_helper 1 "all error" ici_quiet
}
@test "ici_filter_true" {
	# stderr is dropped on success
	test_filtering_helper 0 "passed" ici_filter "good"
}
@test "ici_filter_false" {
	# order of stdout and stderr is changed due to extra filter step
	test_filtering_helper 1 "error all" ici_filter "good"
}
