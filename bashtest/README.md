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
