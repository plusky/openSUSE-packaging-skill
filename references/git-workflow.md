# Git packaging workflow (src.opensuse.org / Gitea)

## Git packaging workflow (src.opensuse.org)

openSUSE is migrating package sources from classic OBS `osc` checkouts to **Git on `src.opensuse.org`** (a Gitea instance). Reference: https://en.opensuse.org/openSUSE:Git_Packaging_Workflow (and its companion https://en.opensuse.org/openSUSE:OBS_to_Git). A package is in the Git workflow when you clone it from `src.opensuse.org` instead of `osc co`-ing it; the checkout is a plain git repo (no `.osc/` dir) with the `.spec`, `.changes`, source tarball(s), `.gitattributes`, and `.gitignore`.

**The spec/`.changes`/spec-cleaner/rpmlint rules in this skill are unchanged** — only the *plumbing* around them (fork / checkout / commit / submit) differs. Everything in "Core directive" still applies: spec-cleaner clean, `.changes` entry per session, local `osc build`, etc.

### Repo topology on src.opensuse.org

- `pool/<pkg>` — the canonical package repo (the source of truth, shared across products). Marked **`source`** in `tea repo search`. Default branch is usually **`factory`**. **Do NOT target PRs here.**
- `<devel-project>/<pkg>` (e.g. `devel-factory/hwdata`, `network:messaging:xmpp/libstrophe`) — the devel-project repo, a **`fork`** of pool in Gitea's fork network. Default branch is usually **`main`**. **This is the PR target for package changes.**
- `<youruser>/<pkg>` — your personal fork.

All three live in one Gitea fork network, so a PR can technically be opened between any of them. Find a package's devel project via `pkgs/_meta/devel_packages` in the `openSUSE/Factory` repo (the Factory web UI doesn't show it yet).

**PR target = the devel-project repo, not `pool`.** A package change (version bump, spec fix, etc.) goes as a PR to `<devel-project>/<pkg>` (base branch `main`) — that is where the `autogits` bots run (they open the follow-on `_ObsPrj` PR and post OBS build results as a comment). `pool/<pkg>` is the canonical/aggregation repo and is **not** the contribution entry point; a PR opened against `pool` is the wrong target and will just be closed. (Confirmed in practice: a `pool/hwdata` PR was closed by the maintainer in favour of the `devel-factory/hwdata` one.) After the devel PR merges, propagation to `pool` and to `openSUSE:Factory` is handled by the bots / the classic `osc sr <devel-project>/<pkg> openSUSE:Factory` step — not by you PRing pool directly.

### Tooling & one-time setup

- **osc ≥ 1.15.0** is required for `osc fork` (earlier versions have fork bugs). `osc build` and `osc sr` still work as documented elsewhere in this skill.
- **`git-lfs` is mandatory** — source tarballs are stored in LFS, configured by the repo's `.gitattributes` (`*.gz *.xz *.zst *.bz2 *.tar … filter=lfs`). After `git add`-ing a tarball, confirm it's a pointer with `git cat-file -p :<tarball>` (should print `version https://git-lfs.github.com/spec/v1` + oid + size), **not** the raw binary. The working-tree file stays the real tarball, so `osc build` still sees real sources.
- **CLI clients**: `osc` (forking + building + Factory SRs), `tea` (Gitea CLI — logins, fork, PR), and `git-obs` (bundled with osc; PR create/review). Check `tea logins list` for an existing `src.opensuse.org` login before assuming auth is needed.
- **SSH**: clone via `gitea@src.opensuse.org:<owner>/<pkg>.git`; your SSH key must be registered at https://src.opensuse.org/user/settings/keys. First clone may need the host key — `ssh-keyscan src.opensuse.org >> ~/.ssh/known_hosts`.

### Command mapping (old osc → git workflow)

| Old `osc` | Git workflow |
|---|---|
| `osc co <prj> <pkg>` | `git clone gitea@src.opensuse.org:<owner>/<pkg>.git` |
| `osc add file` | `git add file` |
| `osc ci` | `git commit` + `git push` |
| `osc vc` | `osc vc` (unchanged — still the canonical `.changes` editor) |
| `osc build` | `osc build` (unchanged) |
| `osc branch` | `osc fork <prj> <pkg>` |
| `osc rdelete prj/pkg` | `git rm <pkg>` (removes the submodule in a project repo) |

### Forking

Two ways, and the difference matters:

- **`osc fork <devel-project> <pkg>`** (recommended) — creates **both** the Gitea fork (`<youruser>/<pkg>`) **and** an OBS project branch (`home:<you>:branches:<devel-project>`) wired to build your fork via scmsync. Use this when you want OBS to build your changes before/without a PR.
- **`tea repo fork --repo <owner>/<pkg>`** (or `git-obs repo fork`) — Gitea-only fork, **no** OBS build branch. Sufficient when you'll rely on local `osc build` plus the post-PR autogits bot build (below). Lighter weight; no OBS home project left behind to clean up.

### Local build in a git checkout — the gotchas

- There is no `.osc/` metadata, so **`osc build` defaults to building against `openSUSE:Factory`, not the devel project.** Pass **`osc build --alternative-project=<devel-project>`** to use the devel project's build config. (Plain `osc build` from a bare spec also needs an explicit `REPOSITORY ARCH BUILD_DESCR` — see "Local builds" below.)
- **`osc service runall source_validator` fails in a git checkout** with `Git SCM package working copy doesn't have … project / The package has no parent project checkout`. This is expected — the validator wants OBS parent-project metadata a plain clone lacks. It's not a blocker for local iteration; the real gate is a clean `osc build` (which parses the spec) plus spec-cleaner. (The server-side workflow runs validation for you on the PR.)
- Pick a repo/arch that publishes your **native** arch to avoid qemu emulation. `openSUSE:Factory/standard` only has `x86_64`/`i586`; for aarch64 use `openSUSE:Factory:ARM/standard` (or a Leap repo that lists aarch64). Confirm with `osc repos <project>`.
- **Emulated foreign arches need an x86_64 host.** `osc build`/`osc chroot` for riscv64 via `openSUSE:Factory:RISCV` aborts on an aarch64 host with `Error: hostarch 'x86_64' is required` — the qemu buildconfig pins the *host* to x86_64. So from an aarch64 machine you cannot locally build riscv64 (and native riscv64 would need a riscv64 host); rely on OBS server-side (x86_64 workers) for that arch, or settle arch-specific questions by source inspection. (When a build *is* justified on a non-native arch, expect it to be much slower under qemu.)

### Submitting changes — PR, not `osc sr` (except to Factory)

Contributors send **pull requests on Gitea**, not OBS submit requests. **Target the devel-project repo** (`<devel-project>/<pkg>`, base branch `main`) — never `pool`:

```
# after git commit + git push to your fork:
git-obs pr create --title "..." --description "..." --target-branch main
# or use tea:  tea pr create --base main --head <youruser>:<branch> --repo <devel-project>/<pkg>
# or the Gitea web UI.
```

`tea`/`git-obs` can choke on a fresh checkout with `core.repositoryformatversion does not support extension: objectformat` (a go-git limitation reading newer git repo configs). When that happens, **create the PR via the Gitea REST API** instead:

```
TOKEN=$(python3 -c "import yaml;c=yaml.safe_load(open('$HOME/.config/tea/config.yml'));print([l['token'] for l in c['logins'] if l['name']=='src.opensuse.org'][0])")
curl -sS -X POST "https://src.opensuse.org/api/v1/repos/<devel-project>/<pkg>/pulls" \
  -H "Authorization: token $TOKEN" -H "Content-Type: application/json" \
  -d '{"head":"<youruser>:<branch>","base":"main","title":"...","body":"..."}'
```

What happens after the PR opens:
- The **`autogits-devel` bot** automatically opens a second PR against the project's `_ObsPrj` repo.
- The **`autogits_obs_staging_bot`** creates an OBS build project, builds the change, and **posts build results as a comment on your PR** — this is your server-side build feedback (you don't need an OBS home branch just to see if it builds).
- Prefix the PR title with **`WIP:`** to suppress the bot automation while iterating.
- Maintainer approves → bot auto-merges. A maintainer's own PR auto-merges on a successful build.

**Submitting to `openSUSE:Factory` is still pure osc** — it is *not* yet managed through Git/Gitea. After your change lands in the devel project (PR merged), run the classic `osc sr <obs-devel-project>/<pkg> openSUSE:Factory` (see "Submit requests" below). The whole Factory review chain (`factory-auto`, `licensedigger`, staging, `opensuse-review-team`) is unchanged.

**The `osc sr` source is the OBS devel-project name, not the Gitea org name** — they differ. The Gitea org `devel-factory` corresponds to the OBS project `devel:openSUSE:Factory` (the catch-all Factory devel project for packages without a more specific devel project). So a package whose git repo is `devel-factory/hwdata` is submitted with:

```
osc sr devel:openSUSE:Factory/hwdata openSUSE:Factory
```

i.e. the SR runs against `api.opensuse.org` (OBS), referencing the OBS-side project, **after** the Gitea PR to `devel-factory/hwdata` has merged and OBS has synced that revision. Don't pass the Gitea path (`devel-factory/hwdata`) to `osc sr` — `osc` won't find it. If unsure of the OBS devel-project name, `osc develproject openSUSE:Factory <pkg>` returns it.

Before submitting, confirm the merge actually synced into OBS — `osc cat <obs-devel-project> <pkg> <pkg>.spec | grep ^Version:` (and the top of the `.changes`) should show your new version. The Gitea→OBS sync is near-instant but not literally instantaneous; if the spec still shows the old version, wait and re-check rather than submitting the stale revision.

**Skip `osc results` before the SR for git-tracked packages.** When the package lives in a git-based devel project (the Git packaging workflow), build verification is the PR/autogits bot's job — it already built the change and posted results on the Gitea PR before it merged. Polling `osc results <obs-devel-project> <pkg>` before `osc sr` is therefore the wrong check for git-tracked packages; skip it and go straight from "merge synced into OBS" to `osc sr`. (The pre-SR `osc results` poll still applies to **classic osc-checkout** devel projects, where OBS is the only thing that built your commit.)

### Leap 16 / SLFO (Package Hub) — PR to the `leap-16.x` branch of `pool`, not a devel repo

Leap 16 is built on **SLFO** (SLES 16 / `SUSE:SLFO:1.2`) and takes community-package contributions **exclusively via the git workflow**. The topology differs from Factory in one crucial way: **the per-product branches live in `pool/<pkg>` itself**, so for Leap you **DO** target `pool` (the opposite of the Factory rule above).

- `pool/<pkg>` carries multiple branches: **`factory`** (Tumbleweed, the default/source-of-truth), **`leap-16.0`**, **`leap-16.1`**, … (one per Leap product). SLE-origin packages instead use **`slfo-main`** / **`slfo-x.y`** branches; when both a `slfo-*` and a `leap-x.y` branch exist, work from the **`leap-x.y`** one.
- **A Leap 16.x community-package update is a PR targeting the `leap-16.x` branch of `pool/<pkg>`** (Package Hub submission). Fork `pool/<pkg>`, branch off `leap-16.x`, sync it to the desired version, push to your fork, and open the PR with `base = leap-16.x`. The `openSUSE:Backports:SLE-16.0` OBS project is **scmsync read-only** (`<scmsync>…/products/PackageHub#leap-16.0`), fed from those branches — so `osc sr … openSUSE:Backports:SLE-16.0` is the *old* path and is wrong here.
- **Syncing leap-16.x up to Factory is a *content* sync, not a `git merge`.** The branches usually have **unrelated histories** (OBS→Git import), so `git merge origin/factory` fails with *"refusing to merge unrelated histories"*. Instead make the tree identical to factory as one commit: `git rm -rqf . && git checkout origin/factory -- . && git add -A && git commit -m "Update to <ver> (sync leap-16.x with Factory)"`. (The old `<ver>.obscpio` LFS file is dropped and the new one added automatically.)
- **LFS gotcha on push:** clone with `GIT_LFS_SKIP_SMUDGE=1` (pointers only), but before pushing the branch to your fork you must have the actual LFS objects locally or the push fails with *"Unable to find source for object …"*. Run **`git lfs fetch --all origin`** first, then push.
- **Review policy:** the Backports/Package Hub team approves; if the sources **match** openSUSE:Factory (or a maintained Leap) no extra sign-off is needed, but a deviation from Factory, or a submitter who isn't a regular Factory maintainer of the package, needs separate Factory-maintainer approval. So sync to *exactly* the Factory version when you can. (Real case: `pool/xmrig` leap-16.0 6.22.0→6.26.0 — PR `pool/xmrig#1` to the `leap-16.0` branch; <your-obs-account> maintains xmrig in Factory so it qualified.)

### AGit workflow (no fork)

Push straight to a magic ref to auto-create a PR — no fork needed:

```
git clone https://src.opensuse.org/<prj>/<pkg>
# edit, commit
git push origin main:refs/for/main/<feature> -o title="Update to X"
```

**Do not use AGit for repos with LFS-stored source archives** — AGit doesn't support LFS yet (per the wiki's own warning). Since almost every package repo stores its tarball in LFS, this means AGit is rarely the right choice for a normal version bump; fork + PR is the safe default.

### Build-result dashboards

`https://br.opensuse.org/status/<PRJ>/<PKG>[/<repo>[/<arch>]]` — human-readable build status, e.g. `https://br.opensuse.org/status/devel:languages:lua/lua54`. Handy to paste into a README badge or to check status without `osc results`.
