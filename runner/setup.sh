#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024, Robert Haschke

DIR_THIS="$(dirname "${BASH_SOURCE[0]}")"

# Setup CCACHE_DIR and disable ccache
CCACHE_DIR=/home/runner/ccache
sudo mkdir -p "$CCACHE_DIR"
sudo chown "$USER:$USER" "$CCACHE_DIR"
echo disable = true >> "$CCACHE_DIR"/ccache.conf

# Install required packages
sudo apt update
sudo apt install build-essential:native

sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64 -O /usr/bin/yq
sudo chmod +x /usr/bin/yq

cp "$DIR_THIS"/cleanup.sh ~/cleanup.sh

mkdir ~/gha
cd ~/gha || true

cat <<EOF > .env
LANG=C.UTF-8
ACTIONS_RUNNER_HOOK_JOB_COMPLETED=$HOME/cleanup.sh
EOF
