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

"""Pinned Windows runtime, downloaded only when a Windows test needs it."""

def _runtime_impl(ctx):
    ctx.download_and_extract(
        url = "https://repo.msys2.org/distrib/x86_64/msys2-base-x86_64-20260927.tar.xz",
        sha256 = "ea2f31a0b6ade63914ce441ffb022f0f6aa96982bfefa2326460a26d5fb01322",
        stripPrefix = "msys64",
    )
    ctx.download_and_extract(
        url = "https://repo.msys2.org/msys/x86_64/diffutils-3.12-1-x86_64.pkg.tar.zst",
        sha256 = "7902c8ce3d4dd69a0f5e98dc9d5c83c17b23314ba486169db57ef6e2835ce3b6",
    )
    ctx.file("BUILD.bazel", '''
load("@rules_shell//shell/toolchains:sh_toolchain.bzl", "sh_toolchain")

package(default_visibility = ["//visibility:public"])
exports_files(["usr/bin/bash.exe"])
filegroup(
    name = "runtime",
    srcs = glob(["usr/bin/**", "usr/share/licenses/**"]),
)
sh_toolchain(
    name = "shell",
    path = {bash_path},
    launcher = "@bazel_tools//tools/launcher:launcher",
    launcher_maker = "@bazel_tools//tools/launcher:launcher_maker",
)
'''.format(bash_path = repr(str(ctx.path("usr/bin/bash.exe")))))

windows_runtime = repository_rule(implementation = _runtime_impl)
