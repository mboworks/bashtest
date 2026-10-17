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

"""Bind helper executables to the execution platform of the actual test action."""

def _rlocation_path(ctx, file):
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    return ctx.workspace_name + "/" + file.short_path

def _validate_name(name):
    letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
    if not name or name[0] not in letters or any([c not in letters + "0123456789" for c in name.elems()]):
        fail("tools keys must be shell environment variable names: " + repr(name))
    if name.startswith(("_BASHTEST", "TEST_", "RUNFILES_", "BASH")) or name in ["mboworks_bashtest", "PATH", "IFS", "SHELLOPTS", "ENV", "EUID", "UID", "PPID"]:
        fail("tools key is reserved by the shell or test runtime: " + name)

def _tools_test_impl(ctx):
    runner = ctx.attr.runner[DefaultInfo]

    # Bazel 7 uses native sh_test, which does not expose RunEnvironmentInfo.
    environment = ctx.attr.runner[RunEnvironmentInfo] if RunEnvironmentInfo in ctx.attr.runner else RunEnvironmentInfo(
        environment = {
            key: ctx.expand_make_variables("env", ctx.expand_location(value, ctx.attr.data), {})
            for key, value in ctx.attr.env.items()
        },
        inherited_environment = ctx.attr.env_inherit,
    )
    entries = []
    tool_files = []
    tool_runfiles = []
    names = []
    for tool, encoded_names in ctx.attr.tools.items():
        if tool.label in [target.label for target in ctx.attr.data]:
            fail("a target cannot be both data and tools: " + str(tool.label))
        info = tool[DefaultInfo]
        executable = info.files_to_run.executable
        if executable == None:
            fail("tools requires an executable target: " + str(tool.label))
        for name in json.decode(encoded_names):
            _validate_name(name)
            if name in names or name in environment.environment or name in environment.inherited_environment:
                fail("tool environment variable is already defined: " + name)
            names.append(name)
            entries.append(name + "\t" + _rlocation_path(ctx, executable) + "\n")
        tool_files.append(executable)
        tool_runfiles.extend([info.default_runfiles, info.data_runfiles])
    manifest = ctx.actions.declare_file(ctx.label.name + ".tools")
    ctx.actions.write(manifest, "".join(entries))

    # Reuse rules_shell's platform-specific launcher, including its Windows exe.
    extension = ".exe" if runner.files_to_run.executable.extension == "exe" else ""
    executable = ctx.actions.declare_file(ctx.label.name + extension)
    ctx.actions.symlink(output = executable, target_file = runner.files_to_run.executable, is_executable = True)
    runfiles = ctx.runfiles(files = tool_files + [manifest]).merge(runner.default_runfiles).merge_all(tool_runfiles)
    return [
        DefaultInfo(executable = executable, runfiles = runfiles),
        RunEnvironmentInfo(
            environment = environment.environment | ({"_BASHTEST_TOOLS_MANIFEST": _rlocation_path(ctx, manifest)} if ctx.attr.tools else {}),
            inherited_environment = environment.inherited_environment,
        ),
        coverage_common.instrumented_files_info(ctx, dependency_attributes = ["runner"]),
    ]

bashtest_tools_test = rule(
    implementation = _tools_test_impl,
    test = True,
    attrs = {
        "data": attr.label_list(allow_files = True),
        "env": attr.string_dict(),
        "env_inherit": attr.string_list(),
        "runner": attr.label(mandatory = True, executable = True, cfg = "target"),
        "tools": attr.label_keyed_string_dict(cfg = config.exec("test")),
        "_collect_cc_coverage": attr.label(
            cfg = config.exec("test"),
            default = "@bazel_tools//tools/test:collect_cc_coverage",
            executable = True,
        ),
        "_lcov_merger": attr.label(
            cfg = config.exec("test"),
            default = configuration_field(fragment = "coverage", name = "output_generator"),
            executable = True,
        ),
    },
    fragments = ["coverage"],
)
