#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2023, Robert Haschke

DIR_THIS="$(dirname "${BASH_SOURCE[0]}")"
SRC_PATH="$(realpath "$DIR_THIS/..")"

# shellcheck source=src/env.sh
source "$SRC_PATH/env.sh"

ici_setup

# shellcheck source=main.sh
source "$1"

ici_teardown
