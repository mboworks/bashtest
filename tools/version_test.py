# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""Exercise the version gate against isolated repository histories."""

from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import tarfile
import unittest


ROOT = Path(__file__).parents[1]


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
        self.set_readme(version)

    def set_readme(self, version):
        (self.root / 'README.md').write_text(
            f'bazel_dep(name = "mboworks_bashtest", version = "{version}")\n')

    def prepare(self, version, check=False):
        args = [sys.executable, str(ROOT / 'tools/prepare_release.py'), version]
        if check:
            args.append('--check')
        return subprocess.run(args, cwd=self.root, capture_output=True, text=True)

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

    def test_changelog_must_match(self):
        (self.root / 'CHANGELOG.md').write_text('# 0.6.1\n')
        self.check('CHANGELOG.md')

    def test_missing_or_ambiguous_dependency_is_rejected(self):
        path = self.root / 'README.md'
        for content in ('No dependency example\n', path.read_text() * 2):
            with self.subTest(content=content):
                path.write_text(content)
                self.check('README.md')
                self.assertNotEqual(self.prepare('0.7.0').returncode, 0)

    def test_development_keeps_released_readme(self):
        self.git('tag', '0.7.0')
        self.set_version('0.7.1')
        self.set_readme('0.7.0')
        self.commit()
        self.check()
        self.set_readme('0.6.1')
        self.check('README.md')
        self.set_readme('0.7.2')
        self.check('README.md')

    def test_release_preparation_and_next_development_cycle(self):
        self.git('tag', '0.7.0')
        self.set_version('0.7.1')
        self.set_readme('0.7.0')
        before = (self.root / 'README.md').read_text()
        result = self.prepare('0.7.1', check=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('before tagging', result.stderr)
        self.assertEqual((self.root / 'README.md').read_text(), before)
        result = self.prepare('0.7.1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('version = "0.7.1"', (self.root / 'README.md').read_text())
        self.assertEqual(self.prepare('0.7.1', check=True).returncode, 0)
        self.assertEqual(self.prepare('0.7.1').returncode, 0)
        self.check()
        self.commit()
        self.git('tag', '0.7.1')
        self.check()
        self.set_version('0.7.2')
        self.set_readme('0.7.1')
        self.commit()
        self.check()

    def test_preparation_rejects_wrong_version_without_writing(self):
        before = (self.root / 'README.md').read_text()
        for version in ('0.7.1', '0.7.0-rc1'):
            self.assertNotEqual(self.prepare(version).returncode, 0)
            self.assertEqual((self.root / 'README.md').read_text(), before)
        (self.root / 'CHANGELOG.md').write_text('# 0.6.1\n')
        self.assertNotEqual(self.prepare('0.7.0').returncode, 0)
        self.assertEqual((self.root / 'README.md').read_text(), before)

    def test_archive_rejects_unprepared_readme_and_packages_prepared_version(self):
        for name in ('tools/prepare_release.py', 'tools/header.txt',
                     'tools/release_notes.sh', '.github/release-notes.md.template'):
            destination = self.root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)
        self.set_version('0.7.1')
        self.set_readme('0.7.0')
        self.commit()
        command = ['bash', str(ROOT / '.github/workflows/release_prep.sh')]
        environment = dict(os.environ, GITHUB_REF_NAME='0.7.1',
                           PATH=str(Path(sys.executable).parent) + os.pathsep + os.environ['PATH'])
        result = subprocess.run(command, cwd=self.root, env=environment,
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('before tagging', result.stderr)
        archive = self.root / 'bashtest-0.7.1.tar.gz'
        self.assertFalse(archive.exists())
        self.assertEqual(self.prepare('0.7.1').returncode, 0)
        self.commit()
        result = subprocess.run(command, cwd=self.root, env=environment,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('version = "0.7.1"', result.stdout)
        with tarfile.open(archive) as packaged:
            for name in ('README.md', 'MODULE.bazel'):
                content = packaged.extractfile('bashtest-0.7.1/' + name).read().decode()
                self.assertIn('version = "0.7.1"', content)
            self.assertEqual(packaged.extractfile('bashtest-0.7.1/VERSION').read(), b'0.7.1')

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
