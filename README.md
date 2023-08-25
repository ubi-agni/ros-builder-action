# github action to build .deb packages from ROS sources

## Inputs

## `ROS_DISTRO`

**Required** The ROS distribution codename to compile for.

## `DEB_DISTRO`

**Required** The Debian/Ubuntu distribution codename to compile for.

## `ROS_SOURCES`

Repos file with list of repositories to package.
Defaults to *.repos

## `EXTRA_SBUILD_CONFIG`

Additional sbuild.conf lines.
For example EXTRA_REPOSITORIES, or VERBOSE.
See man sbuild.conf.

## `EXTRA_ROSDEP_SOURCES`

Additional rosdep sources.

## `GITHUB_TOKEN`

Set to `${{ secrets.GITHUB_TOKEN }}` to deploy to a `DEB_DISTRO-ROS_DISTRO` branch in the same repo.

## ``SQUASH_HISTORY``

If set to true, all previous commits on the target branch will be discarded.
For example, if you are deploying a static site with lots of binary artifacts, this can help prevent the repository from becoming overlay bloated

## Example usage

```
uses: rhaschke/ros-deb-builder-action@new
with:
  ROS_DISTRO: rolling
  DEB_DISTRO: jammy
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```
