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

## Failure diagnostics

Failed expectations print `source-file:line: test failure` on stderr before their
value or command diagnostics. The location is the first assertion call outside
the framework; if an assertion is inside a user-defined helper, it points into
that helper. Locations remain available for assertions in subshells and command
substitutions, and are included in JUnit failure text and captured stderr.

`expect_files_eq` prints its unified diff on stderr whenever files differ, without
requiring `--verbose`. The complete diff is also saved as `<result-file>.diff`.
JUnit reports include the diff, so CI does not need access to a sandbox path to
show what changed. Successful comparisons and successful golden updates do not
print a failure location or diff. Verbose mode does not duplicate failure diffs.

Strict mode's unhandled-command errors continue to identify the failed command
and exit status. They do not claim a source line: Bash 3.2's `ERR` trap metadata
can point at the function declaration rather than the failing command.

## Scratch retention

`--keep-tmpdir=failure` is the default. It preserves the runner-owned
`${BASHTEST_TMPDIR}` after a nonzero process exit, a failed case or lifecycle hook,
an aborted run, invalid runner settings, or a report-writing error. Handling a
nonzero `test_runner` return does not erase that failure for retention purposes.
Failed expectations outside the runner also retain their scratch data, including
failures recorded by waited descendant shells. Successful runs remove it.

`--keep-tmpdir=never` removes owned scratch data even on failure;
`--keep-tmpdir=always` preserves it even on success. Cleanup preserves the original
nonzero process exit status, including signal-derived statuses. If creating the
scratch directory fails, cleanup leaves the caller's `${TEST_TMPDIR}` alone.
Only the runner-created directory is removed, and retained paths are printed to
stderr. Bazel may still delete its sandbox; use local execution or
`--sandbox_debug` when investigating retained artifacts.

## Command failure handling

`expect_success command args...` checks for exit status 0.
`expect_exit_code status command args...` checks for the specified status in
0..255. Arguments are passed directly without string evaluation; stdout and
stderr are preserved, and shell functions run in the same shell:

```sh
test::generator() {
    expect_success "${GENERATOR}" --output "${TEST_TMPDIR}/result with spaces"
    expect_exit_code 2 "${GENERATOR}" --invalid-option
}
```

A failed expectation remains a failure even if its return status is handled or
followed by a successful command. This includes expectations in command
substitutions, `(subshells)`, and background jobs that the test waits for.
`test_has_error` sees these failures in the parent shell. Tests must wait for
background assertion work before returning; long-lived services may instead
be stopped in teardown. Each test and lifecycle hook starts with a
fresh error state; failures do not leak into subsequent cases.

By default, ordinary commands follow Bash's final-return-status semantics.
Calling a test function to collect its return code suppresses `set -e` within
that function, so `false; echo done` alone does not fail a case. Use command
expectations, or opt into strict checking:

```sh
bazel test //path:my_test --test_arg=--strict-commands
```

`--strict-commands` (also `--strict_commands`) records unhandled nonzero command
and pipeline statuses through Bash's `ERR` trap, even if a later command succeeds.
It covers setup, test bodies, teardown, and inherited subshells. Expected failures
handled by `if`, `!`, `&&`, or `||` retain ordinary Bash semantics. Command-exit
expectations deliberately check the command's final status, including expected
nonzero statuses. Strict checking collects failures rather than stopping at the
first one, and shared setup/test state is preserved.

Strict mode requires `test_runner` as a standalone statement, outside conditional
or other contexts that suppress Bash error traps. Unsupported invocation produces
an explicit runner error before tests execute. The runner temporarily owns the
`ERR` trap and `errexit`/`errtrace` options during each function and restores the
caller's settings afterward; do not replace that trap inside a strict test.
Default mode preserves existing conditional runner calls and caller error options.

## Filtering, sharding, and fail-fast

Bazel's native filter selects bare case names without the `test::` prefix:

```sh
bazel test //path:my_test --test_filter='^(reads|writes)_'
```

Bazel supplies this as `TESTBRIDGE_TEST_ONLY`. Bashtest interprets it as a Bash
extended regular expression, with substring matching unless anchored. An explicit
runner filter (`--test_arg=--test_filter=...`, `-f`, or `--gtest_filter`) replaces
that environment default, including an explicitly empty filter. If both explicit
regex and glob filters are provided, their union is selected, preserving the
existing behavior. Invalid regular expressions fail before lifecycle hooks run.
A filter selecting no cases retains exit status 2.

`--gtest_filter` is a legacy name for one **Bash glob**. It does not implement
GoogleTest's colon-separated lists or negative-filter grammar, and `GTEST_FILTER`
is not read. Use a regex such as `^(alpha|beta)$` for multiple names.

The macro's `shard_count` attribute and Bazel's `--test_sharding_strategy` work
with `test_runner`, including a plain `sh_test` sourcing the framework. Cases are
sorted by name in the C locale, excluding lifecycle hooks, then assigned round
robin using `TEST_TOTAL_SHARDS` and zero-based `TEST_SHARD_INDEX`. Filtering is
applied within that stable assignment; each case appears in only its owner's
console/XML report. Each shard acknowledges `TEST_SHARD_STATUS_FILE`.

A shard with no selected cases passes if at least one case matched across the
whole suite; its hooks do not run. A completely empty shard writes a valid report
with zero cases. A shard owning only filtered-out cases reports those as skipped.
Nonempty shards run their own setup and teardown. Tests that depend on another
case's shell state must stay in one shard. Shard variables must be supplied
together as canonical decimal integers of at most nine digits, with a positive
count and an index below the count. Invalid settings or a failed shard-status
write fail before hooks execute.

`bazel test --test_runner_fail_fast` sets `TESTBRIDGE_TEST_RUNNER_FAIL_FAST=1`.
After the first failed case, bashtest marks remaining selected cases in that
shard as skipped and still runs `test_done`. Runtime skips alone do not trigger
fail-fast, unless `--no-skip` turns them into failures. Other shards and targets
are independent; Bazel's `--notest_keep_going` controls stopping between targets.

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

With reporting enabled, function output streams to its original stdout/stderr
while a copy is captured for the report. Standard `head`, `tail`, `tee`, and `wc` tools
must be available on `PATH`; they are included in the managed Windows runtime.
macOS also uses its system `ps` to detect an exited, unreaped coordinator.
Functions still run in the same shell, and setup/teardown state remains visible
to the tests. Capture workers do not
join a test's `wait` or `wait -n`. Background services may keep writing across
setup, cases, and teardown; captured output is attributed to the function active
when it was written. Output between functions is still streamed. Tests should
wait for background assertions before returning and stop services in teardown.
A capture failure makes the test fail as a reporting error rather than silently
losing output. Failed `test_init` and `test_done` hooks appear as additional error
cases; successful hooks do not count as test cases. Filters
produce skipped cases, and `--no-skip` turns runtime skip requests into failures.
An assertion failure or nonzero function return always takes precedence over a
skip request, even if the skip happens after the failure. Invalid extended
regular expressions fail both `expect_matches` and `expect_not_matches` with a
syntax-error diagnostic.
The existing exit code 2 for no passing or failing cases is retained and recorded
as a `test_runner` error. An early exit or a catchable signal during a function
records that function as an error and retains a nonzero exit status; `exit 0`
inside a function is also an error because it aborts the runner.

Before each setup, test, or teardown function, the runner atomically writes a
provisional report containing completed cases and an error for the function
about to run. Its message explicitly labels the report provisional. A completed
run replaces that checkpoint with final results. Termination without cleanup,
such as SIGKILL, leaves the last written checkpoint identifying the function
whose completion was not yet recorded. Readers detect coordinator death, drain
a finite snapshot, and exit even without a stop request. Output already streamed
remains in Bazel's test log; use
`--test_output=streamed` to see output while Bazel runs. Catchable signals finalize
the report with available output. A failed progress-report write prevents the
function from running and fails the target. Reporting begins at `test_runner`;
if termination happens before any report exists, Bazel supplies its fallback.

Nested runner/verifier scripts should select their own output file, or disable
reporting with `GTEST_OUTPUT=`, so an expected failure does not become the parent
target's report.
Verifier fixtures should also choose their own selection environment: clear
`TESTBRIDGE_TEST_ONLY`, set `TESTBRIDGE_TEST_RUNNER_FAIL_FAST=0`, and use
`TEST_TOTAL_SHARDS=1 TEST_SHARD_INDEX=0 TEST_SHARD_STATUS_FILE=` for an unsharded
child. This prevents the parent's filter, shard assignment, or acknowledgement
file from changing the fixture being verified.
