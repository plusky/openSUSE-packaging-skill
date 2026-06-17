#!/usr/bin/env python3
"""Repology "outdated in openSUSE Tumbleweed" sweep, intersected with your packages.

Pulls every project Repology marks outdated in opensuse_tumbleweed (paginated),
then keeps only those whose TW source-package name is in your set, printing
  <srcname>  <packaged-version> -> <newest-version>

Your package set: pass package names on stdin or via --names FILE (one per line,
e.g. the second column of my-packages.sh). With no names, prints the full TW
outdated list (large).

IMPORTANT — every hit is a CANDIDATE, not a confirmed update. Verify before acting
(see references/1-triage.md): compare by tag/commit DATE not version string,
watch for multi-track upstreams (LTS lines, parallel sonames) and deliberately
pinned packages, and remember Repology lags the devel project. Known false
positives stay flagged here.

Usage: my-packages.sh --... | cut -f2 | outdated.py
       outdated.py --names /tmp/names.txt
"""
import sys, json, time, urllib.request, argparse

ap = argparse.ArgumentParser()
ap.add_argument("--names", help="file of package names (default: stdin)")
ap.add_argument("--repo", default="opensuse_tumbleweed")
ap.add_argument("--ua", default="osc-update-check/1.0")
args = ap.parse_args()

src = open(args.names) if args.names else (sys.stdin if not sys.stdin.isatty() else None)
mine = set(l.strip() for l in src if l.strip()) if src else None

def fetch(bound):
    url = f"https://repology.org/api/v1/projects/{bound}?inrepo={args.repo}&outdated=1"
    req = urllib.request.Request(url, headers={"User-Agent": args.ua})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())

results, bound = {}, ""
while True:
    data = fetch(bound)
    if not data:
        break
    results.update(data)
    last = sorted(data)[-1]
    if len(data) < 200:
        break
    bound = last + "/"
    time.sleep(0.4)

hits, seen = [], set()
for proj, pkgs in results.items():
    tw = [p for p in pkgs if p.get("repo") == args.repo]
    if not tw:
        continue
    newest = next((p["version"] for p in pkgs
                   if p.get("status") in ("newest", "devel") and p.get("version")), "?")
    for p in tw:
        s = p.get("srcname") or p.get("binname") or proj
        if (mine is None or s in mine) and s not in seen:
            seen.add(s)
            hits.append((s, p.get("version"), newest))

print(f"# {len(hits)} outdated candidate(s) — VERIFY each (date, not version string)")
for s, cur, new in sorted(hits, key=lambda x: x[0].lower()):
    print(f"{s:32} {str(cur):24} -> {new}")
