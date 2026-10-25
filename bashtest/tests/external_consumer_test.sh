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
    if ! ci_collect_pending "${events}" "${PWD}" "external"; then
        if [[ "${status}" == 0 ]]; then status=1; fi
    fi
    # Windows cannot remove a directory while it is a process working directory.
    bazel shutdown >/dev/null 2>&1 || true
    cd "${repo}"
    rm -rf "${root}"
    exit "${status}"
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
bazel test --build_event_json_file="${events}/external-full.json" --enable_runfiles=no --test_output=errors //:consumer_test @framework//bashtest/tests/...
ci_collect "${events}/external-full.json"
# A filtered/sharded meta-test must not leak its settings into verifier fixtures.
bazel test --build_event_json_file="${events}/external-meta-shards.json" --enable_runfiles=no --test_filter='^junit_cases_and_failures$' \
    --test_sharding_strategy=forced=5 @framework//bashtest/tests:junit_test
ci_collect "${events}/external-meta-shards.json"
bazel run --build_event_json_file="${events}/external-run.json" --enable_runfiles=no //:consumer_test -- --keep-tmpdir=never
ci_collect "${events}/external-run.json"

# Exercise both documented update spellings with a workspace path containing spaces.
# Separate MSYS2 installations have different /tmp mounts. Cross the native
# Bazel boundary with a Windows path that identifies the same directory in both.
workspace="${PWD}"
case "${OSTYPE}" in
    msys*|cygwin*) workspace="$(cygpath -am "${workspace}")" ;;
esac
printf 'stale\n' > golden.txt
bazel run --build_event_json_file="${events}/external-update-long.json" --enable_runfiles=no //:consumer_test -- --update-golden="${workspace}" --keep-tmpdir=never
ci_collect "${events}/external-update-long.json"
[[ "$(cat golden.txt)" == 'hello world' ]]
printf 'stale again\n' > golden.txt
bazel run --build_event_json_file="${events}/external-update-short.json" --enable_runfiles=no //:consumer_test -- -u="${workspace}" --keep-tmpdir=never
ci_collect "${events}/external-update-short.json"
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
if bazel test --build_event_json_file="${events}/expected/external-junit-failure.json" --enable_runfiles=no "${junit_targets[@]}" > junit_failure.log 2>&1; then
    echo >&2 'ERROR: intentionally failing JUnit fixtures passed'
    exit 1
fi
ci_collect "${events}/expected/external-junit-failure.json"
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

# Exercise native Bazel flags through the macro and plain sh_test. These manual
# fixtures are invoked explicitly because their unfiltered beta case must fail.
cat >> BUILD.bazel <<'EOF'
bashtest(
    name = "selection_test",
    srcs = ["selection.sh"],
    tags = ["manual"],
)
EOF
cat > selection.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"
# shellcheck disable=SC2317
test::alpha() { echo CASE:alpha; if [[ "${FAIL_CASE:-}" == alpha ]]; then expect_eq yes no; fi; }
# shellcheck disable=SC2317
test::beta() { echo CASE:beta; expect_eq filtered_case must_not_run; }
# shellcheck disable=SC2317
test::gamma() { echo CASE:gamma; }
# shellcheck disable=SC2317
test::test_done() { echo DONE; }
test_runner
EOF
chmod +x selection.sh
selection_targets=(//:selection_test)
case "${OSTYPE}" in
    msys*|cygwin*) ;;
    *)
        cat >> BUILD.bazel <<'EOF'
sh_test(
    name = "selection_sh_test",
    srcs = ["selection.sh"],
    data = ["@framework//bashtest:bashtest_sh"],
    env = {"mboworks_bashtest": "$(rootpath @framework//bashtest:bashtest_sh)"},
    tags = ["manual"],
)
EOF
        selection_targets+=(//:selection_sh_test)
        ;;
esac
bazel test --build_event_json_file="${events}/external-filter.json" --enable_runfiles=no --test_filter='^(alpha|gamma)$' "${selection_targets[@]}"
ci_collect "${events}/external-filter.json"
bazel test --build_event_json_file="${events}/external-shards.json" --enable_runfiles=no --test_filter='^(alpha|gamma)$' \
    --test_sharding_strategy=forced=5 "${selection_targets[@]}"
ci_collect "${events}/external-shards.json"
for target in "${selection_targets[@]}"; do
    reports=("${junit_logs}/${target#//:}"/shard_*/test.xml)
    [[ "${#reports[@]}" == 5 ]]
    alpha=0 gamma=0 empty=0
    for report in "${reports[@]}"; do
        if grep -F 'name="alpha"' "${report}" >/dev/null; then ((alpha+=1)); fi
        if grep -F 'name="gamma"' "${report}" >/dev/null; then ((gamma+=1)); fi
        if grep -F 'tests="0" failures="0" errors="0"' "${report}" >/dev/null; then ((empty+=1)); fi
    done
    [[ "${alpha}" == 1 && "${gamma}" == 1 && "${empty}" == 2 ]]
    echo "[SHARDING VERIFIED] ${target}: five reports, each selected case once, two empty reports"
done
if bazel test --build_event_json_file="${events}/expected/external-fail-fast.json" --enable_runfiles=no --test_runner_fail_fast --test_env=FAIL_CASE=alpha \
    "${selection_targets[@]}" > selection_failure.log 2>&1; then
    echo >&2 'ERROR: intentionally failing fail-fast fixtures passed'
    exit 1
fi
ci_collect "${events}/expected/external-fail-fast.json"
for target in "${selection_targets[@]}"; do
    report="${junit_logs}/${target#//:}/test.xml"
    grep -F 'tests="3" failures="1" errors="0" skipped="2"' "${report}" >/dev/null
    grep -F 'fail-fast' "${report}" >/dev/null
    grep -F 'DONE' "${junit_logs}/${target#//:}/test.log" >/dev/null
    if grep -F 'CASE:beta' "${junit_logs}/${target#//:}/test.log"; then
        echo >&2 'ERROR: fail-fast executed a later case'
        exit 1
    fi
    echo "[EXPECTED FAILURE: fail-fast fixture] ${target}: later cases skipped and teardown ran"
done

# Verify an actual Bazel timeout keeps the active function's custom report and
# the last live diagnostic, on managed Windows as well as Unix.
cat >> BUILD.bazel <<'EOF'
bashtest(
    name = "interrupted_test",
    srcs = ["interrupted.sh"],
    tags = ["manual"],
)
EOF
cat > interrupted.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090,SC1091,SC2154
source "${mboworks_bashtest}"
# shellcheck disable=SC2317
test::a_completed() { expect_eq ok ok; }
# shellcheck disable=SC2317
test::b_hanging() {
    echo last_diagnostic_before_timeout >&2
    while :; do sleep 1; done
}
test_runner
EOF
chmod +x interrupted.sh
interrupted_targets=(//:interrupted_test)
case "${OSTYPE}" in
    msys*|cygwin*) ;;
    *)
        cat >> BUILD.bazel <<'EOF'
sh_test(
    name = "interrupted_sh_test",
    srcs = ["interrupted.sh"],
    data = ["@framework//bashtest:bashtest_sh"],
    env = {"mboworks_bashtest": "$(rootpath @framework//bashtest:bashtest_sh)"},
    tags = ["manual"],
)
EOF
        interrupted_targets+=(//:interrupted_sh_test)
        ;;
esac
if bazel test --build_event_json_file="${events}/expected/external-timeout.json" --enable_runfiles=no --test_timeout=10 "${interrupted_targets[@]}" > interrupted.log 2>&1; then
    echo >&2 'ERROR: intentionally hanging fixtures passed'
    exit 1
fi
ci_collect "${events}/expected/external-timeout.json"
for target in "${interrupted_targets[@]}"; do
    grep -F "${target}" interrupted.log | grep -F TIMEOUT >/dev/null
    report="${junit_logs}/${target#//:}/test.xml"
    grep -F 'name="a_completed"' "${report}" >/dev/null
    grep -F 'name="b_hanging"' "${report}" >/dev/null
    grep -F '<error' "${report}" >/dev/null
    grep -F last_diagnostic_before_timeout "${junit_logs}/${target#//:}/test.log" >/dev/null
    echo "[EXPECTED FAILURE: timeout fixture] ${target}: active-case error report and live diagnostic retained"
done
