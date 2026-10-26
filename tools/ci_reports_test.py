# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""Observable CI report collection, exit status, and safe rendering contracts."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

import ci_reports


ROOT = Path(__file__).parents[1]


class CiReportsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='ci reports ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def events(self, *outputs, code=0):
        events = self.root / 'events.json'
        events.write_text(''.join(json.dumps({'id': {'testResult': {'label': '//:fixture', 'shard': i + 1}},
                                            'testResult': {'status': 'FAILED', 'testActionOutput': output}}) + '\n'
                                  for i, output in enumerate(outputs)) +
                          json.dumps({'finished': {'exitCode': {'code': code}}}) + '\n')
        return events

    def manifest(self, name, expected='success', code=0, results=None, errors=None):
        folder = self.root / name
        folder.mkdir(exist_ok=True)
        (folder / 'invocation.json').write_text(json.dumps({'expected': expected, 'exit_code': code,
                                                          'results': results or [], 'errors': errors or []}))
        return folder

    def test_copies_only_reported_outputs_before_consumer_cleanup(self):
        source = self.root / 'consumer with spaces'
        source.mkdir()
        (source / 'test.xml').write_text('<testsuite><testcase name="pass"/></testsuite>')
        (source / 'test.log').write_text('diagnostic')
        (source / 'unrelated.xml').write_text('stale shard')
        outputs = [{'name': name, 'uri': (source / name).as_uri()} for name in ('test.xml', 'test.log')]
        destination = self.manifest('collected')
        results, errors = ci_reports.collect(self.events(outputs, outputs), destination)
        self.assertEqual(errors, [])
        self.assertEqual(len(results), 2)
        self.assertEqual([r['shard'] for r in results], [1, 2])
        for item in source.iterdir():
            item.unlink()
        source.rmdir()
        self.assertEqual((destination / 'result_0001/test.log').read_text(), 'diagnostic')
        self.assertEqual(len(list(destination.rglob('test.xml'))), 2)
        self.assertFalse(list(destination.rglob('unrelated.xml')))

    def test_missing_remote_and_partial_outputs_are_reported(self):
        outputs = [{'name': 'test.xml', 'uri': 'bytestream://remote/test.xml'},
                   {'name': 'test.log', 'uri': (self.root / 'missing').as_uri()}]
        results, errors = ci_reports.collect(self.events(outputs), self.root / 'copy')
        self.assertEqual(len(results), 1)
        self.assertEqual(len(errors), 2)
        events = self.events()
        events.write_text('{"unfinished":')
        self.assertTrue(ci_reports.collect(events, self.root / 'partial')[1])

    def test_summary_counts_actual_cases_and_escapes_diagnostics(self):
        folder = self.manifest('expected', expected='failure', code=3, results=[{
            'label': '//:<script>alert(1)</script>', 'run': 1, 'shard': 2, 'attempt': 3,
            'files': ['result_0001/test.xml']}])
        (folder / 'result_0001').mkdir()
        (folder / 'result_0001/test.xml').write_text('''<testsuites tests="999"><testsuite tests="999">
<testcase name="pass"/><testcase name="bad"><failure message="&lt;/pre&gt;">
&lt;script&gt;bad&lt;/script&gt; [link](https://example.com)</failure></testcase>
<testcase name="error"><error/></testcase><testcase name="skip"><skipped/></testcase>
</testsuite></testsuites>''')
        text, failed = ci_reports.summarize(self.root)
        self.assertFalse(failed)
        self.assertNotIn('<th>Failures</th>', text)
        self.assertIn('Expected nonzero exit observed (3)', text)
        self.assertIn('<details><summary>Expected fixture diagnostics', text)
        self.assertNotIn('Test diagnostics (', text)
        self.assertNotIn('<script>', text)
        self.assertIn('&lt;/pre&gt;', text)
        self.assertIn('shard 2, attempt 3', text)

    def test_successful_exit_cannot_mask_failed_xml_or_bazel_test_status(self):
        result = {'label': '//:a', 'run': 1, 'shard': 1, 'attempt': 1,
                  'status': 'PASSED', 'files': ['result_0001/test.xml']}
        folder = self.manifest('tests', results=[result])
        (folder / 'result_0001').mkdir()
        report = folder / 'result_0001/test.xml'
        for kind in ('failure', 'error'):
            report.write_text(f'<testsuite><testcase name="bad"><{kind}/></testcase></testsuite>')
            text, failed = ci_reports.summarize(self.root)
            self.assertTrue(failed)
            self.assertIn('<td>FAILED</td>', text)
            self.assertIn('unexpected JUnit failures/errors', text)
        report.write_text('<testsuite><testcase name="ok"/></testsuite>')
        result['status'] = 'TIMEOUT'
        self.manifest('tests', results=[result])
        text, failed = ci_reports.summarize(self.root)
        self.assertTrue(failed)
        self.assertIn('Bazel test status TIMEOUT', text)

    def test_successful_retry_uses_final_attempt_and_preserves_skips(self):
        results = [{'label': '//:a', 'run': 1, 'shard': 1, 'attempt': attempt,
                    'status': status, 'files': [f'result_000{attempt}/test.xml']}
                   for attempt, status in ((1, 'FAILED'), (2, 'PASSED'))]
        folder = self.manifest('retry', results=results)
        for attempt, case in ((1, '<failure/>'), (2, '<skipped/>')):
            target = folder / f'result_000{attempt}'
            target.mkdir()
            (target / 'test.xml').write_text(f'<testsuite><testcase>{case}</testcase></testsuite>')
        text, failed = ci_reports.summarize(self.root)
        self.assertFalse(failed)
        self.assertIn('<td>Passed</td><td>1</td><td>0</td><td>0</td><td>1</td>', text)
        self.assertNotIn('Test diagnostics (', text)

    def test_unexpected_command_and_collection_failures_fail_summary(self):
        self.manifest('unexpected-pass', expected='failure')
        self.manifest('unexpected-fail', code=3)
        self.manifest('copy-error', errors=['unavailable log'])
        text, failed = ci_reports.summarize(self.root)
        self.assertTrue(failed)
        self.assertIn('unexpected command exit 0', text)
        self.assertIn('unavailable log', text)

    def test_invalid_xml_is_an_error_but_large_xml_is_retained_without_parsing(self):
        folder = self.manifest('xml', results=[{'label': '//:a', 'run': 1, 'shard': 1, 'attempt': 1,
                                               'files': ['result_0001/test.xml']}])
        (folder / 'result_0001').mkdir()
        report = folder / 'result_0001/test.xml'
        for value in ('<unclosed>', '<!DOCTYPE x [<!ENTITY x "expanded">]><testsuite/>'):
            report.write_text(value)
            self.assertTrue(ci_reports.summarize(self.root)[1])
        report.write_bytes('<!DOCTYPE x [<!ENTITY x "expanded">]><testsuite/>'.encode('utf-16'))
        self.assertTrue(ci_reports.summarize(self.root)[1])
        report.write_text('x' * 100)
        with mock.patch.object(ci_reports, 'MAX_XML_BYTES', 50):
            text, failed = ci_reports.summarize(self.root)
        self.assertFalse(failed)
        self.assertIn('summary size limit', text)
        self.assertEqual(report.stat().st_size, 100)

    def test_finalize_recovers_failed_command_and_keeps_earlier_snapshot(self):
        log = self.root / 'test.log'
        log.write_text('first diagnostic')
        events = self.events([{'name': 'test.log', 'uri': log.as_uri()}], code=3)
        staging = self.root / 'pending'
        staging.mkdir()
        event_file = staging / 'root-default.json'
        events.rename(event_file)
        destination = self.root / 'artifact'
        self.assertFalse(ci_reports.finalize(staging, destination))
        invocation = destination / 'root-default'
        self.assertEqual(json.loads((invocation / 'invocation.json').read_text())['exit_code'], 3)
        self.assertTrue((invocation / 'events.json').is_file())
        log.write_text('overwritten by a later invocation')
        self.assertFalse(ci_reports.finalize(staging, destination))
        self.assertEqual((invocation / 'result_0001/test.log').read_text(), 'first diagnostic')

    def test_expected_failure_is_derived_from_event_directory(self):
        expected = self.root / 'expected'
        expected.mkdir()
        events = expected / 'negative.json'
        self.events(code=7).rename(events)
        output = self.root / 'retained-expected'
        self.assertEqual(ci_reports.retain(events, output), 0)
        self.assertEqual(json.loads((output / 'invocation.json').read_text())['expected'], 'failure')

    def test_run_result_does_not_claim_program_success_from_build_events(self):
        events = self.events()
        events.write_text(json.dumps({'started': {'command': 'run'}}) + '\n' + events.read_text())
        output = self.root / 'run'
        self.assertEqual(ci_reports.retain(events, output), 0)
        text, failed = ci_reports.summarize(self.root)
        self.assertFalse(failed)
        self.assertIn('build passed; program exit reported by CI', text)

    def test_retains_original_exit_and_expectation(self):
        output = self.root / 'retained'
        self.assertEqual(ci_reports.retain(self.events(code=7), output, 'failure'), 0)
        invocation = json.loads((output / 'invocation.json').read_text())
        self.assertEqual(invocation['exit_code'], 7)
        self.assertEqual(invocation['expected'], 'failure')

    @unittest.skipUnless(os.name == 'posix', 'POSIX executable fixture')
    def test_tools_consumer_exposes_unexpected_negative_analysis_diagnostics(self):
        fake = self.root / 'bazel'
        fake.write_text('#!/usr/bin/env bash\n'
                        'case "$1" in\n'
                        '  --version) echo "bazel 9.1.1" ;;\n'
                        '  build) echo "UNEXPECTED_ANALYSIS_CAUSE"; exit 1 ;;\n'
                        'esac\n')
        fake.chmod(0o755)
        environment = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ['PATH'])
        environment.pop('BASHTEST_CI_REPORTS', None)
        result = subprocess.run(['bash', str(ROOT / 'bashtest/tests/tools_consumer_test.sh')],
                                env=environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn('[UNEXPECTED CONSUMER FAILURE: invalid.log]', result.stderr)
        self.assertIn('UNEXPECTED_ANALYSIS_CAUSE', result.stderr)

    @unittest.skipUnless(os.name == 'posix', 'POSIX executable fixture')
    def test_consumer_preserves_direct_bazel_failure_while_collecting_in_cleanup(self):
        fake = self.root / 'bazel'
        fake.write_text('#!/usr/bin/env bash\n'
                        'case "$1" in\n'
                        '  --version) echo "bazel 9.1.1" ;;\n'
                        '  test) echo "ORIGINAL_TEST_FAILURE"; exit 7 ;;\n'
                        '  run) printf "%s\\n" "$*" >> "$COLLECTION_CALLS" ;;\n'
                        'esac\n')
        fake.chmod(0o755)
        calls = self.root / 'collection-calls'
        environment = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ['PATH'],
                           BASHTEST_CI_REPORTS=str(self.root / 'artifact'), COLLECTION_CALLS=str(calls))
        result = subprocess.run(['bash', str(ROOT / 'bashtest/tests/tools_consumer_test.sh')],
                                env=environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertIn('ORIGINAL_TEST_FAILURE', result.stdout)
        self.assertIn('finalize', calls.read_text())

    @unittest.skipUnless(os.name == 'posix', 'Bash consumer helper')
    def test_consumer_cleanup_prints_hidden_logs_only_on_unexpected_failure(self):
        (self.root / 'negative.log').write_text('analysis failed for unexpected reason')
        command = f'source "{ROOT}/bashtest/tests/ci_support.sh"; ci_failure_logs "$STATUS" "$LOGS"'
        for status in ('0', '1'):
            result = subprocess.run(['bash', '-c', command], env=dict(os.environ, STATUS=status, LOGS=str(self.root)),
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0)
            self.assertEqual('analysis failed for unexpected reason' in result.stderr, status == '1')


if __name__ == '__main__':
    unittest.main()
