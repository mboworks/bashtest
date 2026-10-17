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
    # Run expected failures in a subshell so the enclosing case stays successful.
    if (expect_files_eq "${golden}" "${result}"); then
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

test_runner
