#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"

# shellcheck disable=SC2317 # Functions are discovered by test_runner.
test::junit_cases_and_failures() {
    local root output status=0 report
    root="$(test_tmpdir junit)"
    report="${root}/reports with spaces/result.xml"
    cat > "${root}/probe.sh" <<'PROBE'
set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"
state=initial
test::test_init() { state=setup; }
test::a_pass() { expect_eq setup "${state}"; state=changed; }
test::b_fail() { expect_eq changed "${state}"; expect_eq '<expected & value>' 'actual'; return 0; }
test::c_skip() { skip_test 'missing "dependency"'; }
test::test_done() { expect_eq changed "${state}"; }
test_runner
PROBE
    output="$(env GTEST_OUTPUT="xml:${report}" "${BASH}" "${root}/probe.sh" --keep-tmpdir=never 2>&1)" || status="${?}"
    expect_eq 1 "${status}"
    expect_output_contains 'Some tests failed.' "${output}"
    output="$(cat "${report}")"
    expect_output_contains 'tests="3" failures="1" errors="0" skipped="1"' "${output}"
    expect_output_contains 'name="a_pass"' "${output}"
    expect_output_contains 'name="b_fail"' "${output}"
    expect_output_contains '&lt;expected &amp; value&gt;' "${output}"
    expect_output_contains '<skipped message="missing &quot;dependency&quot;">' "${output}"
}

# shellcheck disable=SC2317 # Functions are discovered by test_runner.
test::junit_aborted_function() {
    local root output status=0 report
    root="$(test_tmpdir abort)"
    report="${root}/aborted.xml"
    cat > "${root}/probe.sh" <<'PROBE'
set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"
test::abort() { echo 'before abort' >&2; exit 7; }
test_runner
PROBE
    output="$(env GTEST_OUTPUT= XML_OUTPUT_FILE="${report}" "${BASH}" "${root}/probe.sh" \
        --gtest_output="xml:${report}" --keep-tmpdir=never 2>&1)" || status="${?}"
    expect_eq 7 "${status}"
    expect_output_contains 'before abort' "${output}"
    output="$(cat "${report}")"
    expect_output_contains 'tests="1" failures="0" errors="1" skipped="0"' "${output}"
    expect_output_contains 'name="abort"' "${output}"
    expect_output_contains 'exit 7' "${output}"
    expect_output_contains '</testsuites>' "${output}"
}

test_runner
