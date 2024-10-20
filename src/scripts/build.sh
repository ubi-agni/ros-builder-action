#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=src/build.sh
source "${SRC_PATH}/build.sh"

gha_report_result "LATEST_PACKAGE" ""

FAIL_EVENTUALLY=0
BUILT_PACKAGES=()
build_all_sources

ici_log
ici_timed "ccache statistics" ccache -sv

if [ "${#BUILT_PACKAGES[@]}" -gt 0 ]; then
	echo "### Successfully built packages: " > "$GITHUB_STEP_SUMMARY"
	printf -- '- %s\n' "${BUILT_PACKAGES[@]}" >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$FAIL_EVENTUALLY" != 0 ]; then
	ici_exit 1 ici_color_output RED "Some packages failed to build"
fi

gha_report_result "LATEST_PACKAGE" "DONE"
