# Intro

All contributions are generally welcome as long as they fit in with the concepts and goals of this repository and as long as the [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) is being respected.

# Code Rules

All code must adhere to the [RULES.md](RULES.md) and mostly follows the [Google style](https://google.github.io/styleguide/). Where it diverges, the checked-in pre-commit rules are authoritative. Shell conventions are in [STYLE_SH.md](STYLE_SH.md); Beautysh, ShellCheck, and Buildifier enforce the applicable formatting and lint rules.

# Workflow and language rules

Follow [AGENTS.md](AGENTS.md), [GIT_RULES.md](GIT_RULES.md), and [STYLE_SH.md](STYLE_SH.md).
Run `bazel test //...` and keep behavior changes covered by regression tests.

CI summaries separate regular tests, deliberately failing consumer fixtures, and builds.
Regular test counts use the final attempt of each run/shard; earlier retries remain in the
downloadable `test-results` artifact with the XML, logs, and build events. Expected fixture
diagnostics are collapsed and excluded from regular failure/error counts. Their observed nonzero
exit alone does not establish correctness: the consumer scripts check the precise failure behavior,
and the CI step must pass. Likewise, `bazel run` build events describe the build; its CI step checks
the program exit. Unexpected final-attempt failures/errors, command outcomes, and reporting errors
fail summary generation.

# Run pre-commit

All changes will be verified by the pre-commit rules. In order to check these before committing changes install the tool:

```
pre-commit install
```

Once installed the verification can be triggered for all files as follows:

```
pre-commit run -a
```

Without the `-a` only the modified and staged files will be checked.
