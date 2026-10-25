#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"

# Verifier fixtures select their own cases, independently of the outer test's
# filter/shard/fail-fast settings. Additional env arguments can override these.
_junit_probe() {
    env TEST_TOTAL_SHARDS=1 TEST_SHARD_INDEX=0 TEST_SHARD_STATUS_FILE= \
        TESTBRIDGE_TEST_RUNNER_FAIL_FAST=0 TESTBRIDGE_TEST_ONLY= "${@}"
}

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
    output="$(_junit_probe GTEST_OUTPUT="xml:${report}" "${BASH}" "${root}/probe.sh" --keep-tmpdir=never 2>&1)" || status="${?}"
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
    output="$(_junit_probe GTEST_OUTPUT= XML_OUTPUT_FILE="${report}" "${BASH}" "${root}/probe.sh" \
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
        output="$(_junit_probe PROBE="${probe}" GTEST_OUTPUT="xml:${report}" "${BASH}" \
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
        output="$(_junit_probe PROBE="${probe}" GTEST_OUTPUT="xml:${report}" "${BASH}" \
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
    output="$(_junit_probe PROBE=handled GTEST_OUTPUT="xml:${report}" "${BASH}" \
        "${root}/conditional.sh" --strict-commands --keep-tmpdir=never 2>&1)" || status="${?}"
    expect_eq 1 "${status}"
    expect_output_contains 'requires a standalone test_runner' "${output}"
    output="$(cat "${report}")"
    expect_output_contains 'name="test_runner"' "${output}"
    expect_output_contains 'errors="1"' "${output}"
}

# shellcheck disable=SC2317 # Functions are discovered by test_runner.
test::bazel_selection() {
    local root report output status index name
    root="$(test_tmpdir selection)"
    report="${root}/result.xml"
    cat > "${root}/probe.sh" <<'PROBE'
set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"
test::test_init() { echo INIT; }
test::alpha() { echo CASE:alpha; if [[ "${FAIL_CASE:-}" == alpha ]]; then expect_eq yes no; fi; }
test::beta() { echo CASE:beta; }
test::gamma() { echo CASE:gamma; }
test::test_done() { echo DONE; }
test_runner
PROBE
    local command=(_junit_probe "GTEST_OUTPUT=xml:${report}")
    output="$("${command[@]}" TESTBRIDGE_TEST_ONLY='^alpha$' "${BASH}" "${root}/probe.sh")"
    expect_output_contains 'CASE:alpha' "${output}"
    expect_output_not_contains 'CASE:beta' "${output}"
    output="$("${command[@]}" TESTBRIDGE_TEST_ONLY='^alpha$' "${BASH}" "${root}/probe.sh" --gtest_filter='bet*')"
    expect_output_contains 'CASE:beta' "${output}"
    expect_output_not_contains 'CASE:alpha' "${output}"
    for index in 0 1 2 3 4; do
        output="$("${command[@]}" TEST_TOTAL_SHARDS=5 TEST_SHARD_INDEX="${index}" \
            TEST_SHARD_STATUS_FILE="${root}/status-${index}" "${BASH}" "${root}/probe.sh")"
        expect_success test -f "${root}/status-${index}"
        case "${index}" in
            0) name=alpha ;;
            1) name=beta ;;
            2) name=gamma ;;
            *) name= ;;
        esac
        if [[ -n "${name}" ]]; then
            expect_eq "CASE:${name}" "$(printf '%s\n' "${output}" | grep '^CASE:')"
        else
            expect_output_not_contains 'CASE:' "${output}"
            expect_output_not_contains INIT "${output}"
            expect_output_not_contains DONE "${output}"
            expect_output_contains 'tests="0" failures="0" errors="0"' "$(cat "${report}")"
        fi
    done
    status=0
    output="$("${command[@]}" FAIL_CASE=alpha TESTBRIDGE_TEST_RUNNER_FAIL_FAST=1 \
        "${BASH}" "${root}/probe.sh" 2>&1)" || status="${?}"
    expect_eq 1 "${status}"
    expect_output_contains DONE "${output}"
    expect_output_not_contains 'CASE:beta' "${output}"
    expect_output_not_contains 'CASE:gamma' "${output}"
    expect_output_contains 'tests="3" failures="1" errors="0" skipped="2"' "$(cat "${report}")"
    status=0
    output="$("${command[@]}" TEST_TOTAL_SHARDS=2 TEST_SHARD_INDEX=2 \
        "${BASH}" "${root}/probe.sh" 2>&1)" || status="${?}"
    expect_eq 1 "${status}"
    expect_output_contains 'Invalid test shard configuration' "${output}"
    expect_output_not_contains INIT "${output}"
}

# shellcheck disable=SC2317 # Functions are discovered by test_runner.
test::scratch_retention() {
    local root probe status expected output scratch mode retained
    root="$(test_tmpdir retention)"
    cat > "${root}/probe.sh" <<'PROBE'
set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"
printf '%s' "${BASHTEST_TMPDIR}" > "${SCRATCH_RECORD}"
printf evidence > "${BASHTEST_TMPDIR}/evidence"
test::test_init() { if [[ "${PROBE}" == setup ]]; then return 7; fi; }
test::body() {
    case "${PROBE}" in
        failure) expect_eq yes no ;;
        abort) exit 42 ;;
        report) mv "${REPORT_DIRECTORY}" "${REPORT_DIRECTORY}.moved" ;;
    esac
}
test::test_done() { printf done > "${DONE_RECORD}"; if [[ "${PROBE}" == teardown ]]; then return 7; fi; }
test_runner
PROBE
    for probe in pass failure setup teardown abort report; do
        for mode in failure never always; do
            status=0
            expected=1
            [[ "${probe}" != pass ]] || expected=0
            [[ "${probe}" != abort ]] || expected=42
            output="$(_junit_probe PROBE="${probe}" SCRATCH_RECORD="${root}/scratch.path" \
                REPORT_DIRECTORY="${root}/reports-${probe}-${mode}" GTEST_OUTPUT="xml:${root}/reports-${probe}-${mode}/result.xml" \
                DONE_RECORD="${root}/done-${probe}-${mode}" \
                "${BASH}" "${root}/probe.sh" --keep-tmpdir="${mode}" 2>&1)" || status="${?}"
            expect_eq "${expected}" "${status}"
            if [[ "${probe}" == report ]]; then
                expect_output_contains 'Cannot write JUnit report' "${output}"
            fi
            if [[ "${probe}" != abort ]]; then
                expect_success test -f "${root}/done-${probe}-${mode}"
            fi
            scratch="$(cat "${root}/scratch.path")"
            retained=0
            if [[ "${mode}" == always || ( "${mode}" == failure && "${expected}" != 0 ) ]]; then retained=1; fi
            if [[ "${retained}" == 1 ]]; then
                expect_success test -d "${scratch}"
                expect_eq evidence "$(cat "${scratch}/evidence")"
                expect_output_contains "Preserved test scratch directory: ${scratch}" "${output}"
            else
                expect_success test ! -e "${scratch}"
                expect_output_not_contains 'Preserved test scratch directory:' "${output}"
            fi
        done
    done
}

# shellcheck disable=SC2317 # Functions are discovered by test_runner.
test::live_output_and_progress_report() {
    local root pid attempt output observed=0 status=0
    root="$(test_tmpdir live)"
    cat > "${root}/probe.sh" <<'PROBE'
set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"
test::live() {
    # Framework capture workers must not cause an unqualified wait to hang.
    wait
    if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )); then
        local status=0
        wait -n || status="${?}"
        expect_eq 127 "${status}"
    fi
    printf '%s' live_stdout_token
    printf '%s' live_stderr_token >&2
    while [[ ! -e "${RELEASE}" ]]; do sleep 0.02; done
}
test::server_start() {
    "${BASH}" -c 'exec sleep 10' &
    server_pid="${!}"
}
test::server_use() { kill -0 "${server_pid}"; echo service_alive; }
test::test_done() { kill "${server_pid}"; wait "${server_pid}" || :; }
test_runner
PROBE
    _junit_probe "GTEST_OUTPUT=xml:${root}/result.xml" "RELEASE=${root}/release" \
        "${BASH}" "${root}/probe.sh" > "${root}/stdout" 2> "${root}/stderr" &
    pid="${!}"
    for ((attempt=0; attempt<200; attempt++)); do
        if grep -F live_stdout_token "${root}/stdout" >/dev/null && grep -F live_stderr_token "${root}/stderr" >/dev/null; then
            observed=1
            break
        fi
        sleep 0.05
    done
    expect_eq 1 "${observed}"
    output="$(cat "${root}/result.xml")"
    expect_output_contains 'provisional while it is running' "${output}"
    expect_output_contains 'tests="1" failures="0" errors="1"' "${output}"
    # Always release the fixture, including after a failed expectation above.
    : > "${root}/release"
    wait "${pid}" || status="${?}"
    expect_eq 0 "${status}"
    expect_eq 1 "$(grep -c live_stdout_token "${root}/stdout")"
    expect_eq 1 "$(grep -c live_stderr_token "${root}/stderr")"
    output="$(cat "${root}/result.xml")"
    expect_output_contains 'tests="3" failures="0" errors="0"' "${output}"
    expect_output_contains service_alive "$(cat "${root}/stdout")"
    expect_output_contains live_stdout_token "${output}"
    expect_output_contains live_stderr_token "${output}"
}

test_runner
