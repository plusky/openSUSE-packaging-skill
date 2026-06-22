# Leap 16.x / SLFO / Backports — which branch, which flow

Getting a change into Leap 16.x is **not** one path — it depends on where the package comes from. Work this out *first* (`scripts/distro-survey.sh` aside, this is an openSUSE-internal lookup), because the submission target and review bar differ. The git mechanics (fork, LFS, content-sync, PR) live in `references/git-workflow.md`; this page is the **routing + decision** layer plus the topology that's easy to get wrong.

## 1. Where does the package come from? (decides the target branch)

Check the three feeds for Leap 16.0, in this order:

```
osc api /source/SUSE:SLFO:1.2/<pkg>/_meta        # SLE base (scmsync'd from pool ?trackingbranch=slfo-1.2)
osc api /source/openSUSE:Backports:SLE-16.0/<pkg>/_meta
# and the per-product branches in the git pool:
curl -s https://src.opensuse.org/api/v1/repos/pool/<pkg>/branches   # look for leap-16.0 / leap-16.1 / slfo-1.2 / slfo-main
```

| Branches present in `pool/<pkg>` | Origin | PR target for Leap | Reviewed by | Notes |
|---|---|---|---|---|
| `leap-16.0`, `leap-16.1` | **community / Package Hub** | the `leap-16.x` branch of `pool/<pkg>` | Backports/Package Hub team | The common case for community packages. |
| `slfo-1.2`, `slfo-main` (no `leap-16.x`) | **SLE base (`SUSE:SLFO:1.2`)** | the `slfo-1.2` branch (→ SLES 16.0 + Leap 16.0) and `slfo-main` (rolling SLFO → Leap 16.1) | **SLFO/SUSE maintainers — higher bar** | Feeds a commercial product; sync to *exactly* the Factory version. (Real: **xmlstarlet** has only `factory`/`slfo-1.2`/`slfo-main`.) |
| both `slfo-*` and `leap-x.y` | both | prefer the **`leap-x.y`** branch | Backports | When both exist, the community branch is the lighter path. |

**Key trap:** `openSUSE:Backports:SLE-16.0` (OBS) is **scmsync read-only** (`<scmsync>…/products/PackageHub#leap-16.0`), fed from the `leap-16.x` branches — so `osc sr … openSUSE:Backports:SLE-16.0` is the *old* path and is wrong. Submit via the git PR to the branch.

**Factory and Leap can use *different* mechanisms for the same package — check each independently.** `pool/<pkg>` having a `factory` branch does **not** mean Factory consumes it: a package can be **OSC-managed for Factory** (`osc api /source/openSUSE:Factory/<pkg>/_meta` shows a `<devel project=…>`, not `<scmsync>`) while its Leap variant is **git/scmsync-managed** (`leap-16.x` pool branches). When so, the *same* fix goes out two ways in one session: `osc sr` to Factory via the devel project, **and** a git PR to each `leap-16.x` branch. (Real case: archmage — Factory devel project `Archiving` via `osc sr`, but Leap 16.0/16.1 are `pool/archmage` `leap-16.x` branches via PR; the `pool/archmage:factory` branch is just the git mirror, not Factory's source.)

## 2. Is the Leap branch actually behind? (don't sync a no-op)

`leap-16.0`/`leap-16.1` usually point at the same commit, but **not always** — verify per branch, don't assume:
- `tcpreplay`: `leap-16.0` = 4.5.2 but `leap-16.1` lagged at 4.4.4 (older than 16.0!).
- `lldpd`: both Leaps lagged Factory (1.0.18 vs 1.0.22).

Compare the `Version:` on each target branch against Factory before doing anything.

## 3. Two ways to produce the Leap change

- **Content-sync from Factory** (when `pool/<pkg>:factory` already has the new version): make the leap branch *identical* to factory in one commit — `git rm -rqf . && git checkout origin/factory -- . && git add -A && git commit`. Branches have **unrelated histories** (OBS→Git import), so `git merge origin/factory` fails with "refusing to merge unrelated histories" — content-sync, never merge. (`scripts/leap-sync.sh <pkg> [leap-branch]` automates the whole flow for this case.)
- **Apply the change directly to the leap branch** (when Factory's pool branch doesn't carry the fix yet — e.g. you just submitted it to Factory and it hasn't merged): branch off `leap-16.x`, apply the same patch/version bump you put in Factory, push, PR. This is the path for a fresh CVE fix that goes to Factory + Leaps in the same session (lrzip, lldpd).

**Mirror 16.0 ⇄ 16.1 with a cherry-pick:** after committing on one branch, `git checkout -b …-16.1 origin/leap-16.1 && git cherry-pick <commit>` — one build, two PRs.

**LFS gotcha:** clone with `GIT_LFS_SKIP_SMUDGE=1`, but before pushing run `git lfs fetch --all origin` (or `git lfs fetch origin factory`) + `git lfs checkout <tarball>` or the push fails with "Unable to find source for object …". Confirm the tarball staged as an LFS *pointer* with `git cat-file -p :<tarball>` (should print `version https://git-lfs.github.com/spec/v1`).

## 4. New-to-Leap packages are NOT self-service

A Gitea PR merges into an *existing* base branch, and a normal contributor has `push: false` on `pool/<pkg>` — so you **cannot** create a `leap-16.x` branch by PR. Onboarding a new package to Leap needs two `pool`/Package-Hub-maintainer actions: (1) create the `leap-16.x` branch (content = factory), (2) register it as a submodule in `products/PackageHub`'s `leap-16.x` branch `.gitmodules`. That's a coordinated request to the Backports/Package Hub team, not a stack of PRs. (Real wall: monero/monero-gui — no `leap-16.0` branch + `push:false`.)

## 5. Closing the loop with bugzilla / in-flight fixups

- Per the bug hard rule (`references/bugzilla-cve-triage.md`), cite `boo#` for what the Leap update fixes; for Leap/SLFO submissions where acceptance is uncertain, confirm with the user whether to close on submission or leave open.
- **Amending an in-flight Factory/devel submission** (e.g. to add a `boo#` ref after you already submitted): edit the `.changes` entry, commit, then **revoke the stale Factory SR** (`osc request revoke <id> -m "superseding: …"`) and re-submit fresh — don't leave two competing SRs for the same package. (Real: vapoursynth — revoked SR, amended changelog to reference `boo#1268226`, re-forwarded.) Note the home-branch project is auto-removed once its SR is accepted, so re-branch before amending.
