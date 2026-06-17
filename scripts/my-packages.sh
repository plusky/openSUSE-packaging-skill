#!/bin/bash
# List packages where the user is an EXPLICIT package-level maintainer
# (role=maintainer on the package itself) — not project-inherited.
# Output: one "<project>\t<package>" line per package, home:/branches/Maintenance excluded.
#
# Usage: my-packages.sh [--project PRJ] [--user OBSUSER]
#   --project PRJ   only packages in PRJ
#   --user OBSUSER  OBS account (default: `osc whois`). NB the OBS account often
#                   differs from $USER / the email local-part.
set -euo pipefail

user="" ; project=""
while [ $# -gt 0 ]; do
  case "$1" in
    --user) user="$2"; shift 2;;
    --project) project="$2"; shift 2;;
    -h|--help) sed -n '2,12p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$user" ] || user="$(osc whois | sed 's/:.*//')"

# role=maintainer (NOT bugowner); attribute order in the XML is name then project.
osc api "/search/package?match=person[@userid='$user' and @role='maintainer']" 2>/dev/null \
  | grep -oE '<package name="[^"]+" project="[^"]+"' \
  | sed -E 's/<package name="([^"]+)" project="([^"]+)"/\2\t\1/' \
  | grep -vE '^(home:|.*:branches:|openSUSE:Maintenance)' \
  | { [ -n "$project" ] && grep -E "^$project	" || cat; } \
  | sort -u
