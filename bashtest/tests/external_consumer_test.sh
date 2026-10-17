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

# Run outside a Bazel test: this creates and builds a separate consumer module.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The override consumes this checkout, including unreleased development versions.
version="$(sed -nE 's/.*version = "([^"]+)".*/\1/p' "${repo}/MODULE.bazel" | head -n1)"
root="$(mktemp -d)"
cleanup() {
    # Windows cannot remove a directory while it is a process working directory.
    bazel shutdown >/dev/null 2>&1 || true
    cd "${repo}"
    rm -rf "${root}"
}
trap cleanup EXIT
case "${OSTYPE}" in
    msys*|cygwin*) repo="$(cygpath -m "${repo}")" ;;
esac
mkdir -p "${root}/consumer with spaces"
cd "${root}/consumer with spaces"
cp "${repo}/.bazelversion" .bazelversion
cat > MODULE.bazel <<EOF
module(name = "consumer")
bazel_dep(name = "mboworks_bashtest", version = "${version}", repo_name = "framework")
local_path_override(module_name = "mboworks_bashtest", path = "${repo}")
EOF
cat > BUILD.bazel <<'EOF'
load("@framework//bashtest:bashtest.bzl", "bashtest")
bashtest(
    name = "consumer_test",
    srcs = select({"//conditions:default": ["consumer.sh"]}),
    data = ["golden.txt"],
    env = {"GOLDEN": "$(rlocationpath :golden.txt)", "MESSAGE": "hello world"},
)
EOF
printf 'hello world\n' > golden.txt
cat > consumer.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"
# shellcheck disable=SC2317
test::consumer() {
    local result
    result="$(test_tmpdir data)/result.txt"
    printf '%s\n' "${MESSAGE}" > "${result}"
    expect_files_eq "$(rlocation "${GOLDEN}")" "${result}"
}
test_runner
EOF
# Also run the framework's own suite as an external dependency, as BCR does.
# A standalone consumer test alone cannot catch root-workspace assumptions in it.
bazel test --enable_runfiles=no --test_output=errors //:consumer_test @framework//bashtest/tests/...
bazel run --enable_runfiles=no //:consumer_test -- --keep-tmpdir=never

# Exercise both documented update spellings with a workspace path containing spaces.
# Separate MSYS2 installations have different /tmp mounts. Cross the native
# Bazel boundary with a Windows path that identifies the same directory in both.
workspace="${PWD}"
case "${OSTYPE}" in
    msys*|cygwin*) workspace="$(cygpath -am "${workspace}")" ;;
esac
printf 'stale\n' > golden.txt
bazel run --enable_runfiles=no //:consumer_test -- --update-golden="${workspace}" --keep-tmpdir=never
[[ "$(cat golden.txt)" == 'hello world' ]]
printf 'stale again\n' > golden.txt
bazel run --enable_runfiles=no //:consumer_test -- -u="${workspace}" --keep-tmpdir=never
[[ "$(cat golden.txt)" == 'hello world' ]]
