#!/bin/bash
# Run a subset of the TimescaleDB regression suite on a temporary instance.
#
# PostgreSQL refuses to run as root, so when invoked as root this script
# re-executes the make target as the "postgres" user. The SessionStart hook
# has already made the build and test directories writable for that user.
#
# Usage:
#   experiments/date-probe/bin/regress.sh insert_single plan_expand_hypertable
#   SUITE=tsl    experiments/date-probe/bin/regress.sh decompress_vector_qual
#   SUITE=shared experiments/date-probe/bin/regress.sh constify_now
#
# SUITE selects the test tree: core (default, test/), tsl (tsl/test/) or
# shared (tsl/test/shared/). Test names are passed through TESTS=.
# Results and diffs land under build/test/, build/tsl/test/ and
# build/tsl/test/shared/ respectively (regression.diffs, results/*.out).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD_DIR="${TS_BUILD_DIR:-${REPO}/build}"
SUITE="${SUITE:-core}"

case "${SUITE}" in
  core)   target="regresscheck" ;;
  tsl)    target="regresscheck-t" ;;
  shared) target="regresscheck-shared" ;;
  *) echo "unknown SUITE=${SUITE} (core|tsl|shared)" >&2; exit 2 ;;
esac

if [ $# -eq 0 ]; then
  echo "usage: [SUITE=core|tsl|shared] $0 <test-name> [test-name...]" >&2
  exit 2
fi

cmd=(make -C "${BUILD_DIR}" "${target}" TESTS="$*")
if [ "$(id -u)" -eq 0 ]; then
  exec runuser -u postgres -- "${cmd[@]}"
else
  exec "${cmd[@]}"
fi
