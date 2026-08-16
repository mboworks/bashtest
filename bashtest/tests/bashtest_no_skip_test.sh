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

# Under `--no-skip`, a skip is a FAILURE. That is the mode for an environment which guarantees the
# capability a test probes for: there, "skipped" means the guarantee broke, and a suite that
# reports green while skipping its own subject is the bug this flag exists to catch.
#
# The target passes `--no-skip`, exercising the public flag parser as well as the runner behavior.

# shellcheck disable=SC2317 # Functions are called bashtest

set -euo pipefail

# shellcheck disable=SC1090,SC1091,SC2153,SC2154
source "${helly25_bashtest}"

bad_bashtest() {
    echo >&2 "FATAL: Test functionality broken: ${*}"
    exit 1
}

test::a_test_that_passes() {
    expect_eq "x" "x"
}

test::a_skip_that_must_be_reported_as_failure() {
    skip_test "the environment promised this capability" && return
}

test_runner && bad_bashtest "A skip under --no-skip must fail the run."

[[ "${_BASHTEST_NUM_FAIL}" == "1" ]] || bad_bashtest "Expected 1 failure, got '${_BASHTEST_NUM_FAIL}'."
# shellcheck disable=SC2153 # Assigned by the sourced test framework.
[[ "${_BASHTEST_NUM_SKIP}" == "0" ]] || bad_bashtest "Expected 0 skips, got '${_BASHTEST_NUM_SKIP}'."
[[ "${_BASHTEST_NUM_PASS}" == "1" ]] || bad_bashtest "Expected 1 pass, got '${_BASHTEST_NUM_PASS}'."
