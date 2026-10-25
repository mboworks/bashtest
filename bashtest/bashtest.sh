# shellcheck shell=bash
# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# BashTest: see `bazel run //bashtest:bashtest_help`

set -euo pipefail

function die() { echo >&2 "ERROR: ${*}"; exit 1; }

_BASHTEST_USAGE=$(cat <<'EOF'
# bashtest.sh - A Bazel shell test runner.

* All declared functions that start with "test::" are considered as tests.
* Each test should use `return 0` to indicate success or `return 1` for failure.
* Call `test_runner` at the end of the test program.
* Provides '${BASHTEST_TMPDIR}' which is a test scratch directory.
* `test_tmpdir [name]` creates and prints a unique directory below it.
* Tests can be filtered (skipping non matching) using flag '--test_filter `<pattern>`'.
* Tests that use diff functionality 'expect_files_eq' can use '-u="${PWD}"' to
  update their golden files.

## Usage:

* bazel test `<test_target>` [ --test_arg=-f=`<pattern>` ] [ -v ] [ -u="${PWD}" ]
* bazel run `<test_target>` -- [ -f=`<pattern>` ] [ -v ][ -u="${PWD}" ]

## Flags:

* -f --test-filter `<pattern>`  A posix regular expression for tests to run,
                                while skipping other tests. The test as a whole
                                is considered failing if no test was run.
* --gtest-output `<xml[:path]>` Write JUnit XML (also accepts GTEST_OUTPUT).
                                Bazel sets XML_OUTPUT_FILE automatically.
* --gtest-filter                Like '-f' but uses glob patterns.
* --no-skip                     Turn every `skip_test` into a failure. For an
                                environment that GUARANTEES the capability a
                                test probes for, so a skip cannot quietly
                                report green.
* --keep-tmpdir `<mode>`        Scratch retention: `never`, `failure` (the
                                default), or `always`. A retained path is
                                printed at shutdown. Bazel may still remove its
                                sandbox unless run locally or with
                                `--sandbox_debug`.
* -u --update `<workspace>`     Update golden files, assuming the `<workspace>`.
* -v --verbose                  Show additional output while tests succeed or fail.
                                Prints all test calls and file diffs.

Note: If long test flags are denoted with '-'s, then '_' can also be used, e.g.
'--test_filter' and '--test-filter' are both long forms for '-f'.

## Assertions:

* expect_eq "${LHS}" "${RHS}"
                            Asserts that two strings are the same.

* expect_ne "${LHS}" "${RHS}"
                            Asserts that two strings are different.

* expect_files_eq "${LHS}" "${RHS}"
                            Asserts that two file are the same.
                            If the test fails it will explain how to update the
                            golden file. That is the test needs to be run with
                            certain precaution and additional flags, so that it
                            can update the golden file.

* expect_contains "${EXPECTED}" "${ARRAY[@]}"
                            Assert that one string is present in an array.

* expect_not_contains "${EXPECTED}" "${ARRAY[@]}"
                            Assert that one string is NOT present in an array.

* expect_output_contains "${SUBSTRING}" "${TEXT}"
                            Assert that a text contains a literal substring.

* expect_output_not_contains "${SUBSTRING}" "${TEXT}"
                            Assert that a text does NOT contain a substring.

* expect_matches "${REGEX}" "${TEXT}"
                            Assert that a text matches an extended regular
                            expression (ERE). Uses bash built-in matching, so
                            ^ and $ anchor the whole text, not each line.

* expect_not_matches "${REGEX}" "${TEXT}"
                            Assert that a text does NOT match an ERE.

* expect_pcre_matches "${REGEX}" "${TEXT}"
                            Assert that a text matches a Perl Compatible Regular
                            Expression. Requires an external PCRE tool
                            (grep -P, pcre2grep, or pcregrep).

* expect_pcre_not_matches "${REGEX}" "${TEXT}"
                            Assert that a text does NOT match a PCRE.


## Skipping:

* skip_test "${REASON}"     Marks the CURRENT test as skipped and reports the
                            reason. Use `skip_test "reason" && return` to end
                            the test body. With '--no-skip', skips fail.

## Status:

* test_has_error            Returns whether a test function has had an error.
* test_has_failed_tests     Returns whether a test program had previous
                            failing test functions.

## Setup/Shutdown:

* test::test_init           If present, then this function runs first!
                            Test will only be executed if it succeeds.
* test::test_done           If present, then this function runs last!

## Temporary files:

* test_tmpdir [NAME]        Create and print a unique scratch directory. NAME
                            is an optional readable prefix, not a path.

## Example:

```sh
# shellcheck disable=SC2317 # Functions are called bashtest

set -euo pipefail

# shellcheck disable=SC1090,SC1091,SC2154 # Source via magic bahtest variable
source "${mboworks_bashtest}"

function test::hello() {
    expect_ne "Hello" "World"
}

test_runner
```

In your BUILD file:

```bzl
load ("@mboworks_bashtest//bashtest:bashtest.bzl", "bashtest")

bashtest(
    name = "my_test",
    srcs = ["my_test.sh"],
)
```
EOF
)

_BASHTEST_REPORT_OUTPUT="${GTEST_OUTPUT-${XML_OUTPUT_FILE:+xml:${XML_OUTPUT_FILE}}}"
_BASHTEST_FILTER_REGX=""
_BASHTEST_FILTER_GLOB=""
_BASHTEST_KEEP_TMPDIR="failure"
_BASHTEST_UPDATE_GOLDEN=""
_BASHTEST_VERBOSE=

################################################################################
# Flag parsing:
# - short flags with values support optional value separation with '=' or ' '.
# - long form flags must have at least two characters in order to distinguish.
# - we look for '=' and ' ' in long flags
#   - '=' works automatically
#   = ' ' requires the long flag to be set in $LONG_OPTIONS_WITH_ARGS

LONG_OPTIONS_WITH_ARGS=(
    "test[-_]filter"
    "gtest[-_]filter"
    "gtest[-_]output"
    "keep[-_]tmpdir"
    "update[-_]golden"
)
while getopts -- '-:f:hu:v' OPTION; do
    if [ "${OPTION}" = "-" ]; then
        OPTION=  # Triggers fallback if necessary
        for LONGOPT in "${LONG_OPTIONS_WITH_ARGS[@]}"; do
            # shellcheck disable=SC2053 # We want glob matching here.
            if [[ ${OPTARG} == ${LONGOPT}=* ]]; then
                OPTION="${OPTARG%%=*}"
                OPTARG="${OPTARG#"${OPTION}"}"
                OPTARG="${OPTARG#=}"
                OPTERR="--${OPTION}"
                break
            elif [[ "${OPTARG}" == ${LONGOPT} ]]; then
                OPTION="${OPTARG}"
                OPTERR="--${OPTION}"
                if [[ "${#}" -lt "${OPTIND}" ]]; then
                    die "Flag '${OPTERR}' has no argument."
                fi
                _ALLARGS=("${@}")
                OPTARG="${_ALLARGS[$((OPTIND - 1))]}"
                ((OPTIND+=1))
                break
            fi
        done
        if [[ -z "${OPTION}" ]]; then
            OPTION="${OPTARG%%=*}"
            OPTARG="${OPTARG#"${OPTION}"}"
            OPTARG="${OPTARG#=}"
            OPTERR="--${OPTION}"
        fi
        if [[ "${#OPTION}" -le 1 ]]; then
            die "Long options have at least two characters. Did you mean '-${OPTION}'?"
        fi
    else
        OPTARG="${OPTARG:-}"
        OPTARG="${OPTARG#=}"
        OPTERR="-${OPTION}"
    fi
    case "${OPTION}" in
        f|test[-_]filter) _BASHTEST_FILTER_REGX="${OPTARG}" ;;
        gtest[-_]output) _BASHTEST_REPORT_OUTPUT="${OPTARG}" ;;
        gtest[-_]filter) _BASHTEST_FILTER_GLOB="${OPTARG}" ;;
        h|help) echo "${_BASHTEST_USAGE}"; exit 2 ;;
        keep[-_]tmpdir)
            case "${OPTARG}" in
                never|failure|always) _BASHTEST_KEEP_TMPDIR="${OPTARG}" ;;
                *) die "Unknown scratch-retention mode '${OPTARG}'; expected never, failure, or always." ;;
            esac
            ;;
        no[-_]skip) _BASHTEST_NO_SKIP=1 ;;
        u|update[-_]golden) _BASHTEST_UPDATE_GOLDEN="${OPTARG}" ;;
        v|verbose) _BASHTEST_VERBOSE=1 ;;
        *) die "Unknown flag '${OPTERR}'." ;;
    esac
done

################################################################################
# Beyond this point we must be sourced!
[[ -z "$(caller 0)" ]] && die "The ${0} script must be sourced."

_BASHTEST_NUM_PASS=0
_BASHTEST_NUM_FAIL=0
_BASHTEST_NUM_SKIP=0

: "${_BASHTEST_NO_SKIP:=}"

_BASHTEST_HAS_ERROR=0
_BASHTEST_SUGGEST_UPDATE=0
_BASHTEST_INIT_FAILED=0
_BASHTEST_DONE_FAILED=0
_BASHTEST_XML_RUNNING=0
_BASHTEST_XML_STARTED=0
_BASHTEST_XML_ACTIVE=
_BASHTEST_XML_TESTS=0
_BASHTEST_XML_FAILURES=0
_BASHTEST_XML_ERRORS=0
_BASHTEST_XML_SKIPPED=0

function _bashtest_cleanup () {
    # Capture FIRST and re-exit with it at the end: a trap's own last command otherwise becomes the
    # script's exit status, so a `rm` returning 0 turned a fatal abort into success. That is not
    # theoretical - an unbound-variable abort under `set -u` (bash 3.2 hates "${empty[@]}") killed
    # this suite's own test at case 5 of 12 and it still reported PASS, hiding the seven that never
    # ran. A test framework reporting green for tests it did not run is the worst bug it can have.
    local status="${?}"
    if [[ -n "${_BASHTEST_XML_ACTIVE}" ]]; then
        # A fatal exit runs this trap inside the function's log redirection.
        exec 1>&198 2>&199
        _bashtest_xml_replay
        _bashtest_xml_case error "${_BASHTEST_XML_ACTIVE}" "Test program exited before the function completed (exit ${status})."
        [[ "${status}" != 0 ]] || status=1
    elif [[ "${_BASHTEST_XML_RUNNING}" == 1 ]]; then
        _bashtest_xml_case error test_runner "Test runner exited before completion."
        [[ "${status}" != 0 ]] || status=1
    elif [[ "${status}" != 0 && "${_BASHTEST_XML_STARTED}" == 1 && "${_BASHTEST_XML_FAILURES}" == 0 && "${_BASHTEST_XML_ERRORS}" == 0 ]]; then
        _bashtest_xml_case error test_program "Test program exited with status ${status}."
    fi
    if [[ "${_BASHTEST_XML_STARTED}" == 1 ]] && ! _bashtest_xml_write; then
        echo >&2 "ERROR: Cannot write JUnit report: ${_BASHTEST_XML_PATH}"
        [[ "${status}" != 0 ]] || status=1
    fi
    local keep=0
    if [[ "${_BASHTEST_KEEP_TMPDIR}" == "always" ]] \
        || { [[ "${_BASHTEST_KEEP_TMPDIR}" == "failure" ]] && [[ "${_BASHTEST_NUM_FAIL}" != "0" ]]; }; then
        keep=1
    fi
    if [[ "${keep}" == "0" ]]; then
        rm -rf "${BASHTEST_TMPDIR}"
    else
        echo >&2 "Preserved test scratch directory: ${BASHTEST_TMPDIR}"
    fi
    exit "${status}"
}
trap _bashtest_cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 131' QUIT
trap 'exit 143' TERM

mkdir -p "${TEST_TMPDIR:=/tmp/$(date "+%Y%m%dT%H%M%S")}"
BASHTEST_TMPDIR="$(mktemp -d -p "${TEST_TMPDIR}")"
declare -r BASHTEST_TMPDIR

# Creates one uniquely named directory below bashtest's owned scratch root and prints its path.
# The optional name is a basename prefix only: accepting a path would let a test escape cleanup.
# Call as `root="$(test_tmpdir tree)"`; the helper has no caller-state side effects.
test_tmpdir() {
    local name="${1:-tmp}"
    if [[ "${name}" == */* || "${name}" == *\\* || "${name}" == *:* ]] || [[ "${name}" == "." ]] || [[ "${name}" == ".." ]]; then
        die "Temporary-directory name must be a basename: '${name}'."
    fi
    mktemp -d "${BASHTEST_TMPDIR}/${name}.XXXXXX"
}

# Escape XML text and replace bytes that are not legal UTF-8/XML 1.0 with '?'.
# The extra trailing byte lets sed consume invalid bytes even at end of line.
_bashtest_xml_escape() {
    local valid
    valid=$'[\x09\x0d\x20-\x7f]|[\xc2-\xdf][\x80-\xbf]|\xe0[\xa0-\xbf][\x80-\xbf]|[\xe1-\xec\xee][\x80-\xbf][\x80-\xbf]|\xed[\x80-\x9f][\x80-\xbf]|\xef[\x80-\xbe][\x80-\xbf]|\xef\xbf[\x80-\xbd]|\xf0[\x90-\xbf][\x80-\xbf][\x80-\xbf]|[\xf1-\xf3][\x80-\xbf][\x80-\xbf][\x80-\xbf]|\xf4[\x80-\x8f][\x80-\xbf][\x80-\xbf]'
    LC_ALL=C sed -E -e 's/$/ /' -e "s/((${valid})*)./\\1?/g" -e 's/.$//' \
        -e 's/\&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
        -e 's/"/\&quot;/g' -e "s/'/\\&apos;/g"
}

_bashtest_xml_attribute() (
    # Bash 5.2 treats '&' specially in substitutions; older Bash inserts it literally.
    # Keep the option change in a subshell so callers retain their shell settings.
    shopt -u patsub_replacement 2>/dev/null || true
    local text newline="&#10;" carriage_return="&#13;" tab="&#9;"
    text="$(printf '%s' "${1}" | _bashtest_xml_escape; printf '.')"
    text="${text%.}"
    text="${text//$'\n'/${newline}}"
    text="${text//$'\r'/${carriage_return}}"
    text="${text//$'\t'/${tab}}"
    printf '%s' "${text}"
)

_bashtest_xml_init() {
    [[ -n "${_BASHTEST_REPORT_OUTPUT}" ]] || return 0
    case "${_BASHTEST_REPORT_OUTPUT}" in
        xml) _BASHTEST_XML_PATH=test_detail.xml ;;
        xml:*) _BASHTEST_XML_PATH="${_BASHTEST_REPORT_OUTPUT#xml:}"
            _BASHTEST_XML_PATH="${_BASHTEST_XML_PATH:-test_detail.xml}" ;;
        *) die "Unsupported test report format: '${_BASHTEST_REPORT_OUTPUT}'; expected xml[:path]." ;;
    esac
    if [[ "${_BASHTEST_XML_PATH}" == */ || "${_BASHTEST_XML_PATH}" == *\\ ]]; then
        local name candidate index=0
        name="${0##*/}"
        name="${name%.exe}"
        name="${name%.*}"
        candidate="${_BASHTEST_XML_PATH}${name}.xml"
        while [[ -e "${candidate}" ]]; do
            ((index+=1))
            candidate="${_BASHTEST_XML_PATH}${name}_${index}.xml"
        done
        _BASHTEST_XML_PATH="${candidate}"
    fi
    case "${OSTYPE}" in
        msys*|cygwin*) _BASHTEST_XML_PATH="$(cygpath -u "${_BASHTEST_XML_PATH}")" ;;
    esac
    # Anchor relative destinations before test functions can change directory.
    case "${_BASHTEST_XML_PATH}" in
        /*|[a-zA-Z]:/*|[a-zA-Z]:\\*) ;;
        *) _BASHTEST_XML_PATH="${PWD}/${_BASHTEST_XML_PATH}" ;;
    esac
    mkdir -p "$(dirname "${_BASHTEST_XML_PATH}")" || die "Cannot create test report directory."
    _BASHTEST_XML_CASES="${BASHTEST_TMPDIR}/junit-cases.xml"
    : > "${_BASHTEST_XML_CASES}"
    _BASHTEST_XML_SUITE="${TEST_TARGET:-${0##*/}}"
    _BASHTEST_XML_START="${SECONDS}"
    _BASHTEST_XML_STARTED=1
}

# Execute in this shell: state set by setup and test functions must remain visible.
# Only report-enabled runs buffer output, replaying it after each function.
_bashtest_invoke() {
    _BASHTEST_RESULT=0
    if [[ "${_BASHTEST_XML_STARTED}" == 0 ]]; then
        "${1}" || _BASHTEST_RESULT="${?}"
    else
        _BASHTEST_XML_ACTIVE="${1#test::}"
        _BASHTEST_XML_CASE_START="${SECONDS}"
        _BASHTEST_XML_LOG="${BASHTEST_TMPDIR}/junit-current.log"
        _BASHTEST_XML_STDOUT="${BASHTEST_TMPDIR}/junit-stdout.log"
        _BASHTEST_XML_STDERR="${BASHTEST_TMPDIR}/junit-stderr.log"
        "${1}" 198>&1 199>&2 > "${_BASHTEST_XML_STDOUT}" 2> "${_BASHTEST_XML_STDERR}" || _BASHTEST_RESULT="${?}"
        _bashtest_xml_replay
    fi
}

_bashtest_xml_replay() {
    cat "${_BASHTEST_XML_STDOUT}"
    cat "${_BASHTEST_XML_STDERR}" >&2
    cat "${_BASHTEST_XML_STDOUT}" "${_BASHTEST_XML_STDERR}" > "${_BASHTEST_XML_LOG}"
}

# Append one case. Hooks are recorded only on failure, leaving test counts useful.
_bashtest_xml_case() {
    [[ "${_BASHTEST_XML_STARTED}" == 1 ]] || return 0
    local kind="${1}" name="${2}" message="${3:-}" elapsed=0
    if [[ -n "${_BASHTEST_XML_ACTIVE}" ]]; then
        elapsed="$((SECONDS - _BASHTEST_XML_CASE_START))"
    fi
    if [[ "${kind}" != ignored ]]; then
        ((_BASHTEST_XML_TESTS+=1))
        case "${kind}" in
            failure) ((_BASHTEST_XML_FAILURES+=1)) ;;
            error) ((_BASHTEST_XML_ERRORS+=1)) ;;
            skipped) ((_BASHTEST_XML_SKIPPED+=1)) ;;
        esac
        {
            printf '    <testcase name="%s" classname="%s" status="run" time="%s">\n' \
                "$(_bashtest_xml_attribute "${name}")" "$(_bashtest_xml_attribute "${_BASHTEST_XML_SUITE}")" "${elapsed}"
            if [[ "${kind}" != pass ]]; then
                printf '      <%s message="%s">' "${kind}" "$(_bashtest_xml_attribute "${message}")"
                if [[ -n "${_BASHTEST_XML_ACTIVE}" ]]; then
                    _bashtest_xml_escape < "${_BASHTEST_XML_LOG}"
                fi
                printf '</%s>\n' "${kind}"
            fi
            if [[ -n "${_BASHTEST_XML_ACTIVE}" ]]; then
                printf '      <system-out>'
                _bashtest_xml_escape < "${_BASHTEST_XML_STDOUT}"
                printf '</system-out>\n      <system-err>'
                _bashtest_xml_escape < "${_BASHTEST_XML_STDERR}"
                printf '</system-err>\n'
            fi
            printf '    </testcase>\n'
        } >> "${_BASHTEST_XML_CASES}"
    fi
    _BASHTEST_XML_ACTIVE=
}

_bashtest_xml_write() {
    [[ "${_BASHTEST_XML_STARTED}" == 1 ]] || return 0
    local temporary elapsed="$((SECONDS - _BASHTEST_XML_START))"
    temporary="$(mktemp "${_BASHTEST_XML_PATH}.XXXXXX")" || return 1
    {
        printf '<?xml version="1.0" encoding="UTF-8"?>\n<testsuites tests="%s" failures="%s" errors="%s" skipped="%s" time="%s">\n' \
            "${_BASHTEST_XML_TESTS}" "${_BASHTEST_XML_FAILURES}" "${_BASHTEST_XML_ERRORS}" "${_BASHTEST_XML_SKIPPED}" "${elapsed}"
        printf '  <testsuite name="%s" tests="%s" failures="%s" errors="%s" skipped="%s" time="%s">\n' \
            "$(_bashtest_xml_attribute "${_BASHTEST_XML_SUITE}")" "${_BASHTEST_XML_TESTS}" "${_BASHTEST_XML_FAILURES}" "${_BASHTEST_XML_ERRORS}" "${_BASHTEST_XML_SKIPPED}" "${elapsed}"
        cat "${_BASHTEST_XML_CASES}"
        printf '  </testsuite>\n</testsuites>\n'
    } > "${temporary}" && mv -f "${temporary}" "${_BASHTEST_XML_PATH}"
}

################################################################################
function _bashtest_handler() {
    FUNC_NAME="${1}"
    TEST_NAME="${2}"
    if [[ -n "${_BASHTEST_FILTER_GLOB}${_BASHTEST_FILTER_REGX}" ]]; then
        PASS_GLOB=
        PASS_REGX=
        # shellcheck disable=SC2053 # We want glob matching here.
        if [[ -n "${_BASHTEST_FILTER_GLOB}" ]] && [[ ${TEST_NAME} == ${_BASHTEST_FILTER_GLOB} ]]; then
            PASS_GLOB=1
        elif [[ -n "${_BASHTEST_FILTER_REGX}" ]] && [[ ${TEST_NAME} =~ ${_BASHTEST_FILTER_REGX} ]]; then
            PASS_REGX=1
        fi
        if [[ -z "${PASS_GLOB}${PASS_REGX}" ]]; then
            echo "[  SKIP  ] ${TEST_NAME}"
            ((_BASHTEST_NUM_SKIP+=1))
            _bashtest_xml_case skipped "${TEST_NAME}" "Excluded by test filter or failed initialization."
            return
        fi
    fi
    echo "[  TEST  ] ${TEST_NAME}"
    _BASHTEST_HAS_ERROR=0
    _BASHTEST_SKIPPED=0
    _BASHTEST_SKIP_REASON=
    _bashtest_invoke "${FUNC_NAME}"
    if [[ "${_BASHTEST_SKIPPED}" != "0" ]]; then
        if [[ -n "${_BASHTEST_NO_SKIP}" ]]; then
            echo >&2 "[  FAIL  ] ${TEST_NAME} (skip requested under --no-skip: ${_BASHTEST_SKIP_REASON})"
            ((_BASHTEST_NUM_FAIL+=1))
            _bashtest_xml_case failure "${TEST_NAME}" "Skip requested under --no-skip: ${_BASHTEST_SKIP_REASON}"
        else
            echo "[  SKIP  ] ${TEST_NAME}: ${_BASHTEST_SKIP_REASON}"
            ((_BASHTEST_NUM_SKIP+=1))
            _bashtest_xml_case skipped "${TEST_NAME}" "${_BASHTEST_SKIP_REASON}"
        fi
    elif [[ "${_BASHTEST_RESULT}" == "0" ]] && [[ "${_BASHTEST_HAS_ERROR}" == "0" ]]; then
        echo "[  PASS  ] ${TEST_NAME}"
        ((_BASHTEST_NUM_PASS+=1))
        _bashtest_xml_case pass "${TEST_NAME}"
    else
        echo >&2 "[  FAIL  ] ${TEST_NAME}"
        ((_BASHTEST_NUM_FAIL+=1))
        _bashtest_xml_case failure "${TEST_NAME}" "Test failed (exit ${_BASHTEST_RESULT}, expectation error ${_BASHTEST_HAS_ERROR})."
    fi
}

# Marks the current test as skipped. Return from the test immediately after calling it. Use
# `--no-skip` where the environment guarantees the capability so a skip becomes a failure.
#
# ```sh
# test::reads_through_a_mount() {
#     command -v fusermount3 >/dev/null || { skip_test "no fuse3 on this machine"; return; }
#     ...
# }
# ```
skip_test() {
    _BASHTEST_SKIPPED=1
    _BASHTEST_SKIP_REASON="${1:-no reason given}"
}

# Returns whether a test function has had an expectation error. This is reset for every test function.
test_has_error() {
    [[ "${_BASHTEST_HAS_ERROR}" != "0" ]]
}

# Returns whether a test program had previous failing test functions.
test_has_failed_tests() {
    [[ "${_BASHTEST_NUM_FAIL}" != "0" ]]
}

_bashtest_contains_element () {
    local expected="$1"
    shift
    for element; do [[ "${element}" == "${expected}" ]] && return 0; done
    return 1
}

################################################################################
# The test's main function that finds and runs all tests.

function test_runner() {
    _bashtest_xml_init
    _BASHTEST_XML_RUNNING=1
    if [[ -n "${_BASHTEST_FILTER_GLOB}" ]]; then
        echo "Test filter glob: '${_BASHTEST_FILTER_GLOB}'."
    fi
    if [[ -n "${_BASHTEST_FILTER_REGX}" ]]; then
        echo "Test filter regx: '${_BASHTEST_FILTER_REGX}'."
    fi
    echo "----------"
    TEST_FUNCS=()
    while IFS='' read -r line; do TEST_FUNCS+=("${line}"); done < <(declare -F|LC_ALL=C sed -rne 's,^declare -f test::(.*)$,\1,p')
    if _bashtest_contains_element "test_init" ${TEST_FUNCS[@]+"${TEST_FUNCS[@]}"}; then
        _BASHTEST_HAS_ERROR=0
        _bashtest_invoke test::test_init
        if [[ "${_BASHTEST_RESULT}" != 0 || "${_BASHTEST_HAS_ERROR}" != 0 ]]; then
            _bashtest_xml_case error test_init "Test initialization failed."
            _BASHTEST_INIT_FAILED=1
            _BASHTEST_FILTER_GLOB=("${TEST_FUNCS[*]}")
            echo "Test init (test::test_init) failed! Skipping all tests."
        else
            _bashtest_xml_case ignored test_init
        fi
        echo "----------"
    fi
    for TEST in ${TEST_FUNCS[@]+"${TEST_FUNCS[@]}"}; do
        if [[ "${TEST}" != "test_init" ]] && [[ "${TEST}" != "test_done" ]]; then
            _bashtest_handler "test::${TEST}" "${TEST}"
            echo "----------"
        fi
    done
    if _bashtest_contains_element "test_done" ${TEST_FUNCS[@]+"${TEST_FUNCS[@]}"}; then
        _BASHTEST_HAS_ERROR=0
        _bashtest_invoke test::test_done
        if [[ "${_BASHTEST_RESULT}" != 0 || "${_BASHTEST_HAS_ERROR}" != 0 ]]; then
            _BASHTEST_DONE_FAILED=1
            _bashtest_xml_case error test_done "Test shutdown failed."
        else
            _bashtest_xml_case ignored test_done
        fi
        echo "----------"
    fi
    if [[ "${_BASHTEST_NUM_PASS}" == 0 && "${_BASHTEST_NUM_FAIL}" == 0 && "${_BASHTEST_INIT_FAILED}" == 0 ]]; then
        _bashtest_xml_case error test_runner "No tests were run."
    fi
    if ! _bashtest_xml_write; then
        echo >&2 "ERROR: Cannot write JUnit report: ${_BASHTEST_XML_PATH}"
        return 1
    fi
    _BASHTEST_XML_RUNNING=0
    echo "PASS: ${_BASHTEST_NUM_PASS}"
    echo "SKIP: ${_BASHTEST_NUM_SKIP}"
    echo >&2 "FAIL: ${_BASHTEST_NUM_FAIL}"
    echo "----------"
    if [[ "${_BASHTEST_INIT_FAILED}" -ne "0" ]]; then
        echo >&2 "ERROR: Test initialization failed."
        return 1
    fi
    if [[ "${_BASHTEST_NUM_FAIL}" != "0" ]]; then
        echo >&2 "ERROR: Some tests failed."
        if [[ "${_BASHTEST_SUGGEST_UPDATE}" -gt 0 ]]; then
            echo ""
            echo "Some test failures from golden file comparisons can be updated using either of:"
            echo "  > bazel test --spawn_strategy=local --test_arg=-u=\"\${PWD}\" ${TEST_TARGET:-<test_target>}"
            echo "  > bazel run ${TEST_TARGET:-<test_target>} -- -u=\"\${PWD}\""
        fi
        return 1
    elif [[ "${_BASHTEST_NUM_PASS}" == 0 ]]; then
        echo >&2 "ERROR: No tests were run."
        return 2
    fi
    if [[ "${_BASHTEST_DONE_FAILED}" != "0" ]]; then
        echo >&2 "ERROR: Test shutdown failed."
        return 1
    fi
    if [[ "${_BASHTEST_NUM_SKIP}" -gt 0 ]]; then
        echo "All selected tests passed but some tests were skipped."
        return 0
    else
        echo "All tests passed."
        return 0
    fi
}

################################################################################
# Assert that two files are the same.
#
# ```sh
# expect_files_eq <golden_file> <result_file>
# ```
#
# If the test fails it will explain how to update the golden file. That is the
# test needs to be run with certain precaution and additional flags, so that it
# can update the golden file.

# Convert Windows drive paths to one spelling before comparing prefixes. Unix
# paths remain unchanged, including literal backslashes in Unix filenames.
_bashtest_normalize_path() {
    case "${OSTYPE}" in
        msys*|cygwin*) cygpath -m -- "${1}" ;;
        *) printf '%s\n' "${1}" ;;
    esac
}

_bashtest_relative_path() {
    local path root entry logical physical
    path="$(_bashtest_normalize_path "${1}")"
    for root in "${RUNFILES_DIR:-}/${TEST_WORKSPACE:-}" \
        "${TEST_SRCDIR:-}/${TEST_WORKSPACE:-}" \
        "${_BASHTEST_UPDATE_GOLDEN:-}" "${BUILD_WORKSPACE_DIRECTORY:-}" \
        "${TEST_TMPDIR:-}" "${PWD}"; do
        [[ -n "${root}" && "${root}" != / ]] || continue
        root="$(_bashtest_normalize_path "${root}")"
        if [[ "${path}" == "${root%/}/"* ]]; then
            printf '%s\n' "${path#"${root%/}/"}"
            return 0
        fi
    done
    if [[ -f "${RUNFILES_MANIFEST_FILE:-}" && -n "${TEST_WORKSPACE:-}" ]]; then
        while IFS= read -r entry; do
            if [[ "${entry}" == ' '* ]]; then
                entry="${entry# }"
                logical="${entry%% *}"
                physical="${entry#* }"
                logical="${logical//\\s/ }"
                logical="${logical//\\n/$'\n'}"
                logical="${logical//\\b/\\}"
                physical="${physical//\\n/$'\n'}"
                physical="${physical//\\b/\\}"
            else
                logical="${entry%% *}"
                physical="${entry#* }"
            fi
            [[ "${logical}" == "${TEST_WORKSPACE}/"* ]] || continue
            physical="$(_bashtest_normalize_path "${physical}")"
            if [[ "${physical}" == "${path}" ]]; then
                printf '%s\n' "${logical#"${TEST_WORKSPACE}/"}"
                return 0
            fi
        done < "${RUNFILES_MANIFEST_FILE}"
    fi
    printf '%s\n' "${path}"
}

expect_files_eq() {
    FILE_GOLDEN="${1}"
    FILE_RESULT="${2}"
    shift
    shift
    FILE_OUTPUT="${FILE_RESULT}.diff"
    # A manifest may resolve a golden directly into the source tree. Recover its
    # workspace-relative name for diagnostics and explicit golden updates.
    FILE_REL_GOLDEN="$(_bashtest_relative_path "${FILE_GOLDEN}")"
    FILE_REL_RESULT="$(_bashtest_relative_path "${FILE_RESULT}")"
    FILE_REL_OUTPUT="$(_bashtest_relative_path "${FILE_OUTPUT}")"

    if [[ ! -r "${FILE_GOLDEN}" ]]; then
        _BASHTEST_HAS_ERROR=1
        echo >&2 ""
        echo >&2 "Test failure:"
        echo >&2 "  Expected: golden file readable."
        echo >&2 "  Golden:  '${FILE_REL_GOLDEN}'"
        return 1
    fi
    if [[ ! -r "${FILE_RESULT}" ]]; then
        _BASHTEST_HAS_ERROR=1
        echo >&2 ""
        echo >&2 "Test failure:"
        echo >&2 "  Expected: result file readable."
        echo >&2 "  Result:  '${FILE_REL_RESULT}'"
        return 1
    fi
    local diff_status=0
    diff -u --label "a/${FILE_REL_GOLDEN}" --label "b/${FILE_REL_GOLDEN}" \
        "${FILE_GOLDEN}" "${FILE_RESULT}" > "${FILE_OUTPUT}" 2>&1 || diff_status="${?}"
    if [[ "${diff_status}" -gt 1 ]]; then
        _BASHTEST_HAS_ERROR=1
        echo >&2 "ERROR: diff failed (status ${diff_status}); golden file was not updated."
        cat >&2 "${FILE_OUTPUT}"
        return 1
    fi
    if [[ "${diff_status}" == 1 ]]; then
        if [[ -n "${_BASHTEST_UPDATE_GOLDEN}" ]]; then
            UPDATE_FILE="${_BASHTEST_UPDATE_GOLDEN}/${FILE_REL_GOLDEN}"
            if [[ ! -w "${UPDATE_FILE}" ]]; then
                _BASHTEST_HAS_ERROR=1
                echo >&2 ""
                echo >&2 "Test failure:"
                echo >&2 "  Expected: golden file is writable."
                echo >&2 "  Did you mean to use either:"
                echo >&2 "    > bazel test --spawn_strategy=local --test_arg=-u=\"\${PWD}\" ${TEST_TARGET:-<test_target>}"
                echo >&2 "    > bazel run ${TEST_TARGET:-<test_target>} -- -u=\"\${PWD}\""
                echo >&2 ""
                die "Cannot write golden file: '${UPDATE_FILE}'."
                # shellcheck disable=SC2317
                return 1 # Technically we die, but that could be an option.
            fi
            if cp "${FILE_RESULT}" "${UPDATE_FILE}"; then
                echo "Updated golden file '${FILE_REL_GOLDEN}'."
                return 0
            else
                _BASHTEST_HAS_ERROR=1
                echo >&2 ""
                echo >&2 "Test failure:"
                echo >&2 "  Expected: golden file gets updated."
                die "Cannot update golden file: '${UPDATE_FILE}'."
                # shellcheck disable=SC2317
                return 1  # Technically we die, but that could be an option.
            fi
        fi
        _BASHTEST_HAS_ERROR=1
        _BASHTEST_SUGGEST_UPDATE=1
        echo >&2 ""
        echo >&2 "Test failure:"
        echo >&2 "  Expected: files are equal:"
        echo >&2 "  Golden:  '${FILE_REL_GOLDEN}'"
        echo >&2 "  Result:  '${FILE_REL_RESULT}'"
        echo >&2 "  Diff:    '${FILE_REL_OUTPUT}'"
        if [[ -n "${_BASHTEST_VERBOSE}" ]]; then
            echo >&2 "Diff output:"
            cat "${FILE_OUTPUT}" 2>&1
            echo >&2 "----------------------------------------"
        fi
        return 1
    fi
    if [[ -n "${_BASHTEST_VERBOSE}" ]]; then
        echo ""
        echo "Test success:"
        echo "  Result equals golden: '${FILE_REL_GOLDEN}'."
    fi
    return 0
}

################################################################################
# Assert that two string values are the same.
#
# ```sh
# expect_eq <golden_text> <result_text>
# ```

expect_eq() {
    TEXT_GOLDEN="${1}"
    TEXT_RESULT="${2}"
    shift
    shift
    TEXT_GOLDEN_OUT="${TEXT_GOLDEN}"
    TEXT_RESULT_OUT="${TEXT_RESULT}"
    if [[ "${#TEXT_GOLDEN_OUT}" -ge 50 ]]; then
        TEXT_GOLDEN_OUT="${TEXT_GOLDEN_OUT:0:47}..."
    fi
    if [[ "${#TEXT_RESULT_OUT}" -ge 50 ]]; then
        TEXT_RESULT_OUT="${TEXT_RESULT_OUT:0:47}..."
    fi
    if [[ "${TEXT_GOLDEN}" != "${TEXT_RESULT}" ]]; then
        _BASHTEST_HAS_ERROR=1
        echo >&2 ""
        echo >&2 "Test failure:"
        echo >&2 "  Expected: strings are equal:"
        echo >&2 "  Golden:  '${TEXT_GOLDEN_OUT}'"
        echo >&2 "  Result:  '${TEXT_RESULT_OUT}'"
        return 1
    else
        if [[ -n "${_BASHTEST_VERBOSE}" ]]; then
            echo ""
            echo "Test success:"
            echo "  Result equals golden: '${TEXT_GOLDEN_OUT}'."
        fi
        return 0
    fi
}

################################################################################
# Assert that two string values are different.
#
# ```sh
# expect_ne <golden_text> <result_text>
# ```

expect_ne() {
    TEXT_GOLDEN="${1}"
    TEXT_RESULT="${2}"
    shift
    shift
    TEXT_GOLDEN_OUT="${TEXT_GOLDEN}"
    TEXT_RESULT_OUT="${TEXT_RESULT}"
    if [[ "${#TEXT_GOLDEN_OUT}" -ge 50 ]]; then
        TEXT_GOLDEN_OUT="${TEXT_GOLDEN_OUT:0:47}..."
    fi
    if [[ "${#TEXT_RESULT_OUT}" -ge 50 ]]; then
        TEXT_RESULT_OUT="${TEXT_RESULT_OUT:0:47}..."
    fi
    if [[ "${TEXT_GOLDEN}" == "${TEXT_RESULT}" ]]; then
        _BASHTEST_HAS_ERROR=1
        echo >&2 ""
        echo >&2 "Test failure:"
        echo >&2 "  Expected: strings are different:"
        echo >&2 "  Golden:  '${TEXT_GOLDEN_OUT}'"
        echo >&2 "  Result:  '${TEXT_RESULT_OUT}'"
        return 1
    else
        if [[ -n "${_BASHTEST_VERBOSE}" ]]; then
            echo ""
            echo "Test success:"
            echo "  Golden: '${TEXT_GOLDEN_OUT}'."
            echo "  Result: '${TEXT_RESULT_OUT}'."
        fi
        return 0
    fi
}

################################################################################
# Assert that one string is present in an array.
#
# ```sh
# expect_contains ${ELEMENT}" "${ARRAY[@]}"
# ```

expect_contains() {
    ELEMENT="${1}"
    shift
    # ${@+"${@}"}, not "${@}": with no remaining arguments (an EMPTY array was passed) bash 3.2
    # under `set -u` treats "${@}" as unbound and aborts the shell. macOS ships bash 3.2.
    if _bashtest_contains_element "${ELEMENT}" ${@+"${@}"}; then
        if [[ -n "${_BASHTEST_VERBOSE}" ]]; then
            echo ""
            echo "Test success:"
            echo "  Expected: element is present in array: '${ELEMENT}'."
        fi
        return 0
    else
        _BASHTEST_HAS_ERROR=1
        echo >&2 ""
        echo >&2 "Test failure:"
        echo >&2 "  Expected: element is present in array:"
        echo >&2 "  Element:  '${ELEMENT}'"
        echo >&2 "  Array:    '${*+${*}}'"
        return 1
    fi
}

################################################################################
# Assert that one string is NOT present in an array.
#
# ```sh
# expect_not_contains ${ELEMENT}" "${ARRAY[@]}"
# ```

expect_not_contains() {
    ELEMENT="${1}"
    shift
    # See expect_contains: bash 3.2 + `set -u` aborts on "${@}" when nothing remains.
    if ! _bashtest_contains_element "${ELEMENT}" ${@+"${@}"}; then
        if [[ -n "${_BASHTEST_VERBOSE}" ]]; then
            echo ""
            echo "Test success:"
            echo "  Expected: element is NOT present in array: '${ELEMENT}'."
        fi
        return 0
    else
        _BASHTEST_HAS_ERROR=1
        echo >&2 ""
        echo >&2 "Test failure:"
        echo >&2 "  Expected: element is NOT present in array:"
        echo >&2 "  Element:  '${ELEMENT}'"
        echo >&2 "  Array:    '${*+${*}}'"
        return 1
    fi
}

# Truncates a value for display in test output (mirrors expect_eq).
_bashtest_ellipsize() {
    local value="${1}"
    if [[ "${#value}" -ge 50 ]]; then
        value="${value:0:47}..."
    fi
    echo "${value}"
}

################################################################################
# Assert that a text matches an extended regular expression (ERE).
#
# ```sh
# expect_matches <regex> <text>
# ```
#
# Matching uses bash's built-in `[[ "${text}" =~ ${regex} ]]`. No subprocess is
# spawned, so - unlike the `printf ... | grep -qE ...` idiom - this can never
# trigger SIGPIPE under `set -o pipefail` (which bashtest and its test scripts
# enable).
#
# NOTE: `${text}` is matched as a single string, so `^` and `$` anchor the whole
# text, NOT individual lines (this differs from `grep`, which matches per line).
# Unanchored patterns behave the same as with `grep`.

expect_matches() {
    REGEX="${1}"
    TEXT="${2}"
    shift
    shift
    TEXT_OUT="$(_bashtest_ellipsize "${TEXT}")"
    # NOTE: `${REGEX}` must stay unquoted so bash treats it as a pattern.
    if [[ "${TEXT}" =~ ${REGEX} ]]; then
        if [[ -n "${_BASHTEST_VERBOSE}" ]]; then
            echo ""
            echo "Test success:"
            echo "  Expected: text matches regex: '${REGEX}'."
        fi
        return 0
    else
        _BASHTEST_HAS_ERROR=1
        echo >&2 ""
        echo >&2 "Test failure:"
        echo >&2 "  Expected: text matches regex:"
        echo >&2 "  Regex:   '${REGEX}'"
        echo >&2 "  Text:    '${TEXT_OUT}'"
        return 1
    fi
}

################################################################################
# Assert that a text does NOT match an extended regular expression (ERE).
#
# ```sh
# expect_not_matches <regex> <text>
# ```
#
# See `expect_matches` for the matching semantics (whole-text anchoring).

expect_not_matches() {
    REGEX="${1}"
    TEXT="${2}"
    shift
    shift
    TEXT_OUT="$(_bashtest_ellipsize "${TEXT}")"
    # NOTE: `${REGEX}` must stay unquoted so bash treats it as a pattern.
    if [[ "${TEXT}" =~ ${REGEX} ]]; then
        _BASHTEST_HAS_ERROR=1
        echo >&2 ""
        echo >&2 "Test failure:"
        echo >&2 "  Expected: text does NOT match regex:"
        echo >&2 "  Regex:   '${REGEX}'"
        echo >&2 "  Text:    '${TEXT_OUT}'"
        return 1
    else
        if [[ -n "${_BASHTEST_VERBOSE}" ]]; then
            echo ""
            echo "Test success:"
            echo "  Expected: text does NOT match regex: '${REGEX}'."
        fi
        return 0
    fi
}

################################################################################
# Assert that a text contains a literal substring.
#
# ```sh
# expect_output_contains <substring> <text>
# ```
#
# The substring is matched literally (glob metacharacters are not special). Like
# the regex matchers this spawns no subprocess and is SIGPIPE-safe.

expect_output_contains() {
    SUBSTR="${1}"
    TEXT="${2}"
    shift
    shift
    TEXT_OUT="$(_bashtest_ellipsize "${TEXT}")"
    if [[ "${TEXT}" == *"${SUBSTR}"* ]]; then
        if [[ -n "${_BASHTEST_VERBOSE}" ]]; then
            echo ""
            echo "Test success:"
            echo "  Expected: text contains substring: '${SUBSTR}'."
        fi
        return 0
    else
        _BASHTEST_HAS_ERROR=1
        echo >&2 ""
        echo >&2 "Test failure:"
        echo >&2 "  Expected: text contains substring:"
        echo >&2 "  Substring: '${SUBSTR}'"
        echo >&2 "  Text:      '${TEXT_OUT}'"
        return 1
    fi
}

################################################################################
# Assert that a text does NOT contain a literal substring.
#
# ```sh
# expect_output_not_contains <substring> <text>
# ```
#
# The substring is matched literally (glob metacharacters are not special).

expect_output_not_contains() {
    SUBSTR="${1}"
    TEXT="${2}"
    shift
    shift
    TEXT_OUT="$(_bashtest_ellipsize "${TEXT}")"
    if [[ "${TEXT}" == *"${SUBSTR}"* ]]; then
        _BASHTEST_HAS_ERROR=1
        echo >&2 ""
        echo >&2 "Test failure:"
        echo >&2 "  Expected: text does NOT contain substring:"
        echo >&2 "  Substring: '${SUBSTR}'"
        echo >&2 "  Text:      '${TEXT_OUT}'"
        return 1
    else
        if [[ -n "${_BASHTEST_VERBOSE}" ]]; then
            echo ""
            echo "Test success:"
            echo "  Expected: text does NOT contain substring: '${SUBSTR}'."
        fi
        return 0
    fi
}

################################################################################
# PCRE matching support.
#
# Unlike `expect_matches`, PCRE (Perl Compatible Regular Expressions) is not a
# bash built-in, so the PCRE matchers shell out to an external tool. Detection
# order: `grep -P` (GNU grep), `ggrep -P` (GNU grep on macOS via Homebrew),
# `pcre2grep`, then `pcregrep`. The result is cached in `_BASHTEST_PCRE_CMD`.
# If no PCRE tool is available (e.g. a stock macOS install, whose BSD `grep` has
# no `-P`), the PCRE matchers fail with an actionable message rather than
# silently passing.

_BASHTEST_PCRE_CMD=
_BASHTEST_PCRE_CMD_SET=0

# Echoes the detected PCRE command (possibly with a flag, e.g. "grep -P"), or
# an empty string if none is available. The detection is performed only once.
_bashtest_pcre_cmd() {
    if [[ "${_BASHTEST_PCRE_CMD_SET}" == "1" ]]; then
        echo "${_BASHTEST_PCRE_CMD}"
        return 0
    fi
    _BASHTEST_PCRE_CMD_SET=1
    local candidate
    for candidate in "grep -P" "ggrep -P" "pcre2grep" "pcregrep"; do
        # shellcheck disable=SC2086 # Intentional split: candidate may hold a flag.
        if ${candidate} -q -e "x" <<<"x" >/dev/null 2>&1; then
            _BASHTEST_PCRE_CMD="${candidate}"
            break
        fi
    done
    echo "${_BASHTEST_PCRE_CMD}"
    return 0
}

# Runs the detected PCRE tool against a text via a here-string (no pipe, so it
# cannot SIGPIPE under `set -o pipefail`). Return codes mirror grep plus one:
#   0 = match, 1 = no match, 2 = tool/regex error, 3 = no PCRE tool available.
_bashtest_pcre_match() {
    local regex="${1}" text="${2}" cmd rc
    cmd="$(_bashtest_pcre_cmd)"
    if [[ -z "${cmd}" ]]; then
        return 3
    fi
    # shellcheck disable=SC2086 # Intentional split: cmd may hold a flag.
    if ${cmd} -q -e "${regex}" <<<"${text}"; then rc=0; else rc="${?}"; fi
    return "${rc}"
}

################################################################################
# Assert that a text matches a Perl Compatible Regular Expression (PCRE).
#
# ```sh
# expect_pcre_matches <regex> <text>
# ```
#
# Requires an external PCRE tool (see the "PCRE matching support" section). Like
# `expect_matches`, `${text}` is matched as a single string, so `^`/`$` anchor
# the whole text unless the pattern opts into multiline mode (e.g. `(?m)`).

expect_pcre_matches() {
    REGEX="${1}"
    TEXT="${2}"
    shift
    shift
    TEXT_OUT="$(_bashtest_ellipsize "${TEXT}")"
    local rc
    if _bashtest_pcre_match "${REGEX}" "${TEXT}"; then rc=0; else rc="${?}"; fi
    if [[ "${rc}" == "0" ]]; then
        if [[ -n "${_BASHTEST_VERBOSE}" ]]; then
            echo ""
            echo "Test success:"
            echo "  Expected: text matches PCRE regex: '${REGEX}'."
        fi
        return 0
    fi
    _BASHTEST_HAS_ERROR=1
    echo >&2 ""
    echo >&2 "Test failure:"
    if [[ "${rc}" == "3" ]]; then
        echo >&2 "  Expected: text matches PCRE regex, but no PCRE tool is available."
        echo >&2 "  Install GNU grep (grep -P), pcre2grep, or pcregrep."
    else
        echo >&2 "  Expected: text matches PCRE regex:"
    fi
    echo >&2 "  Regex:   '${REGEX}'"
    echo >&2 "  Text:    '${TEXT_OUT}'"
    return 1
}

################################################################################
# Assert that a text does NOT match a Perl Compatible Regular Expression (PCRE).
#
# ```sh
# expect_pcre_not_matches <regex> <text>
# ```
#
# Requires an external PCRE tool (see the "PCRE matching support" section).

expect_pcre_not_matches() {
    REGEX="${1}"
    TEXT="${2}"
    shift
    shift
    TEXT_OUT="$(_bashtest_ellipsize "${TEXT}")"
    local rc
    if _bashtest_pcre_match "${REGEX}" "${TEXT}"; then rc=0; else rc="${?}"; fi
    if [[ "${rc}" == "1" ]]; then
        if [[ -n "${_BASHTEST_VERBOSE}" ]]; then
            echo ""
            echo "Test success:"
            echo "  Expected: text does NOT match PCRE regex: '${REGEX}'."
        fi
        return 0
    fi
    _BASHTEST_HAS_ERROR=1
    echo >&2 ""
    echo >&2 "Test failure:"
    if [[ "${rc}" == "3" ]]; then
        echo >&2 "  Expected: text does NOT match PCRE regex, but no PCRE tool is available."
        echo >&2 "  Install GNU grep (grep -P), pcre2grep, or pcregrep."
    elif [[ "${rc}" == "0" ]]; then
        echo >&2 "  Expected: text does NOT match PCRE regex, but it did:"
    else
        echo >&2 "  Expected: text does NOT match PCRE regex, but the tool errored:"
    fi
    echo >&2 "  Regex:   '${REGEX}'"
    echo >&2 "  Text:    '${TEXT_OUT}'"
    return 1
}
