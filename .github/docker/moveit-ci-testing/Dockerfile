# moveit/moveit:jammy-ci-testing
# Sets up a base image to use for running Continuous Integration

ARG DEB_DISTRO=jammy
FROM moveit/moveit:${DEB_DISTRO}-ci
LABEL org.opencontainers.image.authors="Robert Haschke <rhaschke@techfak.uni-bielefeld.de>"

# Switch to ros-testing
RUN . /etc/os-release && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/ros-one-keyring.gpg] https://ros.packages.techfak.net ${VERSION_CODENAME}-testing main" | tee /etc/apt/sources.list.d/ros1.list && \
    # Upgrade packages to ros-testing and clean apt-cache within one RUN command
    apt-get update && \
    apt-get -qq -y dist-upgrade && \
    #
    # Clear apt-cache to reduce image size
    rm -rf /var/lib/apt/lists/*
