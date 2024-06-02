# Instructions

## Install

```bash
# Configure ROS 2 apt repository
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /etc/apt/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/ros2.list

# Configure custom ROS repository
echo "deb [trusted=yes] https://raw.githubusercontent.com/ubi-agni/ros-builder-action/ci ./" | sudo tee /etc/apt/sources.list.d/jammy-one.list

# Install and setup rosdep
sudo apt update
sudo apt install python3-rosdep
sudo rosdep init

# Define custom rosdep mapping
echo "yaml https://raw.githubusercontent.com/ubi-agni/ros-builder-action/ci/local.yaml @DEB_DISTRO@" | sudo tee /etc/ros/rosdep/sources.list.d/1-jammy-one.list
rosdep update
```
