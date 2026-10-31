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

"""Execution-property regression fixture; not part of the consumer fixtures."""

load("//bashtest:bashtest.bzl", "bashtest")

visibility("private")

def execution_properties_test(name):
    """Verify execution properties belong only to the test, then run its launcher.

    Args:
        name: Name of the executable regression test.
    """

    # A neutral property exercises the test exec group in every runfiles mode.
    properties = {"test.bashtest-regression": "1"}
    bashtest(
        name = name,
        srcs = ["exec_properties_test.sh"],
        exec_properties = properties,
    )
    if native.existing_rule(name).get("exec_properties") != properties:
        fail("The outer test must retain its execution properties")
    for suffix in ["__bashtest_launcher", "__bashtest_launcher_windows"]:
        if native.existing_rule(name + suffix).get("exec_properties"):
            fail("Binary launchers must not inherit test execution properties")
