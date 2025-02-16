ARG DEB_DISTRO=jammy
FROM ubiagni/ros:${DEB_DISTRO}-ros-robot
LABEL org.opencontainers.image.authors="Robert Haschke <rhaschke@techfak.uni-bielefeld.de>"

# install ros packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-one-desktop \
    && rm -rf /var/lib/apt/lists/*
