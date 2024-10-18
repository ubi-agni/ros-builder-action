#!/usr/bin/env python3

from catkin_pkg.package import _get_package_xml, parse_package_string
from rosdep2.main import (
    _get_default_RosdepLookup,
    create_default_installer_context,
    configure_installer_context,
    get_default_installer,
)
from rosdep2.rospkg_loader import DEFAULT_VIEW_KEY
from rosdep2.sources_list import get_sources_cache_dir

from dataclasses import dataclass, field
from pathlib import Path
import argparse
import datetime
import subprocess
import os, re


@dataclass
class Options:
    as_root: dict = field(default_factory=lambda: {})
    dependency_types: list[str] = field(default_factory=lambda: [])
    os_override: str = None
    sources_cache_dir: str = get_sources_cache_dir()
    verbose: bool = False

parser = argparse.ArgumentParser()
parser.add_argument("folder", nargs="?", default=".")
options = parser.parse_args()
folder = Path(options.folder)

# bail out if folder doesn't contain package.xml
if not (folder / "package.xml").exists():
    exit(1)

xml, file = _get_package_xml(folder)
pkg = parse_package_string(xml, filename=file)
pkg.evaluate_conditions(os.environ)

options = Options()
lookup = _get_default_RosdepLookup(options)
installer_context = create_default_installer_context(verbose=options.verbose)
configure_installer_context(installer_context, options)

installer, installer_keys, default_key, os_name, os_version = get_default_installer(
    installer_context=installer_context, verbose=options.verbose
)

view = lookup.get_rosdep_view(DEFAULT_VIEW_KEY, verbose=options.verbose)


def resolve(rosdep_name):
    "Resolve rosdep package name to required system package name(s)"
    try:
        d = view.lookup(rosdep_name)
    except KeyError:
        return []

    rule_installer, rule = d.get_rule_for_platform(
        os_name, os_version, installer_keys, default_key
    )

    return installer_context.get_installer(rule_installer).resolve(rule)

# regex to extract version number and build time from "1.16.0-14jammy.20240914.2055"
regex = re.compile(f'(?P<version>.*){os.environ["DEB_DISTRO"]}\.(?P<stamp>.*)')


def stamp(pkg_name):
    try:
        deb_name = resolve(pkg_name)[0]
        # version scheme only applies to ros packages
        if not deb_name.startswith("ros-"):
            return datetime.datetime.fromtimestamp(0)

        # run shell command: LANG=C apt-cache policy "$1" | sed -n "s#^\s*Candidate:\s\(.*\)#\1#p"
        candidate = subprocess.getoutput(
            f'apt-cache policy "{deb_name}" | sed -n "s#^\\s*Candidate:\\s\\(.*\\)#\\1#p"'
        )
        result = regex.match(candidate).groupdict()
        return datetime.datetime.strptime(result["stamp"], "%Y%m%d.%H%M")
    except IndexError:
        return datetime.datetime.fromtimestamp(0)


current = stamp(pkg.name)
for dep in pkg.build_depends:
    if dep.evaluated_condition:
        # rebuild is needed if any dependency's stamp is newer than package's one
        time = stamp(dep.name)
        if time > current:
            print(f"Rebuild needed due to {dep.name} rebuilt at {time}")
            exit(0)  # rebuild needed

exit(1)  # no rebuild needed
