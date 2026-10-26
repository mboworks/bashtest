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

# Integration test: distinct default and test execution platforms, external module.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=bashtest/tests/ci_support.sh
source "${repo}/bashtest/tests/ci_support.sh"
# The override consumes this checkout, including unreleased development versions.
version="$(sed -nE 's/.*version = "([^"]+)".*/\1/p' "${repo}/MODULE.bazel" | head -n1)"
root="$(mktemp -d)"
events="${root}/events"
mkdir -p "${events}/expected"
case "${OSTYPE}" in
    msys*|cygwin*) events="$(cygpath -am "${events}")" ;;
esac
cleanup() {
    local status="${?}"
    ci_failure_logs "${status}" "${PWD}"
    if ! ci_collect_pending "${events}" "${PWD}" "tools"; then
        if [[ "${status}" == 0 ]]; then status=1; fi
    fi
    bazel shutdown >/dev/null 2>&1 || true
    cd "${repo}"
    rm -rf "${root}"
    exit "${status}"
}
trap cleanup EXIT
case "${OSTYPE}" in
    msys*|cygwin*) repo="$(cygpath -m "${repo}")" ;;
esac
mkdir -p "${root}/tools consumer"
cd "${root}/tools consumer"
cp "${repo}/.bazelversion" .bazelversion
cp "${repo}/bashtest/tests/tool_fixture.bzl" tool_fixture.bzl
cat > MODULE.bazel <<EOF
module(name = "tools_consumer")
bazel_dep(name = "mboworks_bashtest", version = "${version}", repo_name = "framework")
local_path_override(module_name = "mboworks_bashtest", path = "${repo}")
bazel_dep(name = "rules_shell", version = "0.8.0")
bazel_dep(name = "platforms", version = "1.1.0")
EOF
cat > BUILD.bazel <<'EOF'
load("@framework//bashtest:bashtest.bzl", "bashtest")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load(":tool_fixture.bzl", "configuration_data", "tool_source")
constraint_setting(name = "role")
constraint_value(name = "ordinary_role", constraint_setting = ":role")
constraint_value(name = "test_role", constraint_setting = ":role")
platform(name = "ordinary_exec", parents = ["@platforms//host"], constraint_values = [":ordinary_role"])
platform(name = "test_exec", parents = ["@platforms//host"], constraint_values = [":test_role"])
config_setting(name = "is_test_exec", constraint_values = [":test_role"])
configuration_data(
    name = "tool_data",
    platform_marker = select({":is_test_exec": "test-platform", "//conditions:default": "other-platform"}),
)
configuration_data(name = "target_data")
tool_source(name = "helper_source", data = ":tool_data")
sh_binary(name = "helper", srcs = [":helper_source"])
bashtest(
    name = "consumer_test",
    srcs = ["consumer.sh"],
    data = [":target_data"],
    env = {"TARGET_DATA": "$(rlocationpath :target_data)"},
    tools = {"HELPER": ":helper"},
    exec_group_compatible_with = {"test": [":test_role"]},
)
bashtest(
    name = "invalid_tool_test",
    srcs = ["consumer.sh"],
    tools = {"HELPER": ":target_data"},
    tags = ["manual"],
)
bashtest(
    name = "collision_test",
    srcs = ["consumer.sh"],
    tools = {"HELPER": ":helper"},
    env = {"HELPER": "collision"},
    tags = ["manual"],
)
EOF
# Bazel 7 predates per-group constraints; still verify execution-platform tools.
if [[ "$(bazel --version)" == 'bazel 7.'* ]]; then
    sed 's/exec_group_compatible_with = {"test": \[":test_role"\]}/exec_compatible_with = [":test_role"]/' BUILD.bazel > BUILD.tmp
    mv BUILD.tmp BUILD.bazel
fi
cat > consumer.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"
# shellcheck disable=SC2317
test::configuration() {
    expect_eq $'test-platform\nargument with spaces' "$("${HELPER}" 'argument with spaces')"
    expect_eq 'default' "$(cat "$(rlocation "${TARGET_DATA}")")"
}
test_runner
EOF
flags=("--extra_execution_platforms=//:ordinary_exec,//:test_exec" --enable_runfiles=no)
bazel test --build_event_json_file="${events}/tools-test.json" "${flags[@]}" --test_output=errors //:consumer_test
ci_collect "${events}/tools-test.json"
bazel run --build_event_json_file="${events}/tools-run.json" "${flags[@]}" //:consumer_test -- --keep-tmpdir=never
ci_collect "${events}/tools-run.json"
if bazel build --build_event_json_file="${events}/expected/tools-non-executable.json" "${flags[@]}" //:invalid_tool_test >invalid.log 2>&1; then
    echo >&2 'ERROR: non-executable tool was accepted'
    exit 1
fi
ci_collect "${events}/expected/tools-non-executable.json"
grep -F 'tools requires an executable target' invalid.log | sed 's/^/[EXPECTED FAILURE: non-executable tool] /'
if bazel build --build_event_json_file="${events}/expected/tools-collision.json" "${flags[@]}" //:collision_test >collision.log 2>&1; then
    echo >&2 'ERROR: conflicting environment variable was accepted'
    exit 1
fi
ci_collect "${events}/expected/tools-collision.json"
grep -F 'tool environment variable is already defined' collision.log | sed 's/^/[EXPECTED FAILURE: environment collision] /'
