# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""Run CI Bazel commands, retain their exact results, and summarize local JUnit XML."""

import argparse
import html
import json
from pathlib import Path
import shutil
import subprocess
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


def run(output, expected, command):
    output.mkdir(parents=True, exist_ok=False)
    events = output.resolve() / 'events.json'
    executable = shutil.which(command[0]) or command[0]
    command = [executable, command[1], f'--build_event_json_file={events}', *command[2:]]
    status = 1
    errors = []
    try:
        with (output / 'command.log').open('wb') as log:
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            with process.stdout:
                while chunk := process.stdout.read1(65536):
                    log.write(chunk)
                    log.flush()
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.buffer.flush()
            status = process.wait()
    except OSError as error:
        errors.append(str(error))
    results, collection_errors = collect(events, output)
    errors.extend(collection_errors)
    (output / 'invocation.json').write_text(json.dumps({
        'command': command, 'exit_code': status, 'expected': expected,
        'results': results, 'errors': errors,
    }, indent=2) + '\n', encoding='utf-8')
    for error in errors:
        print(f'CI result collection: {error}', file=sys.stderr)
    return status if status else int(bool(errors))


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
    lines = ['## Bazel test results', '',
             'Each row is one invocation. Shards and retry attempts are retained separately; '
             'counts include every reported attempt. Expected failures are checked by the consumer scripts.', '',
             '<table><tr><th>Invocation</th><th>Command</th><th>Tests / failures / errors / skipped</th></tr>']
    details, problems = [], []
    manifests = sorted(directory.glob('*/invocation.json'))
    for index, manifest in enumerate(manifests):
        invocation = json.loads(manifest.read_text(encoding='utf-8'))
        expected = invocation['expected']
        code = invocation['exit_code']
        matched = (code == 0) == (expected == 'success')
        outcome = ('passed' if code == 0 else 'expected failure') if matched else ('UNEXPECTED PASS' if code == 0 else 'FAILED')
        if not matched:
            problems.append(f'{manifest.parent.name}: unexpected command exit {code}')
        problems.extend(invocation['errors'])
        totals = [0, 0, 0, 0]
        reports = 0
        for result in invocation['results']:
            for name in result['files']:
                if not name.endswith('/test.xml'):
                    continue
                try:
                    values, messages = counts(manifest.parent / name)
                    if values is not None:
                        totals = [a + b for a, b in zip(totals, values)]
                        reports += 1
                    for message in messages:
                        if len(details) < 20:
                            details.append(f"{manifest.parent.name} / {result['label'][:200]} "
                                           f"(run {result['run']}, shard {result['shard']}, attempt {result['attempt']}): {message}")
                except (OSError, ValueError, ET.ParseError) as error:
                    problems.append(f'{manifest.parent.name}/{name}: invalid JUnit: {error}')
        count_text = ' / '.join(map(str, totals)) if reports else 'No summarized XML'
        if index < 200:
            lines.append('<tr>' + ''.join(f'<td>{html.escape(value)}</td>' for value in
                                         (manifest.parent.name[:200], f'{outcome} (exit {code}, expected {expected})', count_text)) + '</tr>')
    lines.extend(['</table>', '', f'{len(manifests)} invocations retained. Download the test-results artifact for full logs, XML, and build events.'])
    if details:
        lines.extend(['', 'Failure/error diagnostics (limited to 20 excerpts):', '',
                      '<pre>' + html.escape('\n\n'.join(details)) + '</pre>'])
    if problems:
        lines.extend(['', 'Reporting/command problems:', '',
                      '<pre>' + html.escape('\n'.join(problems)[:8000]) + '</pre>'])
    if not manifests:
        lines.extend(['', 'No recorded invocations; a prerequisite may have failed.'])
    return '\n'.join(lines) + '\n', bool(problems)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='action', required=True)
    runner = commands.add_parser('run')
    runner.add_argument('--output', type=Path, required=True)
    runner.add_argument('--expect', choices=('success', 'failure'), default='success')
    runner.add_argument('command', nargs=argparse.REMAINDER)
    summary = commands.add_parser('summary')
    summary.add_argument('directory', type=Path)
    summary.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.action == 'run':
        command = args.command[1:] if args.command[:1] == ['--'] else args.command
        if len(command) < 2 or command[1] not in ('test', 'build', 'run'):
            parser.error('run requires a Bazel test, build, or run command after --')
        return run(args.output, args.expect, command)
    text, failed = summarize(args.directory)
    with args.output.open('a', encoding='utf-8') as stream:
        stream.write(text)
    return int(failed)


if __name__ == '__main__':
    sys.exit(main())
