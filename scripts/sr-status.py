#!/usr/bin/env python3
"""Pretty status table for submit requests: overall state, the review chain, and
human comments. Reused by Block 3 (submit / watch) to see where each SR sits.

Renders a Markdown table (so it looks nice in a chat/terminal that renders MD).

Usage:
  sr-status.py [--user U] [--state open|all|declined|accepted] [--target PRJ] [ID ...]
    ID ...      specific request ids (overrides --state discovery)
    --state     which of your creator SRs to show (default: open = new,review)
    --target    restrict discovery to a target project (e.g. openSUSE:Factory)
    --user      OBS account (default: `osc whois`)
"""
import sys, argparse, subprocess, xml.etree.ElementTree as ET

def api(path):
    r = subprocess.run(["osc", "api", path], capture_output=True, text=True)
    return r.stdout or ""

EMOJI = {"accepted": "✅", "new": "⏳", "review": "🔎", "declined": "❌",
         "revoked": "🚫", "superseded": "♻️", "obsoleted": "♻️", "": "❔"}
def badge(state): return EMOJI.get(state, "❔")

SHORT = {"factory-auto": "auto", "licensedigger": "lic", "factory-staging": "stg",
         "opensuse-review-team": "team", "repo-checker": "repo"}
# logins whose comments are bot noise, not human feedback
BOTS = ("factory-auto", "licensedigger", "repo-checker", "staging-bot", "_obs_")
def is_bot(who):
    w = (who or "").lower()
    return any(b in w for b in BOTS) or "bot" in w or w.startswith("_")

def review_label(rv):  # short, for the compact table column
    for k in ("by_user", "by_group", "by_project"):
        v = rv.get(k)
        if v:
            return SHORT.get(v, v.split(":")[-1] if k == "by_project" else v)
    return "?"

def review_full(rv):   # full name, for the bulleted blocks format
    for k in ("by_user", "by_group"):
        v = rv.get(k)
        if v:
            return v
    v = rv.get("by_project")
    if v:
        return "staging " + (v.split("Staging:")[1] if "Staging:" in v else v.split(":")[-1])
    return "?"

def clip(s, n=64):
    s = " ".join((s or "").split())
    return (s[: n - 1] + "…") if len(s) > n else s

def human_comment(req_id, state_el):
    # declined: the decline reason on the state element is the salient human note
    if state_el is not None and state_el.get("name") == "declined":
        c = state_el.findtext("comment")
        who = state_el.get("who", "?")
        if c and c.strip():
            return f"💬 {who}: \"{clip(c)}\""
    # otherwise the latest non-bot comment in the thread
    try:
        root = ET.fromstring(api(f"/comments/request/{req_id}") or "<comments/>")
    except ET.ParseError:
        return "—"
    cmts = [c for c in root.findall("comment") if not is_bot(c.get("who"))]
    if not cmts:
        return "—"
    last = cmts[-1]
    return f"💬 {last.get('who','?')}: \"{clip(last.text)}\""

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--user")
    ap.add_argument("--state", default="open")
    ap.add_argument("--target")
    ap.add_argument("--limit", type=int, default=40,
                    help="cap discovered SRs (most recent first); each costs 2 API calls")
    ap.add_argument("--format", choices=["table", "blocks"], default="table",
                    help="table = one cramped row per SR; blocks = per-SR with the review chain as bullets")
    a = ap.parse_args()
    user = a.user or subprocess.run(["osc", "whois"], capture_output=True, text=True).stdout.split(":")[0].strip()

    ids = a.ids
    if not ids:
        states = {"open": "new,review", "all": "new,review,declined,accepted,revoked,superseded"}.get(a.state, a.state)
        q = f"/request?view=collection&states={states}&roles=creator&user={user}&types=submit"
        if a.target:
            q += f"&project={a.target}"
        col = ET.fromstring(api(q) or "<collection/>")
        ids = [r.get("id") for r in col.findall("request")]
        if a.limit and len(ids) > a.limit:
            ids = sorted(ids, key=int, reverse=True)[: a.limit]

    rows = []
    for rid in ids:
        req = ET.fromstring(api(f"/request/{rid}") or "<request/>")
        st = req.find("state")
        sname = st.get("name") if st is not None else ""
        act = req.find("action")
        tgt = act.find("target") if act is not None else None
        pkg = tgt.get("package") if tgt is not None else "?"
        target = tgt.get("project") if tgt is not None else "?"
        rows.append((rid, pkg, sname, req.findall("review"), human_comment(rid, st), target))
    rows.sort(key=lambda r: (r[2] != "declined", r[0]))  # declines first, then by id

    print(f"### Submit requests for `{user}` — {len(rows)} shown\n")
    if a.format == "blocks":
        for rid, pkg, sname, reviews, comment, target in rows:
            print(f"**{rid} — {pkg}**  {badge(sname)} {sname}  ·  → `{target}`")
            for rv in reviews:
                print(f"- {review_full(rv)} {badge(rv.get('state',''))}")
            if comment and comment != "—":
                print(f"- {comment}")
            print()
    else:
        print("| SR | Package | State | Review chain | Human comment |")
        print("|----|---------|-------|--------------|---------------|")
        for rid, pkg, sname, reviews, comment, target in rows:
            chain = " ".join(f"{review_label(rv)}{badge(rv.get('state',''))}" for rv in reviews) or "—"
            print(f"| {rid} | {pkg} | {badge(sname)} {sname} | {chain} | {comment} |")
    print("\n_Legend: ✅ accepted · 🔎 review · ⏳ new/pending · ❌ declined · 🚫 revoked · ♻️ superseded_")

if __name__ == "__main__":
    main()
