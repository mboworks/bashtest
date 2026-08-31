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

"""mboworks_bashtest/bashtest:bashtest"""

load("@rules_shell//shell:sh_test.bzl", "sh_test")

# Resolve the bashtest runtime relative to *this* module's repository. A `Label`
# constructed in a `.bzl` file is resolved against the repo that defines the
# file, so the macro works no matter what apparent repo name a consumer assigns
# it (and under both bzlmod and the legacy WORKSPACE setup). This is what lets
# the module to work without an apparent repository-name alias.
_BASHTEST_SH = Label("//bashtest:bashtest_sh")

def bashtest(
        name,
        deps = [],
        env = {},
        **kwargs):
    """Bashtest wrapper.

    Specialized `sh_shell` rule to simplify `bashtest` usage. The rule provides
    the `mboworks_bashtest` environment variable that should
    be used in test scripts to source the `bashtest.sh` script as follows:

    * File: sh_test.sh

    ```sh
    set -euo pipefail

    # shellcheck disable=SC1090,SC1091,SC2154
    source "${mboworks_bashtest}"

    test::my_test() {
      expect_ne "Hello" "World"
      # Your tests go here...
    }

    # More tests go here...

    test_runner
    ```

    * File: BUILD

    ```bzl
    load("@mboworks_bashtest//bashtest:bashtest.bzl", "bashtest")

    bashtest(
        name = "sh_test",
        srcs = ["sh_test.sh"],
    )
    ```

    Args:
        name:      Name of the test rule. Should end in `_test`
        deps:      Dependencies which will have bashtest_sh automatically added.
        env:       Environment name that automatically adds `mboworks_bashtest`.
        **kwargs:  All other attributes are passed through as is.
    """

    extra_env = {
        "mboworks_bashtest": "$(rootpath {label})".format(label = _BASHTEST_SH),
    }
    sh_test(
        name = name,
        deps = deps + [_BASHTEST_SH],
        env = env | extra_env,
        **kwargs
    )
