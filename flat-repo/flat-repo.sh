#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2023, Robert Haschke

function move_files {
	cd "$DEBS_PATH" || exit 1
	mkdir -p "$REPO_PATH/"
	mv README.md ./*.deb ./*.yaml "$REPO_PATH/"
}

ici_step "Move files from $DEBS_PATH to $REPO_PATH" move_files
ici_cmd apt-ftparchive packages . > Packages
ici_cmd apt-ftparchive release . > Release
