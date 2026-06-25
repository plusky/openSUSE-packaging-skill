#!/bin/bash
# Sweep the OPEN bugzilla bugs across ALL packages you maintain — the "bugs in
# the packages I maintain" view (NOT the same as "assigned to me": openSUSE
# Tumbleweed/Leap bugs are almost never assigned to the package maintainer, and
# their bugzilla *component* is a generic bucket like "Other"/"Basesystem", not
# the source-package name). So the only reliable association is the package name
# in the bug *summary* — this script searches that, then prunes the false
# positives that naive keyword matching produces.
#
# Noise reducers (learned the hard way):
#   * whole-word match — "par"/"dt"/"iw"/"nbd"/"reuse" otherwise match
#     "compare"/device-tree/"firewall"/kernel/"connection reuse" bugs.
#   * CVE affected-package check — a VUL bug summary is
#     "VUL-x: CVE-YYYY-NNNN: <affected-pkg>: ...". If <affected-pkg> is not your
#     package, it is a tracker bug that merely *mentions* your package's name
#     (e.g. "kernel: nbd: ...", "curl: ... connection reuse ...") → dropped.
#   * short-name flag — packages whose name is <=3 chars are inherently noisy;
#     their surviving hits are marked (~) so you eyeball them.
#
# Output is split into FUNCTIONAL (the actionable functional/packaging bugs —
# the usual ask) and VUL (CVE/security tracker bugs, which go through the
# security process). VUL is summarised by default; pass --vul to list it.
#
# Usage: maintained-bugs.sh [--user OBSUSER] [--project PRJ] [--vul] [--all]
#                           [--include-short]
#   --user OBSUSER   OBS account (default: `osc whois`); NB it differs from the
#                    bugzilla email local-part.
#   --project PRJ    restrict to packages in PRJ.
#   --vul            also list the VUL/CVE bugs (not just count them).
#   --all            list everything (functional + VUL), no summarising.
#   --include-short  do not drop <=3-char package names entirely (they are
#                    flagged either way; this keeps even the noisiest ones).
#
# Reads ~/.config/mcp-bugzilla/api-key if present (for restricted bugs).
set -u
here="$(cd "$(dirname "$0")" && pwd)"

user="" ; project="" ; show_vul=0 ; show_all=0 ; inc_short=0
while [ $# -gt 0 ]; do
  case "$1" in
    --user) user="$2"; shift 2;;
    --project) project="$2"; shift 2;;
    --vul) show_vul=1; shift;;
    --all) show_all=1; show_vul=1; shift;;
    --include-short) inc_short=1; shift;;
    -h|--help) sed -n '2,33p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

args=(); [ -n "$user" ] && args+=(--user "$user"); [ -n "$project" ] && args+=(--project "$project")
pkgs="$("$here/my-packages.sh" "${args[@]}" 2>/dev/null | cut -f2 | sort -u)"
[ -n "$pkgs" ] || { echo "no maintained packages found" >&2; exit 1; }

key=""; kf="$HOME/.config/mcp-bugzilla/api-key"; [ -r "$kf" ] && key=$(cat "$kf")

printf '%s\n' "$pkgs" | SHOW_VUL=$show_vul SHOW_ALL=$show_all INC_SHORT=$inc_short BZKEY="$key" python3 -c '
import sys,os,re,json,urllib.parse,urllib.request
pkgs=[l.strip() for l in sys.stdin if l.strip()]
key=os.environ.get("BZKEY",""); show_vul=os.environ["SHOW_VUL"]=="1"
show_all=os.environ["SHOW_ALL"]=="1"; inc_short=os.environ["INC_SHORT"]=="1"
OPEN=["NEW","ASSIGNED","REOPENED","IN_PROGRESS","CONFIRMED","NEEDINFO"]

def query(pkg):
    p=[("short_desc",pkg),("short_desc_type","allwordssubstr"),("resolution","---"),
       ("include_fields","id,status,summary,product,last_change_time")]
    for s in OPEN: p.append(("bug_status",s))
    if key: p.append(("api_key",key))
    url="https://bugzilla.suse.com/rest/bug?"+urllib.parse.urlencode(p)
    try:
        return json.load(urllib.request.urlopen(url,timeout=60)).get("bugs",[])
    except Exception:
        return []

# affected pkg encoded in a CVE/VUL summary: "...CVE-YYYY-NNNN: <pkg[,pkg]>: ..."
cve_aff=re.compile(r"CVE-\d{4}-\d+:\s*([A-Za-z0-9._+-]+(?:,[A-Za-z0-9._+-]+)*)\s*:")

func={}; vul={}; suppressed=0; short_pkgs=[]
for pkg in pkgs:
    short = len(pkg)<=3
    if short and not inc_short:
        short_pkgs.append(pkg)
        # still query, but only keep very strong matches (summary starts "pkg:" / "pkg ")
    wb=re.compile(r"(?<![\w-])"+re.escape(pkg)+r"(?![\w-])", re.I)
    strong=re.compile(r"^\[?"+re.escape(pkg)+r"\b", re.I)
    for b in query(pkg):
        s=b.get("summary","")
        if not wb.search(s):
            continue
        is_vul = ("VUL-" in s) or ("CVE-" in s)
        # CVE affected-package mismatch → tracker bug that just names our pkg
        if is_vul:
            m=cve_aff.search(s)
            if m:
                aff=[a.lower() for a in m.group(1).split(",")]
                if pkg.lower() not in aff:
                    suppressed+=1; continue
        # short pkg: require a strong (anchored) match unless --include-short
        if short and not inc_short and not strong.search(s):
            suppressed+=1; continue
        rec=(b["id"],b.get("status",""),pkg,short,s,b.get("last_change_time",""))
        (vul if is_vul else func).setdefault(pkg,[]).append(rec)

def emit(title,d):
    n=sum(len(v) for v in d.values())
    print(f"\n=== {title} ({n}) ===")
    for pkg in sorted(d):
        for (bid,st,p,sh,s,_) in sorted(d[pkg],key=lambda r:r[4]):
            flag="~" if sh else " "
            print(f"  boo#{bid}  {st:11}{flag}{p:20} | {s[:70]}")

print(f"swept {len(pkgs)} maintained package(s); "
      f"functional={sum(len(v) for v in func.values())} "
      f"vul={sum(len(v) for v in vul.values())} "
      f"(suppressed {suppressed} false-positive/tracker matches)")
emit("FUNCTIONAL / packaging bugs", func)
if show_vul or show_all:
    emit("VUL / CVE bugs", vul)
else:
    print(f"\n(+{sum(len(v) for v in vul.values())} VUL/CVE bugs — pass --vul to list; security process)")
if short_pkgs and not inc_short:
    names=" ".join(sorted(short_pkgs))
    print(f"\nnote: {len(short_pkgs)} short (<=3 char) package name(s) kept only on anchored matches "
          f"(~ flag); --include-short to widen: {names}")
'
