#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2023, Robert Haschke

# shellcheck disable=SC2086

function move_files {
	mkdir -p $REPO_PATH
	mv $DEBS_PATH/README.md \
	   $DEBS_PATH/*.deb \
		$DEBS_PATH/*.yaml \
		$REPO_PATH
}

ici_timed "Move files from $DEBS_PATH to $REPO_PATH" move_files
ici_cmd apt-ftparchive packages . > Packages
ici_cmd apt-ftparchive release . > Release
