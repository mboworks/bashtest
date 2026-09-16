# Shell style

Follow the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) unless
this document or repository tooling says otherwise.

## Tooling

- Use Bash. Executable scripts start with `#!/usr/bin/env bash`, followed by the licence header.
- Format with the pinned `beautysh` pre-commit hook.
- Run ShellCheck and explain necessary local suppressions next to the affected code.
- Use `set -euo pipefail` in scripts unless a documented compatibility constraint prevents it.
- Quote expansions unless word splitting is intentional and documented.
- Make function variables `local` and use lower-case names for locals and functions.

The formatter and linter versions are pinned in [`.pre-commit-config.yaml`](.pre-commit-config.yaml).

## Functions and state

- A function returns data on standard output and diagnostics on standard error.
- Do not return results by mutating caller variables, global counters, the working directory, shell
  options, or traps.
- A function whose stated purpose is an external effect may perform that effect; keep its scope
  narrow and explicit.
- Avoid `eval`, `printf -v`, and string-built command lines. Use arrays for commands and arguments.
- Prefer small functions with one clear responsibility.

```sh
make_tree() {
  local root
  root="$(mktemp -d)"
  mkdir -p "${root}/src"
  echo "${root}"
}

tree="$(make_tree)"
```

## Conditions and loops

- Prefer `[[ ... ]]` for string and file tests and `(( ... ))` for arithmetic.
- Use `case` for multi-way string matching.
- Read lines with `while IFS= read -r line`; do not lose backslashes or surrounding whitespace.
- Do not parse structured data with fragile `grep`/`sed` pipelines when `jq`, `yq`, or a small
  checked-in Python tool provides a reliable parser.

## Temporary files and cleanup

- Tests put temporary files below `${BASHTEST_TMPDIR}` and use `test_tmpdir name` for retained fixtures.
  The framework owns their cleanup; test bodies must not add cleanup traps or recursive deletion.
- Quote and validate deletion targets. Never recursively delete an unresolved variable, a broad
  workspace path, or a user directory.
- Framework/standalone scripts may use a cleanup trap only for resources they own, after the path is known.
- Bazel tests use `${TEST_TMPDIR}` for target-owned temporary output and resolve runfiles through
  `${TEST_SRCDIR}` and `${TEST_WORKSPACE}`.

## Portability

- Support the Bash versions available on the macOS and Linux runners in the CI matrix.
- Do not assume GNU-only flags in scripts that run on macOS; branch on capabilities when necessary.
- Avoid `mapfile` where a script must run under the system Bash shipped with macOS.
- Preserve upper-case names for environment and Bazel runfile variables.
- Check required external programs early and fail with a useful message.
