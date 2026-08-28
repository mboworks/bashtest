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

set -euo pipefail

function die() { echo "ERROR: ${*}" 1>&2 ; exit 1; }

function version_key() {
    local version="${1}"
    awk -F. '{ printf "%010d%010d%010d\n", $1, $2, $3 }' <<<"${version}"
}

BAZELMOD_VERSION="$(sed -rne 's,.*version = "([0-9]+([.][0-9]+)+.*)".*,\1,p' < MODULE.bazel|head -n1)"
CHANGELOG_VERSION="$(sed -rne 's,^# ([0-9]+([.][0-9]+)+.*)$,\1,p' < CHANGELOG.md|head -n1)"

if [ "${BAZELMOD_VERSION}" != "${CHANGELOG_VERSION}" ]; then
    die "MODULE.bazel (${BAZELMOD_VERSION}) != CHANGELOG.md (${CHANGELOG_VERSION})."
fi

if [[ ! "${BAZELMOD_VERSION}" =~ ^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$ ]]; then
    die "MODULE.bazel version (${BAZELMOD_VERSION}) must use numeric X.Y.Z format."
fi

LATEST_RELEASE="$(
    git tag --list |
        awk '/^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$/' |
        while read -r version; do
            printf '%s %s\n' "$(version_key "${version}")" "${version}"
        done |
        sort |
        tail -n1 |
        awk '{ print $2 }'
)"

if [[ -n "${LATEST_RELEASE}" ]] &&
[[ "$(version_key "${BAZELMOD_VERSION}")" < "$(version_key "${LATEST_RELEASE}")" ]]; then
    die "Development version (${BAZELMOD_VERSION}) is older than latest release tag (${LATEST_RELEASE})."
fi

# Equality is valid while main still points at the released commit. The first
# subsequent commit (normally the next PR) must advance the development version.
if [[ -n "${LATEST_RELEASE}" ]] &&
[[ "${BAZELMOD_VERSION}" == "${LATEST_RELEASE}" ]] &&
[[ "$(git rev-parse HEAD)" != "$(git rev-list -n1 "${LATEST_RELEASE}")" ]]; then
    die "Development version (${BAZELMOD_VERSION}) still matches latest release tag (${LATEST_RELEASE}), but HEAD contains later work. Bump MODULE.bazel and CHANGELOG.md."
fi
