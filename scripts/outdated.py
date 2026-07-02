#!/usr/bin/env python3
"""Repology "outdated in openSUSE Tumbleweed" sweep, intersected with your packages.

Pulls every project Repology marks outdated in opensuse_tumbleweed (paginated),
then keeps only those whose TW source-package name is in your set, printing
  <srcname>  <packaged-version> -> <newest-version>

Your package set: pass package names on stdin or via --names FILE (one per line,
e.g. the second column of my-packages.sh). With no names, prints the full TW
outdated list (large).

REPOLOGY LAGS PUBLISHED TUMBLEWEED, WHICH LAGS THE DEVEL PROJECT, so a large
fraction of raw hits are false positives — the update already landed in Factory
and Repology just hasn't caught up. By default (when filtering by --names/stdin)
this script therefore cross-checks every hit against the live Factory `Version:`
and SUPPRESSES the ones Factory already ships at the "newest" version, so the
output is actually actionable instead of a wall of known-lag noise. Use
--no-factory-check to skip that (raw Repology view). The cross-check needs a
working `osc` against api.opensuse.org.

Surviving candidates are still CANDIDATES, not confirmed updates — verify before
acting (see references/triage.md): compare by tag/commit DATE not version string,
watch for multi-track upstreams (LTS lines, parallel sonames) and deliberately
pinned packages. Known false positives stay flagged here.

Usage: my-packages.sh --... | cut -f2 | outdated.py
       outdated.py --names /tmp/names.txt
       outdated.py --names /tmp/names.txt --no-factory-check   # raw Repology
"""
import sys, json, time, urllib.request, argparse, subprocess, re
from concurrent.futures import ThreadPoolExecutor

ap = argparse.ArgumentParser()
ap.add_argument("--names", help="file of package names (default: stdin)")
ap.add_argument("--repo", default="opensuse_tumbleweed")
ap.add_argument("--ua", default="osc-update-check/1.0")
ap.add_argument("--project", default="openSUSE:Factory",
                help="reference project whose live Version: confirms a hit (default openSUSE:Factory)")
ap.add_argument("--no-factory-check", action="store_true",
                help="skip the live cross-check; print every raw Repology hit (incl. lag false positives)")
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
    # Prefer a real 'newest' release; fall back to 'devel' (pre-release) ONLY
    # when no newest exists, and tag the fallback so triage sees it — the
    # first-in-list-order pick used to let a preceding rc/beta become the
    # proposed target version.
    newest = next((p["version"] for p in pkgs
                   if p.get("status") == "newest" and p.get("version")), None)
    if newest is not None:
        newest_disp = newest
    else:
        dev = next((p["version"] for p in pkgs
                    if p.get("status") == "devel" and p.get("version")), None)
        newest, newest_disp = (dev, f"{dev} (devel)") if dev else ("?", "?")
    for p in tw:
        s = p.get("srcname") or p.get("binname") or proj
        if (mine is None or s in mine) and s not in seen:
            seen.add(s)
            hits.append((s, p.get("version"), newest, newest_disp))

# Cross-check against the live reference project to drop Repology-lag false positives.
def ref_version(pkg):
    """Returns (status, version): ('ok', v) | ('absent', None) | ('failed', None).
    A network hiccup / osc failure must NOT be conflated with 'not in project'."""
    try:
        r = subprocess.run(["osc", "cat", args.project, pkg, f"{pkg}.spec"],
                           capture_output=True, text=True, timeout=30)
    except Exception:
        return ("failed", None)
    if r.returncode != 0:
        # 404 (package/file absent) vs any other failure (auth, network, 5xx)
        if "404" in (r.stderr or ""):
            return ("absent", None)
        return ("failed", None)
    for line in r.stdout.splitlines():
        m = re.match(r"^Version:\s*(\S+)", line)
        if m:
            return ("ok", m.group(1))
    return ("absent", None)  # in project but no parseable Version

do_check = (mine is not None) and not args.no_factory_check
refv = {}
if do_check and hits:
    with ThreadPoolExecutor(max_workers=8) as ex:
        refv = dict(zip((h[0] for h in hits),
                        ex.map(ref_version, (h[0] for h in hits))))

candidates, suppressed = [], []
for s, cur, new, new_disp in hits:
    status, fv = refv.get(s, (None, None))
    if do_check and status == "ok" and new != "?" and fv == new:
        suppressed.append((s, fv))          # reference already at newest -> Repology lag
    else:
        candidates.append((s, cur, new_disp, status, fv))

shortprj = args.project.split(":")[-1] or args.project
if do_check:
    print(f"# {len(candidates)} candidate(s) after {args.project} cross-check, "
          f"{len(suppressed)} suppressed as already-current — still VERIFY each (date, not string)")
else:
    print(f"# {len(candidates)} outdated candidate(s) — VERIFY each (date, not version string)")

for s, cur, new_disp, status, fv in sorted(candidates, key=lambda x: x[0].lower()):
    extra = ""
    if do_check:
        if status == "failed":
            extra = "   (check failed)"
        elif status == "absent":
            extra = f"   (not in {args.project})"
        elif fv != cur:
            extra = f"   ({shortprj}={fv})"
    print(f"{s:32} {str(cur):24} -> {new_disp}{extra}")

if do_check and suppressed:
    print(f"# suppressed (already at newest in {args.project}): "
          + " ".join(f"{s}={fv}" for s, fv in sorted(suppressed)))
