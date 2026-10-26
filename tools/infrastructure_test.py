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
        self.assertIn("disk-cache: ${{ github.workflow }}-${{ matrix.bazel || 'pinned' }}", workflow)
        self.assertIn('needs: [release-site-tests, pre-commit, test]', workflow)
        self.assertIn('os: [ubuntu-latest, macos-latest, windows-latest]', workflow)

    def test_every_platform_tests_supported_bazel_versions(self):
        workflow = (Path(__file__).parents[1] / '.github/workflows/main.yml').read_text()
        self.assertIn('bazel: ["7.7.2", "8.8.2", ""]', workflow)
        # Job-level selection must also reach external consumer workspaces and
        # Windows commands, rather than being limited to a single root test step.
        self.assertIn('    env:\n      USE_BAZEL_VERSION: ${{ matrix.bazel }}', workflow)
        self.assertIn("name: test (${{ matrix.os }}, Bazel ${{ matrix.bazel || 'pinned' }})", workflow)
        self.assertIn("name: test-results-${{ matrix.os }}-bazel-${{ matrix.bazel || 'pinned' }}", workflow)

    def test_test_diagnostics_survive_failed_steps(self):
        workflow = (Path(__file__).parents[1] / '.github/workflows/main.yml').read_text()
        self.assertIn('name: Summarize JUnit results\n      if: always()', workflow)
        self.assertIn('name: Retain test diagnostics\n      if: always()', workflow)
        self.assertIn("name: test-results-${{ matrix.os }}-bazel-${{ matrix.bazel || 'pinned' }}", workflow)
        self.assertIn('retention-days: 7', workflow)
        self.assertIn('bazel test //... --build_event_json_file=', workflow)
        self.assertIn('bazel test --enable_runfiles=no //... --build_event_json_file=', workflow)
        self.assertIn('bazel run //tools:ci_reports -- finalize', workflow)
        self.assertNotIn('ci_bazel', workflow)
        root = Path(__file__).parents[1]
        for name in ('ci_support.sh', 'external_consumer_test.sh', 'tools_consumer_test.sh'):
            self.assertNotIn('ci_bazel', (root / 'bashtest/tests' / name).read_text())
        windows = (root / 'bashtest/tests/windows_runtime_test.ps1').read_text()
        self.assertNotIn('Invoke-TestBazel', windows)
        self.assertIn('& $bazel test //...', windows)
        summary = workflow.split('- name: Summarize JUnit results', 1)[1].split('- name: Retain test diagnostics', 1)[0]
        self.assertIn('MSYS_NO_PATHCONV: "1"', summary)
        self.assertNotIn('python3 -m unittest', workflow)
        self.assertEqual(workflow.count('uses: actions/setup-python@'), 1)
        self.assertNotIn('pull_request_target', workflow)
        self.assertNotIn('checks: write', workflow)

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
