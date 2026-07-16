#!/bin/bash
# watch-submissions.sh — cron-friendly DELTA watcher for your submissions:
# snapshots your ACTIVE OBS submit requests (states new,review; roles=creator)
# plus your OPEN src.opensuse.org (Gitea) PRs, diffs against the saved
# baseline, prints only the delta, then refreshes the baseline. Complements
# sr-status.py: that renders the full current status; this answers "what
# CHANGED since the last firing?" cheaply enough to run from a cron/scheduled
# prompt without spamming (NOCHANGE is the common case — stay silent on it).
#
# Output protocol (stable — scheduled-prompt playbooks key on the first line):
#   BASELINE-INIT      first run; snapshot saved, nothing to diff
#   NOCHANGE           no delta
#   CHANGED            followed by one "  * ..." line per delta:
#                        NEW SR <id> <pkg> [state]       entered the active set
#                        SR <id> <pkg>: staging A -> B   staging (re)assignment
#                        RESOLVE SR <id> <pkg> (...)     left new/review
#                        NEW PR <repo>#<n>
#                        RESOLVE PR <repo>#<n> '<title>' (no longer open)
#   WATCH-ERROR ...    query failure; baseline untouched (exit 2)
#
# "RESOLVE" means the item left the watched set; the CALLER fetches the final
# state (osc request show <id> / tea api .../pulls/<n> — accepted/declined/
# revoked vs merged/closed). The watcher itself stays one-API-call-per-leg
# cheap and does not chase resolutions.
#
# Usage: watch-submissions.sh [--user U] [--login GITEA_LOGIN]
#                             [--state-dir DIR] [--allow-empty] [--no-prs]
#   --user        OBS account (default: osc whois)
#   --login       tea login name for the Gitea leg (default: src.opensuse.org)
#   --state-dir   where the baseline JSON lives
#                 (default: ${XDG_STATE_HOME:-~/.local/state}/osc-submission-watch)
#   --allow-empty accept an empty OBS active set as truth. Default is to treat
#                 it as a failed query and keep the baseline — right for anyone
#                 who usually has SRs in flight, wrong the day you have none.
#   --no-prs      skip the Gitea leg entirely
#
# Failure semantics: an OBS query failure (or empty set without --allow-empty)
# aborts with WATCH-ERROR, baseline untouched. A Gitea-leg failure does NOT
# invent "RESOLVE PR" lines: the PR diff is skipped for this run, the baseline
# keeps its previous PR set, and a "! gitea leg unavailable" note is appended.
set -o pipefail

OBSUSER="" LOGIN="src.opensuse.org"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/osc-submission-watch"
ALLOW_EMPTY=0 NO_PRS=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/,""); print}' "$0"; exit 0;;
    --user) OBSUSER="$2"; shift 2;;
    --login) LOGIN="$2"; shift 2;;
    --state-dir) STATE_DIR="$2"; shift 2;;
    --allow-empty) ALLOW_EMPTY=1; shift;;
    --no-prs) NO_PRS=1; shift;;
    *) echo "unknown argument: $1 (see --help)" >&2; exit 2;;
  esac
done

if [ -z "$OBSUSER" ]; then
  OBSUSER=$(osc whois 2>/dev/null | cut -d: -f1 | tr -d '[:space:]')
fi
if [ -z "$OBSUSER" ]; then
  echo "WATCH-ERROR: cannot determine OBS user (osc whois failed; pass --user)"
  exit 2
fi
mkdir -p "$STATE_DIR" || { echo "WATCH-ERROR: cannot create state dir $STATE_DIR"; exit 2; }
BASE="$STATE_DIR/baseline-$OBSUSER.json"

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

osc api "/request?view=collection&roles=creator&user=$OBSUSER&states=new,review&limit=250" \
    >"$TMP/obs.xml" 2>"$TMP/obs.err"
OBS_RC=$?

GITEA_RC=1
if [ "$NO_PRS" = 0 ]; then
  tea api --login "$LOGIN" "/repos/issues/search?type=pulls&state=open&created=true&limit=50" \
      >"$TMP/gitea.json" 2>"$TMP/gitea.err"
  GITEA_RC=$?
fi

OBS_RC=$OBS_RC GITEA_RC=$GITEA_RC ALLOW_EMPTY=$ALLOW_EMPTY NO_PRS=$NO_PRS \
BASE="$BASE" TMP="$TMP" python3 - <<'PYEOF'
import json, os, sys, xml.etree.ElementTree as ET

tmp, base_path = os.environ["TMP"], os.environ["BASE"]
allow_empty = os.environ["ALLOW_EMPTY"] == "1"
no_prs = os.environ["NO_PRS"] == "1"

# ---- OBS leg (hard requirement: no diff without a trusted active set) ----
if os.environ["OBS_RC"] != "0":
    err = open(f"{tmp}/obs.err").read().strip().splitlines()
    print("WATCH-ERROR: OBS request query failed "
          f"({err[-1] if err else 'osc api rc!=0'}); baseline untouched")
    sys.exit(2)
try:
    root = ET.parse(f"{tmp}/obs.xml").getroot()
except ET.ParseError as e:
    print(f"WATCH-ERROR: OBS response not parseable ({e}); baseline untouched")
    sys.exit(2)

obs = {}
for r in root.findall("request"):
    rid = r.get("id")
    st = r.find("state")
    act = r.find("action")
    tgt = act.find("target") if act is not None else None
    src = act.find("source") if act is not None else None
    pkg = ((tgt.get("package") if tgt is not None else None)
           or (src.get("package") if src is not None else "?"))
    # pending staging review (by_project ...Staging:adi:NN) = current assignment
    stg = ""
    for rv in r.findall("review"):
        if rv.get("state") == "new":
            by = rv.get("by_project") or ""
            if "Staging" in by:
                parts = by.split(":")
                # ...Staging:adi:40 -> adi:40, ...Staging:G -> G
                stg = parts[-1] if parts[-2] == "Staging" else ":".join(parts[-2:])
    obs[rid] = {"pkg": pkg, "state": st.get("name") if st is not None else "?",
                "staging": stg}
if not obs and not allow_empty:
    print("WATCH-ERROR: OBS active set came back empty (likely a query failure; "
          "pass --allow-empty if you really have no open SRs); baseline untouched")
    sys.exit(2)

# ---- Gitea leg (soft: a failure skips the PR diff, never fakes RESOLVEs) ----
gitea, gitea_ok = {}, False
if not no_prs and os.environ["GITEA_RC"] == "0":
    try:
        for it in json.load(open(f"{tmp}/gitea.json")):
            repo = (it.get("repository") or {}).get("full_name", "?")
            gitea[f"{repo}#{it.get('number')}"] = {"title": (it.get("title") or "")[:60]}
        gitea_ok = True
    except Exception:
        gitea_ok = False

base = None
if os.path.exists(base_path):
    try:
        base = json.load(open(base_path))
    except Exception:
        base = None  # corrupt baseline: reinitialize below

if base is None:
    json.dump({"obs": obs, "gitea": gitea if gitea_ok else {}},
              open(base_path, "w"), indent=1)
    print("BASELINE-INIT: first snapshot saved"
          + ("" if gitea_ok or no_prs else " (OBS only — gitea leg unavailable)"))
    sys.exit(0)

changes = []
bo = base.get("obs", {})
for rid, v in obs.items():
    if rid not in bo:
        changes.append(f"NEW SR {rid} {v['pkg']} [{v['state']}]")
    elif bo[rid].get("staging") != v.get("staging"):
        changes.append(f"SR {rid} {v['pkg']}: staging "
                       f"{bo[rid].get('staging') or '-'} -> {v.get('staging') or '-'}")
for rid, v in bo.items():
    if rid not in obs:
        changes.append(f"RESOLVE SR {rid} {v['pkg']} "
                       "(left review; fetch final state: accepted/declined/revoked)")

bg = base.get("gitea", {})
if gitea_ok:
    for k in gitea:
        if k not in bg:
            changes.append(f"NEW PR {k}")
    for k, v in bg.items():
        if k not in gitea:
            changes.append(f"RESOLVE PR {k} '{v.get('title', '')}' "
                           "(no longer open; fetch final state: merged/closed)")

print("CHANGED" if changes else "NOCHANGE")
for c in changes:
    print("  * " + c)
if not gitea_ok and not no_prs:
    print("  ! gitea leg unavailable this run (PR diff skipped; PR baseline kept)")

json.dump({"obs": obs, "gitea": gitea if gitea_ok else bg},
          open(base_path, "w"), indent=1)
PYEOF
