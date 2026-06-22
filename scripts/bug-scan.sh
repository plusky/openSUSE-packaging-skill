#!/bin/bash
# List the OPEN bugzilla bugs for a package, in ONE call — the "investigate the
# package's bugs whenever you touch it" hard rule, for contexts without the
# bugzilla MCP (agents, scripts). When the MCP is available prefer
# mcp__bugzilla__bugs_quicksearch; this is the REST fallback.
#
# Usage: bug-scan.sh <pkg> [--all]
#   default: open states only (NEW,ASSIGNED,REOPENED,IN_PROGRESS,CONFIRMED,NEEDINFO)
#   --all:   include RESOLVED/VERIFIED too
#
# Reads the API key (for restricted bugs) from ~/.config/mcp-bugzilla/api-key if
# present; works unauthenticated for public bugs otherwise.
set -u
pkg="${1:?usage: bug-scan.sh <pkg> [--all]}"
mode="${2:-}"
keyfile="$HOME/.config/mcp-bugzilla/api-key"
key=""; [ -r "$keyfile" ] && key=$(cat "$keyfile")

base="https://bugzilla.suse.com/rest/bug"
q="quicksearch=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$pkg")"
fields="include_fields=id,summary,status,product,component,version"
url="$base?$q&$fields"
[ "$mode" != "--all" ] && for s in NEW ASSIGNED REOPENED IN_PROGRESS CONFIRMED NEEDINFO; do url="$url&status=$s"; done
[ -n "$key" ] && url="$url&api_key=$key"

curl -fsSL --max-time 30 "$url" 2>/dev/null | python3 -c "
import sys,json
try: d=json.load(sys.stdin)
except Exception: print('(bugzilla query failed)'); sys.exit(0)
bugs=d.get('bugs',[])
print(f'== {len(bugs)} bug(s) for \"$pkg\" ==')
for b in sorted(bugs,key=lambda x:-x['id']):
    sec='VUL' if 'CVE-' in b.get('summary','') else '   '
    print(f\"  boo#{b['id']}  {b['status']:11} [{b.get('product','?')[:20]:20}] {sec} {b['summary'][:90]}\")
if bugs: print('Cite the relevant boo# in the .changes; close (with explicit approval) what the change fixes.')
"
