#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2023, Robert Haschke

DIR_THIS="$(dirname "${BASH_SOURCE[0]}")"
SRC_PATH="$(realpath "$DIR_THIS/../src")"
DEBS_PATH=${DEBS_PATH:-~/debs}

# shellcheck source=src/env.sh
source "${SRC_PATH}/env.sh"

ici_setup

ici_cmd echo "cmd"
ici_label echo "label"
ici_timed "title" echo "timed"

ici_teardown
