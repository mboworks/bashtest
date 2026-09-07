# bashtest.sh - A Bazel shell test runner.

[Release website](https://mboworks.github.io/bashtest/)

This shell test library provides Bazel macro rules to simplify shell testing.

The library is tested with continuous integration: [![Test](https://github.com/mboworks/bashtest/actions/workflows/main.yml/badge.svg)](https://github.com/mboworks/bashtest/actions/workflows/main.yml).

## Bashtest

Run one of the following commands to get detailed information on the actual bashtest.sh script:

* `bazel run //bashtest:bashtest_help`
* `bazel run //bashtest:bashtest_help | pandoc -s -t man | man -l -`
* `bazel run //bashtest:bashtest_help | pandoc | lynx -stdin`

The flags can be used on the `bazel run` and `bazel test` commands (the latter requiring `--test_arg=...`).

Use `--keep-tmpdir=never|failure|always` to control scratch retention; the default is `failure`.
A retained path is printed at shutdown. Bazel itself may still remove a sandbox unless the test runs
locally or with `--sandbox_debug`.

### Functionality

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
source "${mboworks_bashtest}"

test::my_test() {
  expect_ne "Hello" "World"
  # Your tests go here...
}

# More tests go here...

test_runner
```

2) Write or extend a BUILD file

```bzl
load("@mboworks_bashtest//bashtest:bashtest.bzl", "bashtest")

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

Check [Releases](https://github.com/mboworks/bashtest/releases) for details. All that is needed is a `bazel_dep` instruction with the correct version.

```
bazel_dep(name = "mboworks_bashtest", version = "0.6.1")
```

## Release website

Release notes use `.github/release-notes.md.template`, rendered by
`tools/release_notes.sh TAG`, to link to that tag's versioned website and related
release resources. The existing changelog and installation notes remain included.

The [website](https://mboworks.github.io/bashtest/) forwards to the latest published
stable release at `site/tag/<tag>/`, preserving the exact Git tag name.
Each release keeps its converted HTML, images, and configured files. Retrying
publication leaves an existing snapshot unchanged; a different commit cannot
replace it. Older versions remain directly accessible.

[`release-site.json`](release-site.json) defines the layout. Source names are
relative to the repository root; destinations are relative to that release's
site directory. For example:

```json
{
  "pages": {
    "README.md": "index.html",
    "docs/guide.md": "guide/index.html"
  },
  "files": {
    "schema/example.json": "schema/v1.json"
  },
  "links": [
    {
      "label": "Release",
      "href": "https://github.com/{owner}/{repo}/releases/tag/{tag}"
    }
  ]
}
```

Use existing source files in the actual configuration. `pages` converts Markdown;
optional `files` copies other files unchanged. `README.md` must map to `index.html`.
The generated `documents.html`, `release.json`, `release-site.json`, and `assets/`
paths are reserved. Destination paths cannot have hidden components (names starting
with a dot), because the Pages artifact uploader excludes them. Hidden source
paths remain valid; for example, `.github/workflows/README.md` maps to
`workflows/index.html`.
Navigation links support `{owner}`, `{repo}`, `{tag}`, `{version}`, and `{commit}`.
`{version}` omits a leading `v` for compatibility with coverage report paths.
By default, the configuration and content come from the release tag. Every linked
local Markdown page (including directory README links) must have a `pages` mapping.
Publication fails for an omitted mapping, a missing generated file, or a broken
anchor within the snapshot. Links to configured pages follow their destination
mappings; other local source links use the exact release commit. Embedded images are copied, including remote badges. Markdown
conversion uses the [GitHub Markdown API](https://docs.github.com/en/rest/markdown/markdown)
at publication time; browsing the result requires no Markdown renderer or CDN.

After the Release workflow succeeds, `Publish release site` retains the snapshot
on `coverage-pages` and deploys the complete Pages tree. Coverage and site
publication share a concurrency group to preserve both trees. GitHub's latest
stable release selects the root redirect; backfilling an older release does not
make it latest. The workflow can also be dispatched with a published tag to retry
publication. Enable GitHub Pages with
**GitHub Actions** as its source, and set the repository's About website to
`https://mboworks.github.io/bashtest/`.

### Backfill a historical release

No new release or tag change is needed. Manually dispatch `Publish release site`
with `tag` set to the historical release and `config_path` set to a tracked JSON
file on `main`. Leave `config_path` empty to use a configuration already in the tag.
For example, after selecting a compatible configuration and an existing tag:

```sh
gh workflow run pages.yml --repo mboworks/bashtest --ref main \
  -f tag="$RELEASE_TAG" -f config_path=release-site.json
```

The override controls only publication layout; all Markdown and copied files come
from the selected tag. Each new snapshot retains the exact configuration as
`release-site.json`, with its SHA-256, origin, and source commit in `release.json`.
A configuration can serve several historical tags when its sources exist in each.
For another layout, commit another configuration and select its path. Missing
sources or links fail publication instead of using newer content. Retrying a
published tag preserves its original HTML and configuration.

Local regression tests: `python3 -m unittest discover -s tools -p release_site_test.py`.
CI also converts the configured documentation and checks the generated links in
a disposable runner directory. It never commits, retains, or deploys that preview.
