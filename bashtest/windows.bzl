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

"""Windows test launcher with a declared MSYS2 runtime."""

def _path(ctx, file):
    return file.short_path[3:] if file.short_path.startswith("../") else ctx.workspace_name + "/" + file.short_path

def _windows_test_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name + ".exe")
    info = ctx.actions.args().use_param_file("%s", use_always = True).set_param_file_format("multiline")
    info.add("binary_type=Bash")
    info.add(ctx.workspace_name, format = "workspace_name=%s")

    # Bazel emits a manifest even when runfiles trees are enabled. Prefer it
    # without relying on rules_shell-only configuration APIs.
    info.add("symlink_runfiles_enabled=0")
    info.add(_path(ctx, ctx.file._bash), format = "bash_bin_path=%s")
    info.add(_path(ctx, ctx.file._launcher), format = "bash_file_rlocationpath=%s")
    ctx.actions.run(
        executable = ctx.executable._launcher_maker,
        inputs = [ctx.executable._native_launcher],
        outputs = [executable],
        arguments = [ctx.executable._native_launcher.path, info, executable.path],
    )
    dependencies = ctx.attr.data + ctx.attr.deps + [ctx.attr._runtime]
    runfiles = ctx.runfiles(files = [ctx.file._launcher, ctx.file._bash])
    for dependency in dependencies:
        default = dependency[DefaultInfo]
        runfiles = runfiles.merge(ctx.runfiles(transitive_files = default.files)).merge(default.default_runfiles)
    return [
        DefaultInfo(executable = executable, runfiles = runfiles),
        RunEnvironmentInfo(
            environment = {key: ctx.expand_make_variables("env", ctx.expand_location(value, ctx.attr.data), {}) for key, value in ctx.attr.env.items()},
            inherited_environment = ctx.attr.env_inherit,
        ),
        coverage_common.instrumented_files_info(ctx, dependency_attributes = ["data", "deps"]),
    ]

windows_bashtest_test = rule(
    implementation = _windows_test_impl,
    test = True,
    attrs = {
        "data": attr.label_list(allow_files = True),
        "deps": attr.label_list(),
        "env": attr.string_dict(),
        "env_inherit": attr.string_list(),
        "_bash": attr.label(default = "@bashtest_windows_runtime//:usr/bin/bash.exe", allow_single_file = True),
        "_launcher": attr.label(default = "//bashtest:launcher.sh", allow_single_file = True),
        "_launcher_maker": attr.label(default = "@bazel_tools//tools/launcher:launcher_maker", executable = True, cfg = "exec"),
        "_native_launcher": attr.label(default = "@bazel_tools//tools/launcher:launcher", executable = True, cfg = "target"),
        "_runtime": attr.label(default = "@bashtest_windows_runtime//:runtime"),
    },
)
