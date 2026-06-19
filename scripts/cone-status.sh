#!/bin/bash
# Per-package build-status table for a whole project (a dependency cone in a
# home: project), in ONE call — so an unattended/remote-build run can gate on
# "is the whole branch green yet?" without hand-rolling an
# `osc results | parse the bare code row` pipeline each time.
#
# Reads the _result API (all packages at once), prints a code->package table,
# and — crucially — distinguishes a SETTLED failure from a stale `failed` while
# a rebuild is still pending (the result carries dirty="true", or some package is
# still scheduled/building). It only trusts failures once nothing is in flight.
#
# Exit code (loop on it):
#   0  every applicable package succeeded            -> ready to submit
#   1  still building/scheduled/blocked, or dirty    -> call again later
#   2  a settled failure (failed/broken/unresolvable) with nothing in flight
#
# Usage: cone-status.sh <project> [repo] [arch]
#   repo default: first <repository> in the project _meta;  arch default: x86_64
set -uo pipefail
[ $# -ge 1 ] || { sed -n '2,18p' "$0"; exit 2; }
prj="$1"; repo="${2:-}"; arch="${3:-x86_64}"

if [ -z "$repo" ]; then
  repo="$(osc api "/source/$prj/_meta" 2>/dev/null \
          | grep -oE '<repository name="[^"]+"' | head -1 \
          | sed -E 's/.*name="([^"]+)"/\1/')"
  [ -n "$repo" ] || { echo "no repository in $prj/_meta — pass one explicitly" >&2; exit 2; }
fi

res="$(osc api "/build/$prj/_result?repository=$repo&arch=$arch" 2>/dev/null)"
[ -n "$res" ] || { echo "no build result for $prj $repo/$arch" >&2; exit 2; }

# result-level state: dirty flag + overall code (building/published/...)
rtag="$(printf '%s\n' "$res" | grep -oE '<result [^>]*>' | head -1)"
dirty=0; printf '%s' "$rtag" | grep -q 'dirty="true"' && dirty=1
overall="$(printf '%s' "$rtag" | grep -oE 'state="[^"]+"|code="[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"/\1/')"

# per-package code rows: "<code> <package>"
rows="$(printf '%s\n' "$res" \
        | grep -oE '<status package="[^"]+" code="[^"]+"' \
        | sed -E 's/<status package="([^"]+)" code="([^"]+)"/\2 \1/')"
[ -n "$rows" ] || { echo "no package statuses parsed for $prj $repo/$arch" >&2; exit 2; }

echo "## $prj — $repo/$arch (overall: ${overall:-?}$([ $dirty = 1 ] && echo ', dirty'))"
printf '%s\n' "$rows" | sort -k1,1 -k2 | while read -r code pkg; do
  printf '  %-13s %s\n' "$code" "$pkg"
done

# classify
pending=0; failed=0; green=0; total=0
while read -r code pkg; do
  [ -n "$code" ] || continue
  total=$((total+1))
  case "$code" in
    succeeded)                              green=$((green+1));;
    failed|broken|unresolvable)             failed=$((failed+1));;
    disabled|excluded)                      total=$((total-1));;   # not applicable
    *)                                      pending=$((pending+1));; # scheduled/building/blocked/finished/signing/dispatching
  esac
done <<EOF
$(printf '%s\n' "$rows")
EOF

echo
echo "summary: $green ok / $failed failed / $pending in-flight  (of $total applicable)"

if [ "$pending" -gt 0 ] || [ "$dirty" = 1 ]; then
  exit 1                       # something still in flight — don't trust failures yet
elif [ "$failed" -gt 0 ]; then
  exit 2                       # settled failure
else
  exit 0                       # all green
fi
