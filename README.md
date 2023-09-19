## github action to build .deb packages from ROS sources

This repository provides actions and resusable workflows helping to build Debian packages from ROS package sources.
For convenience, the built packages from [`ros-one.repos`](./ros-one.repos) are hosted at https://ros.packages.techfak.net.

```bash
# Configure ROS 2 apt repository (for python3-rosdep, pythron3-colcon)
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /etc/apt/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/ros2.list

# Configure ROS One apt repository
sudo curl -sSL https://ros.packages.techfak.net/gpg.key -o /etc/apt/keyrings/ros-one-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/ros-one-keyring.gpg] https://ros.packages.techfak.net/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/ros1.list

# Install and setup rosdep
sudo apt update
sudo apt install python3-rosdep
sudo rosdep init

# Define custom rosdep package mapping
echo "yaml https://ros.packages.techfak.net/ros-one.yaml ubuntu" | sudo tee /etc/ros/rosdep/sources.list.d/1-ros-one.list
rosdep update
```
Note: Replace `ubuntu` for `debian` on a Debian distro.

### Reusable workflows [build.yaml](.github/workflows/build.yaml) + [deploy.yaml](.github/workflows/deploy.yaml)

These workflows are intended for reuse by an external repository to build a custom list of ROS packages. The `build` workflow stores created `.debs` as an artifact that can be manually downloaded or automatically uploaded to a repository server (via the `deploy` workflow) subsequently.

A simple usage example looks like this:

```yaml
jobs:
  build:
    uses: ubi-agni/ros-builder-action/.github/workflows/build.yaml@main
    with:
      ROS_SOURCES: '*.repos'

  deploy:
    needs: build
    if: always()
    uses: ubi-agni/ros-builder-action/.github/workflows/deploy.yaml@main
    with:
      DEPLOY_URL: ${{ vars.DEPLOY_URL || 'self' }}
      TOKEN: ${{ secrets.GITHUB_TOKEN }}                  # used for own repo
      SSH_PRIVATE_KEY: ${{ secrets.DEPLOY_PRIVATE_KEY }}  # used for other repo
```

More complex usage examples can be found in [interactive.yaml](.github/workflows/interactive.yaml) or [splitted.yaml](.github/workflows/splitted.yaml).

### environment variables

The build process is controlled by several environment variables. Usually, those environment variables are inititialized from inputs, [repository variables](https://docs.github.com/en/actions/learn-github-actions/variables), or the given default value - in that order.

variable               | type   | default   | semantics
-----------------------|--------|-----------|---------------------------------------------------------------------
`ROS_DISTRO`           | string | one       | ROS distribution codename to compile for
`DEB_DISTRO`           | string | jammy     | The Debian/Ubuntu distribution codename to compile for.
`ROS_SOURCES`          | string | `*.repos` | [ROS sources to compile](#what-to-build)
`COLCON_PKG_SELECTION` | string |           | [colcon package selectio argument(s)](#where-to-start-building-from)
|<td colspan=3>**Workflow control**</td>
`SKIP_EXISTING`        | boolean | false    | [Skip (re)building packages already existing in the repository](#where-to-start-building-from)
`DOWNLOAD_DEBS`        | boolean | false    | [Continue building from previous debs artifact?](#where-to-start-building-from)
`BUILD_TIMEOUT`        | number  | 340      | Cancel build after this time, before github will do (minutes)
`CONTINUE_ON_ERROR`    | boolean | false    | Continue building even if some packages already failed
|<td colspan=3>**Package source options**</td>
`EXTRA_DEB_SOURCES`    | string  |          | Extra debian sources to use in host and sbuild chroot
`INSTALL_GPG_KEYS`     | string  |          | code to run for installing GPG keys (for use with EXTRA_DEB_SOURCES)
`EXTRA_ROSDEP_SOURCES` | string  |          | path to a rosdep-compatible yaml file specifying custom dependency mappings
|<td colspan=3>**Package source options**</td>
`EXTRA_SBUILD_CONFIG`  | string  |          | lines to add to ~/.sbuildrc
`EXTRA_SBUILD_OPTS`    | string  |          | options to pass to sbuild on commandline
`DEB_BUILD_OPTIONS`    | string  | nocheck  | options used debian/rules
|<td colspan=3>**Deployment variables**</td>
`DEBS_PATH`            | string  | ~/debs   | path to store generated .debs in
`DEPLOY_URL`           | string  |          | repository URL for deployment
`DEPLOY_FILES`         | string  | deb      | list of file types to deploy: deb, ddeb, dsc, changes
`DEPLOY_FILE_SIZE_LIMIT` | string |         | size limit for files (100M on github)
`TOKEN`                | secret  | secrets.GITHUB_TOKEN | github token for pushing to own repo
`SSH_PRIVATE_KEY`      | secret  |                      | ssh private key for pushing to an external repo
|<td colspan=3>**Debugging options**</td>
`VERBOSE`              | string  |          | verboseness for all (value true) or selected steps (bloom sbuild apt ccache)
`TRACE`                | boolean | false    | Enable function tracing
`DEBUG_BASH`           | boolean | false    | Enable bash debugging (`set -x`) and tracing

### Where to start building from?

Building a complete ROS distro from scratch takes a lot of time, often more than allowed by github actions (6h). For this reason, it is possible to continue a build either from a previous build (downloading an existing `debs` artifact) or from an existing repository. For the former, set the input `DOWNLOAD_DEBS=true`, for the latter add the deploy repository to `EXTRA_DEB_SOURCES`. Note that this variable supports shell variable expansion, i.e. you can use `$DEB_DISTRO` and/or `$ROS_DISTRO` to generically specify the deploy repository across different builds.
In both cases, set the variable/input `SKIP_EXISTING=true` to actually skip building of already existing packages.

The example workflow [splitted.yaml](.github/workflows/splitted.yaml) uses `DOWNLOAD_DEBS` to build a large ROS distro from several `.repos` files.

Specifying `COLCON_PKG_SELECTION` allows to limit the build to a subset of packages via [colcon package selection options](https://colcon.readthedocs.io/en/released/reference/package-selection-arguments.html). For example:
- To rebuild a specific package and all its downstream dependencies:  
  `--packages-above-and-dependencies <pkg ...>`
- To rebuild a single package (only use if ABI/API hasn't changed):  
  `--packages-select <pkg ...>`

### What to build?

`ROS_SOURCES` specifies a (space-separated) list of inputs suitable for `vcs import`.

### Where to deploy?

The built packages can be deployed to a flat Debian repository, for example on a github branch.
The easiest way to do so is to specify `DEPLOY_URL=self`, causing deployment to the active github repository into the branch `$DEB_DISTRO-$ROS-DISTRO`.
However, you can also specify another github repo.
