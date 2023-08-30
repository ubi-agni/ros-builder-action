#!/bin/bash
# shellcheck disable=SC2034,1091
DEBS_PATH=/tmp/debs
REPO_PATH=/tmp/repo
SRC_PATH="$PWD/src"

source "$SRC_PATH/env.sh"

ici_setup
. sub.sh
ici_teardown
