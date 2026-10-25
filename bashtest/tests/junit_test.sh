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

# shellcheck disable=SC2317 # Functions are discovered by test_runner.
test::failures_cannot_become_skips_or_negative_matches() {
    local root report probe output status expected
    root="$(test_tmpdir classification)"
    report="${root}/result.xml"
    cat > "${root}/probe.sh" <<'PROBE'
set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"
test::a_pass() { :; }
test::b_probe() {
    case "${PROBE}" in
        assertion_skip) expect_eq yes no; skip_test 'later skip' ;;
        return_skip) skip_test 'later skip'; return 7 ;;
        invalid_positive) expect_matches '[' text; return 0 ;;
        invalid_negative) expect_not_matches '[' text; return 0 ;;
        substitution) local captured; captured="$(expect_eq yes no)"; return 0 ;;
        subshell) (expect_eq yes no); return 0 ;;
        background) expect_eq yes no & wait; return 0 ;;
        valid_negative) expect_not_matches needle haystack ;;
    esac
}
test_runner
PROBE
    for probe in assertion_skip return_skip invalid_positive invalid_negative substitution subshell background valid_negative; do
        status=0
        expected=1
        [[ "${probe}" != valid_negative ]] || expected=0
        output="$(env PROBE="${probe}" GTEST_OUTPUT="xml:${report}" "${BASH}" \
            "${root}/probe.sh" --keep-tmpdir=never 2>&1)" || status="${?}"
        expect_eq "${expected}" "${status}"
        case "${probe}" in
            invalid_*) expect_output_contains 'Invalid extended regular expression' "${output}" ;;
        esac
        output="$(cat "${report}")"
        expect_output_contains "tests=\"2\" failures=\"${expected}\" errors=\"0\" skipped=\"0\"" "${output}"
    done
}

# shellcheck disable=SC2317 # Functions are discovered by test_runner.
test::strict_commands_and_exit_assertions() {
    local root report probe output status expected
    root="$(test_tmpdir strict)"
    report="${root}/result.xml"
    cat > "${root}/probe.sh" <<'PROBE'
set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"
state=initial
test::test_init() { state=setup; }
test::a_probe() {
    expect_eq setup "${state}"
    state=changed
    case "${PROBE}" in
        command) false; echo after ;;
        substitution) local captured; captured="$(false; echo after)" ;;
        pipeline) false | true; echo after ;;
        handled)
            if false; then return 9; fi
            false || :
            ! false
            expect_exit_code 3 "${BASH}" -c 'exit 3'
            expect_success printf '%s\n' 'argument with spaces'
            ;;
    esac
    return 0
}
test::b_state() { expect_eq changed "${state}"; }
test_runner
PROBE
    for probe in command substitution pipeline handled; do
        status=0
        expected=1
        [[ "${probe}" != handled ]] || expected=0
        output="$(env PROBE="${probe}" GTEST_OUTPUT="xml:${report}" "${BASH}" \
            "${root}/probe.sh" --strict-commands --keep-tmpdir=never 2>&1)" || status="${?}"
        expect_eq "${expected}" "${status}"
        expect_output_contains '[  PASS  ] b_state' "${output}"
        if [[ "${expected}" == 1 ]]; then
            expect_output_contains 'Unhandled command failure' "${output}"
        fi
        output="$(cat "${report}")"
        expect_output_contains "tests=\"2\" failures=\"${expected}\" errors=\"0\" skipped=\"0\"" "${output}"
    done
    sed 's/^test_runner$/if test_runner; then exit 9; else exit 1; fi/' "${root}/probe.sh" > "${root}/conditional.sh"
    status=0
    output="$(env PROBE=handled GTEST_OUTPUT="xml:${report}" "${BASH}" \
        "${root}/conditional.sh" --strict-commands --keep-tmpdir=never 2>&1)" || status="${?}"
    expect_eq 1 "${status}"
    expect_output_contains 'requires a standalone test_runner' "${output}"
    output="$(cat "${report}")"
    expect_output_contains 'name="test_runner"' "${output}"
    expect_output_contains 'errors="1"' "${output}"
}

test_runner
