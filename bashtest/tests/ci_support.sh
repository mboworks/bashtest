#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0

# Private CI helpers shared by the standalone consumer scripts.
ci_bazel() {
    local name="${1}" expected="${2}" reporter
    shift 2
    if [[ -z "${BASHTEST_CI_REPORTS:-}" ]]; then
        bazel "${@}"
        return
    fi
    reporter="${BASH_SOURCE[0]%/*}/../../tools/ci_reports.py"
    case "${OSTYPE}" in
        msys*|cygwin*) reporter="$(cygpath -am "${reporter}")" ;;
    esac
    "${BASHTEST_CI_PYTHON:-python3}" "${reporter}" run \
        --output "${BASHTEST_CI_REPORTS}/${name}" --expect "${expected}" -- bazel "${@}"
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
