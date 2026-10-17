#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
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

set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"

# shellcheck disable=SC2317 # Functions are discovered by test_runner.
test::executable_and_runfiles() {
    # shellcheck disable=SC2154
    expect_eq $'default\nargument with spaces' "$("${HELPER}" 'argument with spaces')"
    # shellcheck disable=SC2154
    expect_eq 'default' "$(cat "$(rlocation "${TARGET_DATA}")")"
    # shellcheck disable=SC2154
    expect_eq "${HELPER}" "${HELPER_ALIAS}"
    # shellcheck disable=SC2154
    # location retains sh_test rootpath semantics; use rlocation above for I/O.
    expect_eq 'bashtest/tests/target_data.txt' "${TARGET_LOCATION}"
    # Distinct executables must both be available in this single test invocation.
    # shellcheck disable=SC2154
    expect_ne "${HELPER}" "${SECOND_HELPER}"
    expect_eq $'second-tool\nsecond argument' "$("${SECOND_HELPER}" 'second argument')"
    case "${OSTYPE}" in
        msys*|cygwin*) expect_matches '[.]exe$' "${HELPER}" ;;
    esac
}

test_runner
