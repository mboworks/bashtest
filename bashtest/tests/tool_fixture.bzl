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

"""Configuration-sensitive fixtures for executable helper tests."""

def _path(ctx, file):
    return file.short_path[3:] if file.short_path.startswith("../") else ctx.workspace_name + "/" + file.short_path

def _configuration_data_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.write(output, ctx.attr.platform_marker + "\n")
    return [DefaultInfo(files = depset([output]))]

configuration_data = rule(
    implementation = _configuration_data_impl,
    attrs = {"platform_marker": attr.string(default = "default")},
)

def _tool_source_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output,
        "#!/usr/bin/env bash\nset -euo pipefail\ncat \"$(rlocation '" + _path(ctx, ctx.file.data) + "')\"\nprintf '%s\\n' \"$@\"\n",
        is_executable = True,
    )
    return [DefaultInfo(files = depset([output]), runfiles = ctx.runfiles(files = [ctx.file.data]))]

tool_source = rule(
    implementation = _tool_source_impl,
    attrs = {"data": attr.label(allow_single_file = True)},
)
