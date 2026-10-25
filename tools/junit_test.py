# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""Parse actual runner reports and verify JUnit/GoogleTest output contracts."""

import os
import selectors
import signal
import time
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

    def run_probe(self, body, *args, output=True, runner='test_runner', background=False, **environment):
        script = self.root / 'probe.sh'
        script.write_text('set -euo pipefail\nsource "$LIBRARY"\n' + body + '\n' + runner + '\n')
        env = {key: value for key, value in os.environ.items()
               if key not in ('GTEST_OUTPUT', 'XML_OUTPUT_FILE', 'TEST_TARGET',
                               'TESTBRIDGE_TEST_ONLY', 'TESTBRIDGE_TEST_RUNNER_FAIL_FAST',
                               'TEST_TOTAL_SHARDS', 'TEST_SHARD_INDEX', 'TEST_SHARD_STATUS_FILE')}
        env.update(LIBRARY=str(ROOT / 'bashtest/bashtest.sh'), TEST_TMPDIR=str(self.root))
        if output:
            env['XML_OUTPUT_FILE'] = str(self.xml)
        env.update(environment)
        if background:
            return subprocess.Popen(['bash', str(script), *args], cwd=self.root, env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
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

    def test_assertions_in_subshells_cannot_disappear(self):
        for output in (True, False):
            for command in ('local captured; captured="$(expect_eq yes no)"',
                            '(expect_eq yes no)', 'expect_eq yes no & wait'):
                with self.subTest(output=output, command=command):
                    result = self.run_probe(f'''
test::a_failure() {{ {command}; if test_has_error; then echo failure_observed; fi; return 0; }}
test::b_after() {{ test_has_error && return 8; expect_eq ok ok; }}
''', output=output)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertIn(b'[  FAIL  ] a_failure', result.stderr)
                    self.assertIn(b'failure_observed', result.stdout)
                    self.assertIn(b'[  PASS  ] b_after', result.stdout)
                    if output:
                        cases = self.report()
                        self.assertIsNotNone(cases['a_failure'].find('failure'))
                        self.assertIsNone(cases['b_after'].find('failure'))

    def test_hook_subshell_assertions_are_errors(self):
        for hook in ('test_init', 'test_done'):
            result = self.run_probe(f'test::{hook}() {{ local result; result="$(expect_eq yes no)"; return 0; }}\n'
                                    'test::body() { :; }')
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIsNotNone(self.report()[hook].find('error'))

    def test_strict_commands_detect_unhandled_failures(self):
        commands = ('false; echo after', 'local result; result="$(false; echo after)"',
                    '(false; echo after)', 'false | true; echo after')
        for output in (True, False):
            for command in commands:
                with self.subTest(command=command, output=output):
                    result = self.run_probe(f'test::bad() {{ {command}; return 0; }}',
                                            '--strict-commands', output=output)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertIn(b'Unhandled command failure', result.stderr)
                    if output:
                        self.assertIsNotNone(self.report()['bad'].find('failure'))

    def test_strict_commands_allow_handled_statuses_and_preserve_state(self):
        result = self.run_probe('''
state=initial
test::test_init() { state=setup; }
test::a_handled() {
    if false; then return 9; fi
    false || :
    ! false
    expect_exit_code 3 "$BASH" -c 'exit 3'
    expect_success echo 'argument with spaces'
    expect_eq setup "$state"
    state=changed
}
test::b_state() { expect_eq changed "$state"; }
''', '--strict_commands')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(b'Unhandled command failure', result.stderr)
        self.assertIn(b'argument with spaces', result.stdout)

    def test_strict_commands_reject_conditional_runner_calls(self):
        for runner in ('if test_runner; then exit 9; else exit 1; fi',
                       'test_runner || exit 1'):
            result = self.run_probe('test::body() { echo should_not_run; }',
                                    '--strict-commands', runner=runner)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn(b'requires a standalone test_runner', result.stderr)
            self.assertNotIn(b'should_not_run', result.stdout)
            self.assertIsNotNone(self.report()['test_runner'].find('error'))

    def test_strict_mode_restores_caller_error_trap_and_shell_options(self):
        result = self.run_probe('''
trap 'echo original_error_trap' ERR
before_options="$-"
test::body() { expect_eq ok ok; }
''', '--strict-commands', runner='test_runner\n'
                                '[[ "$-" == "$before_options" ]]\ntrap -p ERR')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(b'original_error_trap', result.stdout)

    def test_command_assertions_work_without_strict_mode(self):
        result = self.run_probe('''
state=initial
helper() { state=changed; return 3; }
test::commands() { expect_exit_code 3 helper; expect_eq changed "$state"; expect_success true; }
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        for command in ('expect_success false', 'expect_exit_code 2 true',
                        'expect_exit_code invalid false', 'expect_success'):
            result = self.run_probe(f'test::bad() {{ {command}; return 0; }}')
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIsNotNone(self.report()['bad'].find('failure'))

    def test_failed_expectations_report_the_assertion_source_line(self):
        for command in ('expect_eq yes no', 'expect_ne same same', 'expect_success false',
                        'expect_exit_code 2 true', 'expect_matches "[" text',
                        'expect_not_matches "[" text'):
            for output in (True, False):
                with self.subTest(command=command, output=output):
                    result = self.run_probe(f'test::body() {{\n    {command}\n    return 0\n}}', output=output)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    script = self.root / 'probe.sh'
                    line = script.read_text().splitlines().index(f'    {command}') + 1
                    location = f'{script}:{line}: test failure'
                    self.assertIn(location.encode(), result.stderr)
                    self.assertNotIn(location.encode(), result.stdout)
                    if output:
                        self.assertIn(location, self.report()['body'].find('failure').text)
        helper = self.root / 'assertion helper with spaces.sh'
        helper.write_text('helper() {\n    expect_eq yes no\n}\n')
        result = self.run_probe('source "$HELPER"\ntest::wrapped() { helper; }', HELPER=str(helper))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(f'{helper}:2: test failure'.encode(), result.stderr)
        self.assertIn(f'{helper}:2: test failure', self.report()['wrapped'].find('failure').text)

    def test_subshell_assertions_keep_their_source_location(self):
        for command in ('(expect_eq yes no)', 'local value; value="$(expect_eq yes no)"'):
            result = self.run_probe(f'test::body() {{\n    {command}\n    return 0\n}}')
            self.assertEqual(result.returncode, 1, result.stderr)
            script = self.root / 'probe.sh'
            line = script.read_text().splitlines().index(f'    {command}') + 1
            self.assertIn(f'{script}:{line}: test failure', self.report()['body'].find('failure').text)

    def test_golden_diff_is_in_stderr_and_xml_without_verbose(self):
        golden = self.root / 'golden with spaces.txt'
        actual = self.root / 'actual with spaces.txt'
        golden.write_text('old <value> & text\n')
        actual.write_text('new <value> & text\n')
        for args in ((), ('--verbose',)):
            result = self.run_probe('test::golden() { expect_files_eq "$GOLDEN" "$ACTUAL"; }',
                                    *args, GOLDEN=str(golden), ACTUAL=str(actual))
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn(b'-old <value> & text', result.stderr)
            self.assertEqual(result.stderr.count(b'+new <value> & text'), 1)
            self.assertNotIn(b'+new <value> & text', result.stdout)
            case = self.report()['golden']
            self.assertIn('-old <value> & text', case.find('failure').text)
            self.assertIn('+new <value> & text', case.find('system-err').text)
            self.assertIn('+new <value> & text', Path(str(actual) + '.diff').read_text())

    def observe_live_output(self, process):
        captured = {'stdout': b'', 'stderr': b''}
        deadline = time.monotonic() + 5
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ, 'stdout')
            selector.register(process.stderr, selectors.EVENT_READ, 'stderr')
            while time.monotonic() < deadline:
                for key, _ in selector.select(timeout=0.1):
                    chunk = os.read(key.fd, 65536)
                    if chunk:
                        captured[key.data] += chunk
                    else:
                        selector.unregister(key.fileobj)
                if b'live_stdout_token' in captured['stdout'] and b'live_stderr_token' in captured['stderr']:
                    return captured
                if process.poll() is not None:
                    break
        self.fail(f'Output was not live: {captured}; process status={process.poll()}')

    def stop_probe(self, process):
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.communicate(timeout=5)

    @unittest.skipUnless(os.name == 'posix', 'requires POSIX pipe selectors and process groups')
    def test_output_is_live_and_provisional_report_becomes_final(self):
        release = self.root / 'release'
        process = self.run_probe('''
state=initial
test::test_init() { state=setup; }
test::a_live() {
    wait
    if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )); then
        local status=0
        wait -n || status=$?
        expect_eq 127 "$status"
    fi
    expect_eq setup "$state"
    state=changed
    printf '%s' live_stdout_token
    printf '%s' live_stderr_token >&2
    while [[ ! -e "$RELEASE" ]]; do sleep 0.02; done
}
test::b_after() { expect_eq changed "$state"; }
''', background=True, RELEASE=str(release))
        self.addCleanup(self.stop_probe, process)
        captured = self.observe_live_output(process)
        self.assertIsNone(process.poll())
        provisional = self.report()
        self.assertEqual(set(provisional), {'a_live'})
        self.assertIn('provisional', provisional['a_live'].find('error').attrib['message'])
        release.touch()
        out, err = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0, captured['stderr'] + err)
        self.assertEqual((captured['stdout'] + out).count(b'live_stdout_token'), 1)
        self.assertEqual((captured['stderr'] + err).count(b'live_stderr_token'), 1)
        final = self.report()
        self.assertEqual(set(final), {'a_live', 'b_after'})
        self.assertIsNone(final['a_live'].find('error'))
        self.assertIn('live_stdout_token', final['a_live'].find('system-out').text)
        self.assertIn('live_stderr_token', final['a_live'].find('system-err').text)

    @unittest.skipUnless(os.name == 'posix', 'requires POSIX pipe selectors and process groups')
    def test_sigkill_leaves_active_case_error_and_live_diagnostics(self):
        for active in ('b_hanging', 'test_init', 'test_done'):
            with self.subTest(active=active):
                process = self.run_probe(f'''
test::a_done() {{ :; }}
test::{active}() {{
    echo live_stdout_token
    echo live_stderr_token >&2
    while :; do sleep 1; done
}}
''', background=True)
                self.addCleanup(self.stop_probe, process)
                captured = self.observe_live_output(process)
                self.assertIsNone(process.poll())
                os.kill(process.pid, signal.SIGKILL)
                process.communicate(timeout=5)
                self.assertEqual(process.returncode, -signal.SIGKILL)
                cases = self.report()
                expected = {active} if active == 'test_init' else {'a_done', active}
                self.assertEqual(set(cases), expected)
                if active != 'test_init':
                    self.assertIsNone(cases['a_done'].find('error'))
                self.assertIn('completion was not recorded', cases[active].find('error').attrib['message'])
                self.assertIn(b'live_stdout_token', captured['stdout'])
                self.assertIn(b'live_stderr_token', captured['stderr'])

    @unittest.skipUnless(os.name == 'posix', 'requires POSIX process-group cleanup')
    def test_setup_service_can_keep_logging_until_teardown(self):
        ready = self.root / 'service ready'
        process = self.run_probe('''
test::test_init() {
    "$BASH" -c 'echo service_started; : > "$READY"; exec sleep 30' &
    service_pid=$!
    while [[ ! -e "$READY" ]]; do sleep 0.02; done
}
test::a_alive() { kill -0 "$service_pid"; }
test::b_alive() { kill -0 "$service_pid"; }
test::test_done() { kill "$service_pid"; wait "$service_pid" || :; }
''', background=True, READY=str(ready))
        self.addCleanup(self.stop_probe, process)
        out, err = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0, err)
        self.assertEqual(out.count(b'service_started'), 1)
        cases = self.report()
        self.assertEqual(set(cases), {'a_alive', 'b_alive'})
        self.assertTrue(all(case.find('error') is None for case in cases.values()))

    def test_large_output_is_exact_when_sigpipe_is_ignored(self):
        payload = (b'x' * 127 + b'\n') * 16384
        path = self.root / 'large output'
        path.write_bytes(payload)
        result = self.run_probe("trap '' PIPE\ntest::large() { cat \"$PAYLOAD\"; }", PAYLOAD=str(path))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count(b'x' * 127 + b'\n'), 16384)
        self.assertNotIn(b'Broken pipe', result.stderr)
        self.assertEqual(self.report()['large'].find('system-out').text, payload.decode())

    def test_capture_worker_failure_is_a_reported_error(self):
        tools = self.root / 'fake bin'
        tools.mkdir()
        head = tools / 'head'
        head.write_text('#!/usr/bin/env bash\ncat > /dev/null\nexit 3\n')
        head.chmod(0o755)
        result = self.run_probe('PATH="$FAKE_BIN:$PATH"\ntest::body() { echo payload; }', FAKE_BIN=str(tools))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(b'Cannot capture test output completely', result.stderr)
        self.assertIn(b'head=3', result.stderr)
        self.assertIsNotNone(self.report()['body'].find('error'))

    def test_capture_worker_without_acknowledgement_does_not_hang(self):
        # Fault injection: a worker exits before it can publish completion.
        result = self.run_probe('_bashtest_capture_worker() { trap - EXIT; sleep 0.05; return 7; }\n'
                                'test::body() { :; }')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(b'Cannot start test output capture', result.stderr)
        self.assertIsNotNone(self.report()['test_runner'].find('error'))

    def test_progress_report_failure_stops_the_case(self):
        result = self.run_probe('mktemp() { return 1; }\ntest::body() { echo must_not_run; }')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(b'Cannot write JUnit progress report', result.stderr)
        self.assertNotIn(b'must_not_run', result.stdout)
        self.assertIn(b'Preserved test scratch directory:', result.stderr)

    def test_native_bazel_filter_and_explicit_override(self):
        body = 'test::alpha() { echo alpha_body; }\ntest::beta() { echo beta_body; }'
        for args, expected in (((), 'alpha'), (('--test_filter=^beta$',), 'beta'),
                               (('--gtest_filter=bet*',), 'beta')):
            result = self.run_probe(body, *args, TESTBRIDGE_TEST_ONLY='^alpha$')
            self.assertEqual(result.returncode, 0, result.stderr)
            cases = self.report()
            self.assertIsNone(cases[expected].find('skipped'))
            self.assertIsNotNone(cases['beta' if expected == 'alpha' else 'alpha'].find('skipped'))
        result = self.run_probe(body, '--test_filter=', TESTBRIDGE_TEST_ONLY='absent')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(case.find('skipped') is None for case in self.report().values()))
        # Preserve the existing union when both explicit filter types are given.
        result = self.run_probe(body, '--test_filter=^alpha$', '--gtest_filter=bet*')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(case.find('skipped') is None for case in self.report().values()))

    def test_invalid_filter_rejected_before_hooks(self):
        result = self.run_probe('test::test_init() { echo must_not_run; }\n'
                                'test::body() { :; }', TESTBRIDGE_TEST_ONLY='[')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(b'Invalid test filter', result.stderr)
        self.assertNotIn(b'must_not_run', result.stdout)
        self.assertIsNotNone(self.report()['test_runner'].find('error'))

    def test_shards_partition_cases_and_allow_empty_shards(self):
        body = ("test::test_init() { echo init_hook; }\n"
                "test::test_done() { echo done_hook; }\n"
                "test::alpha() { :; }\ntest::beta() { :; }\ntest::gamma() { :; }")
        names = []
        for index in range(5):
            with self.subTest(index=index):
                status = self.root / f'shard-{index}'
                result = self.run_probe(body, TEST_TOTAL_SHARDS='5', TEST_SHARD_INDEX=str(index),
                                        TEST_SHARD_STATUS_FILE=str(status))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(status.exists())
                cases = self.report()
                expected = ('alpha', 'beta', 'gamma')[index:index + 1]
                self.assertEqual(list(cases), list(expected))
                names.extend(cases)
                self.assertEqual(b'init_hook' in result.stdout, bool(expected))
                self.assertEqual(b'done_hook' in result.stdout, bool(expected))
        self.assertEqual(names, ['alpha', 'beta', 'gamma'])
        # Partition the full sorted list consistently, then filter within shards.
        result = self.run_probe(body, TEST_TOTAL_SHARDS='2', TEST_SHARD_INDEX='1',
                                TESTBRIDGE_TEST_ONLY='^alpha$')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(list(self.report()), ['beta'])
        self.assertIsNotNone(self.report()['beta'].find('skipped'))
        result = self.run_probe(body, TEST_TOTAL_SHARDS='2', TEST_SHARD_INDEX='1',
                                TESTBRIDGE_TEST_ONLY='absent')
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIsNotNone(self.report()['test_runner'].find('error'))

    def test_invalid_sharding_and_handshake_failures(self):
        for environment in ({'TEST_TOTAL_SHARDS': '0', 'TEST_SHARD_INDEX': '0'},
                            {'TEST_TOTAL_SHARDS': '2', 'TEST_SHARD_INDEX': '-1'},
                            {'TEST_TOTAL_SHARDS': '2', 'TEST_SHARD_INDEX': '2'},
                            {'TEST_TOTAL_SHARDS': 'two', 'TEST_SHARD_INDEX': '0'},
                            {'TEST_TOTAL_SHARDS': '2'}, {'TEST_SHARD_INDEX': '0'},
                            {'TEST_TOTAL_SHARDS': '9999999999999999999999', 'TEST_SHARD_INDEX': '0'}):
            with self.subTest(environment=environment):
                result = self.run_probe('test::body() { echo must_not_run; }', **environment)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn(b'Invalid test shard configuration', result.stderr)
                self.assertNotIn(b'must_not_run', result.stdout)
                self.assertIsNotNone(self.report()['test_runner'].find('error'))
        result = self.run_probe('test::body() { :; }', TEST_TOTAL_SHARDS='1',
                                TEST_SHARD_INDEX='0', TEST_SHARD_STATUS_FILE=str(self.root / 'missing/status'))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(b'Cannot acknowledge test sharding', result.stderr)

    def test_fail_fast_reports_remaining_cases_and_still_runs_teardown(self):
        body = ("test::alpha() { expect_eq yes no; return 0; }\n"
                "test::beta() { echo beta_body; }\ntest::gamma() { :; }\n"
                "test::test_done() { echo done_hook; }")
        for flag in ('1', '0', ''):
            result = self.run_probe(body, TESTBRIDGE_TEST_RUNNER_FAIL_FAST=flag)
            self.assertEqual(result.returncode, 1, result.stderr)
            cases = self.report()
            self.assertIsNotNone(cases['alpha'].find('failure'))
            self.assertIn(b'done_hook', result.stdout)
            if flag == '1':
                self.assertNotIn(b'beta_body', result.stdout)
                self.assertIn('fail-fast', cases['beta'].find('skipped').attrib['message'])
                self.assertIsNotNone(cases['gamma'].find('skipped'))
            else:
                self.assertIn(b'beta_body', result.stdout)
                self.assertIsNone(cases['beta'].find('skipped'))
        result = self.run_probe(body, TESTBRIDGE_TEST_RUNNER_FAIL_FAST='1', TESTBRIDGE_TEST_ONLY='beta')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(self.report()['beta'].find('skipped'))
        result = self.run_probe('test::alpha() { skip_test absent; }\ntest::beta() { :; }',
                                '--no-skip', TESTBRIDGE_TEST_RUNNER_FAIL_FAST='1')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIsNotNone(self.report()['beta'].find('skipped'))

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
        result = self.run_probe('test::pass() { mv "$REPORT_DIRECTORY" "$REPORT_DIRECTORY.moved"; }',
                                f'--gtest_output=xml:{directory}/result.xml',
                                REPORT_DIRECTORY=str(directory))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(b'Cannot write JUnit report', result.stderr)
        self.assertFalse((directory / 'result.xml').exists())

    def test_scratch_retention_modes_and_original_exit_status(self):
        record = self.root / 'scratch.path'
        prefix = 'printf "%s" "$BASHTEST_TMPDIR" > "$SCRATCH_RECORD"\n' \
                 'printf evidence > "$BASHTEST_TMPDIR/evidence"\n'
        for output in (True, False):
            for mode in ('never', 'failure', 'always'):
                for command, status in ((':', 0), ('return 7', 1), ('exit 42', 42)):
                    with self.subTest(output=output, mode=mode, command=command):
                        result = self.run_probe(prefix + f'test::body() {{ {command}; }}',
                                                f'--keep-tmpdir={mode}', output=output,
                                                SCRATCH_RECORD=str(record))
                        self.assertEqual(result.returncode, status, result.stderr)
                        scratch = Path(record.read_text())
                        retained = mode == 'always' or (mode == 'failure' and status != 0)
                        self.assertEqual(scratch.exists(), retained)
                        self.assertEqual(b'Preserved test scratch directory:' in result.stderr, retained)
                        if retained:
                            self.assertEqual((scratch / 'evidence').read_text(), 'evidence')

    def test_scratch_retained_for_hooks_aborts_and_invalid_selection(self):
        record = self.root / 'scratch.path'
        prefix = 'printf "%s" "$BASHTEST_TMPDIR" > "$SCRATCH_RECORD"\n'
        for output in (True, False):
            for body, args, status in (
                    ('test::test_init() { return 3; }\ntest::body() { :; }', (), 1),
                    ('test::test_done() { return 3; }\ntest::body() { :; }', (), 1),
                    ('test::body() { exit 0; }', (), 1),
                    ('test::body() { echo "$UNDEFINED_RETENTION_PROBE"; }', (), 1),
                    ('test::body() { kill -TERM $$; }', (), 143),
                    ('test::body() { :; }', ('--test_filter=[',), 1),
                    ('test::body() { :; }', ('--test_filter=absent',), 2)):
                with self.subTest(output=output, body=body, args=args):
                    result = self.run_probe(prefix + body, *args, output=output,
                                            SCRATCH_RECORD=str(record))
                    self.assertEqual(result.returncode, status, result.stderr)
                    self.assertTrue(Path(record.read_text()).is_dir())
                    self.assertIn(b'Preserved test scratch directory:', result.stderr)
        # A conditional caller can handle the runner status, but the diagnostic
        # artifacts must survive even when the program ultimately exits 0.
        result = self.run_probe(prefix + 'test::body() { :; }', '--test_filter=[',
                                output=False, runner='test_runner || :', SCRATCH_RECORD=str(record))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(Path(record.read_text()).is_dir())

    def test_scratch_retained_for_report_write_errors(self):
        record = self.root / 'scratch.path'
        directory = self.root / 'report directory'
        prefix = 'printf "%s" "$BASHTEST_TMPDIR" > "$SCRATCH_RECORD"\n'
        result = self.run_probe(prefix + 'test::body() { mv "$REPORT_DIRECTORY" "$REPORT_DIRECTORY.moved"; }',
                                f'--gtest_output=xml:{directory}/result.xml',
                                SCRATCH_RECORD=str(record), REPORT_DIRECTORY=str(directory))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertTrue(Path(record.read_text()).is_dir())
        self.assertIn(b'Cannot write JUnit report', result.stderr)

    def test_scratch_creation_failure_never_cleans_the_caller_path(self):
        blocked = self.root / 'not a directory'
        blocked.write_text('caller-owned')
        caller = self.root / 'caller scratch'
        caller.mkdir()
        sentinel = caller / 'sentinel'
        sentinel.write_text('preserve me')
        result = self.run_probe('', output=False, TEST_TMPDIR=str(blocked), BASHTEST_TMPDIR=str(caller))
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(b'unbound variable', result.stderr)
        self.assertNotIn(b'Preserved test scratch directory:', result.stderr)
        self.assertEqual(blocked.read_text(), 'caller-owned')
        self.assertEqual(sentinel.read_text(), 'preserve me')

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
