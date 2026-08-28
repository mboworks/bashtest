#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright (c) M. Boerger and the MBO Works authors
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

# invoked by release workflow
# (via https://github.com/bazel-contrib/.github/blob/master/.github/workflows/release_ruleset.yaml)

set -euo pipefail

function die() {
    echo "ERROR: ${*}" 1>&2
    exit 1
}

# Custom args to update as needed.
PACKAGE_NAME="bashtest"
BAZELMOD_NAME="mboworks_bashtest"
PATCHES=()

# Automatic vars from workflow integration.
TAG="${GITHUB_REF_NAME}"
VERSION="${TAG#v}" # Strip leading 'v' if present.

if [[ "${TAG}" == "v${VERSION}" ]]; then
    die "Tag '${TAG}' has leading 'v'."
fi

# Computed vars.
PREFIX="${PACKAGE_NAME}-${TAG}"         # Internal archive root directory folder: bashtest-0.4.0
ARCHIVE="${PACKAGE_NAME}-${TAG}.tar.gz" # Target asset name on GitHub: bashtest-0.4.0.tar.gz

BAZELMOD_VERSION="$(sed -rne 's,.*version = "([0-9]+([.][0-9]+)+.*)".*,\1,p' <MODULE.bazel | head -n1)"
CHANGELOG_VERSION="$(sed -rne 's,^# ([0-9]+([.][0-9]+)+.*)$,\1,p' <CHANGELOG.md | head -n1)"

if [[ "${BAZELMOD_VERSION}" != "${VERSION}" ]]; then
    die "Tag = '${TAG}' does not match version = '${BAZELMOD_VERSION}' in MODULE.bazel."
fi
if [[ "${CHANGELOG_VERSION}" != "${VERSION}" ]]; then
    die "Tag = '${TAG}' does not match version = '${CHANGELOG_VERSION}' in CHANGELOG.md."
fi

# Instead of embed the version in MODULE.bazel, we expect it to be correct already.
# perl -pi -e "s/version = \"\d+\.\d+\.\d+\",/version = \"${TAG}\",/g" MODULE.bazel

# Empty `BUILD.bazel`
{
    cat tools/header.txt
    echo ""
    echo "\"\"\"Empty root BUILD for @${BAZELMOD_NAME}.\"\"\""
} >BUILD.bazel

# Apply patches
for patch in ${PATCHES[@]+"${PATCHES[@]}"}; do
    patch -s -p 1 <"${patch}"
done

# Exclude some dev stuff from the archive.
EXCLUDES=(
    ".bcr"
    ".github"
    ".pre-commit"
    ".pre-commit-config.yaml"
    "tools"
)
{
    for exclude in "${EXCLUDES[@]}"; do
        echo "${exclude} export-ignore"
        if [[ -d "${exclude}" ]]; then
            echo "${exclude}/** export-ignore"
        fi
    done
} >>.gitattributes

# Build the archive from the patched/generated worktree, not the committed
# "${TAG}" tree: `git archive "${TAG}"` reads the commit and would silently drop
# the edits above (any patches, the generated BUILD.bazel). Stage the worktree
# into a THROWAWAY index so the real index/checkout is never touched (nothing to
# undo afterwards), and archive that tree. export-ignore still applies via the
# staged .gitattributes (+ --worktree-attributes).
TMP_INDEX="$(mktemp -u)"
GIT_INDEX_FILE="${TMP_INDEX}" git read-tree HEAD
GIT_INDEX_FILE="${TMP_INDEX}" git add --all
ARCHIVE_TREE="$(GIT_INDEX_FILE="${TMP_INDEX}" git write-tree)"
rm -f "${TMP_INDEX}"
git archive --format=tar.gz --prefix="${PREFIX}/" -o "${ARCHIVE}" --add-virtual-file="${PREFIX}/VERSION:${VERSION}" --worktree-attributes "${ARCHIVE_TREE}"

# Print header
echo "# Version ${VERSION}"
echo "## [Changelog](https://github.com/mboworks/${PACKAGE_NAME}/blob/${TAG}/CHANGELOG.md)"

# Print Changelog
awk '/^#/{f+=1;if(f>1)exit} !/^#/{print}' <CHANGELOG.md

cat <<EOF
## For Bazel MODULE.bazel

\`\`\`
bazel_dep(name = "${BAZELMOD_NAME}", version = "${VERSION}")
\`\`\`
EOF
