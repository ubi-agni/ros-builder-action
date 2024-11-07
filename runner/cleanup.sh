#!/bin/bash

# rm -rf ~/debs "$DEBS_PATH"
rm -rf ~/gha/work
sudo rm -rf /etc/apt/sources.list.d/ros-builder-debs.list
sudo rm -rf /var/cache/sbuild-chroot
