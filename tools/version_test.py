# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""Exercise the version gate against isolated repository histories."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
REFERENCES = (
    'README.md',
    'bashtest/tests/external_consumer_test.sh',
    'bashtest/tests/tools_consumer_test.sh',
)


class VersionTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.git('init', '--quiet')
        self.git('config', 'user.name', 'Version test')
        self.git('config', 'user.email', 'version-test@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        self.set_version('0.7.0')
        self.commit()

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.root, check=True,
                              capture_output=True, text=True)

    def commit(self):
        self.git('add', '.')
        self.git('-c', 'core.hooksPath=/dev/null', 'commit', '--quiet',
                 '--allow-empty', '-m', 'Fixture')

    def set_version(self, version):
        (self.root / 'MODULE.bazel').write_text(
            f'module(name = "mboworks_bashtest", version = "{version}")\n')
        (self.root / 'CHANGELOG.md').write_text(f'# {version}\n\n# 0.1.0\n')
        for name in REFERENCES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f'bazel_dep(name = "mboworks_bashtest", version = "{version}")\n')

    def check(self, error=None):
        result = subprocess.run(['bash', str(ROOT / '.pre-commit/check_version.sh')],
                                cwd=self.root, capture_output=True, text=True)
        if error is None:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(error, result.stderr)

    def test_matching_versions_without_tags(self):
        self.check()

    def test_each_reference_must_match(self):
        for name in ('CHANGELOG.md', *REFERENCES):
            with self.subTest(name=name):
                self.set_version('0.7.0')
                path = self.root / name
                path.write_text(path.read_text().replace('0.7.0', '0.6.1'))
                self.check(name)

    def test_missing_dependency_is_rejected(self):
        for name in REFERENCES:
            with self.subTest(name=name):
                self.set_version('0.7.0')
                (self.root / name).write_text('No dependency example\n')
                self.check(name)

    def test_invalid_version_is_rejected(self):
        self.set_version('0.7.0-rc1')
        self.check('numeric X.Y.Z')

    def test_released_commit_then_next_development_commit(self):
        self.git('tag', '0.7.0')
        self.check()
        self.commit()
        self.check('HEAD contains later work')
        self.set_version('0.7.1')
        self.check()

    def test_latest_release_uses_numeric_order(self):
        self.git('tag', '0.9.0')
        self.git('tag', '0.10.0')
        self.git('tag', 'unrelated-tag')
        self.set_version('0.9.1')
        self.check('older than latest release tag (0.10.0)')
        self.set_version('0.10.1')
        self.check()


if __name__ == '__main__':
    unittest.main()
