#!/bin/bash
# List packages where the user is an EXPLICIT package-level maintainer
# (role=maintainer on the package itself) — not project-inherited.
# Output: one "<project>\t<package>" line per package, home:/branches/Maintenance excluded.
#
# Usage: my-packages.sh [--project PRJ] [--user OBSUSER]
#   --project PRJ   only packages in PRJ
#   --user OBSUSER  OBS account (default: `osc whois`). NB the OBS account often
#                   differs from $USER / the email local-part.
#
# An auth/network failure exits non-zero with osc's stderr — it must never look
# like "maintains no packages"; a genuinely empty result says so on stderr.
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

# role=maintainer (NOT bugowner). Capture first: an osc failure (auth, network)
# must surface, not be eaten by a pipeline.
if ! resp="$(osc api "/search/package?match=person[@userid='$user' and @role='maintainer']" 2>&1)"; then
  echo "ERROR: osc api search failed for user '$user':" >&2
  echo "$resp" >&2
  exit 2
fi

# Parse with xml.etree — a grep of 'name=... project=...' depends on OBS's
# attribute order and would silently break on a reorder.
out="$(printf '%s' "$resp" | python3 -c '
import sys, xml.etree.ElementTree as ET
try:
    root = ET.fromstring(sys.stdin.read() or "<collection/>")
except ET.ParseError as e:
    sys.stderr.write(f"ERROR: unparseable search response: {e}\n"); sys.exit(2)
for p in root.findall("package"):
    prj, name = p.get("project", ""), p.get("name", "")
    if not prj or not name:
        continue
    print(f"{prj}\t{name}")
')"

filtered="$(printf '%s\n' "$out" \
  | grep -vE '^(home:|.*:branches:|openSUSE:Maintenance)' \
  | { [ -n "$project" ] && grep -E "^$project	" || cat; } \
  | sort -u)" || true

if [ -z "$filtered" ]; then
  echo "no explicit package-level maintainerships for '$user'${project:+ in $project}" >&2
  exit 0
fi
printf '%s\n' "$filtered"
