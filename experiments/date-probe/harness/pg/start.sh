#!/bin/bash
# Start the dedicated benchmark cluster for the DATE probe.
#
# PostgreSQL refuses to run as root, so the cluster is initialized, owned
# and run by the "postgres" OS user. The data directory lives in
# experiments/date-probe/.pgdata (gitignored) and the cluster listens on
# port 5433, so it never collides with the system cluster on 5432 or with
# the temporary instances pg_regress starts.
#
# Idempotent: initializes only when .pgdata is missing, starts only when
# the cluster is not already running.
#
# Usage: harness/pg/start.sh
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE_DIR="$(dirname "${HARNESS_DIR}")"
PGDATA="${PGDATA:-${PROBE_DIR}/.pgdata}"
PGPORT="${PGPORT:-5433}"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
PGUSER_OS="${PGUSER_OS:-postgres}"

log() { echo "[pg] $*"; }

as_pg() {
  if [ "$(id -u)" -eq 0 ]; then
    runuser -u "${PGUSER_OS}" -- "$@"
  else
    "$@"
  fi
}

# pg_ctl, initdb and the backend all need to traverse every directory above
# PGDATA as the postgres user; a git worktree under a root-owned home is not
# traversable by default.
if [ "$(id -u)" -eq 0 ]; then
  d="${PROBE_DIR}"
  while [ "${d}" != "/" ]; do
    chmod a+rx "${d}" 2>/dev/null || true
    d="$(dirname "${d}")"
  done
fi

if [ ! -s "${PGDATA}/PG_VERSION" ]; then
  log "initializing cluster in ${PGDATA} (port ${PGPORT})"
  rm -rf "${PGDATA}"
  mkdir -p "${PGDATA}"
  chown "${PGUSER_OS}" "${PGDATA}"
  chmod 700 "${PGDATA}"
  as_pg "${PGBIN}/initdb" -D "${PGDATA}" -U "${PGUSER_OS}" --encoding=UTF8 --locale=C >/dev/null

  cat >>"${PGDATA}/postgresql.conf" <<CONF

# --- DATE probe harness ---------------------------------------------------
port = ${PGPORT}
shared_preload_libraries = 'timescaledb'
timescaledb.telemetry_level = off
shared_buffers = 2GB
work_mem = 64MB
maintenance_work_mem = 512MB
max_worker_processes = 16
timezone = 'UTC'
log_directory = 'log'
logging_collector = on
CONF
  log "initialized"
fi

if as_pg "${PGBIN}/pg_ctl" -D "${PGDATA}" status >/dev/null 2>&1; then
  log "already running on port ${PGPORT}"
else
  log "starting on port ${PGPORT}"
  # pg_ctl -l needs log/ to exist before the collector creates it
  as_pg mkdir -p "${PGDATA}/log"
  as_pg "${PGBIN}/pg_ctl" -D "${PGDATA}" -l "${PGDATA}/log/pg_ctl.log" -w -t 60 start >/dev/null
  log "started"
fi

"${PGBIN}/psql" -X -p "${PGPORT}" -U "${PGUSER_OS}" -d postgres \
  -Atc "SELECT 'ready: ' || current_setting('server_version')" >&2
