#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2023, Robert Haschke

DIR_THIS="$(dirname "${BASH_SOURCE[0]}")"
SRC_PATH="$(realpath "$DIR_THIS/../src")"

sed -E 's/^@test "?([^" ]+)"? /function test_\1 /' "$DIR_THIS/util.bats" > /tmp/filtered_util_bats.sh
# shellcheck source=/dev/null
source /tmp/filtered_util_bats.sh

# shellcheck source=src/util.sh
source "${SRC_PATH}/util.sh"
ici_setup

# define methods used in test functions
function run {
	shift # ignore expected result
	"$@"
	echo
}

function assert_output {
	true
}

# define wrapper to run test functions
function test {
	local test_name=$1; shift
	echo "==== $test_name ===="
	"test_${test_name}" "$@"
}


test ici_quiet_true
test ici_quiet_false
test ici_filter_true
test ici_filter_false
test ici_filter_out_true
test ici_filter_out_false

ici_teardown
