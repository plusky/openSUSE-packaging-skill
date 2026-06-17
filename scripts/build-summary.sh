#!/bin/bash
# Summarize the last `osc build` from its preserved build log — in ONE invocation,
# so agents/sessions get the literal numbers without ad-hoc `sudo grep` pipelines.
# Surfaces: build result, %check/ctest pass count, the rpmlint badness summary +
# every E:/W: line, and the produced RPMs.
#
# The build log is root-owned, so this uses `sudo` (a single, reviewable command).
#
# Usage: build-summary.sh [repo-arch]      (default: standard-aarch64)
#   repo-arch  the build root under /var/tmp/build-root/ (e.g. standard-x86_64)
set -uo pipefail
ra="${1:-standard-aarch64}"
log="/var/tmp/build-root/$ra/.build.log"
rpms="/var/tmp/build-root/$ra/home/abuild/rpmbuild/RPMS"
sudo test -f "$log" || { echo "no build log at $log (run an osc build first, or pass the right repo-arch)" >&2; exit 2; }

strip='s/^\[[^]]*\] //'   # drop the "[  98s] " elapsed-time prefix

echo "## Build summary — $ra"
echo
echo "### Result"
sudo grep -hE 'finished "build|failed "build|RPM build errors|exceeds threshold, aborting' "$log" \
  | sed -E "$strip" | tail -2
echo
echo "### %check / tests"
t=$(sudo grep -hE '[0-9]+ (passed|failed)|[0-9]+% tests passed|Total Test time|No tests were found|Ran [0-9]+ test' "$log" | sed -E "$strip" | tail -3)
[ -n "$t" ] && echo "$t" || echo "(no test summary found — does the spec have a %check?)"
echo
echo "### rpmlint"
sudo grep -hE 'packages and [0-9].* checked;|[0-9]+ errors?, [0-9]+ warnings?.*badness' "$log" | sed -E "$strip" | tail -1
issues=$(sudo grep -hE ': (E|W): ' "$log" | sed -E "$strip" | sort -u)
[ -n "$issues" ] && { echo; echo "$issues" | head -40; } || echo "(no E:/W: lines)"
echo
echo "### RPMs produced"
sudo find "$rpms" -name '*.rpm' ! -name '*debuginfo*' ! -name '*debugsource*' 2>/dev/null \
  | sed 's#.*/##' | sort || echo "(none — build did not reach packaging)"
