## github action to build .deb packages from ROS sources

This repository provides actions and resusable workflows helping to build Debian packages from ROS package sources.

### workflow [generic.yaml](.github/workflows/generic.yaml)

This workflow is intended for reuse by an external repository to build a custom list of ROS packages. Resulting `.debs` are provided as a build artifact and can be uploaded to a repository server subsequently.

A simple usage example looks like this:

```yaml
jobs:
  build:
    uses: ubi-agni/ros-builder-action/.github/workflows/generic.yaml@main
    with:
      ROS_SOURCES: '*.repos'
```

More complex usage examples can be found in [interactive.yaml](.github/workflows/interactive.yaml) or [splitted.yaml](.github/workflows/splitted.yaml).

### environment variables

The build process is controlled by several environment variables. Usually, those environment variables are inititialized from inputs, [repository variables](https://docs.github.com/en/actions/learn-github-actions/variables), or the given default value - in that order.

variable               | type    | default                   | semantics
-----------------------|---------|---------------------------|----------------------------------------------------------------------------
`ROS_DISTRO`           | string  | one                       | ROS distribution codename to compile for
`DEB_DISTRO`           | string  | jammy                     | The Debian/Ubuntu distribution codename to compile for.
`ROS_SOURCES`          | string  | `*.repos`                 | [ROS sources to compile](#what-to-build)
`SKIP_EXISTING`        | boolean | false                     | [Skip (re)building packages already existing in the repository](#where-to-start-building-from)
`DOWNLOAD_DEBS`        | boolean | false                     | [Continue building from previous debs artifact?](#where-to-start-building-from)
`BUILD_TIMEOUT`        | number  | 340                       | Cancel build after this time, before github will do (minutes)
`EXTRA_DEB_SOURCES`    | string  |                           | Extra debian sources to add to sources.list
`INSTALL_GPG_KEYS`     | string  |                           | code to run for installing GPG keys (for use with EXTRA_DEB_SOURCES)
`EXTRA_ROSDEP_SOURCES` | string  |                           | path to a rosdep-compatible yaml file specifying custom dependency mappings
`EXTRA_SBUILD_CONFIG`  | string  |                           | lines to add to ~/.sbuildrc
`EXTRA_SBUILD_OPTS`    | string  |                           | options to pass to sbuild on commandline
`DEB_BUILD_OPTIONS`    | string  | nocheck                   | options used debian/rules
`CONTINUE_ON_ERROR`    | boolean | false                     | Continue building even if some packages already failed
`DEBS_PATH`            | string  | ~/debs                    | path to store generated .debs in
`REPO_PATH`            | string  | ~/repo                    | path to generate package repository in
`DEPLOY_URL`           | string  |                           | repository URL for deployment
`BRANCH`               | string  | `$DEB_DISTRO-$ROS_DISTRO` | branch to use for deployment

### Where to start building from?

Building a complete ROS distro from scratch takes a lot of time, often more than allowed by github actions (6h). For this reason, it is possible to continue a build either from a previous build (downloading an existing `debs` artifact) or from an existing repository. For the former, set the input `DOWNLOAD_DEBS=true`, for the latter add the repository to `EXTRA_DEB_SOURCES`. In both cases, set the variable/input `SKIP_EXISTING=true` to actually skip building of already existing packages.

The example workflow [splitted.yaml](.github/workflows/splitted.yaml) uses `DOWNLOAD_DEBS` to build a large ROS distro from several `.repos` files.

### What to build?

`ROS_SOURCES` specifies a (space-separated) list of inputs suitable for `vcs import`.
