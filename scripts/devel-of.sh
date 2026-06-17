#!/bin/bash
# Print the devel project registered for a package in a target project.
# Exit 0 + "<devel-project>/<pkg>" if present; "NOT IN <target> (new package)" + exit 3 on 404.
# This is the lightweight pre-SR existence check (don't `osc list | grep`).
#
# Usage: devel-of.sh <package> [target-project]   (target default: openSUSE:Factory)
set -uo pipefail
[ $# -ge 1 ] || { sed -n '2,7p' "$0"; exit 2; }
pkg="$1" ; target="${2:-openSUSE:Factory}"
if out="$(osc develproject "$target" "$pkg" 2>/dev/null)" && [ -n "$out" ]; then
  echo "$out"
else
  echo "NOT IN $target (new package?) — submit via its devel project first (see references/3-submit-watch.md)"
  exit 3
fi
