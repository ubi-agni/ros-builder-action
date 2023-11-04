#!/bin/bash
set -e

# setup ros environment
# shellcheck disable=SC1090
source "/opt/ros/$ROS_DISTRO/setup.bash" --
exec "$@"
