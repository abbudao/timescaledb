#!/bin/bash
# One-command reproducer for the DATE chunk-exclusion gap.
#
# Prints EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY OFF) of Q1
#
#     SELECT count(*), avg(v1) FROM <tbl> WHERE <time col> >= now() - interval '30 days'
#
# side by side for the DATE-keyed and the TIMESTAMPTZ-keyed twin, and saves it
# to experiments/date-probe/results/repro-<short sha>.txt. That file is the
# evidence for the upstream issue.
#
# Needs the data harness/run.sh loaded; it reuses the same cluster and
# database (the data directory survives a stop). Run it the same way, under
# the install lock and after installing your own build:
#
#   experiments/date-probe/bin/locked.sh bash -c \
#     'make -C build install && experiments/date-probe/harness/repro.sh'
#
# Flags: --db NAME (default date_probe), --keep (leave the cluster running)
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_DIR="$(dirname "${HARNESS_DIR}")"
REPO="$(cd "${PROBE_DIR}/../.." && pwd)"
RESULTS_DIR="${PROBE_DIR}/results"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
PGPORT="${PGPORT:-5433}"
PGUSER_OS="${PGUSER_OS:-postgres}"
DB=date_probe
KEEP=false

while [ $# -gt 0 ]; do
  case "$1" in
    --db)   DB="$2"; shift 2 ;;
    --keep) KEEP=true; shift ;;
    -h|--help) sed -n '2,25p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

SHA="$(git -C "${REPO}" rev-parse --short HEAD)"
OUT="${RESULTS_DIR}/repro-${SHA}.txt"
mkdir -p "${RESULTS_DIR}"

# Restart, so the plans come from the build just installed under the lock and
# not from whatever the postmaster preloaded when it was last started.
"${HARNESS_DIR}/pg/stop.sh"
"${HARNESS_DIR}/pg/start.sh"

PSQL=("${PGBIN}/psql" -X -q -p "${PGPORT}" -U "${PGUSER_OS}" -d "${DB}" -v ON_ERROR_STOP=1)

if ! "${PSQL[@]}" -Atc "SELECT 1 FROM metrics_date LIMIT 1" >/dev/null 2>&1; then
  echo "no data in ${DB}.metrics_date -- run harness/run.sh first" >&2
  exit 1
fi

EXPLAIN_OPTS='EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY OFF)'

{
  echo "DATE vs TIMESTAMPTZ chunk exclusion for 'time >= now() - interval 30 days'"
  echo "=========================================================================="
  echo
  echo "commit:    ${SHA}"
  echo -n "extension: "
  "${PSQL[@]}" -Atc "SELECT extversion FROM pg_extension WHERE extname = 'timescaledb'"
  echo -n "postgres:  "
  "${PSQL[@]}" -Atc "SELECT current_setting('server_version')"
  echo -n "generated: "
  date -u +"%Y-%m-%dT%H:%M:%SZ"
  echo
  echo "Both hypertables hold the same rows and the same number of chunks; they"
  echo "differ only in the type of the time column."
  echo
  "${PSQL[@]}" -c "
    SELECT h.hypertable_name,
           d.column_name,
           d.column_type,
           d.time_interval,
           (SELECT count(*) FROM show_chunks(
                format('%I.%I', h.hypertable_schema, h.hypertable_name)::regclass)) AS chunks,
           (SELECT count(*) FROM timescaledb_information.chunks c
             WHERE c.hypertable_name = h.hypertable_name AND c.is_compressed) AS compressed_chunks
    FROM timescaledb_information.hypertables h
    JOIN timescaledb_information.dimensions d
      ON d.hypertable_name = h.hypertable_name AND d.dimension_number = 1
    WHERE h.hypertable_name IN ('metrics_date', 'metrics_tstz')
    ORDER BY h.hypertable_name"

  echo
  echo "--- Q1 on metrics_date (DATE dimension) ---------------------------------"
  echo
  "${PSQL[@]}" -c "${EXPLAIN_OPTS}
    SELECT count(*) AS n, avg(v1) AS avg_v1
    FROM metrics_date
    WHERE day >= now() - interval '30 days'"

  echo
  echo "--- Q1 on metrics_tstz (TIMESTAMPTZ dimension) --------------------------"
  echo
  "${PSQL[@]}" -c "${EXPLAIN_OPTS}
    SELECT count(*) AS n, avg(v1) AS avg_v1
    FROM metrics_tstz
    WHERE ts >= now() - interval '30 days'"

  echo
  echo "--- same predicate written with the column's own type -------------------"
  echo
  "${PSQL[@]}" -c "${EXPLAIN_OPTS}
    SELECT count(*) AS n, avg(v1) AS avg_v1
    FROM metrics_date
    WHERE day >= current_date - 30"
} | tee "${OUT}"

echo
echo "saved to ${OUT}"

if [ "${KEEP}" != true ]; then
  "${HARNESS_DIR}/pg/stop.sh"
fi
