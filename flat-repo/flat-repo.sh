#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2023, Robert Haschke

# shellcheck disable=SC2086,2153

# shellcheck source=src/prepare.sh
source "${SRC_PATH}/prepare.sh"  # for generate_readme

ici_cmd mkdir -p "$REPO_PATH"

ici_cmd cd "$DEBS_PATH"
ici_timed "Move .debs from $DEBS_PATH to $REPO_PATH" mv ./*.deb ./*.yaml "$REPO_PATH"

ici_cmd cd "$REPO_PATH"
ici_cmd apt-ftparchive packages . > Packages
ici_cmd apt-ftparchive release . > Release
ici_cmd generate_readme "$DEPLOY_URL" "$BRANCH" > README.md
