#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""Prepare tracked version references before reviewing and tagging a release."""

import argparse
from pathlib import Path
import re


VERSION = r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)'
DEPENDENCY = re.compile(r'(bazel_dep\(name = "mboworks_bashtest", version = ")[^"]+("\))')


def prepare(root, version, check=False):
    if not re.fullmatch(VERSION, version):
        raise ValueError('Release version must use numeric X.Y.Z format.')
    module = re.search(r'\bversion\s*=\s*"([^"]+)"', (root / 'MODULE.bazel').read_text())
    changelog = re.search(r'^# (\S+)$', (root / 'CHANGELOG.md').read_text(), re.MULTILINE)
    if not module or module[1] != version or not changelog or changelog[1] != version:
        raise ValueError('Requested release must match MODULE.bazel and the first CHANGELOG.md heading.')
    path = root / 'README.md'
    original = path.read_text()
    updated, count = DEPENDENCY.subn(lambda match: match[1] + version + match[2], original)
    if count != 1:
        raise ValueError('README.md must contain exactly one bashtest dependency example.')
    if check:
        if updated != original:
            raise ValueError(f'Run python3 tools/prepare_release.py {version}, then review and merge the change before tagging.')
    elif updated != original:
        path.write_text(updated)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version')
    parser.add_argument('--check', action='store_true', help='Verify without changing files')
    args = parser.parse_args()
    try:
        prepare(Path.cwd(), args.version, args.check)
    except (ValueError, OSError) as error:
        parser.exit(1, f'ERROR: {error}\n')


if __name__ == '__main__':
    main()
