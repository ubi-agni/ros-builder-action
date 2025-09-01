ARG DEB_DISTRO=jammy
FROM ubiagni/ros:${DEB_DISTRO}-ros-core
LABEL org.opencontainers.image.authors="Robert Haschke <rhaschke@techfak.uni-bielefeld.de>"

# install bootstrap tools
RUN apt-get update && apt-get install --no-install-recommends -y \
        build-essential \
        python3-rosdep \
        python3-vcstool \
    && rm -rf /var/lib/apt/lists/*

# bootstrap rosdep
RUN rosdep init && \
    echo "yaml https://ros.packages.techfak.net/ros-one.yaml one" | sudo tee /etc/ros/rosdep/sources.list.d/1-ros-one.list && \
    rosdep update

# install ros packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-one-ros-base \
    && rm -rf /var/lib/apt/lists/*
