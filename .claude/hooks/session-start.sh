#!/bin/bash
# SessionStart hook for Claude Code on the web.
#
# Makes a fresh remote container able to build TimescaleDB and run its
# regression suite: installs the PostgreSQL 16 server headers, the
# clang-format version pinned by CI, and the legacy timezone names the
# tests rely on (US/Pacific, PST8PDT); configures a Debug build; compiles;
# installs the extension into the system PostgreSQL; and makes the
# directories the test runner writes to accessible to the non-root
# "postgres" user, because PostgreSQL refuses to start as root.
#
# Idempotent: every step is skipped when its result is already present.
# Only runs in the remote environment.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

REPO="${CLAUDE_PROJECT_DIR:-$(pwd)}"
BUILD_DIR="${REPO}/build"
PGVER=16
export DEBIAN_FRONTEND=noninteractive

log() { echo "[session-start] $*"; }

# --- 1. System packages -----------------------------------------------------
need_pkgs=()
[ -f /usr/include/postgresql/${PGVER}/server/postgres.h ] || need_pkgs+=("postgresql-server-dev-${PGVER}")
command -v clang-format-17 >/dev/null 2>&1 || need_pkgs+=("clang-format-17")
[ -f /usr/share/zoneinfo/US/Pacific ] || need_pkgs+=("tzdata-legacy")
if [ ${#need_pkgs[@]} -gt 0 ]; then
  log "installing: ${need_pkgs[*]}"
  apt-get update -qq >/dev/null 2>&1 || true
  apt-get install -y -qq -o Dpkg::Options::="--force-confold" "${need_pkgs[@]}" >/dev/null
fi
if [ -x /usr/bin/clang-format-17 ]; then
  update-alternatives --install /usr/bin/clang-format clang-format /usr/bin/clang-format-17 100 >/dev/null 2>&1 || true
fi

# --- 2. Configure ------------------------------------------------------------
if [ ! -f "${BUILD_DIR}/CMakeCache.txt" ]; then
  log "configuring Debug build in ${BUILD_DIR}"
  ( cd "${REPO}" && BUILD_FORCE_REMOVE=true ./bootstrap -DCMAKE_BUILD_TYPE=Debug -DREGRESS_CHECKS=ON >/dev/null )
fi

# --- 3. Compile and install --------------------------------------------------
log "compiling"
make -C "${BUILD_DIR}" -j"$(nproc)" >/dev/null
log "installing into system PostgreSQL ${PGVER}"
make -C "${BUILD_DIR}" install >/dev/null

# --- 4. Let the postgres user run the regression suite ----------------------
# pg_regress starts a temporary instance under build/test and writes a
# temp_schedule file into the source test directories.
id postgres >/dev/null 2>&1 || useradd -m postgres
chmod a+rx "$(dirname "${REPO}")" "${REPO}"
chmod -R a+rwX "${BUILD_DIR}"
chmod a+w "${REPO}/test" "${REPO}/tsl/test" "${REPO}/tsl/test/shared"

# --- 5. Environment for the session -----------------------------------------
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export TS_BUILD_DIR=\"${BUILD_DIR}\""
    echo "export PATH=\"/usr/lib/postgresql/${PGVER}/bin:\$PATH\""
  } >> "${CLAUDE_ENV_FILE}"
fi

log "ready: build in ${BUILD_DIR}; run tests with experiments/date-probe/bin/regress.sh <test...>"
