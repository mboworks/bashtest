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
test::managed_windows_runtime() {
    expect_matches 'bashtest_windows_runtime' "${BASH}"
    for tool in cat cp cut date diff grep mkdir mktemp rm sed cygpath; do
        expect_matches 'bashtest_windows_runtime' "$(command -v "${tool}")"
    done
    expect_pcre_matches '(?<=prefix)VALUE' 'prefixVALUE'
    expect_eq 'second' "$(sed -n '2p' <<<$'first\nsecond')"
    local scratch
    scratch="$(test_tmpdir 'runtime with spaces')"
    printf '%s\n' content > "${scratch}/one"
    cp "${scratch}/one" "${scratch}/two"
    expect_files_eq "${scratch}/one" "${scratch}/two"
}

test_runner
