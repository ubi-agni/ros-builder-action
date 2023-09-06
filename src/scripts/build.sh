#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=src/build.sh
source "${SRC_PATH}/build.sh"

FAIL_EVENTUALLY=0
build_all_sources
ici_cmd update_repo
return $FAIL_EVENTUALLY
