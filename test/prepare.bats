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
	DEBS_PATH=${DEBS_PATH:-~/debs}
	REPO_PATH=${REPO_PATH:-~/repo}

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


@test "parse_repository_url" {
	GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-ubi-agni/ros-repo}
	local repo=$GITHUB_REPOSITORY
	local b="branch"

	run repository_url self $b
	assert_output "https://raw.githubusercontent.com/$repo/$b"

	run repository_url "git@github.com:$repo.git" $b
	assert_output "https://raw.githubusercontent.com/$repo/$b"
}
