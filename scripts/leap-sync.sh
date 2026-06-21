#!/bin/bash
# Sync a package's Leap product branch up to its Factory branch on
# src.opensuse.org and open the Package Hub PR — the repetitive git flow for
# "push the latest <pkg> from Factory to Leap", done in one call.
#
# What it does: clone pool/<pkg> (LFS pointers only), verify the leap branch
# EXISTS (new packages can't be onboarded this way — see below), make its tree
# identical to the factory branch as one commit, fetch the LFS objects, fork,
# push to your fork, and open a PR targeting the leap branch.
#
# IMPORTANT — only works for packages ALREADY in Leap (an existing leap-NN
# branch in pool/<pkg>). Adding a NEW package to Leap needs a pool maintainer to
# create the branch first (a contributor PR cannot create a branch); this script
# errors out in that case. See references/git-workflow.md "Leap 16 / SLFO".
#
# Requires: a src.opensuse.org login in ~/.config/tea/config.yml, git-lfs, tea.
#
# Usage: leap-sync.sh <pkg> [leap-branch]      (leap-branch default: leap-16.0)
set -uo pipefail
[ $# -ge 1 ] || { sed -n '2,21p' "$0"; exit 2; }
pkg="$1"; leap="${2:-leap-16.0}"
tok=$(python3 -c "import yaml,os;c=yaml.safe_load(open(os.path.expanduser('~/.config/tea/config.yml')));print([l['token'] for l in c['logins'] if l['name']=='src.opensuse.org'][0])" 2>/dev/null)
[ -n "$tok" ] || { echo "no src.opensuse.org token in ~/.config/tea/config.yml" >&2; exit 2; }
user=$(python3 -c "import yaml,os;c=yaml.safe_load(open(os.path.expanduser('~/.config/tea/config.yml')));print(next((l.get('user') for l in c['logins'] if l['name']=='src.opensuse.org'),''))" 2>/dev/null)
[ -n "$user" ] || { echo "could not determine your src.opensuse.org username from the tea login" >&2; exit 2; }

wd=$(mktemp -d); trap 'rm -rf "$wd"' EXIT
GIT_LFS_SKIP_SMUDGE=1 git clone -q "https://src.opensuse.org/pool/$pkg.git" "$wd/$pkg" || { echo "no pool/$pkg repo" >&2; exit 2; }
cd "$wd/$pkg" || exit 2
git fetch -q origin factory "$leap" 2>/dev/null || { echo "ERROR: pool/$pkg has no '$leap' branch — this is a NEW-to-Leap package; a pool maintainer must create the branch first (contributor PRs can't). See references/git-workflow.md." >&2; exit 3; }

fver=$(git show "origin/factory:$pkg.spec" 2>/dev/null | grep -iE '^Version:' | head -1 | awk '{print $2}')
lver=$(git show "origin/$leap:$pkg.spec"   2>/dev/null | grep -iE '^Version:' | head -1 | awk '{print $2}')
echo "$pkg: factory=$fver  $leap=$lver"
[ -n "$fver" ] || { echo "could not read factory version" >&2; exit 2; }
if [ "$fver" = "$lver" ]; then echo "already in sync — nothing to do"; exit 0; fi

br="$leap-sync-$fver"
git checkout -q -b "$br" "origin/$leap"
git rm -rqf . >/dev/null 2>&1
git checkout "origin/factory" -- .
git add -A
git commit -q -m "Update to $fver (sync $leap with Factory)"
git lfs fetch --all origin >/dev/null 2>&1

tea repo fork --repo "pool/$pkg" --login src.opensuse.org >/dev/null 2>&1
git remote add fork "https://$user:$tok@src.opensuse.org/$user/$pkg.git" 2>/dev/null \
  || git remote set-url fork "https://$user:$tok@src.opensuse.org/$user/$pkg.git"
git push -q fork "$br" || { echo "push failed" >&2; exit 2; }

body="Sync the $leap branch up to the Factory version $fver (was $lver). Sources are identical to openSUSE:Factory."
resp=$(curl -sS -X POST "https://src.opensuse.org/api/v1/repos/pool/$pkg/pulls" \
  -H "Authorization: token $tok" -H "Content-Type: application/json" \
  -d "{\"head\":\"$user:$br\",\"base\":\"$leap\",\"title\":\"Update to $fver (sync $leap with Factory)\",\"body\":\"$body\"}")
echo "$resp" | python3 -c "import sys,json;d=json.load(sys.stdin);print('PR:', d.get('html_url') or d.get('message'))" 2>/dev/null \
  || { echo "PR API response:"; echo "$resp" | head -c 300; }
