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

# Resolve both the framework and caller script before invoking Bash. In particular,
# Windows normally supplies a manifest instead of a runfiles symlink directory.
# This is the v3 bootstrap from rules_shell's runfiles library.
set -uo pipefail
set +e
f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090,SC1091
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null ||
source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null ||
source "$0.runfiles/$f" 2>/dev/null ||
source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null ||
source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null ||
{ echo >&2 "ERROR: cannot find $f"; exit 1; }
set -e

# The macro supplies canonical rlocation paths, independent of the consumer's
# apparent repository name. Keep the public variable a sourceable physical path.
# shellcheck disable=SC2154
mboworks_bashtest="$(rlocation "${mboworks_bashtest}")"
# shellcheck disable=SC2154
_BASHTEST_ENTRYPOINT="$(rlocation "${_BASHTEST_SCRIPT}")"
if [[ ! -r "${mboworks_bashtest}" || ! -r "${_BASHTEST_ENTRYPOINT}" ]]; then
    echo >&2 "ERROR: cannot resolve bashtest runtime or test script"
    exit 1
fi
export mboworks_bashtest
runfiles_export_envvars
if [[ -n "${_BASHTEST_TOOLS_MANIFEST:-}" ]]; then
    _BASHTEST_TOOLS_FILE="$(rlocation "${_BASHTEST_TOOLS_MANIFEST}")"
    while IFS=$'\t' read -r _BASHTEST_TOOL_NAME _BASHTEST_TOOL_RUNFILE; do
        _BASHTEST_TOOL_PATH="$(rlocation "${_BASHTEST_TOOL_RUNFILE}")"
        if [[ ! -f "${_BASHTEST_TOOL_PATH}" ]]; then
            echo >&2 "ERROR: cannot resolve tool ${_BASHTEST_TOOL_NAME}: ${_BASHTEST_TOOL_RUNFILE}"
            exit 1
        fi
        export "${_BASHTEST_TOOL_NAME}=${_BASHTEST_TOOL_PATH}"
    done < "${_BASHTEST_TOOLS_FILE}"
fi
exec "${BASH}" "${_BASHTEST_ENTRYPOINT}" "$@"
