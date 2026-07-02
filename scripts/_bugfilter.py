"""Shared bugzilla noise filters for bug-scan.sh and maintained-bugs.sh.

openSUSE bugs carry the package name only in the *summary* (the bugzilla
component is a generic bucket), so both scripts match summaries by keyword —
and prune the false positives that produces. The two reducers, learned the
hard way:

* whole-word match — "par"/"dt"/"iw"/"nbd"/"reuse" otherwise match
  "compare"/device-tree/"firewall"/kernel/"connection reuse" bugs.
* CVE affected-package check — a VUL bug summary is
  "VUL-x: CVE-YYYY-NNNN: <affected-pkg>: ...". If <affected-pkg> is not the
  package, it is a tracker bug that merely *mentions* the package's name
  (e.g. "kernel: nbd: ...", "curl: ... connection reuse ...") -> suppressed.
* short-name anchor — <=3-char names are inherently noisy; keep their hits
  only on an anchored "^pkg"/"^[pkg" match (callers flag them "~").
"""
import re

# affected pkg encoded in a CVE/VUL summary: "...CVE-YYYY-NNNN: <pkg[,pkg]>: ..."
CVE_AFF = re.compile(r"CVE-\d{4}-\d+:\s*([A-Za-z0-9._+-]+(?:,[A-Za-z0-9._+-]+)*)\s*:")


def wholeword(pkg):
    """Whole-word regex for a package name (word chars and '-' are boundaries)."""
    return re.compile(r"(?<![\w-])" + re.escape(pkg) + r"(?![\w-])", re.I)


def strong(pkg):
    """Anchored match for short/noisy names: summary starts 'pkg' / '[pkg'."""
    return re.compile(r"^\[?" + re.escape(pkg) + r"\b", re.I)


def is_vul(summary):
    return ("VUL-" in summary) or ("CVE-" in summary)


def cve_affected_mismatch(pkg, summary):
    """True iff the summary names an explicit CVE affected-package list that
    does NOT include pkg — i.e. a tracker bug that merely mentions it."""
    m = CVE_AFF.search(summary or "")
    if not m:
        return False
    return pkg.lower() not in [a.lower() for a in m.group(1).split(",")]


def keep(pkg, summary, anchored_short=True):
    """Full filter verdict for one (package, bug-summary) pair.

    Returns (keep, short_flag):
      keep       -- False if the hit is a false positive to suppress
      short_flag -- True if pkg is a short (<=3 char) name kept only on an
                    anchored match (callers print it flagged '~')
    """
    s = summary or ""
    if not wholeword(pkg).search(s):
        return False, False
    if is_vul(s) and cve_affected_mismatch(pkg, s):
        return False, False
    short = len(pkg) <= 3
    if short and anchored_short and not strong(pkg).search(s):
        return False, True
    return True, short


if __name__ == "__main__":
    # not a CLI — a shared module for bug-scan.sh / maintained-bugs.sh
    print(__doc__)
