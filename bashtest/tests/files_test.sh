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
test::golden_paths_and_updates() {
    local root golden result
    root="$(test_tmpdir golden)"
    mkdir -p "${root}/source/data" "${root}/output with spaces"
    golden="${root}/source/data/golden [1].txt"
    result="${root}/output with spaces/result.txt"
    printf 'old\n' > "${golden}"
    cp "${golden}" "${result}"
    expect_files_eq "${golden}" "${result}"
    printf 'new\n' > "${result}"
    # This verifier owns an isolated marker for intentionally failed expectations.
    if (_BASHTEST_FAILURE_FILE="${root}/expected-mismatch"; expect_files_eq "${golden}" "${result}"); then
        expect_eq failure success
    fi
    expect_output_contains '+new' "$(cat "${result}.diff")"
    # A manifest-only lookup supplies the physical source path, while the
    # update destination must retain the logical workspace-relative path.
    mkdir -p "${root}/update/data"
    cp "${golden}" "${root}/update/data/golden [1].txt"
    printf ' _main/data/golden\\s[1].txt %s\n' "${golden}" > "${root}/MANIFEST"
    (
        export RUNFILES_DIR=
        export TEST_SRCDIR=
        export TEST_TMPDIR=
        export TEST_WORKSPACE=_main
        export RUNFILES_MANIFEST_FILE="${root}/MANIFEST"
        export BUILD_WORKSPACE_DIRECTORY=
        _BASHTEST_UPDATE_GOLDEN="${root}/update"
        # Avoid matching the inherited working directory before the manifest.
        cd "${root}/output with spaces"
        expect_files_eq "${golden}" "${result}"
    )
    expect_eq new "$(cat "${root}/update/data/golden [1].txt")"
    expect_eq old "$(cat "${golden}")"
}

# shellcheck disable=SC2317
test::reject_windows_path_names() {
    local name status
    for name in 'dir\child' 'C:child' 'C:\child'; do
        status=0
        (test_tmpdir "${name}") >/dev/null 2>&1 || status="${?}"
        expect_ne 0 "${status}"
    done
}

# shellcheck disable=SC2317
test::diff_error_does_not_update_golden() {
    local root status=0
    root="$(test_tmpdir diff-error)"
    printf 'old\n' > "${root}/golden.txt"
    printf 'new\n' > "${root}/result.txt"
    (
        # Simulate a tool failure, distinct from diff's content-mismatch status.
        # shellcheck disable=SC2329 # Called indirectly by expect_files_eq.
        diff() { echo >&2 'simulated diff error'; return 2; }
        _BASHTEST_UPDATE_GOLDEN="${root}"
        _BASHTEST_FAILURE_FILE="${root}/expected-diff-error"
        expect_files_eq "${root}/golden.txt" "${root}/result.txt"
    ) || status="${?}"
    expect_eq 1 "${status}"
    expect_eq old "$(cat "${root}/golden.txt")"
}

test_runner
