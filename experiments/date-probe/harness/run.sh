#!/bin/bash
# DATE probe benchmark harness.
#
# Loads the twin hypertables (metrics_date keyed by DATE, metrics_tstz keyed
# by TIMESTAMPTZ), runs the fixed query set, compresses, and writes three
# result files under experiments/date-probe/results/.
#
# Usage:
#   harness/run.sh --variant baseline --scale small
#   harness/run.sh --variant tiebreaker --scale small --orderby 'day DESC, seq DESC'
#   harness/run.sh --variant interval-1d --scale small --chunk-interval '1 day'
#   harness/run.sh --variant no-index --scale small --no-index
#   harness/run.sh --variant reorder --scale small --reorder
#
# Flags:
#   --variant NAME        result file prefix; the names in the table below
#                         also preselect the knobs
#   --scale smoke|small|customer
#   --chunk-interval TXT  e.g. '7 days' (default)
#   --no-index            create_default_indexes => false
#   --reorder             padding-free column order
#   --orderby TXT         compress_orderby for metrics_date, e.g. 'day DESC, seq DESC';
#                         the twin gets the same with the time column renamed
#   --start-date DATE     first day of data (default: today - days + 1, so the
#                         data reaches the present and now()-based queries hit)
#   --db NAME             database name (default date_probe)
#   --keep                leave the cluster running when done
#
# Variant presets: baseline, reorder, tiebreaker, interval-1d, interval-30d,
# no-index. Explicit flags win over the preset.
#
# This exercises the system-wide extension, so it must run under the install
# lock, right after installing your own build:
#
#   experiments/date-probe/bin/locked.sh bash -c \
#     'make -C build install && experiments/date-probe/harness/run.sh --variant baseline --scale small'
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_DIR="$(dirname "${HARNESS_DIR}")"
REPO="$(cd "${PROBE_DIR}/../.." && pwd)"
RESULTS_DIR="${PROBE_DIR}/results"
SQL_DIR="${HARNESS_DIR}/sql"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
PGPORT="${PGPORT:-5433}"
PGUSER_OS="${PGUSER_OS:-postgres}"

VARIANT=baseline
SCALE=small
CHUNK_INTERVAL=
WITH_INDEX=
REORDER=
ORDERBY=
START_DATE=
DB=date_probe
KEEP=false

while [ $# -gt 0 ]; do
  case "$1" in
    --variant)        VARIANT="$2"; shift 2 ;;
    --scale)          SCALE="$2"; shift 2 ;;
    --chunk-interval) CHUNK_INTERVAL="$2"; shift 2 ;;
    --no-index)       WITH_INDEX=false; shift ;;
    --index)          WITH_INDEX=true; shift ;;
    --reorder)        REORDER=true; shift ;;
    --orderby)        ORDERBY="$2"; shift 2 ;;
    --start-date)     START_DATE="$2"; shift 2 ;;
    --db)             DB="$2"; shift 2 ;;
    --keep)           KEEP=true; shift ;;
    -h|--help)        sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

# --- variant presets, overridden by explicit flags ---------------------------
case "${VARIANT}" in
  reorder)      : "${REORDER:=true}" ;;
  tiebreaker)   : "${ORDERBY:=day DESC, seq DESC}" ;;
  interval-1d)  : "${CHUNK_INTERVAL:=1 day}" ;;
  interval-30d) : "${CHUNK_INTERVAL:=30 days}" ;;
  no-index)     : "${WITH_INDEX:=false}" ;;
esac
: "${CHUNK_INTERVAL:=7 days}"
: "${WITH_INDEX:=true}"
: "${REORDER:=false}"

case "${SCALE}" in
  smoke)    DAYS=20;   DEVICES=20;   RPD=4  ;;  # seconds, for checking the harness itself
  small)    DAYS=400;  DEVICES=200;  RPD=24 ;;
  customer) DAYS=1095; DEVICES=2000; RPD=24 ;;
  *) echo "unknown scale: ${SCALE} (smoke|small|customer)" >&2; exit 2 ;;
esac

if [ -z "${START_DATE}" ]; then
  START_DATE="$(date -u -d "today - $((DAYS - 1)) days" +%F)"
fi
END_DATE="$(date -u -d "${START_DATE} + $((DAYS - 1)) days" +%F)"
MID="$(date -u -d "${START_DATE} + $((DAYS / 2)) days" +%F)"
D1="$(date -u -d "${MID} - 15 days" +%F)"
D2="$(date -u -d "${D1} + 31 days" +%F)"
DPOINT="${MID}"

if [ -n "${ORDERBY}" ]; then
  HAS_ORDERBY=true
  ORDERBY_DATE="${ORDERBY}"
  ORDERBY_TSTZ="$(echo "${ORDERBY}" | sed -E 's/\bday\b/ts/g')"
else
  HAS_ORDERBY=false
  ORDERBY_DATE=""
  ORDERBY_TSTZ=""
fi

SHA="$(git -C "${REPO}" rev-parse --short HEAD)"
RUN_ID="${VARIANT}-${SHA}-$(date -u +%Y%m%dT%H%M%SZ)"
PREFIX="${RESULTS_DIR}/${VARIANT}-${SHA}"
QUERIES_CSV="${PREFIX}-queries.csv"
STORAGE_CSV="${PREFIX}-storage.csv"
SUMMARY_MD="${PREFIX}-summary.md"

mkdir -p "${RESULTS_DIR}"

PSQL=("${PGBIN}/psql" -X -q -p "${PGPORT}" -U "${PGUSER_OS}" -v ON_ERROR_STOP=1)

step() { echo; echo "=== $* ($(date -u +%H:%M:%S)) ==="; }

T_START=$(date +%s)

# The postmaster loads timescaledb through shared_preload_libraries and keeps
# that copy in memory for its whole life, so a cluster left running from an
# earlier session would serve whatever build was installed back then -- from
# another worktree, possibly. Restart it, so the run measures the build that
# was just installed inside the lock.
step "cluster (restart, to pick up the freshly installed extension)"
"${HARNESS_DIR}/pg/stop.sh"
"${HARNESS_DIR}/pg/start.sh"

step "database ${DB}"
"${PGBIN}/psql" -X -q -p "${PGPORT}" -U "${PGUSER_OS}" -d postgres \
  -c "DROP DATABASE IF EXISTS ${DB}" -c "CREATE DATABASE ${DB}"

PSQL+=(-d "${DB}")

step "setup"
"${PSQL[@]}" -f "${SQL_DIR}/setup.sql"

step "schema (variant ${VARIANT}, chunk interval '${CHUNK_INTERVAL}', indexes ${WITH_INDEX}, orderby '${ORDERBY_DATE:-default}')"
"${PSQL[@]}" \
  -v run_id="${RUN_ID}" -v variant="${VARIANT}" -v scale="${SCALE}" -v git_sha="${SHA}" \
  -v days="${DAYS}" -v devices="${DEVICES}" -v rpd="${RPD}" \
  -v chunk_interval="${CHUNK_INTERVAL}" -v with_index="${WITH_INDEX}" \
  -v reorder="${REORDER}" -v has_orderby="${HAS_ORDERBY}" \
  -v orderby_date="${ORDERBY_DATE}" -v orderby_tstz="${ORDERBY_TSTZ}" \
  -v start_date="${START_DATE}" -v end_date="${END_DATE}" \
  -f "${SQL_DIR}/schema.sql"

step "load ${DAYS} days x ${DEVICES} devices x ${RPD} rows"
"${PSQL[@]}" -v run_id="${RUN_ID}" -v days="${DAYS}" -v devices="${DEVICES}" \
  -v rpd="${RPD}" -v start_date="${START_DATE}" -f "${SQL_DIR}/load.sql"

step "snapshot before compression"
"${PSQL[@]}" -v run_id="${RUN_ID}" -f "${SQL_DIR}/snapshot.sql"

step "compress"
"${PSQL[@]}" -v run_id="${RUN_ID}" -f "${SQL_DIR}/compress.sql"

step "queries on metrics_date"
"${PSQL[@]}" -v run_id="${RUN_ID}" -v variant="${VARIANT}" \
  -v tbl=metrics_date -v col=day \
  -v q2bound="current_date - 30" \
  -v d1="${D1}" -v d2="${D2}" -v dpoint="${DPOINT}" \
  -f "${SQL_DIR}/queries.sql"

step "queries on metrics_tstz"
"${PSQL[@]}" -v run_id="${RUN_ID}" -v variant="${VARIANT}" \
  -v tbl=metrics_tstz -v col=ts \
  -v q2bound="date_trunc('day', now()) - interval '30 days'" \
  -v d1="${D1}" -v d2="${D2}" -v dpoint="${DPOINT}" \
  -f "${SQL_DIR}/queries.sql"

step "Q6 continuous aggregate on metrics_date"
"${PSQL[@]}" -v run_id="${RUN_ID}" -v tbl=metrics_date -v col=day -v cagg=cagg_date \
  -f "${SQL_DIR}/cagg.sql"

step "Q6 continuous aggregate on metrics_tstz"
"${PSQL[@]}" -v run_id="${RUN_ID}" -v tbl=metrics_tstz -v col=ts -v cagg=cagg_tstz \
  -f "${SQL_DIR}/cagg.sql"

step "storage"
"${PSQL[@]}" -v run_id="${RUN_ID}" -f "${SQL_DIR}/storage.sql"

step "results"
"${PSQL[@]}" -v run_id="${RUN_ID}" -v queries_csv="${QUERIES_CSV}" \
  -v storage_csv="${STORAGE_CSV}" -f "${SQL_DIR}/export.sql"
"${PGBIN}/psql" -X -q -A -t -p "${PGPORT}" -U "${PGUSER_OS}" -d "${DB}" \
  -v ON_ERROR_STOP=1 -v run_id="${RUN_ID}" -f "${SQL_DIR}/summary.sql" >"${SUMMARY_MD}"

echo "  ${QUERIES_CSV}"
echo "  ${STORAGE_CSV}"
echo "  ${SUMMARY_MD}"

if [ "${KEEP}" = true ]; then
  echo "cluster left running on port ${PGPORT} (database ${DB})"
else
  step "cluster down"
  "${HARNESS_DIR}/pg/stop.sh"
fi

echo
echo "run ${RUN_ID} finished in $(( $(date +%s) - T_START ))s"
