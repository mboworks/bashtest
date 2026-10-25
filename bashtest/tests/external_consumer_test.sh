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

# Verify that Bazel collects per-function failure XML, rather than its fallback
# single-case wrapper, for both our macro and a plain rules_shell sh_test.
cat >> BUILD.bazel <<'EOF'
bashtest(
    name = "junit_failure_test",
    srcs = ["junit_failure.sh"],
    tags = ["manual"],
)
EOF
cat > junit_failure.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"
# shellcheck disable=SC2317
test::intentional_failure() { expect_eq 'expected <value>' 'actual & value'; }
# shellcheck disable=SC2317
test::passing_case() { expect_eq ok ok; }
test_runner
EOF
chmod +x junit_failure.sh
junit_targets=(//:junit_failure_test)
case "${OSTYPE}" in
    msys*|cygwin*) ;; # Native sh_test retains its own Windows shell configuration.
    *)
        # Loads must precede rule calls in BUILD files.
        { echo 'load("@rules_shell//shell:sh_test.bzl", "sh_test")'; cat BUILD.bazel; } > BUILD.tmp
        mv BUILD.tmp BUILD.bazel
        cat >> BUILD.bazel <<'EOF'
sh_test(
    name = "junit_sh_failure_test",
    srcs = ["junit_failure.sh"],
    data = ["@framework//bashtest:bashtest_sh"],
    env = {"mboworks_bashtest": "$(rootpath @framework//bashtest:bashtest_sh)"},
    tags = ["manual"],
)
EOF
        # A direct rules_shell dependency is required for the plain sh_test load.
        echo 'bazel_dep(name = "rules_shell", version = "0.8.0")' >> MODULE.bazel
        junit_targets+=(//:junit_sh_failure_test)
        ;;
esac
if bazel test --enable_runfiles=no "${junit_targets[@]}" > junit_failure.log 2>&1; then
    echo >&2 'ERROR: intentionally failing JUnit fixtures passed'
    exit 1
fi
junit_logs="$(bazel info bazel-testlogs)"
case "${OSTYPE}" in
    msys*|cygwin*) junit_logs="$(cygpath -u "${junit_logs}")" ;;
esac
for target in "${junit_targets[@]}"; do
    report="${junit_logs}/${target#//:}/test.xml"
    grep -F 'tests="2" failures="1" errors="0" skipped="0"' "${report}" >/dev/null
    grep -F 'name="intentional_failure"' "${report}" >/dev/null
    grep -F 'name="passing_case"' "${report}" >/dev/null
    grep -F 'expected &lt;value&gt;' "${report}" >/dev/null
    grep -F 'actual &amp; value' "${report}" >/dev/null
    echo "[EXPECTED FAILURE: JUnit fixture] ${target}: Bazel collected per-function failure XML"
done
