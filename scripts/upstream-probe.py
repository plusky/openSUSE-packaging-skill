#!/usr/bin/env python3
"""Single-package "real latest upstream by DATE" probe with prerelease filtering.

Mechanizes the per-candidate verification from references/triage.md (the
Repology false-positive discipline): a higher version NUMBER can be an OLDER
release — projects renumber (flowgrind's packaged 0.8.2 is from 2021, its
"newer" 0.12 tag from 2009), so the decisive check is the tag/upload DATE,
never a string/semver sort. Complements outdated.py (the bulk sweep); this is
the per-candidate deep check.

Traps encoded here (from triage.md):
  * GitHub `tags?per_page=1` returns git/alphabetical order, NOT chronological
    — never trusted alone; every tag is dated via its commit.
  * A tag without a *release object* (releases/tags/<tag> 404 / empty assets)
    has no maintainer-uploaded tarball — only the auto-archive, which for
    autotools projects lacks `configure` (adopting it costs an autoreconf +
    autoconf/automake/libtool BRs and loses the .asc). Flagged in the output.
  * Git-snapshot packaged versions (~git/+git/+hg + a YYYYMMDD) compare by the
    upstream HEAD commit date, not by tag.
  * Prereleases (rc/alpha/beta/dev/pre; PyPI prerelease/yanked flags) are
    filtered out of "latest stable".

Usage:
  upstream-probe.py <pkg> [--project openSUSE:Factory]   # spec fetched via osc
  upstream-probe.py --spec <file>
  upstream-probe.py --url <github|gitlab|pypi url> [--version <packaged-ver>]

Exit codes:
  0  CURRENT           — packaged version is the latest stable (by date)
  1  UPDATE-CANDIDATE  — a genuinely newer (by date) stable release exists
  3  SUSPECT           — the "newer" version is OLDER by date (renumbering?);
                         do not downgrade
  2  a probe failed (network/auth/unresolvable upstream) — never a silent
     CURRENT
"""
import argparse, json, re, subprocess, sys, urllib.request, urllib.error, urllib.parse
from datetime import datetime, timezone

TIMEOUT = 20
PRERELEASE = re.compile(r"(?:^|[.\-_~])(rc|alpha|beta|dev|pre|a\d+$|b\d+$)", re.I)
SNAPSHOT = re.compile(r"[+~](?:git|hg)\.?(\d{8})", re.I)

def die(msg, code=2):
    sys.stderr.write(f"ERROR: {msg}\n")
    sys.exit(code)

def http_json(url, headers=None):
    req = urllib.request.Request(url, headers={"User-Agent": "openSUSE-upstream-probe/1.0",
                                               **(headers or {})})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.loads(r.read().decode())

# ---------- GitHub: prefer gh api when authenticated (5000 req/h vs 60 anon) --
_GH = None
def gh_ok():
    global _GH
    if _GH is None:
        try:
            _GH = subprocess.run(["gh", "auth", "status"], capture_output=True,
                                 timeout=15).returncode == 0
        except Exception:
            _GH = False
    return _GH

def gh_json(path):
    """GET a GitHub API path; returns parsed JSON or None on 404."""
    if gh_ok():
        r = subprocess.run(["gh", "api", path], capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            # 404 = absent; 422 = "No commit found for SHA: <tag>" (a ref that
            # does not exist) — both are facts ("not there"), not failures
            if "404" in r.stderr or "Not Found" in r.stderr or "HTTP 422" in r.stderr:
                return None
            raise RuntimeError(f"gh api {path}: {r.stderr.strip()}")
        return json.loads(r.stdout)
    try:
        return http_json(f"https://api.github.com/{path}")
    except urllib.error.HTTPError as e:
        if e.code in (404, 422):
            return None
        raise

def parse_date(s):
    if not s:
        return None
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc)

def is_prerelease(v):
    return bool(PRERELEASE.search(v or ""))

def norm(v):
    # strip any non-digit prefix: "v1.2" -> "1.2", "flowgrind-0.8.2" -> "0.8.2"
    return re.sub(r"^[^0-9]*", "", v or "")

# ---------- spec resolution ----------------------------------------------------
def spec_facts(text):
    ver = url = src = None
    for line in text.splitlines():
        m = re.match(r"^Version:\s*(\S+)", line, re.I)
        if m and not ver: ver = m.group(1)
        m = re.match(r"^URL:\s*(\S+)", line, re.I)
        if m and not url: url = m.group(1)
        m = re.match(r"^Source0?:\s*(\S+)", line, re.I)
        if m and not src: src = m.group(1)
    return ver, url, src

def pick_forge(url, src):
    for cand in (src, url):
        if not cand: continue
        m = re.search(r"github\.com/([^/]+)/([^/#?]+)", cand)
        if m: return ("github", m.group(1), m.group(2).removesuffix(".git"))
        m = re.search(r"gitlab\.([^/]+)/([^#?]+?)/-/", cand) or \
            re.search(r"(gitlab\.[^/]+)/([^/]+/[^/#?]+)", cand)
        if m and "gitlab" in cand:
            host = re.search(r"(gitlab\.[^/]+)", cand).group(1)
            proj = re.search(r"gitlab\.[^/]+/([^#?]+?)(?:/-/|\.git|/archive|$)", cand)
            if proj: return ("gitlab", host, proj.group(1).strip("/"))
        if "pythonhosted.org" in cand or "pypi.org" in cand or "pypi.python.org" in cand:
            m = re.search(r"(?:packages/source/./|pypi\.org/(?:project|pypi)/)([A-Za-z0-9._-]+)", cand)
            if m: return ("pypi", None, m.group(1))
    return (None, None, None)

# ---------- backends -----------------------------------------------------------
def probe_pypi(name, packaged):
    d = http_json(f"https://pypi.org/pypi/{name}/json")
    releases = d.get("releases", {})
    def rel_date(v):
        files = releases.get(v) or []
        ds = [parse_date(f.get("upload_time_iso_8601")) for f in files
              if not f.get("yanked")]
        ds = [x for x in ds if x]
        return max(ds) if ds else None
    stable = [(v, rel_date(v)) for v in releases
              if not is_prerelease(v) and rel_date(v)]
    if not stable:
        die(f"pypi {name}: no dated stable releases")
    latest_v, latest_d = max(stable, key=lambda x: x[1])
    return {"packaged_date": rel_date(packaged) or rel_date(norm(packaged)),
            "latest_stable": (latest_v, latest_d),
            "latest_tag": (latest_v, latest_d),
            "asset_note": "PyPI sdist/wheel (real release files)"}

def probe_github(owner, repo, packaged):
    base = f"repos/{owner}/{repo}"
    def tag_date(tag):
        c = gh_json(f"{base}/commits/{tag}")
        return parse_date(((c or {}).get("commit") or {}).get("committer", {}).get("date")) if c else None
    out = {}
    # packaged version's tag date (v-prefix tolerant; snapshot → HEAD compare)
    snap = SNAPSHOT.search(packaged or "")
    if snap:
        out["packaged_date"] = datetime.strptime(snap.group(1), "%Y%m%d").replace(tzinfo=timezone.utc)
        head = gh_json(f"{base}/commits?per_page=1")
        out["head_date"] = parse_date(((head or [{}])[0].get("commit") or {})
                                      .get("committer", {}).get("date")) if head else None
    else:
        out["packaged_date"] = None
        for cand in (packaged, f"v{packaged}", norm(packaged), f"{repo}-{packaged}"):
            if not cand: continue
            d = tag_date(cand)
            if d:
                out["packaged_date"] = d
                break
    # latest stable release (the release the maintainer marked latest)
    rel = gh_json(f"{base}/releases/latest")
    if rel:
        out["latest_stable"] = (rel.get("tag_name"), parse_date(rel.get("published_at")))
        out["asset_note"] = (f"{len(rel.get('assets') or [])} release asset(s)"
                             if rel.get("assets") else
                             "NO release assets — auto-archive only (autotools: "
                             "no configure -> autoreconf + autoconf/automake/libtool cost)")
    # latest tag by DATE (list order is git/alphabetical — date the top ones)
    tags = gh_json(f"{base}/tags?per_page=20") or []
    dated = []
    for t in tags[:10]:   # cap the API cost; enough to beat git-order junk
        d = parse_date(None)
        c = t.get("commit") or {}
        if c.get("sha"):
            cc = gh_json(f"{base}/commits/{c['sha']}")
            d = parse_date(((cc or {}).get("commit") or {}).get("committer", {}).get("date"))
        if d:
            dated.append((t.get("name"), d))
    if dated:
        stable = [x for x in dated if not is_prerelease(x[0])] or dated
        out["latest_tag"] = max(stable, key=lambda x: x[1])
        if "latest_stable" not in out:
            out["latest_stable"] = out["latest_tag"]
            # a tag with no release object usually has no upstream tarball
            rt = gh_json(f"{base}/releases/tags/{out['latest_tag'][0]}")
            out["asset_note"] = ("release object present" if rt else
                                 "tag has NO release object — auto-archive only")
    if "latest_stable" not in out:
        die(f"github {owner}/{repo}: no releases and no datable tags")
    return out

def probe_gitlab(host, proj, packaged):
    enc = urllib.parse.quote(proj, safe="")
    tags = http_json(f"https://{host}/api/v4/projects/{enc}/repository/tags")
    if not tags:
        die(f"gitlab {proj}: no tags")
    def d(t): return parse_date((t.get("commit") or {}).get("committed_date"))
    dated = [(t.get("name"), d(t)) for t in tags if d(t)]
    stable = [x for x in dated if not is_prerelease(x[0])] or dated
    latest = max(stable, key=lambda x: x[1])
    packaged_date = next((dd for n, dd in dated
                          if norm(n) == norm(packaged)), None)
    return {"packaged_date": packaged_date, "latest_stable": latest,
            "latest_tag": max(dated, key=lambda x: x[1]),
            "asset_note": "gitlab: check the release for uploaded assets vs auto-archive"}

# ---------- main ---------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("pkg", nargs="?", help="package name (spec fetched via osc)")
    ap.add_argument("--spec", help="local spec file to read instead")
    ap.add_argument("--url", help="probe this forge/pypi URL directly")
    ap.add_argument("--version", help="packaged version (with --url)")
    ap.add_argument("--project", default="openSUSE:Factory")
    a = ap.parse_args()

    packaged, url, src = a.version, a.url, None
    if a.spec:
        packaged, url, src = spec_facts(open(a.spec).read())
    elif a.pkg:
        r = subprocess.run(["osc", "cat", a.project, a.pkg, f"{a.pkg}.spec"],
                           capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            die(f"osc cat {a.project}/{a.pkg}/{a.pkg}.spec: {r.stderr.strip()}")
        packaged, url, src = spec_facts(r.stdout)
    elif not a.url:
        ap.error("need <pkg>, --spec or --url")

    forge, host, name = pick_forge(a.url or url, src)
    if not forge:
        die(f"could not resolve a supported forge from URL={url!r} Source={src!r} "
            f"(supported: github, gitlab, pypi)")

    try:
        if forge == "pypi":
            facts = probe_pypi(name, packaged)
        elif forge == "github":
            facts = probe_github(host or name.split("/")[0], name, packaged)
        else:
            facts = probe_gitlab(host, name, packaged)
    except (urllib.error.URLError, OSError, RuntimeError, ValueError) as e:
        die(f"{forge} probe failed: {e}")

    def fmt(pair):
        if not pair: return "?"
        v, d = pair
        return f"{v} ({d.date() if d else 'undated'})"

    pd = facts.get("packaged_date")
    lv, ld = facts.get("latest_stable", (None, None))
    print(f"packaged:       {packaged} ({pd.date() if pd else 'date unknown'})")
    print(f"latest stable:  {fmt(facts.get('latest_stable'))}")
    if facts.get("latest_tag") and facts["latest_tag"] != facts.get("latest_stable"):
        print(f"latest tag:     {fmt(facts.get('latest_tag'))}")
    if facts.get("head_date"):
        print(f"upstream HEAD:  {facts['head_date'].date()} (snapshot package — compare by commit date)")
    if facts.get("asset_note"):
        print(f"release assets: {facts['asset_note']}")

    # ---- verdict ----
    if facts.get("head_date") and pd:          # snapshot package
        if facts["head_date"].date() > pd.date():
            print(f"VERDICT: UPDATE-CANDIDATE — upstream HEAD ({facts['head_date'].date()}) "
                  f"is newer than the packaged snapshot ({pd.date()})")
            sys.exit(1)
        print("VERDICT: CURRENT (snapshot at upstream HEAD)")
        sys.exit(0)
    if norm(lv or "") == norm(packaged or ""):
        print("VERDICT: CURRENT")
        sys.exit(0)
    if pd and ld:
        if pd == ld:
            print("VERDICT: CURRENT (packaged tag and latest stable share the same date)")
            sys.exit(0)
        if ld > pd:
            print(f"VERDICT: UPDATE-CANDIDATE — {lv} is newer by date ({ld.date()} > {pd.date()})")
            sys.exit(1)
        print(f"VERDICT: SUSPECT: \"newer\" version {lv} is OLDER by date "
              f"({ld.date()} <= {pd.date()}) — possible renumbering, do not downgrade")
        sys.exit(3)
    if ld and not pd:
        print(f"VERDICT: UPDATE-CANDIDATE — latest stable {lv} ({ld.date()}); packaged "
              f"version's date unknown (tag not found) — VERIFY the dates by hand before acting")
        sys.exit(1)
    die("could not date either side — verify by hand")

if __name__ == "__main__":
    main()
