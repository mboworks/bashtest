# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""Observable CI report collection, exit status, and safe rendering contracts."""

import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import ci_reports


ROOT = Path(__file__).resolve().parents[1]


class CiReportsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='ci reports ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def events(self, *outputs):
        events = self.root / 'events.json'
        events.write_text(''.join(json.dumps({'id': {'testResult': {'label': '//:fixture', 'shard': i + 1}},
                                            'testResult': {'status': 'FAILED', 'testActionOutput': output}}) + '\n'
                                  for i, output in enumerate(outputs)))
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
        self.assertIn('4 / 1 / 1 / 1', text)
        self.assertIn('expected failure', text)
        self.assertNotIn('<script>', text)
        self.assertIn('&lt;/pre&gt;', text)
        self.assertIn('shard 2, attempt 3', text)

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

    def test_runner_preserves_nonzero_exit_and_logs(self):
        fake = self.root / 'fake_bazel.py'
        fake.write_text("import pathlib,sys\n"
                        "pathlib.Path(sys.argv[2].split('=',1)[1]).write_text('')\n"
                        "print('last diagnostic', flush=True)\n"
                        "sys.exit(7)\n")
        output = self.root / 'status-seven'
        original = subprocess.Popen
        def start(command, **kwargs):
            return original([sys.executable, str(fake), *command[1:]], **kwargs)
        with mock.patch.object(ci_reports.subprocess, 'Popen', side_effect=start), \
                mock.patch.object(sys, 'stdout', mock.Mock(buffer=io.BytesIO())):
            status = ci_reports.run(output, 'failure', ['bazel', 'test', '//:fixture'])
        self.assertEqual(status, 7)
        self.assertIn('last diagnostic', (output / 'command.log').read_text())
        self.assertEqual(json.loads((output / 'invocation.json').read_text())['exit_code'], 7)

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
