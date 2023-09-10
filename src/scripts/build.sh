#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=src/build.sh
source "${SRC_PATH}/build.sh"

gha_report_result "LATEST_PACKAGE" ""

FAIL_EVENTUALLY=0
build_all_sources
ici_cmd update_repo
[ "$FAIL_EVENTUALLY" != 0 ] || ici_exit 1
