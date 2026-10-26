# Infrastructure and publishing

Adapted from [proto PR 100](https://github.com/mboworks/proto/pull/100) and xff PRs 835–848,
excluding 841. This repository keeps its Starlark/shell test pipeline and native setup-bazel
cache support. C++ clang-tidy orchestration, sanitizer caches, and coverage history ordering do
not apply to its current jobs.

## CI and caching

Main and numeric release tags run push validation; branches run in pull-request context,
including forks, without duplicating the complete matrix on each push. Only superseded PR runs
are cancelled. The final gate retains release-site tests, pre-commit, and every test-matrix cell.

Every pull request and main/tag run tests Linux, macOS, and Windows with Bazel 7.7.2,
8.8.2, and the version in `.bazelversion`. The empty version entry in the matrix
lets Bazelisk read that file, avoiding a second copy of the default version.
Job-level `USE_BAZEL_VERSION` applies to root tests, report tooling, and external
consumer workspaces. Every cell runs both root runfiles modes and the consumer
checks; Windows additionally verifies the managed runtime with Unix tools removed
from PATH. Job names, disk caches, and artifacts distinguish each version.

The pinned setup-bazel action retains native platform-specific cache paths, including Windows
where supported. In the Test workflow, PRs and release tags restore caches; only main saves them.
The separate upstream Release build disables cache mounting because it cannot restrict writes
to main. Bazelisk and
repository downloads remain cached because these small projects do not download the C++ LLVM
payload that motivated compiled-output-only caching in proto and xff. The action's existing
OS/architecture and build/dependency-hash keys remain intact. Exact cache hits are immutable;
source-only edits need not refresh these small build-configuration caches.

The final main job reports compressed repository cache usage and the ten largest entries.
Use these measurements before introducing stricter budgets or custom eviction. A missing
inventory is reported without replacing test failures. This inventory includes all refs and
may briefly lag post-job cache uploads; verify later runs before claiming savings.

### Test diagnostics

Every test-matrix job retains a `test-results-OS-bazel-VERSION` Actions artifact for seven days,
including on failure. The workflow and consumer scripts execute ordinary Bazel
commands with `--build_event_json_file`. Collection runs separately through the
Bazel-built `//tools:ci_reports` tool, which copies the `test.log` and `test.xml`
files named by that
invocation's test-result events. Root runfiles modes, external consumers, shards,
and retry attempts remain separate. Results are copied before another command can
overwrite them and before consumer cleanup removes its temporary workspace. Stale
results in `bazel-testlogs` are not collected. Missing local outputs and malformed
build events are reported as collection errors; remote-only output URIs are not
downloaded by this local-CI collector.

An always-run step separates regular test counts, intentional failure checks, and
builds in the job summary. Counts use the final attempt of each run/shard; earlier
retries remain in the artifact. Intentional fixture diagnostics are collapsed and
excluded from ordinary failure/error counts. It first collects pending root results, including
commands that failed before an explicit collection call. Consumer cleanup does the
same before deleting its workspace and retains negative-analysis command logs.
Build/test status comes from the build events' finished event;
Bazel's ordinary exit status still determines the test step's outcome. For
`bazel run`, build events describe the build, while the native CI step reports
the program's exit status. Event files
under an `expected/` directory identify intentional failure commands. Console
output remains in the native Actions step logs. It counts actual cases rather than trusting aggregate
XML attributes, labels intentionally failing fixture commands, and fails on
unexpected command outcomes, final-attempt Bazel/JUnit failures or errors,
collection errors, or malformed JUnit XML. The
consumer scripts still verify each expected failure's precise behavior and print
captured negative-test logs if those checks fail. A missing report is shown as
such, leaving the original Bazel command status authoritative.

Summary names and excerpts are HTML-escaped, diagnostics are placed in literal
`pre` blocks, and only 20 bounded excerpts and 200 invocation rows are displayed.
XML files above 8 MiB remain in the artifact but are not parsed for the summary;
DTD/entity declarations are rejected. Complete reports and logs are retained.
Summary generation uses Python's standard library and `GITHUB_STEP_SUMMARY`, with
no PR comments, check-writing token, or privileged follow-up workflow. Python tests
are `py_test` targets under `//tools/...` and run with `bazel test //...`; the
collector and documentation verifier are `py_binary` targets. `rules_python` and
its Python 3.13 toolchain are dev dependencies, so consumers acquire no Python
runtime requirement. No separate Python installation or unittest CI job is needed.
Tests that exercise Unix process/signal or Git/shell release behavior run on Linux
and macOS. Portable Python suites also run in the stripped-PATH Windows job.

To reproduce capture locally, use a fresh output directory for each invocation:

```sh
export BASHTEST_CI_REPORTS=/tmp/bashtest-reports
mkdir -p "$BASHTEST_CI_REPORTS"
bazel test //... --build_event_json_file="$BASHTEST_CI_REPORTS/root.json"
bazel run //tools:ci_reports -- collect --events "$BASHTEST_CI_REPORTS/root.json" --output "$BASHTEST_CI_REPORTS/root"
bash bashtest/tests/external_consumer_test.sh
bazel run //tools:ci_reports -- finalize "$BASHTEST_CI_REPORTS" --destination "$BASHTEST_CI_REPORTS" --output /tmp/bashtest-summary.md
```

Without `BASHTEST_CI_REPORTS`, the standalone consumer scripts run Bazel directly.
Artifact retention after forced runner termination is limited to files already
written; ordinary Bazel test timeouts are collected and verified explicitly.

## Publishing

The release publisher uses trusted main tooling and the tagged documentation snapshot.
The shared 64-pixel README logo and favicons match MBO Works' other repositories.
Favicons are inserted after staging the complete deployment copy; retained release snapshots
stay unchanged. Decoration is idempotent and resolves links from nested pages.

The shared release workflow is pinned to the same v7.7.0 commit as proto. Standard releases
are staged as drafts until archives and attestations are uploaded, then published once. Published
immutable prereleases cannot later be promoted. BCR publication follows release success and can
be retried independently; its failure does not require recreating a release or moving its tag.
Release helpers, numeric tags, and version agreement keep their existing contracts. No module
dependency versions change in this rollout.

### Published-site budget

Each publisher fetches only the latest `coverage-pages` snapshot with `--depth=1` and no tags.
`storage-report.json` measures the complete retained tree before committing and the staged tree
again after deployment-only artwork. It records file counts and bytes by top-level directory,
excluding Git metadata and the report itself. Release pages and assets are not changed.

Publication warns at **250 MB**. An emergency **9 GB** payload guard leaves TAR packaging headroom;
GitHub's [supported published-site limit](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits)
remains **1 GB**, so the emergency guard is not an operating target. Review growth before reaching
that limit. This repository does not currently publish coverage, so no coverage retention or
browser loader is introduced. Git history, build caches, and Actions artifacts are separate budgets.
The change follows [mbo PR #549](https://github.com/mboworks/mbo/pull/549).

## Contributor rules and verification

`AGENTS.md`, `GIT_RULES.md`, and `STYLE_SH.md` synchronize applicable shared rules. `RULES.md`
retains this repository's layout and API promises. Beautysh remains the shell formatter; no C++
style guide or competing shell formatter is introduced.

Run `bazel test //...` and `pre-commit run --all-files`. CI also builds the configured release documentation to validate
links and mappings before publication.

## Version consistency

`MODULE.bazel` and the first `CHANGELOG.md` heading identify the development
version. Both external consumer scripts derive their dependency version from
`MODULE.bazel`, because their local overrides consume this checkout. Historical
changelog entries retain their original versions.

The README installation example stays at the latest released version during
development. Before a release, run `python3 tools/prepare_release.py X.Y.Z` on a
release-preparation branch. It verifies the module/changelog version and updates
the README automatically. Review and merge that change before tagging. This brief
preparation stage is the only time the example should name an upcoming release.
Both `tools/trigger_release.sh` (including dry runs) and the archive workflow require
`prepare_release.py --check` to pass, so the tag, archive README, module, and
release notes agree. BCR metadata and release assets already derive their version
from the release tag. Preparation does not commit, tag, or publish anything.

The `compare-versions` pre-commit hook accepts the latest numeric release tag for
the README, or the development version for a prepared release. Without local tags,
it can only validate the README's format and upper bound; CI fetches all tags.
The released commit may keep its release version; the first subsequent commit
must advance the development version. `tools/version_test.py` exercises these
relationships and release preparation in temporary Git repositories. These tests
run through the infrastructure pre-commit hook and CI.
