#!/bin/bash
# List the OPEN bugzilla bugs for a package, in ONE call — the "investigate the
# package's bugs whenever you touch it" hard rule, for contexts without the
# bugzilla MCP (agents, scripts). When the MCP is available prefer
# mcp__bugzilla__bugs_quicksearch; this is the REST fallback.
#
# Results are pruned through the shared noise filters (scripts/_bugfilter.py:
# whole-word match + CVE affected-package check) so a name like par/nbd doesn't
# surface kernel/compare tracker bugs whose boo# you'd then wrongly cite.
#
# Usage: bug-scan.sh <pkg> [--all]
#   default: open states only (NEW,ASSIGNED,REOPENED,IN_PROGRESS,CONFIRMED,NEEDINFO)
#   --all:   include RESOLVED/VERIFIED too
#
# Reads the API key (for restricted bugs) from ~/.config/mcp-bugzilla/api-key if
# present (sent as a header, never on the URL/argv); works unauthenticated for
# public bugs otherwise. Exits 2 (loudly) on a failed query — a failure is NOT
# "no bugs".
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

pkg="" ; mode=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all) mode="--all"; shift;;
    -h|--help) sed -n '2,19p' "$0"; exit 0;;
    -*) echo "unknown arg: $1" >&2; exit 2;;
    *) if [ -z "$pkg" ]; then pkg="$1"; else echo "unexpected arg: $1" >&2; exit 2; fi; shift;;
  esac
done
[ -n "$pkg" ] || { sed -n '2,19p' "$0"; exit 2; }

keyfile="$HOME/.config/mcp-bugzilla/api-key"
key=""; [ -r "$keyfile" ] && key=$(cat "$keyfile")

base="https://bugzilla.suse.com/rest/bug"
q="quicksearch=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$pkg")"
fields="include_fields=id,summary,status,product,component,version"
url="$base?$q&$fields"
[ "$mode" != "--all" ] && for s in NEW ASSIGNED REOPENED IN_PROGRESS CONFIRMED NEEDINFO; do url="$url&status=$s"; done

# API key goes in a HEADER — an &api_key= URL parameter lands on argv
# (/proc/<pid>/cmdline) and in server logs.
if ! resp=$(curl -fsSL --max-time 30 ${key:+-H "X-BUGZILLA-API-KEY: $key"} "$url" 2>&1); then
  echo "ERROR: bugzilla query failed for '$pkg': $resp" >&2
  exit 2
fi

printf '%s' "$resp" | PKG="$pkg" BFDIR="$here" python3 -c "
import sys, os, json
sys.path.insert(0, os.environ['BFDIR'])
import _bugfilter
pkg = os.environ['PKG']
try:
    d = json.load(sys.stdin)
except Exception as e:
    sys.stderr.write(f'ERROR: unparseable bugzilla response: {e}\n'); sys.exit(2)
if 'error' in d and d.get('error'):
    sys.stderr.write(f'ERROR: bugzilla returned an error: {d}\n'); sys.exit(2)
bugs = d.get('bugs', [])
kept, suppressed = [], 0
for b in bugs:
    ok, short = _bugfilter.keep(pkg, b.get('summary',''))
    if ok:
        kept.append((b, short))
    else:
        suppressed += 1
print(f'== {len(kept)} bug(s) for \"{pkg}\" ==')
for b, short in sorted(kept, key=lambda x: -x[0]['id']):
    sec = 'VUL' if _bugfilter.is_vul(b.get('summary','')) else '   '
    flag = '~' if short else ' '
    print(f\"  boo#{b['id']}  {b['status']:11}{flag}[{b.get('product','?')[:20]:20}] {sec} {b['summary'][:90]}\")
if suppressed:
    print(f'(suppressed {suppressed} tracker/false-positive matches — whole-word + CVE affected-package filters)')
if kept:
    print('Cite the relevant boo# in the .changes; close (with explicit approval) what the change fixes.')
"
