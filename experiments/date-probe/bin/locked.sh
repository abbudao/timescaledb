#!/bin/bash
# Serialize anything that installs or exercises the system-wide extension.
#
# All worktrees on this machine share one PostgreSQL installation, so
# `make install`, the regression suites and the benchmark harness from
# different worktrees must not overlap: the last `make install` wins and
# every test that runs meanwhile loads whatever it left behind.
#
# Wrap the whole install-plus-test sequence in one call so the extension
# cannot change underneath it:
#
#   experiments/date-probe/bin/locked.sh bash -c \
#     'make -C build install && experiments/date-probe/bin/regress.sh insert_single'
#
# Waits for the lock indefinitely; prints who holds it every minute.
set -euo pipefail

LOCK_FILE="${TS_INSTALL_LOCK:-/tmp/ts-extension-install.lock}"

if [ $# -eq 0 ]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 2
fi

exec 9>"${LOCK_FILE}"
until flock -w 60 9; do
  echo "[locked] waiting for ${LOCK_FILE} held by: $(cat "${LOCK_FILE}.owner" 2>/dev/null || echo unknown)" >&2
done
echo "$(id -un)@$(hostname) pid=$$ cwd=$(pwd) $(date -u +%FT%TZ)" > "${LOCK_FILE}.owner"
trap 'rm -f "${LOCK_FILE}.owner"' EXIT

# Close the lock descriptor in the child. A daemon started by the command
# (a harness postgres, for instance) would otherwise inherit it and keep the
# lock held long after this script has exited.
"$@" 9>&-
