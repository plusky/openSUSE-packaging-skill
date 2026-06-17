#!/bin/bash
# List the user's own submit requests (roles=creator), grouped by state.
# `osc rq list -U` is NOT a creator filter (it returns anything you're involved
# in, incl. as reviewer), so this uses the request-search API with roles=creator.
#
# Usage: my-requests.sh [--state open|declined|accepted|all] [--user OBSUSER] [--target PRJ]
#   --state   open (new,review) | declined | accepted | all   (default: open)
#   --user    OBS account (default: `osc whois`)
#   --target  restrict to a target project (e.g. openSUSE:Factory)
set -euo pipefail

user="" ; state="open" ; target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --user) user="$2"; shift 2;;
    --state) state="$2"; shift 2;;
    --target) target="$2"; shift 2;;
    -h|--help) sed -n '2,12p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$user" ] || user="$(osc whois | sed 's/:.*//')"
case "$state" in
  open) states="new,review";;
  all)  states="new,review,declined,accepted,revoked,superseded";;
  *)    states="$state";;
esac

q="/request?view=collection&states=${states}&roles=creator&user=${user}&types=submit"
[ -n "$target" ] && q="${q}&project=${target}"
osc api "$q" 2>/dev/null | python3 -c '
import sys,xml.etree.ElementTree as ET
root=ET.fromstring(sys.stdin.read() or "<collection/>")
rows=[]
for r in root.findall("request"):
    a=r.find("action"); s=r.find("state")
    src=a.find("source") if a is not None else None
    tgt=a.find("target") if a is not None else None
    rows.append((r.get("id"), s.get("name") if s is not None else "?",
        (src.get("project")+"/"+src.get("package")) if src is not None else "?",
        (tgt.get("project")+"/"+tgt.get("package")) if tgt is not None else "?"))
print(f"{len(rows)} request(s)")
for i,st,s,t in sorted(rows, key=lambda x:x[1]):
    print(f"  {i}  [{st:9}]  {s} -> {t}")
'
