# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""Parse actual runner reports and verify JUnit/GoogleTest output contracts."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]


class JunitTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.xml = self.root / 'bazel result.xml'

    def run_probe(self, body, *args, output=True, **environment):
        script = self.root / 'probe.sh'
        script.write_text('set -euo pipefail\nsource "$LIBRARY"\n' + body + '\ntest_runner\n')
        env = {key: value for key, value in os.environ.items()
               if key not in ('GTEST_OUTPUT', 'XML_OUTPUT_FILE', 'TEST_TARGET')}
        env.update(LIBRARY=str(ROOT / 'bashtest/bashtest.sh'), TEST_TMPDIR=str(self.root))
        if output:
            env['XML_OUTPUT_FILE'] = str(self.xml)
        env.update(environment)
        return subprocess.run(['bash', str(script), *args], cwd=self.root, env=env,
                              capture_output=True, timeout=10)

    def report(self, path=None):
        report = ET.parse(path or self.xml).getroot()
        self.assertEqual(report.tag, 'testsuites')
        suite, = list(report)
        cases = suite.findall('testcase')
        for node in (report, suite):
            self.assertEqual(int(node.attrib['tests']), len(cases))
            for key, child in (('failures', 'failure'), ('errors', 'error'), ('skipped', 'skipped')):
                self.assertEqual(int(node.attrib[key]), sum(case.find(child) is not None for case in cases))
            self.assertGreaterEqual(float(node.attrib['time']), 0)
        for case in cases:
            self.assertEqual(case.attrib['classname'], suite.attrib['name'])
            self.assertGreaterEqual(float(case.attrib['time']), 0)
        return {case.attrib['name']: case for case in cases}

    def test_cases_diagnostics_and_shared_shell_state(self):
        result = self.run_probe('''
state=initial
test::test_init() { state=setup; }
test::a_pass() { expect_eq setup "$state"; state=changed; }
test::b_expectation_failure() { expect_eq changed "$state"; expect_eq 'expected <&' 'actual "value"'; return 0; }
test::c_return_failure() { echo 'stdout'; echo 'stderr' >&2; return 7; }
test::d_skip() { skip_test $'missing <& "dependency"\nnext line'; }
test::test_done() { expect_eq changed "$state"; }
''', TEST_TARGET='//example:quoted"<&')
        self.assertEqual(result.returncode, 1, result.stderr)
        cases = self.report()
        self.assertEqual(set(cases), {'a_pass', 'b_expectation_failure', 'c_return_failure', 'd_skip'})
        self.assertIsNone(cases['a_pass'].find('failure'))
        self.assertIn("expected <&", cases['b_expectation_failure'].find('failure').text)
        self.assertIn('actual "value"', cases['b_expectation_failure'].find('failure').text)
        failure = cases['c_return_failure'].find('failure')
        self.assertIn('exit 7', failure.attrib['message'])
        self.assertIn('stdout', failure.text)
        self.assertIn('stderr', failure.text)
        self.assertEqual(cases['d_skip'].find('skipped').attrib['message'], 'missing <& "dependency"\nnext line')
        self.assertIn(b'stdout', result.stdout)
        self.assertNotIn(b'stderr', result.stdout)
        self.assertIn(b'stderr', result.stderr)
        self.assertIn('stdout', cases['c_return_failure'].find('system-out').text)
        self.assertIn('stderr', cases['c_return_failure'].find('system-err').text)

    def test_failure_takes_precedence_over_a_later_skip(self):
        for output in (True, False):
            for body in ('expect_eq yes no; skip_test "later skip"',
                         'skip_test "later skip"; return 7'):
                with self.subTest(output=output, body=body):
                    result = self.run_probe('test::a_pass() { :; }\n'
                                            f'test::bad() {{ {body}; }}', output=output)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertIn(b'[  FAIL  ] bad', result.stderr)
                    self.assertNotIn(b'[  SKIP  ] bad', result.stdout)
                    if output:
                        case = self.report()['bad']
                        self.assertIsNotNone(case.find('failure'))
                        self.assertIsNone(case.find('skipped'))

    def test_invalid_ere_fails_positive_and_negative_assertions(self):
        for assertion in ('expect_matches', 'expect_not_matches'):
            for output in (True, False):
                with self.subTest(assertion=assertion, output=output):
                    result = self.run_probe(f'test::bad() {{ {assertion} "[" text; return 0; }}',
                                            output=output)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertIn(b'Invalid extended regular expression', result.stderr)
                    if output:
                        self.assertIsNotNone(self.report()['bad'].find('failure'))
        result = self.run_probe('test::valid() { expect_not_matches "needle" "haystack"; }')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_skip_is_failure_under_no_skip(self):
        result = self.run_probe('test::skip() { skip_test "not available"; }', '--no-skip')
        self.assertEqual(result.returncode, 1)
        case = self.report()['skip']
        self.assertIsNone(case.find('skipped'))
        self.assertIn('not available', case.find('failure').attrib['message'])

    def test_filtered_and_empty_suites(self):
        result = self.run_probe('test::keep() { :; }\ntest::other() { exit 9; }', '--gtest_filter=keep')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNotNone(self.report()['other'].find('skipped'))
        result = self.run_probe('test::other() { exit 9; }', '--test_filter=absent')
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIsNotNone(self.report()['test_runner'].find('error'))
        result = self.run_probe('')
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn('No tests were run', self.report()['test_runner'].find('error').attrib['message'])

    def test_hook_failures_are_errors_and_setup_skips_bodies(self):
        for hook in ('test_init', 'test_done'):
            for body in ('return 3', 'expect_eq yes no; return 0'):
                with self.subTest(hook=hook, body=body):
                    result = self.run_probe(f'test::{hook}() {{ {body}; }}\ntest::body() {{ :; }}')
                    self.assertEqual(result.returncode, 1, result.stderr)
                    cases = self.report()
                    self.assertIsNotNone(cases[hook].find('error'))
                    if hook == 'test_init':
                        self.assertIsNotNone(cases['body'].find('skipped'))

    def test_early_exits_and_signals_cannot_report_success(self):
        for command, status in (('exit 0', 1), ('exit 7', 7), ('kill -TERM $$', 143),
                                ('echo "${UNDEFINED_JUNIT_PROBE}"', 1)):
            with self.subTest(command=command):
                result = self.run_probe(f'test::abort() {{ echo before; {command}; }}')
                self.assertEqual(result.returncode, status, result.stderr)
                error = self.report()['abort'].find('error')
                self.assertIsNotNone(error)
                self.assertIn('before', error.text)

    def test_unicode_xml_metacharacters_and_binary_logs(self):
        result = self.run_probe(r'''
test::bytes() {
    printf 'café 日本語 😀 <&> "quote" '\''apostrophe'\'' ]]>\n'
    printf '\000\001\013\014\033\377\300\200\355\240\200\357\277\276\364\220\200\200\n'
    return 1
}
''')
        self.assertEqual(result.returncode, 1)
        text = self.report()['bytes'].find('failure').text
        self.assertIn('café 日本語 😀 <&> "quote" \'apostrophe\' ]]>', text)
        self.assertIn('?', text)

    def test_output_precedence_and_supported_flag_spellings(self):
        env_path = self.root / 'env.xml'
        explicit = self.root / 'cli <& output.xml'
        for flag in ('--gtest_output', '--gtest-output'):
            result = self.run_probe('test::pass() { :; }', flag, f'xml:{explicit}',
                                    GTEST_OUTPUT=f'xml:{env_path}')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.report(explicit)
            self.assertFalse(env_path.exists())
            self.assertFalse(self.xml.exists())
        result = self.run_probe('test::pass() { :; }', GTEST_OUTPUT=f'xml:{env_path}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.report(env_path)
        self.assertFalse(self.xml.exists())

    def test_default_filename_directory_and_collision(self):
        result = self.run_probe('test::pass() { :; }', '--gtest_output=xml')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.report(self.root / 'test_detail.xml')
        directory = self.root / 'directory with spaces'
        directory.mkdir()
        original = directory / 'probe.xml'
        original.write_text('preserve previous report')
        result = self.run_probe('test::pass() { :; }', f'--gtest_output=xml:{directory}/')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(original.read_text(), 'preserve previous report')
        self.report(directory / 'probe_1.xml')

    def test_duration_and_relative_destination_survive_directory_changes(self):
        result = self.run_probe('test::slow() { sleep 1; cd /; }', '--gtest_output=xml:relative.xml')
        self.assertEqual(result.returncode, 0, result.stderr)
        case = self.report(self.root / 'relative.xml')['slow']
        self.assertGreaterEqual(float(case.attrib['time']), 1)

    def test_write_failure_after_passing_tests_remains_failure(self):
        directory = self.root / 'deleted directory'
        result = self.run_probe('test::pass() { rmdir "$REPORT_DIRECTORY"; }',
                                f'--gtest_output=xml:{directory}/result.xml',
                                REPORT_DIRECTORY=str(directory))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(b'Cannot write JUnit report', result.stderr)
        self.assertFalse((directory / 'result.xml').exists())

    def test_disabled_reports_and_invalid_output_fail_closed(self):
        for environment in ({'GTEST_OUTPUT': ''}, {'output': False}):
            result = self.run_probe('test::pass() { :; }', **environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(self.xml.exists())
        result = self.run_probe('test::pass() { :; }', '--gtest_output=')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.xml.exists())
        result = self.run_probe('test::pass() { :; }', '--gtest_output=json:out.json')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'Unsupported test report format', result.stderr)
        self.assertFalse(self.xml.exists())
        blocked = self.root / 'not a directory'
        blocked.write_text('file')
        result = self.run_probe('test::pass() { :; }', f'--gtest_output=xml:{blocked}/out.xml')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.xml.exists())


if __name__ == '__main__':
    unittest.main()
