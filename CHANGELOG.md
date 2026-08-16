# 0.6.0

* Added `skip_test "${REASON}"`: skips the CURRENT test and ends its body immediately, so a
  capability probe needs no `&& return` at the call site. Test bodies now run in a subshell, which
  is what makes that possible; a body can therefore no longer leak variables into later tests.
* Added `--no-skip`, which turns every `skip_test` into a failure. For an environment that
  GUARANTEES the capability a test probes for, where a skip means the guarantee broke.
* Fixed: a fatal abort inside a test no longer reports success. The `EXIT` trap's own last command
  became the script's exit status, so a failing run could exit 0. This repository's own test suite
  was dying at case 5 of 12 under `set -u` and still reporting PASS, hiding the seven that never
  ran.
* Fixed: `expect_contains` / `expect_not_contains` aborted the shell when given an EMPTY array.
  bash 3.2 (which macOS ships) treats `"${@}"` and `"${array[@]}"` as unbound under `set -u`.

# 0.5.1

# 0.5.0

* Added text-matching assertions:
  * `expect_output_contains` / `expect_output_not_contains`: literal substring checks.
  * `expect_matches` / `expect_not_matches`: extended regular expression (ERE) checks via bash's built-in `[[ =~ ]]` (no subprocess, so SIGPIPE-safe under `set -o pipefail`). `^`/`$` anchor the whole text, not individual lines.
  * `expect_pcre_matches` / `expect_pcre_not_matches`: Perl Compatible Regular Expression checks. These shell out to an external tool (`grep -P`, `ggrep -P`, `pcre2grep`, or `pcregrep`) via a here-string and fail with an actionable message when none is available.
* Documented the `cmd | grep -q` SIGPIPE-under-pipefail pitfall in the README.

# 0.4.0

* Renamed the module repo to `helly25_bashtest` and dropped the `com_helly25_bashtest` alias. The `bashtest` macro now resolves its runtime via a repo-relative `Label`, so it works regardless of the apparent repo name. Consumers must update `load("@helly25_bashtest//bashtest:bashtest.bzl", "bashtest")` (previously `@com_helly25_bashtest`).
* Dropped legacy `WORKSPACE` support; the module is now bzlmod-only.
* Extended the BCR presubmit support matrix: added Bazel 9.x and the Linux platforms ubuntu 22.04, Debian 12, and Rocky Linux 8 (alongside the existing ubuntu 24.04 and macOS).

# 0.3.1

* Re-release of 0.3.0 (no functional changes).

# 0.3.0

* Added explicit load of `sh_library` (needed for bazel 9).
* Upgraded dependencies: bazel 9.1.1, bazel_skylib 1.8.2, platforms 1.0.0, rules_shell 0.6.1.

# 0.2.0

* Added convenient target to print `bashtest` help `bazel run //bashtest:bashtest_help` which can be used with `|pandoc -s -t man|man -l -`.
* Fixed description for flag '--test_filter'.
* Added '--gtest_filter' which is an actual glob based filter (as opposed to '--test_filter' which uses posix regular expressions).
* Correct support for space separated flag values.

# 0.1.0

* Initial version moved from helly25_mbo//testing/bashtest*
