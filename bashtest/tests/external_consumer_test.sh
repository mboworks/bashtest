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
root="$(mktemp -d)"
trap 'rm -rf "${root}"' EXIT
case "${OSTYPE}" in
    msys*|cygwin*) repo="$(cygpath -m "${repo}")" ;;
esac
mkdir -p "${root}/consumer with spaces"
cd "${root}/consumer with spaces"
cp "${repo}/.bazelversion" .bazelversion
cat > MODULE.bazel <<EOF
module(name = "consumer")
bazel_dep(name = "mboworks_bashtest", version = "0.6.2", repo_name = "framework")
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
bazel test --enable_runfiles=no --test_output=errors //:consumer_test
bazel run --enable_runfiles=no //:consumer_test -- --keep-tmpdir=never
