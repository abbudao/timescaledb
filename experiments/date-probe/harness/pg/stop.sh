#!/bin/bash
# Stop the DATE probe benchmark cluster. Idempotent.
#
# Usage: harness/pg/stop.sh [--destroy]
#   --destroy  also remove the data directory
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE_DIR="$(dirname "${HARNESS_DIR}")"
PGDATA="${PGDATA:-${PROBE_DIR}/.pgdata}"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
PGUSER_OS="${PGUSER_OS:-postgres}"
DESTROY=false
[ "${1:-}" = "--destroy" ] && DESTROY=true

log() { echo "[pg] $*"; }

as_pg() {
  if [ "$(id -u)" -eq 0 ]; then
    runuser -u "${PGUSER_OS}" -- "$@"
  else
    "$@"
  fi
}

if [ -s "${PGDATA}/PG_VERSION" ] && as_pg "${PGBIN}/pg_ctl" -D "${PGDATA}" status >/dev/null 2>&1; then
  log "stopping"
  as_pg "${PGBIN}/pg_ctl" -D "${PGDATA}" -m fast -w -t 60 stop >/dev/null
  log "stopped"
else
  log "not running"
fi

if [ "${DESTROY}" = true ]; then
  log "removing ${PGDATA}"
  rm -rf "${PGDATA}"
fi
