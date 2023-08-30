#!/bin/bash
# shellcheck disable=SC2034,1091
DEBS_PATH=/tmp/debs
REPO_PATH=/tmp/repo
SRC_PATH="$PWD/src"

source "$SRC_PATH/env.sh"
ici_setup

HOOK="for i in 1 2 3; do echo -n '.' ; sleep 1 ; done"
ici_hook HOOK

ici_teardown
