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

# `skip_test` ends the test it is called from and counts as SKIP, not PASS and not FAIL. The
# assertions live AFTER test_runner because a skipped test cannot assert about itself: the whole
# point is that its body stops there.

# shellcheck disable=SC2317 # Functions are called bashtest

set -euo pipefail

# shellcheck disable=SC1090,SC1091,SC2154
source "${helly25_bashtest}"

bad_bashtest() {
    echo >&2 "FATAL: Test functionality broken: ${*}"
    exit 1
}

_REACHED_AFTER_SKIP=0

test::a_test_that_passes() {
    expect_eq "x" "x"
}

test::skip_ends_the_body_immediately() {
    skip_test "pretending this machine lacks a capability"
    # If skip_test merely returned, execution would continue here - which is exactly the bug that
    # made every caller write `skip_if_x && return` by hand.
    _REACHED_AFTER_SKIP=1
    bad_bashtest "Statements after skip_test must not run."
}

test::skip_needs_no_reason() {
    skip_test
}

test_runner || bad_bashtest "Skipped tests must not fail the run."

[[ "${_BASHTEST_NUM_SKIP}" == "2" ]] || bad_bashtest "Expected 2 skips, got '${_BASHTEST_NUM_SKIP}'."
[[ "${_BASHTEST_NUM_PASS}" == "1" ]] || bad_bashtest "Expected 1 pass, got '${_BASHTEST_NUM_PASS}'."
[[ "${_BASHTEST_NUM_FAIL}" == "0" ]] || bad_bashtest "Expected 0 failures, got '${_BASHTEST_NUM_FAIL}'."

# The subshell is what stops the body, so the parent's variable must be untouched. This also pins
# that a test body cannot leak state into later tests.
[[ "${_REACHED_AFTER_SKIP}" == "0" ]] || bad_bashtest "Body continued past skip_test."
