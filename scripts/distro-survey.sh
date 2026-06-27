#!/bin/bash
# Survey how other distributions package <pkg> — version (and a patch-count hint)
# across Fedora, Debian, Gentoo, Arch, Alpine, openEuler, Void, NixOS, FreeBSD
# ports, OpenMandriva and Mageia, in ONE call.
# Implements the "survey other distros whenever you touch a package" hard rule
# (catch config options / patches / fixes / a newer-or-different upstream lineage
# we're missing). Best-effort: a distro that 404s or isn't packaged is shown as
# "-" rather than failing the whole run.
#
# Usage: distro-survey.sh <pkg> [factory-version]
#   factory-version (optional) is printed alongside for a quick lag comparison.
#
# Output: one line per distro: "<distro>  <version>  <patches/notes>".
set -u
pkg="${1:?usage: distro-survey.sh <pkg> [factory-version]}"
fac="${2:-}"
UA='openSUSE-distro-survey/1.0'
get() { curl -fsSL -A "$UA" --max-time 20 "$@" 2>/dev/null; }

printf '== distro survey: %s ==\n' "$pkg"
[ -n "$fac" ] && printf '  %-10s %s\n' 'Factory' "$fac"

# Fedora (rawhide spec)
fv=$(get "https://src.fedoraproject.org/rpms/$pkg/raw/rawhide/f/$pkg.spec" | grep -m1 -iE '^Version:' | awk '{print $2}')
fp=$(get "https://src.fedoraproject.org/api/0/rpms/$pkg/tree/rawhide" >/dev/null 2>&1; echo)
printf '  %-10s %s\n' 'Fedora' "${fv:--}"

# Debian (sources.debian.org API)
dv=$(get "https://sources.debian.org/api/src/$pkg/" | python3 -c "import sys,json;d=json.load(sys.stdin);vs=[v['version'] for v in d.get('versions',[])];print(vs[0] if vs else '-')" 2>/dev/null)
printf '  %-10s %s\n' 'Debian' "${dv:--}"

# Gentoo (newest ebuild filename)
gv=$(get "https://gitweb.gentoo.org/repo/gentoo.git/plain/$(get "https://gitweb.gentoo.org/repo/gentoo.git/plain/" >/dev/null; echo)" >/dev/null 2>&1; \
     for cat in app-arch app-misc dev-libs sys-apps net-misc app-text dev-util sys-libs; do \
       e=$(get "https://gitweb.gentoo.org/repo/gentoo.git/tree/$cat/$pkg" | grep -oE "$pkg-[0-9][^'\"<]*\.ebuild" | sed -E "s/^$pkg-//;s/\.ebuild$//" | sort -V | tail -1); \
       [ -n "$e" ] && { echo "$e ($cat)"; break; }; done)
printf '  %-10s %s\n' 'Gentoo' "${gv:--}"

# Arch (official repos)
av=$(get "https://archlinux.org/packages/search/json/?name=$pkg" | python3 -c "import sys,json;r=json.load(sys.stdin).get('results',[]);print(r[0]['pkgver'] if r else '-')" 2>/dev/null)
printf '  %-10s %s\n' 'Arch' "${av:--}"

# Alpine (aports APKBUILD on edge, common repos)
alv='-'
for repo in main community testing; do
  v=$(get "https://gitlab.alpinelinux.org/alpine/aports/-/raw/master/$repo/$pkg/APKBUILD" | grep -m1 -E '^pkgver=' | cut -d= -f2)
  [ -n "$v" ] && { alv="$v ($repo)"; break; }
done
printf '  %-10s %s\n' 'Alpine' "$alv"

# openEuler (src-openeuler spec on gitee)
ov=$(get "https://gitee.com/src-openeuler/$pkg/raw/master/$pkg.spec" | grep -m1 -iE '^Version:' | awk '{print $2}')
printf '  %-10s %s\n' 'openEuler' "${ov:--}"

# Void Linux (void-packages template — reliable, version=<v>)
vv=$(get "https://raw.githubusercontent.com/void-linux/void-packages/master/srcpkgs/$pkg/template" | grep -m1 -E '^version=' | cut -d= -f2)
printf '  %-10s %s\n' 'Void' "${vv:--}"

# NixOS / FreeBSD ports / OpenMandriva / Mageia — one Repology call, by repo prefix.
# Repology project name usually == srcname; best-effort, '-' on mismatch/absence.
REPOLOGY=$(get "https://repology.org/api/v1/project/$pkg")
rg() {
  printf '%s' "$REPOLOGY" | python3 -c '
import sys, json
pref = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    print("-"); sys.exit()
vs = sorted({p.get("version","") for p in d if p.get("repo","").startswith(pref) and p.get("version")})
print(vs[-1] if vs else "-")
' "$1"
}
printf '  %-10s %s\n' 'NixOS'       "$(rg nix)"
printf '  %-10s %s\n' 'FreeBSD'     "$(rg freebsd)"
printf '  %-10s %s\n' 'OpenMandr.'  "$(rg openmandriva)"
printf '  %-10s %s\n' 'Mageia'      "$(rg mageia)"

echo "(divergence → a newer version, a different upstream lineage, or a patch worth pulling; inspect the laggard-vs-leader spec/patches directly.)"
