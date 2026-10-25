#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0

# Private CI helpers shared by the standalone consumer scripts and root CI.
ci_bazel() {
    local name="${1}" expected="${2}" repo output events verb status statuses=()
    shift 2
    if [[ -z "${BASHTEST_CI_REPORTS:-}" ]]; then
        bazel "${@}"
        return
    fi
    repo="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)" || return 1
    mkdir -p "${BASHTEST_CI_REPORTS}" || return 1
    output="${BASHTEST_CI_REPORTS}/${name}"
    mkdir "${output}" || return 1
    output="$(cd "${output}" && pwd)" || return 1
    case "${OSTYPE}" in
        msys*|cygwin*) output="$(cygpath -am "${output}")" ;;
    esac
    events="${output}/events.json"
    verb="${1}"
    shift
    if bazel "${verb}" "--build_event_json_file=${events}" "${@}" 2>&1 | tee "${output}/command.log"; then
        statuses=("${PIPESTATUS[@]}")
    else
        statuses=("${PIPESTATUS[@]}")
    fi
    status="${statuses[0]}"
    if [[ "${status}" == 0 && "${statuses[1]}" != 0 ]]; then status=1; fi
    if ! (cd "${repo}" && bazel run //tools:ci_reports -- collect \
        --events "${events}" --output "${output}" --exit-code "${status}" --expect "${expected}") \
        > "${output}/collection.log" 2>&1; then
        cat "${output}/collection.log" >&2
        [[ "${status}" != 0 ]] || status=1
    fi
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
