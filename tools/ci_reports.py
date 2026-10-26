# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""Retain exact Bazel invocation results and summarize local JUnit XML."""

import argparse
import html
import json
from pathlib import Path
import shutil
import sys
from urllib.parse import urlsplit
from urllib.request import url2pathname
import xml.etree.ElementTree as ET


MAX_XML_BYTES = 8 * 1024 * 1024


def collect(events, destination):
    """Copy only this invocation's BEP test outputs, including shards and retries."""
    results, errors = [], []
    try:
        with events.open(encoding='utf-8') as stream:
            for line in stream:
                event = json.loads(line)
                if 'testResult' not in event:
                    continue
                identity = event['id']['testResult']
                result = {'label': identity['label'], 'run': identity.get('run', 1),
                          'shard': identity.get('shard', 1), 'attempt': identity.get('attempt', 1),
                          'status': event['testResult'].get('status', 'UNKNOWN'), 'files': []}
                folder = destination / f'result_{len(results) + 1:04d}'
                results.append(result)
                for output in event['testResult'].get('testActionOutput', []):
                    if output.get('name') not in ('test.log', 'test.xml'):
                        continue
                    uri = urlsplit(output.get('uri', ''))
                    if uri.scheme != 'file' or uri.netloc not in ('', 'localhost'):
                        errors.append(f"Unavailable local output for {identity['label']}: {output['name']}")
                        continue
                    folder.mkdir(parents=True, exist_ok=True)
                    target = folder / output['name']
                    try:
                        shutil.copyfile(Path(url2pathname(uri.path)), target)
                        result['files'].append(target.relative_to(destination).as_posix())
                    except OSError as error:
                        errors.append(str(error))
    except (OSError, ValueError, KeyError) as error:
        errors.append(f'Cannot read build events: {error}')
    return results, errors


def retain(events, output, expected=None):
    output.mkdir(parents=True, exist_ok=True)
    results, errors = collect(events, output)
    status = None
    command = None
    try:
        for line in events.read_text(encoding='utf-8').splitlines():
            event = json.loads(line)
            command = event.get('started', {}).get('command', command)
            finished = event.get('finished', {})
            if 'exitCode' in finished:
                status = finished['exitCode'].get('code', 0)
        if events.resolve() != (output / 'events.json').resolve():
            shutil.copyfile(events, output / 'events.json')
    except (OSError, ValueError) as error:
        errors.append(str(error))
    if status is None:
        errors.append('Build events have no confirmed command exit status')
        status = 1
    expected = expected or ('failure' if events.parent.name == 'expected' else 'success')
    (output / 'invocation.json').write_text(json.dumps({
        'exit_code': status, 'expected': expected, 'command': command, 'results': results, 'errors': errors,
    }, indent=2) + '\n', encoding='utf-8')
    for error in errors:
        print(f'CI result collection: {error}', file=sys.stderr)
    return int(bool(errors))


def finalize(events_directory, destination):
    failed = False
    events_files = sorted(events_directory.glob('*.json')) + sorted((events_directory / 'expected').glob('*.json'))
    for events in events_files:
        output = destination / events.stem
        # Earlier snapshots must survive later commands overwriting their source.
        if (output / 'invocation.json').exists():
            continue
        failed = bool(retain(events, output)) or failed
    return failed


class SummaryTreeBuilder(ET.TreeBuilder):
    def doctype(self, name, pubid, system):
        raise ValueError('DTD/entity declarations are not supported')


def counts(path):
    if path.stat().st_size > MAX_XML_BYTES:
        return None, ['XML exceeds the summary size limit; see the artifact.']
    data = path.read_bytes()
    root = ET.fromstring(data, parser=ET.XMLParser(target=SummaryTreeBuilder()))
    if root.tag not in ('testsuites', 'testsuite'):
        raise ValueError('Expected a JUnit testsuite or testsuites root')
    cases = list(root.iter('testcase'))
    totals = [len(cases), 0, 0, 0]
    details = []
    for case in cases:
        for index, kind in enumerate(('failure', 'error', 'skipped'), 1):
            node = case.find(kind)
            if node is not None:
                totals[index] += 1
                if kind != 'skipped' and len(details) < 3:
                    details.append(f"{case.get('name', '?')[:200]}: "
                                   f"{node.get('message', '')[:400]} {(node.text or '')[:800]}")
    return totals, details


def summarize(directory):
    sections = {'Tests': [], 'Expected-failure checks': [], 'Builds': []}
    details, expected_details, problems = [], [], []
    manifests = sorted(directory.glob('*/invocation.json'))
    for index, manifest in enumerate(manifests):
        invocation = json.loads(manifest.read_text(encoding='utf-8'))
        negative = invocation['expected'] == 'failure'
        code = invocation['exit_code']
        matched = (code != 0) if negative else (code == 0)
        invocation_problems = list(invocation['errors'])
        if not matched:
            invocation_problems.append(f'unexpected command exit {code}')
        totals = [0, 0, 0, 0]
        reports = 0
        messages = []
        # Earlier failed retries remain in the artifact; only the final attempt
        # for each run/shard contributes to the displayed outcome and case counts.
        attempts = {}
        for result in invocation['results']:
            key = (result['label'], result['run'], result['shard'])
            if key not in attempts or result['attempt'] > attempts[key]['attempt']:
                attempts[key] = result
        for result in attempts.values():
            if not negative and result.get('status', 'PASSED') not in ('PASSED', 'FLAKY'):
                invocation_problems.append(f"{result['label']}: Bazel test status {result['status']}")
            for name in result['files']:
                if not name.endswith('/test.xml'):
                    continue
                try:
                    values, excerpts = counts(manifest.parent / name)
                    if values is not None:
                        totals = [a + b for a, b in zip(totals, values)]
                        reports += 1
                        if not negative and (values[1] or values[2]):
                            invocation_problems.append(f'{name}: unexpected JUnit failures/errors')
                    for message in excerpts:
                        if len(messages) < 20:
                            messages.append(f"{manifest.parent.name} / {result['label'][:200]} "
                                            f"(run {result['run']}, shard {result['shard']}, attempt {result['attempt']}): {message}")
                except (OSError, ValueError, ET.ParseError) as error:
                    invocation_problems.append(f'{name}: invalid JUnit: {error}')
        problems.extend(f'{manifest.parent.name}: {problem}' for problem in invocation_problems)
        if negative and matched and not invocation_problems:
            expected_details.extend(messages)
        else:
            details.extend(messages)
        outcome = 'FAILED' if invocation_problems else 'Passed'
        if negative:
            section = 'Expected-failure checks'
            outcome = 'FAILED' if invocation_problems else f'Expected nonzero exit observed ({code})'
            cells = (manifest.parent.name[:200], outcome)
        elif invocation.get('command') in ('run', 'build'):
            section = 'Builds'
            if invocation.get('command') == 'run':
                outcome = 'build ' + outcome.lower() + '; program exit reported by CI'
            cells = (manifest.parent.name[:200], outcome)
        else:
            section = 'Tests'
            cells = (manifest.parent.name[:200], outcome, *map(str, totals)) if reports else (
                manifest.parent.name[:200], outcome, 'Unavailable', '—', '—', '—')
        if index < 200:
            sections[section].append('<tr>' + ''.join(f'<td>{html.escape(value)}</td>' for value in cells) + '</tr>')
    lines = ['## Bazel test results', '',
             'Unexpected results or reporting problems detected.' if problems else
             'No unexpected results in the recorded build/test reports.', '',
             'Case counts use the final attempt of each run/shard. All attempts remain in the artifact. '
             'CI steps determine overall success, including consumer assertions and bazel run program exits.']
    for section, rows in sections.items():
        if not rows:
            continue
        lines.extend(['', f'### {section}', ''])
        if section == 'Expected-failure checks':
            lines.extend(['These fixtures deliberately fail to exercise failure XML, fail-fast, timeouts, '
                          'and invalid tool declarations. Their failures/errors are expected fixture output, '
                          'excluded from the test table. Consumer scripts check the precise behavior; '
                          'the rows below report the observed command exit.', ''])
        columns = ('Invocation', 'Outcome', 'Cases', 'Failures', 'Errors', 'Skipped') if section == 'Tests' else ('Invocation', 'Outcome')
        lines.append('<table><tr>' + ''.join(f'<th>{column}</th>' for column in columns) + '</tr>')
        lines.extend(rows)
        lines.append('</table>')
    lines.extend(['', f'{len(manifests)} invocations retained. Download the test-results artifact for full logs, XML, and build events.'])
    if details:
        lines.extend(['', 'Test diagnostics (limited to 20 excerpts):', '',
                      '<pre>' + html.escape('\n\n'.join(details[:20])) + '</pre>'])
    if expected_details:
        lines.extend(['', '<details><summary>Expected fixture diagnostics (intentional failures; limited to 20 excerpts)</summary>', '',
                      '<pre>' + html.escape('\n\n'.join(expected_details[:20])) + '</pre>', '', '</details>'])
    if problems:
        lines.extend(['', 'Unexpected test/command results or reporting problems:', '',
                      '<pre>' + html.escape('\n'.join(problems)[:8000]) + '</pre>'])
    if not manifests:
        lines.extend(['', 'No recorded invocations; a prerequisite may have failed.'])
    return '\n'.join(lines) + '\n', bool(problems)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='action', required=True)
    collector = commands.add_parser('collect')
    collector.add_argument('--events', type=Path, required=True)
    collector.add_argument('--output', type=Path, required=True)
    collector.add_argument('--expect', choices=('success', 'failure'))
    finalizer = commands.add_parser('finalize')
    finalizer.add_argument('directory', type=Path)
    finalizer.add_argument('--destination', type=Path, required=True)
    finalizer.add_argument('--output', type=Path)
    summary = commands.add_parser('summary')
    summary.add_argument('directory', type=Path)
    summary.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.action == 'collect':
        return retain(args.events, args.output, args.expect)
    failed = False
    if args.action == 'finalize':
        failed = finalize(args.directory, args.destination)
        if args.output is None:
            return int(failed)
    directory = args.destination if args.action == 'finalize' else args.directory
    text, summary_failed = summarize(directory)
    failed = summary_failed or failed
    with args.output.open('a', encoding='utf-8') as stream:
        stream.write(text)
    return int(failed)


if __name__ == '__main__':
    sys.exit(main())
