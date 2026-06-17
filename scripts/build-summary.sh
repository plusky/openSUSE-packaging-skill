#!/bin/bash
# Summarize the last `osc build` from its build log — in ONE invocation, so a
# session/agent gets the literal numbers without ad-hoc grep pipelines.
# Surfaces: build result, %check/ctest pass count, the rpmlint badness summary +
# every E:/W: line, and the produced RPMs.
#
# No sudo: the preserved build log and RPMs under /var/tmp/build-root are readable
# by the build user. If a profile blocks reading them there, capture the build
# yourself instead — `osc build … 2>&1 | tee /tmp/osc-build.log` — and pass that
# file as the argument; osc streams the identical log to stdout.
#
# Usage: build-summary.sh [repo-arch | logfile]   (default: standard-aarch64)
set -uo pipefail
arg="${1:-standard-aarch64}"
if [ -f "$arg" ]; then            # a captured/teed log file
  log="$arg"; rpms=""
else                              # a repo-arch under the build root
  log="/var/tmp/build-root/$arg/.build.log"
  rpms="/var/tmp/build-root/$arg/home/abuild/rpmbuild/RPMS"
fi
[ -r "$log" ] || { echo "can't read build log '$log' — run a build, pass the right repo-arch, or tee 'osc build' output to a file and pass that" >&2; exit 2; }

strip='s/^\[[^]]*\] //'   # drop the "[  98s] " elapsed-time prefix

echo "## Build summary — $arg"
echo
echo "### Result"
grep -hE 'finished "build|failed "build|RPM build errors|exceeds threshold, aborting' "$log" | sed -E "$strip" | tail -2
echo
echo "### %check / tests"
t=$(grep -hE '[0-9]+ (passed|failed)|[0-9]+% tests passed|Total Test time|No tests were found|Ran [0-9]+ test' "$log" | sed -E "$strip" | tail -3)
[ -n "$t" ] && echo "$t" || echo "(no test summary found — does the spec have a %check?)"
echo
echo "### rpmlint"
grep -hE 'packages and [0-9].* checked;|[0-9]+ errors?, [0-9]+ warnings?.*badness' "$log" | sed -E "$strip" | tail -1
issues=$(grep -hE ': (E|W): ' "$log" | sed -E "$strip" | sort -u)
[ -n "$issues" ] && { echo; echo "$issues" | head -40; } || echo "(no E:/W: lines)"
echo
echo "### RPMs produced"
if [ -n "$rpms" ] && [ -d "$rpms" ]; then
  find "$rpms" -name '*.rpm' ! -name '*debuginfo*' ! -name '*debugsource*' 2>/dev/null | sed 's#.*/##' | sort
else
  grep -hoE '[^ ]+\.rpm' "$log" | grep -vE 'debuginfo|debugsource|\.src\.rpm' | sed 's#.*/##' | sort -u
fi
