#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=src/build.sh
source "${SRC_PATH}/build.sh"

function on_exit() {
	ici_log
	ici_timed "ccache statistics" ccache -sv

	if [ "${#BUILT_PACKAGES[@]}" -gt 0 ]; then
		echo "### Successfully built packages: " > "$GITHUB_STEP_SUMMARY"
		printf -- '- %s\n' "${BUILT_PACKAGES[@]}" >> "$GITHUB_STEP_SUMMARY"
	fi
}

gha_report_result "LATEST_PACKAGE" ""

FAIL_EVENTUALLY=0
BUILT_PACKAGES=()
ici_on_teardown on_exit
build_all_sources

gha_report_result "LATEST_PACKAGE" "DONE"

if [ "$FAIL_EVENTUALLY" != 0 ]; then
	ici_exit 1 ici_color_output RED "Some packages failed to build"
fi
