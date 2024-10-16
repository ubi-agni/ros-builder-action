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
import os, sys


@dataclass
class Options:
    as_root: dict = field(default_factory=lambda: {})
    dependency_types: list[str] = field(default_factory=lambda: [])
    os_override: str = None
    sources_cache_dir: str = get_sources_cache_dir()
    verbose: bool = False


debs = Path(sys.argv[1])
folder = Path(sys.argv[2] if len(sys.argv) > 2 else ".")

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

    installer = installer_context.get_installer(rule_installer)
    resolved = installer.resolve(rule)
    return resolved


for dep in pkg.build_depends:
    if dep.evaluated_condition:
        for name in resolve(dep.name):
            # check whether file debs/name*.deb exists
            if any(debs.glob(f"{name}*.deb")):
                print(f"Rebuild needed due to {name}")
                exit(0)  # rebuild needed

exit(1)  # no rebuild needed
