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
	# shellcheck source=src/prepare.sh
	source "${SRC_PATH}/prepare.sh"
}

@test "restrict_src_to_packages" {
	# redirect original output from tee inside restrict_src_to_packages
	function ici_asroot {
		cat - > /tmp/actual
	}
	restrict_src_to_packages "release o=origin" "pkg1 pkg2"

	run cat /tmp/actual
	local expected
	expected=$(cat <<-EOF

	Package: *
	Pin: release o=origin
	Pin-Priority: -1

	Package: pkg1
	Pin: release o=origin
	Pin-Priority: 500

	Package: pkg2
	Pin: release o=origin
	Pin-Priority: 500
EOF
)
	assert_output "$expected"
}

@test "url_from_deb_source" {
	run -0 url_from_deb_source "deb http://archive.ubuntu.com/ubuntu focal main universe"
	assert_output "http://archive.ubuntu.com/ubuntu/dists/focal"

	run -0 url_from_deb_source "deb http://archive.ubuntu.com/ubuntu/ focal"
	assert_output "http://archive.ubuntu.com/ubuntu/dists/focal"
	run -0 url_from_deb_source "deb http://archive.ubuntu.com/ubuntu// focal"
	assert_output "http://archive.ubuntu.com/ubuntu/dists/focal"

	run -0 url_from_deb_source "deb [option1=val1 option2=val2] http://archive.ubuntu.com/ubuntu focal main universe"
	assert_output "http://archive.ubuntu.com/ubuntu/dists/focal"

	run -0 url_from_deb_source "deb http://archive.ubuntu.com/ubuntu ./"
	assert_output "http://archive.ubuntu.com/ubuntu"

	run -1 url_from_deb_source "deb [option1=val1 option2=val2] http://archive.ubuntu.com/ubuntu"
}

@test "validate_deb_sources_good" {
	local src
	for src in \
		"deb http://archive.ubuntu.com/ubuntu focal" \
		"$(echo -e "\ndeb https://raw.githubusercontent.com/v4hn/ros-o-builder/jammy-one/repository ./")" \
		; do
		local orig=$src
		# check correct modification of src variable
		validate_deb_sources src # modification fails with subshell use!
		output="$src" assert_output "$(echo "$orig" | grep -v -e '^$')"

		# check for empty output (no warnings/errors generated)
		run validate_deb_sources orig
		assert_output ""
	done
}
@test "validate_deb_sources_invalid" {
	local orig="http://archive.ubuntu.com/ubuntu"
	local src=$orig
	validate_deb_sources src # modification of src variable fails with subshell use!
	output="$src" assert_output "" # src should be cleared
	validate_deb_sources orig | grep "Invalid deb source spec" # check output

	local orig="deb http://archive.ubuntu.com/ubuntu ./"
	local src=$orig
	validate_deb_sources src # modification of src variable fails with subshell use!
	output="$src" assert_output "" # src should be cleared
	validate_deb_sources orig | grep "deb repository" | grep "is missing Release file"
}
