#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0

# Collection only: callers execute Bazel commands directly.
ci_collect() {
    [[ -n "${BASHTEST_CI_REPORTS:-}" ]] || return 0
    local events="${1}" repo name
    repo="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)" || return 1
    name="${events##*/}"
    (cd "${repo}" && bazel run //tools:ci_reports -- collect \
        --events "${events}" --output "${BASHTEST_CI_REPORTS}/${name%.json}")
}

# Capture a failed command's results before the consumer workspace is deleted.
ci_collect_pending() {
    [[ -n "${BASHTEST_CI_REPORTS:-}" ]] || return 0
    local events="${1}" logs="${2}" suite="${3}" repo log status=0
    repo="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)" || return 1
    (cd "${repo}" && bazel run //tools:ci_reports -- finalize \
        "${events}" --destination "${BASHTEST_CI_REPORTS}") || status=1
    mkdir -p "${BASHTEST_CI_REPORTS}/consumer-logs/${suite}" || return 1
    for log in "${logs}"/*.log; do
        [[ -f "${log}" ]] || continue
        cp "${log}" "${BASHTEST_CI_REPORTS}/consumer-logs/${suite}/" || status=1
    done
    return "${status}"
}

ci_failure_logs() {
    local status="${1}" directory="${2}" log
    [[ "${status}" != 0 ]] || return 0
    for log in "${directory}"/*.log; do
        [[ -f "${log}" ]] || continue
        printf >&2 '\n[UNEXPECTED CONSUMER FAILURE: %s]\n' "${log##*/}"
        cat "${log}" >&2
    done
}
