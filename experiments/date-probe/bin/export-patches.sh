#!/bin/bash
# Export the probe's local branches as patch series so work survives a lost
# container and can be resumed in another session or on another machine.
#
# Usage: experiments/date-probe/bin/export-patches.sh [out-dir]
#
# Produces, under out-dir (default: ./probe-patches-<utc timestamp>):
#   base/      patches of the base branch relative to upstream main
#   <branch>/  patches of each probe/* branch relative to the base branch
#   MANIFEST.md  branch names, head SHAs, patch counts, and the apply order
#
# Resume on a fresh clone of upstream main:
#   git checkout -b claude/hypertable-date-time-dimension-ms75bt && git am base/*.patch
#   for each branch: git checkout -b <branch> claude/hypertable-date-time-dimension-ms75bt && git am <branch dir>/*.patch
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
BASE_BRANCH="claude/hypertable-date-time-dimension-ms75bt"
UPSTREAM="origin/main"
OUT="${1:-${REPO}/probe-patches-$(date -u +%Y%m%dT%H%M%SZ)}"

mkdir -p "${OUT}/base"
cd "${REPO}"

# Branches that were cut from another probe branch rather than from the base.
# Their series are exported relative to that parent so the parent's commits
# are not duplicated under new hashes when the hand-off is applied.
parent_of() {
  case "$1" in
    probe/a2-constify-date)          echo "probe/a1-runtime-transform" ;;
    probe/c1-defaults-measurement)   echo "probe/harness" ;;
    *)                               echo "${BASE_BRANCH}" ;;
  esac
}

{
  echo "# Probe patch manifest"
  echo
  echo "Exported $(date -u +%FT%TZ) from $(hostname)."
  echo
  echo "Apply order: top to bottom. Each series applies on top of the branch in"
  echo "its parent column, which must have been applied first."
  echo
  echo "| series | branch | parent | head | patches |"
  echo "|---|---|---|---|---|"
} > "${OUT}/MANIFEST.md"

count_patches() { find "$1" -maxdepth 1 -name '*.patch' | wc -l; }

git format-patch -q "${UPSTREAM}..${BASE_BRANCH}" -o "${OUT}/base" >/dev/null
echo "| base | ${BASE_BRANCH} | ${UPSTREAM} | $(git rev-parse --short "${BASE_BRANCH}") | $(count_patches "${OUT}/base") |" >> "${OUT}/MANIFEST.md"

# Parents before children: branches cut from the base first, then the rest.
branches=$(git for-each-ref --format='%(refname:short)' 'refs/heads/probe/*')
ordered=""
for br in ${branches}; do [ "$(parent_of "${br}")" = "${BASE_BRANCH}" ] && ordered="${ordered} ${br}"; done
for br in ${branches}; do [ "$(parent_of "${br}")" = "${BASE_BRANCH}" ] || ordered="${ordered} ${br}"; done

for br in ${ordered}; do
  parent="$(parent_of "${br}")"
  dir="${OUT}/${br//\//-}"
  mkdir -p "${dir}"
  git format-patch -q "${parent}..${br}" -o "${dir}" >/dev/null
  echo "| ${br//\//-} | ${br} | ${parent} | $(git rev-parse --short "${br}") | $(count_patches "${dir}") |" >> "${OUT}/MANIFEST.md"
done

# Uncommitted work in agent worktrees is not exported; list it so nobody
# assumes it was.
{
  echo
  echo "## Worktrees with uncommitted changes at export time"
  echo
  while read -r path _sha _branch; do
    if [ -n "$(git -C "${path}" status --porcelain 2>/dev/null | grep -v '^??' || true)" ]; then
      echo "- ${path}"
    fi
  done < <(git worktree list)
} >> "${OUT}/MANIFEST.md"

echo "exported to ${OUT}"
cat "${OUT}/MANIFEST.md"
