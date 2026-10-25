# mboworks_bashtest//bashtest

Bashtest provides `sh_test` wrapper that simplifies the creation of shell tests.


  * bashtest:bashtest, bashtest/bashtest.sh
  * sh_library `bashtest_sh` which provides a test runner for complex shell tests involving golden files that provides built-in golden update functionality (see `bazel run //bashtest:bashtest_help`).
    * status helper `test_has_error`: Returns whether a test function has had an expectation error. This is reset for every test function.
    * status helper `test_has_failed_tests`: Returns whether a test program had previous failing test functions.
    * scratch helper `test_tmpdir [name]`: Creates and prints a unique directory below `${BASHTEST_TMPDIR}`.
    * expectation `expect_eq` "\${LHS}" "\${RHS}": Asserts that two strings are the same.
    * expectation `expect_ne` "\${LHS}" "\${RHS}": Asserts that two strings are different.
    * expectation `expect_files_eq` "\${LHS}" "\${RHS}": Asserts that two files are the same (supports golden updates).
    * expectation `expect_contains` "\${EXPECTED}" "\${ARRAY[@]}": Assert that one string is present in an array.
    * expectation `expect_not_contains` "\${EXPECTED}" "\${ARRAY[@]}": Assert that one string is not present in an array.
    * expectation `expect_output_contains` "\${SUBSTRING}" "\${TEXT}": Assert that a text contains a literal substring.
    * expectation `expect_output_not_contains` "\${SUBSTRING}" "\${TEXT}": Assert that a text does not contain a literal substring.
    * expectation `expect_matches` "\${REGEX}" "\${TEXT}": Assert that a text matches an extended regular expression (bash built-in; `^`/`$` anchor the whole text).
    * expectation `expect_not_matches` "\${REGEX}" "\${TEXT}": Assert that a text does not match an extended regular expression.
    * expectation `expect_pcre_matches` "\${REGEX}" "\${TEXT}": Assert that a text matches a Perl Compatible Regular Expression (requires an external PCRE tool).
    * expectation `expect_pcre_not_matches` "\${REGEX}" "\${TEXT}": Assert that a text does not match a Perl Compatible Regular Expression.
    * control `skip_test` "\${REASON}": Marks the current test as skipped and reports the reason. Use `skip_test "reason" && return` to end the test body.
    * special test function `test::test_init`: If present, then this function runs first! Tests will only be executed if it succeeds.
    * special test function `test::test_done`: If present, then this function runs last!

The macro supports directory and manifest-only runfiles on Linux, macOS, and
Windows x86-64 with an automatically provisioned MSYS2 runtime. See the root [installation requirements](../README.md#installation-and-requirements)
for Windows setup and resolving data dependencies with `rlocation`.

## Executable tools

Use `tools` to build helper executables for the test execution platform and export
resolved paths automatically:

```starlark
bashtest(
    name = "generator_test",
    srcs = ["generator_test.sh"],
    tools = {"GENERATOR": "//tools:generator"},
)
```

The script can invoke `"${GENERATOR}" --output "${TEST_TMPDIR}/result"`.
Tools must be executable Bazel targets; their runtime runfiles are included.
This uses the test execution group, including `exec_group_compatible_with` on Bazel 8 and newer, so
cross-compilation builds helpers for the platform running the test. `data`
continues to use the target configuration. Do not put the same target in both
`data` and `tools`. Multiple names may refer to the same tool.

Keys must be shell environment variable names and must not conflict with `env`
or `env_inherit`. Names beginning with `_BASHTEST`, `TEST_`, `RUNFILES_`, or `BASH`,
and `mboworks_bashtest`, `PATH`, `IFS`, `SHELLOPTS`, `ENV`, `EUID`, `UID`, and
`PPID` are reserved. Quote exported paths when invoking tools, including on
Windows. No `$(location ...)` expansion is needed for tool paths.

## JUnit XML for CI

When run with `bazel test`, `test_runner` writes a JUnit-style XML report to
Bazel's `XML_OUTPUT_FILE`. Bazel collects it as
`bazel-testlogs/<package>/<target>/test.xml`. Each `test::name` becomes a separate
`testcase`; reports include durations in whole seconds, assertion diagnostics,
return-code failures, skipped cases and their reasons, and captured function
output. XML text is escaped, and invalid UTF-8 or XML 1.0 bytes become `?`.

This also works with a plain `rules_shell` `sh_test` that sources `bashtest.sh`
and calls `test_runner`: reporting uses Bazel's standard test environment and
requires no extra rule attribute. The bashtest macro supplies the framework and
its managed Windows runtime as usual; a plain `sh_test` retains its own shell
and runfiles configuration.

Outside `bazel test`, enable a report with either of:

```sh
GTEST_OUTPUT=xml:results.xml ./my_test.sh
bazel run //path:my_test -- --gtest_output=xml:results.xml
```

Selection follows GoogleTest's precedence: `--gtest_output` (or
`--gtest-output`) overrides `GTEST_OUTPUT`, which overrides `XML_OUTPUT_FILE`.
`xml` and `xml:` default to `test_detail.xml` in the initial working directory.
A directory path ending in `/` selects `<script-name>.xml`, adding `_1`, `_2`,
and so on if a report already exists. Parent directories are created. An explicit
file path replaces that file. With `bazel run`, use an absolute output path to
keep the location independent of Bazel's working directory. An empty
`GTEST_OUTPUT` or `--gtest_output=` disables reporting. JSON output is unsupported;
an unsupported format or failure to write a report makes the test fail.

With reporting enabled, function output is buffered and replayed after each
function, while functions continue to run in the same shell. Setup and teardown
state remains visible to the tests. Failed `test_init` and `test_done` hooks appear
as additional error cases; successful hooks do not count as test cases. Filters
produce skipped cases, and `--no-skip` turns runtime skip requests into failures.
An assertion failure or nonzero function return always takes precedence over a
skip request, even if the skip happens after the failure. Invalid extended
regular expressions fail both `expect_matches` and `expect_not_matches` with a
syntax-error diagnostic.
The existing exit code 2 for no passing or failing cases is retained and recorded
as a `test_runner` error. An early exit or a catchable signal during a function
records that function as an error and retains a nonzero exit status; `exit 0`
inside a function is also an error because it aborts the runner. SIGKILL and
machine termination cannot be handled; Bazel supplies its fallback reporting when
no custom report exists. Reporting begins when `test_runner` is called.

Nested runner/verifier scripts should select their own output file, or disable
reporting with `GTEST_OUTPUT=`, so an expected failure does not become the parent
target's report.
