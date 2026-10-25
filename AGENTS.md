# Agent and contributor rules - bashtest

These rules apply to human and automated contributors. [RULES.md](RULES.md) owns code layout and API
compatibility; [STYLE_SH.md](STYLE_SH.md) owns shell conventions;
[GIT_RULES.md](GIT_RULES.md) owns branch and PR operations.
[CONTRIBUTING.md](CONTRIBUTING.md) describes contributor onboarding.

Run `bazel test //...` and `pre-commit run --all-files` before proposing repository-wide changes. Add regression tests for
behavior changes. Preserve the supported operating systems in CI and keep direct Bazel dependencies
explicit. Keep developer-only dependencies separate from the published module where supported.

Never weaken lint rules or required checks to make CI pass. Do not commit Bazel outputs, local rc
files, caches, or generated release artifacts. Format Starlark with the pinned Buildifier hooks.
Use the existing shell test framework and its diagnostics. Keep public behavior documented in the
same change. Keep Markdown tables vertically aligned; generated docs retain their source of truth.

Versions in `MODULE.bazel` and the first `CHANGELOG.md` heading must agree. Follow
[version consistency](docs/infrastructure.md#version-consistency) for the released README
example, derived consumer versions, and release preparation. Use `tools/trigger_release.sh` for
numeric semantic-version release tags. Preserve the existing immutable GitHub release and BCR publication
flow. [Infrastructure guidance](docs/infrastructure.md) explains CI, caching, and site publishing.
