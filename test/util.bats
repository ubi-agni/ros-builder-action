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
