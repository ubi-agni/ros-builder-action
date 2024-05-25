# moveit/moveit:jammy-ci
# Sets up a base image to use for running Continuous Integration on Travis

ARG DEB_DISTRO=jammy
FROM ubiagni/ros:${DEB_DISTRO}-ros-base

ENV TERM xterm
ENV IN_DOCKER 1

# Commands are combined in single RUN statement with "apt/lists" folder removal to reduce image size
# https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#minimize-the-number-of-layers
RUN \
    # Update apt package list as previous containers clear the cache
    apt-get -q update && \
    apt-get -q -y dist-upgrade && \
    #
    # Install some base dependencies
    apt-get -q install --no-install-recommends -y \
        # Some basic requirements
        wget python3-vcstool git sudo \
        # Qt6 packages for Jammy
        $(test "$ROS_DISTRO" = "one" && echo "qt6-base-dev qt6-base-dev-tools libqt6opengl6-dev") \
        # Preferred build tools
        clang clang-format-12 clang-tidy clang-tools ccache && \
    #
    # Download MoveIt sources, so that we can fetch all necessary dependencies
    mkdir -p /tmp/src && \
    git clone --branch master --depth 1 https://github.com/ros-planning/moveit /tmp/src/moveit && \
    vcs import --recursive --shallow --input /tmp/src/moveit/.github/workflows/upstream.rosinstall /tmp/src && \
    #
    # Download all dependencies of MoveIt
    rosdep update $(test "${ROS_DISTRO}" = "melodic" && echo "--include-eol-distros") && \
    DEBIAN_FRONTEND=noninteractive \
    rosdep install -y --from-paths /tmp/src --ignore-src --rosdistro ${ROS_DISTRO} --as-root=apt:false && \
    # Remove the source code from this container
    rm -rf /tmp/src && \
    #
    # Clear apt-cache to reduce image size
    rm -rf /var/lib/apt/lists/* && \
    # Globally disable git security
    # https://github.blog/2022-04-12-git-security-vulnerability-announced
    git config --global --add safe.directory "*"
