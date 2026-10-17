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

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load(":tools.bzl", "bashtest_tools_test")
load(":windows.bzl", "windows_launcher_binary")

# Resolve the bashtest runtime relative to *this* module's repository. A `Label`
# constructed in a `.bzl` file is resolved against the repo that defines the
# file, so the macro works no matter what apparent repo name a consumer assigns
# it through bzlmod. This lets the module work without an apparent
# repository-name alias.
_BASHTEST_SH = Label("//bashtest:bashtest_sh")
_LAUNCHER = Label("//bashtest:launcher.sh")
_RUNFILES = Label("@rules_shell//shell/runfiles")

def bashtest(
        name,
        deps = [],
        env = {},
        srcs = [],
        data = [],
        tools = {},
        **kwargs):
    """Bashtest wrapper.

    Specialized `sh_test` rule to simplify `bashtest` usage. The rule provides
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
        srcs:      Exactly one Bash test script.
        data:      Runtime files made available through Bazel runfiles.
        deps:      Dependencies which will have bashtest_sh automatically added.
        env:       Environment name that automatically adds `mboworks_bashtest`.
        tools:     Environment variable names mapped to executable targets built for test execution.
        **kwargs:  All other attributes are passed through as is.
    """

    # Keep configurable srcs working; rlocationpath validates that the selected
    # filegroup expands to exactly one file during analysis.
    script = name + "__bashtest_script"
    native.filegroup(
        name = script,
        srcs = srcs,
        testonly = True,
        visibility = ["//visibility:private"],
    )
    extra_env = {
        "mboworks_bashtest": "$(rlocationpath {label})".format(label = _BASHTEST_SH),
        "_BASHTEST_SCRIPT": "$(rlocationpath {label})".format(label = ":" + script),
    }
    # Define an executable launcher, not another test. The single test below
    # owns both this executable and every execution-platform tool dependency.
    runner_name = name + "__bashtest_launcher"
    launcher_kwargs = dict(kwargs)
    for attribute in ["args", "env_inherit", "size", "timeout", "flaky", "shard_count", "local", "exec_group_compatible_with"]:
        launcher_kwargs.pop(attribute, None)
    launcher_kwargs["testonly"] = True
    compatibility = kwargs.get("target_compatible_with", [])
    launcher_kwargs["target_compatible_with"] = compatibility + select({
        str(Label("//bashtest:windows")): ["@platforms//:incompatible"],
        "//conditions:default": [],
    })
    sh_binary(
        name = runner_name,
        srcs = [_LAUNCHER],
        deps = deps + [_BASHTEST_SH, _RUNFILES],
        data = data + [":" + script, _BASHTEST_SH],
        **launcher_kwargs
    )
    launcher_kwargs.pop("use_bash_launcher", None)
    launcher_kwargs["target_compatible_with"] = compatibility + select({
        str(Label("//bashtest:windows")): [],
        "//conditions:default": ["@platforms//:incompatible"],
    })
    windows_launcher_binary(
        name = runner_name + "_windows",
        deps = deps + [_BASHTEST_SH, _RUNFILES],
        data = data + [":" + script, _BASHTEST_SH],
        **launcher_kwargs
    )
    outer_kwargs = dict(kwargs)
    outer_kwargs.pop("use_bash_launcher", None)
    tool_names = {}
    for variable, label in tools.items():
        tool_names.setdefault(label, []).append(variable)
    bashtest_tools_test(
        name = name,
        runner = select({
            str(Label("//bashtest:windows")): ":" + runner_name + "_windows",
            "//conditions:default": ":" + runner_name,
        }),
        env = env | extra_env,
        tools = {label: json.encode(names) for label, names in tool_names.items()},
        data = data + [":" + script, _BASHTEST_SH],
        **outer_kwargs
    )
