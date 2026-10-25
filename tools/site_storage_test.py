# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""Publication accounting preserves every release and measures both trees."""

import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import site_storage


class SiteStorageTest(unittest.TestCase):
    def test_complete_tree_accounting_preserves_releases_and_is_repeatable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            files = {'site/tag/1.2.3/index.html': b'release page', 'schema/v1.json': b'{}',
                     'favicon.ico': b'icon', '.git/objects/private': b'not deployed'}
            for name, data in files.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            with contextlib.redirect_stdout(io.StringIO()):
                result = site_storage.report(root)
                again = site_storage.report(root)
            self.assertEqual(result, again)
            self.assertEqual(result['total_bytes'], 18)
            self.assertEqual(result['sections']['site'], {'files': 1, 'bytes': 12})
            self.assertNotIn('.git', result['sections'])
            self.assertEqual(json.loads((root / 'storage-report.json').read_text()), result)
            for name, data in files.items():
                self.assertEqual((root / name).read_bytes(), data)

    def test_advisory_and_emergency_payload_boundaries(self):
        with tempfile.TemporaryDirectory() as directory:
            for size, warns, fails in ((249_999_999, False, False), (250_000_000, True, False),
                                       (9_000_000_000, True, False), (9_000_000_001, True, True)):
                with self.subTest(size=size), mock.patch.object(
                        site_storage, 'sizes', return_value={'site': {'files': 1, 'bytes': size}}):
                    output = io.StringIO()
                    with contextlib.redirect_stdout(output):
                        if fails:
                            with self.assertRaisesRegex(ValueError, 'deployment ceiling'):
                                site_storage.report(Path(directory))
                        else:
                            site_storage.report(Path(directory))
                    self.assertEqual('::warning::' in output.getvalue(), warns)

    def test_publisher_measures_before_commit_and_after_artwork_with_shallow_fetch(self):
        source = (Path(__file__).parent.parent / '.github/workflows/pages.yml').read_text()
        self.assertLess(source.index('site_storage.py site'), source.index('git -C site commit'))
        self.assertLess(source.index('site_artwork.py'), source.index('site_storage.py public'))
        self.assertLess(source.index('site_storage.py public'), source.index('uses: actions/upload-pages-artifact@'))
        self.assertIn('git fetch --no-tags --depth=1 origin', source)
        self.assertIn('git ls-remote --heads origin refs/heads/coverage-pages', source)
        self.assertNotIn('git fetch origin\n', source)


if __name__ == '__main__':
    unittest.main()
