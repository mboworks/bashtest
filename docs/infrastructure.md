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

## Contributor rules and verification

`AGENTS.md`, `GIT_RULES.md`, and `STYLE_SH.md` synchronize applicable shared rules. `RULES.md`
retains this repository's layout and API promises. Beautysh remains the shell formatter; no C++
style guide or competing shell formatter is introduced.

Run `bazel test //...`, `python3 -m unittest discover -s tools -p '*_test.py'`, and
`pre-commit run --all-files`. CI also builds the configured release documentation to validate
links and mappings before publication.
