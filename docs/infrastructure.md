# Infrastructure and publishing

Adapted from [proto PR 100](https://github.com/mboworks/proto/pull/100) and xff PRs 835–848,
excluding 841. This repository keeps its Starlark/shell test pipeline and native setup-bazel
cache support. C++ clang-tidy orchestration, sanitizer caches, and coverage history ordering do
not apply to its current jobs.

## CI and caching

Main and numeric release tags run push validation; branches run in pull-request context,
including forks, without duplicating the complete matrix on each push. Only superseded PR runs
are cancelled. The final gate retains release-site tests, pre-commit, and every test-matrix cell.

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

Every test-matrix job retains a `test-results-OS` Actions artifact for seven days,
including on failure. `tools/ci_reports.py run` saves each Bazel command's console
log and build events, then copies the `test.log` and `test.xml` files named by that
invocation's test-result events. Root runfiles modes, external consumers, shards,
and retry attempts remain separate. Results are copied before another command can
overwrite them and before consumer cleanup removes its temporary workspace. Stale
results in `bazel-testlogs` are not collected. Missing local outputs and malformed
build events are reported as collection errors; remote-only output URIs are not
downloaded by this local-CI collector.

An always-run step writes per-invocation JUnit counts and limited failure/error
excerpts to the job summary. It counts actual cases rather than trusting aggregate
XML attributes, labels intentionally failing fixture commands, and fails on
unexpected command outcomes, collection errors, or malformed JUnit XML. The
consumer scripts still verify each expected failure's precise behavior and print
captured negative-test logs if those checks fail. A missing report is shown as
such, leaving the original Bazel command status authoritative.

Summary names and excerpts are HTML-escaped, diagnostics are placed in literal
`pre` blocks, and only 20 bounded excerpts and 200 invocation rows are displayed.
XML files above 8 MiB remain in the artifact but are not parsed for the summary;
DTD/entity declarations are rejected. Complete reports and logs are retained.
Summary generation uses Python's standard library and `GITHUB_STEP_SUMMARY`, with
no PR comments, check-writing token, or privileged follow-up workflow. Python is
a CI reporting dependency, including an absolute interpreter path when Windows
validation strips PATH; it is not a requirement for running bashtest.

To reproduce capture locally, use a fresh output directory for each invocation:

```sh
python3 tools/ci_reports.py run --output /tmp/bashtest-reports/root -- bazel test //...
BASHTEST_CI_REPORTS=/tmp/bashtest-reports bash bashtest/tests/external_consumer_test.sh
python3 tools/ci_reports.py summary /tmp/bashtest-reports --output /tmp/bashtest-summary.md
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

Run `bazel test //...`, `python3 -m unittest discover -s tools -p '*_test.py'`, and
`pre-commit run --all-files`. CI also builds the configured release documentation to validate
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
