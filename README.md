# bashtest.sh - A Bazel shell test runner.

This shell test library provides Bazel macro rules to simplify shell testing.

The library is tested with continuous integration: [![Test](https://github.com/helly25/bashtest/actions/workflows/main.yml/badge.svg)](https://github.com/helly25/bashtest/actions/workflows/main.yml).

## Bashtest

Run one of the following commands to get detailed information on the actual bashtest.sh script:

* `bazel run //bashtest:bashtest_help`
* `bazel run //bashtest:bashtest_help | pandoc -s -t man | man -l -`
* `bazel run //bashtest:bashtest_help | pandoc | lynx -stdin`

The flags can be used on the `bazel run` and `bazel test` commands (the latter requiring `--test_arg=...`).

### Functionality

* status helper `test_has_error`: Returns whether a test function has had an expectation error. This is reset for every test function.
* status helper `test_has_failed_tests`: Returns whether a test program had previous failing test functions.
* expectation `expect_eq` "\${LHS}" "\${RHS}": Asserts that two strings are the same.
* expectation `expect_ne` "\${LHS}" "\${RHS}": Asserts that two strings are different.
* expectation `expect_files_eq` "\${LHS}" "\${RHS}": Asserts that two file are the same (supports golden updates).
* expectation `expect_contains` "\${EXPECTED}" "\${ARRAY[@]}": Assert that one string is present in an array.
* expectation `expect_not_contains` "\${EXPECTED}" "\${ARRAY[@]}": Assert that one string is not present in an array.
* expectation `expect_output_contains` "\${SUBSTRING}" "\${TEXT}": Assert that a text contains a literal substring.
* expectation `expect_output_not_contains` "\${SUBSTRING}" "\${TEXT}": Assert that a text does not contain a literal substring.
* expectation `expect_matches` "\${REGEX}" "\${TEXT}": Assert that a text matches an extended regular expression (bash built-in; `^`/`$` anchor the whole text).
* expectation `expect_not_matches` "\${REGEX}" "\${TEXT}": Assert that a text does not match an extended regular expression.
* expectation `expect_pcre_matches` "\${REGEX}" "\${TEXT}": Assert that a text matches a Perl Compatible Regular Expression (requires an external PCRE tool: `grep -P`, `pcre2grep`, or `pcregrep`).
* expectation `expect_pcre_not_matches` "\${REGEX}" "\${TEXT}": Assert that a text does not match a Perl Compatible Regular Expression.
* control `skip_test` "\${REASON}": Marks the current test as skipped and reports the reason. Use `skip_test "reason" && return` to end the test body.
* special test function `test::test_init`: If present, then this function runs first! Tests will only be executed if it succeeds.
* special test function `test::test_done`: If present, then this function runs last!

### Example

1) Write a test that sources bashtest.

```sh
set -euo pipefail

# shellcheck disable=SC1090,SC1091,SC2154
source "${helly25_bashtest}"

test::my_test() {
  expect_ne "Hello" "World"
  # Your tests go here...
}

# More tests go here...

test_runner
```

2) Write or extend a BUILD file

```bzl
load("@helly25_bashtest//bashtest:bashtest.bzl", "bashtest")

bashtest(
    name = "sh_test",
    srcs = ["sh_test.sh"],
)
```

### Matching command output

To assert on captured command output, prefer the built-in matchers
(`expect_output_contains`, `expect_matches`, `expect_pcre_matches`) over
hand-rolled pipelines.

> [!WARNING]
> bashtest runs under `set -o pipefail` (and recommends the same for your test
> scripts). The common idiom `printf '%s' "${output}" | grep -qE '...'` is a
> footgun there: `grep -q` exits on the first match, the producing command gets
> `SIGPIPE`, and `pipefail` turns that into a non-zero exit — a flaky failure on
> large output. Feed the text via a here-string (`grep -qE -- '...' <<<"${output}"`)
> or, better, use `expect_matches`, which relies on bash's built-in `[[ =~ ]]`
> and spawns no subprocess at all.

## Installation and requirements

This repository requires bash to work (Linux, MacOs).

### MODULE.bazel

Check [Releases](https://github.com/helly25/bashtest/releases) for details. All that is needed is a `bazel_dep` instruction with the correct version.

```
bazel_dep(name = "helly25_bashtest", version = "0.0.0")
```
