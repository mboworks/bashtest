# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""Regression checks for PR cache isolation and complete validation gates."""

from pathlib import Path
import unittest


class InfrastructureTest(unittest.TestCase):
    def test_prs_restore_but_only_main_writes_caches(self):
        workflow = (Path(__file__).parents[1] / '.github/workflows/main.yml').read_text()
        self.assertIn('pull_request: {}', workflow)
        self.assertIn("cache-save: ${{ github.ref == 'refs/heads/main' }}", workflow)
        self.assertIn("cancel-in-progress: ${{ github.event_name == 'pull_request' }}", workflow)
        self.assertIn('repository-cache: true', workflow)
        self.assertIn('disk-cache: ${{ github.workflow }}', workflow)
        self.assertIn('needs: [release-site-tests, pre-commit, test]', workflow)
        self.assertIn('os: [ubuntu-latest, macos-latest]', workflow)

    def test_release_uploads_before_immutable_publication(self):
        workflow = (Path(__file__).parents[1] / '.github/workflows/release.yml').read_text()
        self.assertIn('release_ruleset.yaml@1d798ff015ed0696433e01e2c3ccbb2abefadad7', workflow)
        self.assertIn('prerelease: false', workflow)
        self.assertIn('mount_bazel_caches: false', workflow)
        self.assertIn('needs: release', workflow)
        self.assertNotIn('prerelease: true', workflow)

    def test_documented_rules_are_published(self):
        import json
        root = Path(__file__).parents[1]
        config = json.loads((root / 'release-site.json').read_text())
        for name in ('AGENTS.md', 'GIT_RULES.md', 'STYLE_SH.md', 'docs/infrastructure.md'):
            self.assertTrue((root / name).is_file())
            self.assertIn(name, config['pages'])


if __name__ == '__main__':
    unittest.main()
