#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright (c) The helly25 authors (helly25.com)
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# shellcheck disable=SC2317 # Functions are called bashtest

set -euo pipefail

# shellcheck disable=SC1090,SC1091,SC2154
source "${helly25_bashtest}"


bad_bashtest() {
    echo >&2 "FATAL: Test functionality broken: ${*}"
    exit 1
}

_DONE_CALLED=0
_INIT_CALLED=0

test::test_init() {
    echo "Hello World of tests."
    _INIT_CALLED=1
}

test::test_done() {
    echo "The world is ending."
    _DONE_CALLED=1
}

test::test_tmpdir_allocates_unique_named_directories() {
    local first second
    first="$(test_tmpdir fixture)"
    second="$(test_tmpdir fixture)"
    [[ -d "${first}" ]] || bad_bashtest "test_tmpdir did not create '${first}'."
    [[ -d "${second}" ]] || bad_bashtest "test_tmpdir did not create '${second}'."
    [[ "${first}" != "${second}" ]] || bad_bashtest "test_tmpdir reused '${first}'."
    [[ "${first}" == "${BASHTEST_TMPDIR}/fixture."* ]] \
        || bad_bashtest "test_tmpdir escaped or ignored its prefix: '${first}'."
}

test::test_tmpdir_rejects_paths() {
    local output status=0
    output="$(test_tmpdir ../escape 2>&1)" || status="${?}"
    [[ "${status}" != "0" ]] || bad_bashtest "test_tmpdir accepted a path."
    [[ "${output}" == *"must be a basename"* ]] || bad_bashtest "test_tmpdir gave no useful error."
}

test::expect_eq() {
    [[ "${_BASHTEST_HAS_ERROR}" == "0" ]] || bad_bashtest "Test starts with _BASHTEST_HAS_ERROR != 0, got '${_BASHTEST_HAS_ERROR}'."

    NUM_PASS="${_BASHTEST_NUM_PASS}"
    NUM_FAIL="${_BASHTEST_NUM_FAIL}"
    NUM_SKIP="${_BASHTEST_NUM_SKIP}"

    expect_eq "Hello" "Hello"
    test_has_error && bad_bashtest "expect_eq with same values."
    _BASHTEST_HAS_ERROR=0

    expect_eq "Hello" "World"
    test_has_error || bad_bashtest "expect_eq with different values."
    _BASHTEST_HAS_ERROR=0

    expect_eq "Hello" "City"
    test_has_error || bad_bashtest "expect_eq with different values."
    _BASHTEST_HAS_ERROR=0

    expect_eq "Meow" "Meow"
    test_has_error && bad_bashtest "expect_eq with different values."
    _BASHTEST_HAS_ERROR=0

    [[ "${_BASHTEST_NUM_PASS}" == "${NUM_PASS}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_PASS."
    [[ "${_BASHTEST_NUM_FAIL}" == "${NUM_FAIL}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_FAIL."
    [[ "${_BASHTEST_NUM_SKIP}" == "${NUM_SKIP}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_SKIP."
    _BASHTEST_NUM_PASS="${NUM_PASS}"
    _BASHTEST_NUM_FAIL="${NUM_FAIL}"
    _BASHTEST_NUM_SKIP="${NUM_SKIP}"
}

test::expect_ne() {
    [[ "${_BASHTEST_HAS_ERROR}" == "0" ]] || bad_bashtest "Test starts with _BASHTEST_HAS_ERROR != 0, got '${_BASHTEST_HAS_ERROR}'."

    NUM_PASS="${_BASHTEST_NUM_PASS}"
    NUM_FAIL="${_BASHTEST_NUM_FAIL}"
    NUM_SKIP="${_BASHTEST_NUM_SKIP}"

    expect_ne "Hello" "Hello"
    test_has_error || bad_bashtest "expect_ne with same values."
    _BASHTEST_HAS_ERROR=0

    expect_ne "Hello" "World"
    test_has_error && bad_bashtest "expect_ne with different values."
    _BASHTEST_HAS_ERROR=0

    expect_ne "Hello" "City"
    test_has_error && bad_bashtest "expect_ne with different values."
    _BASHTEST_HAS_ERROR=0

    expect_ne "Meow" "Meow"
    test_has_error || bad_bashtest "expect_ne with different values."
    _BASHTEST_HAS_ERROR=0

    [[ "${_BASHTEST_NUM_PASS}" == "${NUM_PASS}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_PASS."
    [[ "${_BASHTEST_NUM_FAIL}" == "${NUM_FAIL}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_FAIL."
    [[ "${_BASHTEST_NUM_SKIP}" == "${NUM_SKIP}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_SKIP."
    _BASHTEST_NUM_PASS="${NUM_PASS}"
    _BASHTEST_NUM_FAIL="${NUM_FAIL}"
    _BASHTEST_NUM_SKIP="${NUM_SKIP}"
}

test::expect_contains() {
    [[ "${_BASHTEST_HAS_ERROR}" == "0" ]] || bad_bashtest "Test starts with _BASHTEST_HAS_ERROR != 0, got '${_BASHTEST_HAS_ERROR}'."

    NUM_PASS="${_BASHTEST_NUM_PASS}"
    NUM_FAIL="${_BASHTEST_NUM_FAIL}"
    NUM_SKIP="${_BASHTEST_NUM_SKIP}"

    EMPTY=()
    expect_contains "foo" ${EMPTY[@]+"${EMPTY[@]}"} && bad_bashtest "Element is not present, yet test passed."
    _BASHTEST_HAS_ERROR=0

    expect_contains "" ${EMPTY[@]+"${EMPTY[@]}"} && bad_bashtest "Element is not present, yet test passed."
    _BASHTEST_HAS_ERROR=0

    FOO_BAR=("foo" "bar")
    expect_contains "foo" "${FOO_BAR[@]}" || bad_bashtest "Element is present, yet test failed."
    _BASHTEST_HAS_ERROR=0

    expect_contains "bar" "${FOO_BAR[@]}" || bad_bashtest "Element is present, yet test failed."
    _BASHTEST_HAS_ERROR=0

    expect_contains "baz" "${FOO_BAR[@]}" && bad_bashtest "Element is not present, yet test passed."
    _BASHTEST_HAS_ERROR=0

    expect_contains "" "${FOO_BAR[@]}" && bad_bashtest "Element is not present, yet test passed."
    _BASHTEST_HAS_ERROR=0

    FOO_BAR+=("")

    expect_contains "" "${FOO_BAR[@]}" || bad_bashtest "Element is present, yet test failed."
    _BASHTEST_HAS_ERROR=0

    [[ "${_BASHTEST_NUM_PASS}" == "${NUM_PASS}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_PASS."
    [[ "${_BASHTEST_NUM_FAIL}" == "${NUM_FAIL}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_FAIL."
    [[ "${_BASHTEST_NUM_SKIP}" == "${NUM_SKIP}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_SKIP."
    _BASHTEST_NUM_PASS="${NUM_PASS}"
    _BASHTEST_NUM_FAIL="${NUM_FAIL}"
    _BASHTEST_NUM_SKIP="${NUM_SKIP}"
}

test::expect_not_contains() {
    [[ "${_BASHTEST_HAS_ERROR}" == "0" ]] || bad_bashtest "Test starts with _BASHTEST_HAS_ERROR != 0, got '${_BASHTEST_HAS_ERROR}'."

    NUM_PASS="${_BASHTEST_NUM_PASS}"
    NUM_FAIL="${_BASHTEST_NUM_FAIL}"
    NUM_SKIP="${_BASHTEST_NUM_SKIP}"

    EMPTY=()
    expect_not_contains "foo" ${EMPTY[@]+"${EMPTY[@]}"} || bad_bashtest "Element is not present, yet test failed."
    _BASHTEST_HAS_ERROR=0

    expect_not_contains "" ${EMPTY[@]+"${EMPTY[@]}"} || bad_bashtest "Element is not present, yet test failed."
    _BASHTEST_HAS_ERROR=0

    FOO_BAR=("foo" "bar")
    expect_not_contains "foo" "${FOO_BAR[@]}" && bad_bashtest "Element is present, yet test passed."
    _BASHTEST_HAS_ERROR=0

    expect_not_contains "bar" "${FOO_BAR[@]}" && bad_bashtest "Element is present, yet test passed."
    _BASHTEST_HAS_ERROR=0

    expect_not_contains "baz" "${FOO_BAR[@]}" || bad_bashtest "Element is not present, yet test failed."
    _BASHTEST_HAS_ERROR=0

    expect_not_contains "" "${FOO_BAR[@]}" || bad_bashtest "Element is not present, yet test failed."
    _BASHTEST_HAS_ERROR=0

    FOO_BAR+=("")

    expect_not_contains "" "${FOO_BAR[@]}" && bad_bashtest "Element is present, yet test passed."
    _BASHTEST_HAS_ERROR=0

    [[ "${_BASHTEST_NUM_PASS}" == "${NUM_PASS}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_PASS."
    [[ "${_BASHTEST_NUM_FAIL}" == "${NUM_FAIL}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_FAIL."
    [[ "${_BASHTEST_NUM_SKIP}" == "${NUM_SKIP}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_SKIP."
    _BASHTEST_NUM_PASS="${NUM_PASS}"
    _BASHTEST_NUM_FAIL="${NUM_FAIL}"
    _BASHTEST_NUM_SKIP="${NUM_SKIP}"
}

test::expect_output_contains() {
    [[ "${_BASHTEST_HAS_ERROR}" == "0" ]] || bad_bashtest "Test starts with _BASHTEST_HAS_ERROR != 0, got '${_BASHTEST_HAS_ERROR}'."

    NUM_PASS="${_BASHTEST_NUM_PASS}"
    NUM_FAIL="${_BASHTEST_NUM_FAIL}"
    NUM_SKIP="${_BASHTEST_NUM_SKIP}"

    TEXT=$'line one\nSECOND line\nthird'

    expect_output_contains "SECOND" "${TEXT}" || bad_bashtest "Substring is present, yet test failed."
    _BASHTEST_HAS_ERROR=0

    expect_output_contains "ECOND li" "${TEXT}" || bad_bashtest "Substring within a line is present, yet test failed."
    _BASHTEST_HAS_ERROR=0

    expect_output_contains "" "${TEXT}" || bad_bashtest "Empty substring should always be contained."
    _BASHTEST_HAS_ERROR=0

    expect_output_contains "absent" "${TEXT}" && bad_bashtest "Substring is not present, yet test passed."
    _BASHTEST_HAS_ERROR=0

    # Glob metacharacters must be treated literally.
    expect_output_contains "a*b" "has a*b literal" || bad_bashtest "Literal '*' is present, yet test failed."
    _BASHTEST_HAS_ERROR=0

    expect_output_contains "a*b" "has aXXb glob" && bad_bashtest "'*' was treated as a glob, yet test passed."
    _BASHTEST_HAS_ERROR=0

    [[ "${_BASHTEST_NUM_PASS}" == "${NUM_PASS}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_PASS."
    [[ "${_BASHTEST_NUM_FAIL}" == "${NUM_FAIL}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_FAIL."
    [[ "${_BASHTEST_NUM_SKIP}" == "${NUM_SKIP}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_SKIP."
    _BASHTEST_NUM_PASS="${NUM_PASS}"
    _BASHTEST_NUM_FAIL="${NUM_FAIL}"
    _BASHTEST_NUM_SKIP="${NUM_SKIP}"
}

test::expect_output_not_contains() {
    [[ "${_BASHTEST_HAS_ERROR}" == "0" ]] || bad_bashtest "Test starts with _BASHTEST_HAS_ERROR != 0, got '${_BASHTEST_HAS_ERROR}'."

    NUM_PASS="${_BASHTEST_NUM_PASS}"
    NUM_FAIL="${_BASHTEST_NUM_FAIL}"
    NUM_SKIP="${_BASHTEST_NUM_SKIP}"

    TEXT=$'line one\nSECOND line\nthird'

    expect_output_not_contains "absent" "${TEXT}" || bad_bashtest "Substring is not present, yet test failed."
    _BASHTEST_HAS_ERROR=0

    expect_output_not_contains "SECOND" "${TEXT}" && bad_bashtest "Substring is present, yet test passed."
    _BASHTEST_HAS_ERROR=0

    expect_output_not_contains "" "${TEXT}" && bad_bashtest "Empty substring is always contained, yet test passed."
    _BASHTEST_HAS_ERROR=0

    expect_output_not_contains "a*b" "has aXXb glob" || bad_bashtest "'*' treated as glob, yet test failed."
    _BASHTEST_HAS_ERROR=0

    [[ "${_BASHTEST_NUM_PASS}" == "${NUM_PASS}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_PASS."
    [[ "${_BASHTEST_NUM_FAIL}" == "${NUM_FAIL}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_FAIL."
    [[ "${_BASHTEST_NUM_SKIP}" == "${NUM_SKIP}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_SKIP."
    _BASHTEST_NUM_PASS="${NUM_PASS}"
    _BASHTEST_NUM_FAIL="${NUM_FAIL}"
    _BASHTEST_NUM_SKIP="${NUM_SKIP}"
}

test::expect_matches() {
    [[ "${_BASHTEST_HAS_ERROR}" == "0" ]] || bad_bashtest "Test starts with _BASHTEST_HAS_ERROR != 0, got '${_BASHTEST_HAS_ERROR}'."

    NUM_PASS="${_BASHTEST_NUM_PASS}"
    NUM_FAIL="${_BASHTEST_NUM_FAIL}"
    NUM_SKIP="${_BASHTEST_NUM_SKIP}"

    TEXT=$'line one\nSECOND line\nthird'

    expect_matches "SECOND" "${TEXT}" || bad_bashtest "Unanchored regex is present, yet test failed."
    _BASHTEST_HAS_ERROR=0

    expect_matches "l[a-z]+ one" "${TEXT}" || bad_bashtest "ERE class should match 'line one'."
    _BASHTEST_HAS_ERROR=0

    expect_matches "^line one" "${TEXT}" || bad_bashtest "'^' should anchor the start of the text."
    _BASHTEST_HAS_ERROR=0

    expect_matches "third\$" "${TEXT}" || bad_bashtest "'\$' should anchor the end of the text."
    _BASHTEST_HAS_ERROR=0

    # Whole-text anchoring: '^SECOND' must NOT match, SECOND is not at the start.
    expect_matches "^SECOND" "${TEXT}" && bad_bashtest "'^' must anchor the whole text, not each line."
    _BASHTEST_HAS_ERROR=0

    expect_matches "absent" "${TEXT}" && bad_bashtest "Regex is not present, yet test passed."
    _BASHTEST_HAS_ERROR=0

    expect_matches "[[:digit:]]+" "abc123" || bad_bashtest "POSIX digit class should match."
    _BASHTEST_HAS_ERROR=0

    [[ "${_BASHTEST_NUM_PASS}" == "${NUM_PASS}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_PASS."
    [[ "${_BASHTEST_NUM_FAIL}" == "${NUM_FAIL}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_FAIL."
    [[ "${_BASHTEST_NUM_SKIP}" == "${NUM_SKIP}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_SKIP."
    _BASHTEST_NUM_PASS="${NUM_PASS}"
    _BASHTEST_NUM_FAIL="${NUM_FAIL}"
    _BASHTEST_NUM_SKIP="${NUM_SKIP}"
}

test::expect_not_matches() {
    [[ "${_BASHTEST_HAS_ERROR}" == "0" ]] || bad_bashtest "Test starts with _BASHTEST_HAS_ERROR != 0, got '${_BASHTEST_HAS_ERROR}'."

    NUM_PASS="${_BASHTEST_NUM_PASS}"
    NUM_FAIL="${_BASHTEST_NUM_FAIL}"
    NUM_SKIP="${_BASHTEST_NUM_SKIP}"

    TEXT=$'line one\nSECOND line\nthird'

    expect_not_matches "absent" "${TEXT}" || bad_bashtest "Regex is not present, yet test failed."
    _BASHTEST_HAS_ERROR=0

    expect_not_matches "SECOND" "${TEXT}" && bad_bashtest "Regex is present, yet test passed."
    _BASHTEST_HAS_ERROR=0

    # Whole-text anchoring: '^SECOND' does not match, so not_matches should pass.
    expect_not_matches "^SECOND" "${TEXT}" || bad_bashtest "'^SECOND' does not anchor-match, yet test failed."
    _BASHTEST_HAS_ERROR=0

    [[ "${_BASHTEST_NUM_PASS}" == "${NUM_PASS}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_PASS."
    [[ "${_BASHTEST_NUM_FAIL}" == "${NUM_FAIL}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_FAIL."
    [[ "${_BASHTEST_NUM_SKIP}" == "${NUM_SKIP}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_SKIP."
    _BASHTEST_NUM_PASS="${NUM_PASS}"
    _BASHTEST_NUM_FAIL="${NUM_FAIL}"
    _BASHTEST_NUM_SKIP="${NUM_SKIP}"
}

test::expect_pcre_matches() {
    [[ "${_BASHTEST_HAS_ERROR}" == "0" ]] || bad_bashtest "Test starts with _BASHTEST_HAS_ERROR != 0, got '${_BASHTEST_HAS_ERROR}'."

    NUM_PASS="${_BASHTEST_NUM_PASS}"
    NUM_FAIL="${_BASHTEST_NUM_FAIL}"
    NUM_SKIP="${_BASHTEST_NUM_SKIP}"

    if [[ -n "$(_bashtest_pcre_cmd)" ]]; then
        # '\d' is a PCRE-ism unavailable in bash's ERE engine.
        expect_pcre_matches '\d+' "abc123" || bad_bashtest "PCRE '\\d+' should match digits."
        _BASHTEST_HAS_ERROR=0

        expect_pcre_matches '\d+' "no digits here" && bad_bashtest "PCRE '\\d+' matched a digitless text."
        _BASHTEST_HAS_ERROR=0
    else
        echo "No PCRE tool available; verifying the matcher fails gracefully."
        expect_pcre_matches '\d+' "abc123" && bad_bashtest "Without a PCRE tool the matcher must fail, yet it passed."
        _BASHTEST_HAS_ERROR=0
    fi

    [[ "${_BASHTEST_NUM_PASS}" == "${NUM_PASS}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_PASS."
    [[ "${_BASHTEST_NUM_FAIL}" == "${NUM_FAIL}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_FAIL."
    [[ "${_BASHTEST_NUM_SKIP}" == "${NUM_SKIP}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_SKIP."
    _BASHTEST_NUM_PASS="${NUM_PASS}"
    _BASHTEST_NUM_FAIL="${NUM_FAIL}"
    _BASHTEST_NUM_SKIP="${NUM_SKIP}"
}

test::expect_pcre_not_matches() {
    [[ "${_BASHTEST_HAS_ERROR}" == "0" ]] || bad_bashtest "Test starts with _BASHTEST_HAS_ERROR != 0, got '${_BASHTEST_HAS_ERROR}'."

    NUM_PASS="${_BASHTEST_NUM_PASS}"
    NUM_FAIL="${_BASHTEST_NUM_FAIL}"
    NUM_SKIP="${_BASHTEST_NUM_SKIP}"

    if [[ -n "$(_bashtest_pcre_cmd)" ]]; then
        expect_pcre_not_matches '\d+' "no digits here" || bad_bashtest "PCRE '\\d+' is absent, yet not_matches failed."
        _BASHTEST_HAS_ERROR=0

        expect_pcre_not_matches '\d+' "abc123" && bad_bashtest "PCRE '\\d+' is present, yet not_matches passed."
        _BASHTEST_HAS_ERROR=0
    else
        echo "No PCRE tool available; verifying the matcher fails gracefully."
        expect_pcre_not_matches '\d+' "abc123" && bad_bashtest "Without a PCRE tool the matcher must fail, yet it passed."
        _BASHTEST_HAS_ERROR=0
    fi

    [[ "${_BASHTEST_NUM_PASS}" == "${NUM_PASS}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_PASS."
    [[ "${_BASHTEST_NUM_FAIL}" == "${NUM_FAIL}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_FAIL."
    [[ "${_BASHTEST_NUM_SKIP}" == "${NUM_SKIP}" ]] || bad_bashtest "Test modified _BASHTEST_NUM_SKIP."
    _BASHTEST_NUM_PASS="${NUM_PASS}"
    _BASHTEST_NUM_FAIL="${NUM_FAIL}"
    _BASHTEST_NUM_SKIP="${NUM_SKIP}"
}

test_runner || bad_bashtest "Test was meant to pass but did not."

[[ "${_INIT_CALLED}" == "1" ]] || bad_bashtest "Test init (test::test_init) was not called."
[[ "${_DONE_CALLED}" == "1" ]] || bad_bashtest "Test done (test::test_done) was not called."
