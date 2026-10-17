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
test::manifest_only_with_spaces() {
    local root library launcher output status=0
    root="$(test_tmpdir manifest)"
    mkdir -p "${root}/files with spaces" "${root}/scratch"
    library="$(rlocation bazel_tools/tools/bash/runfiles/runfiles.bash)"
    # shellcheck disable=SC2154
    launcher="$(rlocation "${LAUNCHER_RUNFILE}")"
    cp "${mboworks_bashtest}" "${root}/files with spaces/runtime.sh"
    cat > "${root}/files with spaces/probe.sh" <<'PROBE'
set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"
 test::probe() {
    expect_eq 'value with spaces' "${PROBE_VALUE}"
    [[ -d "$(test_tmpdir fixture)" ]]
}
test_runner
PROBE
    # Logical keys need no escaping; physical paths may contain spaces.
    printf '%s %s\n' \
        bazel_tools/tools/bash/runfiles/runfiles.bash "${library}" \
        framework/runtime.sh "${root}/files with spaces/runtime.sh" \
        consumer/probe.sh "${root}/files with spaces/probe.sh" > "${root}/MANIFEST"
    output="$(env RUNFILES_DIR= RUNFILES_MANIFEST_FILE="${root}/MANIFEST" \
        mboworks_bashtest=framework/runtime.sh _BASHTEST_SCRIPT=consumer/probe.sh \
        TEST_TMPDIR="${root}/scratch" PROBE_VALUE='value with spaces' \
        "${BASH}" "${launcher}" --keep-tmpdir=always 2>&1)" || status="${?}"
    expect_eq 0 "${status}"
    expect_output_contains 'All tests passed.' "${output}"
    expect_output_contains 'Preserved test scratch directory:' "${output}"

    status=0
    output="$(env RUNFILES_DIR= RUNFILES_MANIFEST_FILE="${root}/MANIFEST" \
        mboworks_bashtest=framework/runtime.sh _BASHTEST_SCRIPT=consumer/probe.sh \
        TEST_TMPDIR="${root}/scratch" PROBE_VALUE=wrong \
        "${BASH}" "${launcher}" --keep-tmpdir=never 2>&1)" || status="${?}"
    expect_eq 1 "${status}"
    expect_output_contains 'Some tests failed.' "${output}"

    status=0
    output="$(env RUNFILES_DIR= RUNFILES_MANIFEST_FILE="${root}/MANIFEST" \
        mboworks_bashtest=framework/runtime.sh _BASHTEST_SCRIPT=consumer/missing.sh \
        "${BASH}" "${launcher}" 2>&1)" || status="${?}"
    expect_ne 0 "${status}"
    expect_output_contains 'cannot resolve bashtest runtime or test script' "${output}"
}

test_runner
