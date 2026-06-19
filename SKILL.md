---
name: openSUSE-packaging
description: Authoring, modifying, reviewing, or building openSUSE RPM packages — spec files, .changes files, osc / OBS and Git (src.opensuse.org / Gitea) workflows. Use whenever the working directory has a .osc/ folder or a *.spec file, when the user mentions osc, OBS, rpmbuild, openSUSE Build Service, src.opensuse.org, the Git packaging workflow, tea, git-obs, osc fork, spec file, .changes file, rpmlint, or asks to build/submit/review/fork a package, check if packages are out of date, or open a package pull request. Covers Specfile guidelines, the Git packaging workflow, Shared library policy, Systemd packaging, Patches, Changelog format, and language-specific packaging (Python, Perl, Ruby, Go, Rust, Java, PHP, Haskell, Lua, R, Meson, Vala).
---

# openSUSE packaging

Rules for authoring, modifying, and building RPM packages for openSUSE / SUSE via OBS. Derived from https://en.opensuse.org/openSUSE:Packaging_guidelines and its linked subpages. If this skill and the wiki disagree on a specific question, fetch the wiki page and trust it — the upstream pages are authoritative.

## How to use this skill — the three-block pipeline

Most package work is one of three blocks, run in order with a feedback loop. **Load the reference for the block you're in (don't read all of them up front), call the bundled `scripts/` for the recurring osc/Repology queries instead of re-deriving them, and optionally fork the matching `agents/` playbook as a subagent for a large or long-running block.** This top-level file stays loaded the whole time and carries only the cross-cutting rules below; the per-block detail lives in `references/`.

**Block 1 — Triage: does the package need updating?** → read `references/1-triage.md`
Enumerate what you maintain, compare against upstream **by date, not version string**, and weed out multi-track / deliberately-pinned false positives. Scripts: `scripts/my-packages.sh`, `scripts/outdated.py`.

**Block 2 — Update, build, clean up.** → read `references/2-update-build.md` (plus `references/specfile-guidelines.md` for spec-section authoring rules, and `references/git-workflow.md` if the package is git/scmsync rather than a classic `.osc` checkout)
Bump the version / run the source service, rebase or drop patches, run spec-cleaner, build locally with `osc build` (read the rpmlint summary, run `%check`), and fix FTBFS from the pitfalls catalog. **Gate to leave this block: a clean local `osc build` *and* a green `source_validator`.**

**Block 3 — Submit to Factory and watch.** → read `references/3-submit-watch.md`
Show the diff, commit, file the `osc sr` (or a Gitea PR for git-workflow packages), then watch the submission. If a review declines or comments, evaluate it — trivial source/spec fixes loop straight back to **Block 2**, which re-gates before re-submitting. Scripts: `scripts/my-requests.sh`, `scripts/devel-of.sh`.

The three blocks form a **loop**: Block 3 feedback (a decline, a staging FTBFS, a reviewer comment) routes back into Block 2, which re-builds and re-gates before the next submit.

### Bundled scripts (`scripts/`)

Call these instead of hand-writing the osc-API / Repology incantations every time (they encode the exact queries that are easy to get subtly wrong — the `role='maintainer'` person match, the `roles=creator` request search, the Repology pagination + `srcname` intersection):

- `my-packages.sh [--project P] [--user U]` — packages where you are an **explicit package-level** maintainer (not project-inherited).
- `my-requests.sh [--state open|declined|all] [--user U]` — your submit requests, grouped/filtered by state (plain list).
- `sr-status.py [--state open|declined|all] [--limit N] [ID …]` — **pretty status table**: overall state, the full review chain (licensedigger / factory-auto / factory-staging / staging-project / opensuse-review-team, each badged), and human comments. The Block-3 watch view.
- `outdated.py [--names FILE]` — Repology "outdated in openSUSE Tumbleweed" ∩ your package set.
- `devel-of.sh <pkg> [target-project]` — the devel project registered for a package (`404` = not in the target / new package).
- `gpg-verify.sh <tarball> <keyring>` — verify a signed source tarball against a package keyring (handles the ASCII-armored-keyring trap).
- `build-summary.sh [repo-arch]` — the last `osc build`'s result, `%check`/ctest pass count, rpmlint badness summary + every E:/W: line, and the produced RPMs, in one `sudo`-wrapped invocation (the build log is root-owned).
- `cone-status.sh <project> [repo] [arch]` — per-package build-status table for a whole project (a dependency cone in a `home:` project) with a loopable exit code (`0` all green, `1` in flight/dirty, `2` settled failure). The watch view for the unattended/remote-build mode; encodes the stale-failure-while-rebuilding guard so it won't cry failure on a pending rebuild.

Each script prints usage with `--help` and defaults the OBS account to `osc whois` unless `--user` is given.

### Delegation playbooks (`agents/`)

Each block has an `agents/<block>.md` playbook (`1-triage`, `2-update-build`, `3-submit-watch`). These are **not** auto-registered Claude Code subagents — the harness only discovers spawnable agents under `~/.claude/agents/`. Instead the orchestrator **forks one as a subagent** when a block is large or benefits from an isolated context (e.g. "fork a subagent with the prompt in `agents/3-submit-watch.md` to watch SR 12345 and loop back if it's declined"). To promote them to first-class `subagent_type`s, copy the files into `~/.claude/agents/`.

## OBS vs IBS

There are **two separate build services**, and the workflows in this skill apply to one of them. Don't conflate them:

- **OBS** — `build.opensuse.org` / `api.opensuse.org`. Hosts `openSUSE:Factory`, `openSUSE:Factory:NonFree`, `openSUSE:Backports:*`, `openSUSE:Leap:*`, `devel:*`, `Publishing`, `home:*`, etc. This is the default what plain `osc` and the rest of this skill assume.
- **IBS** — `build.suse.de` / `api.suse.de` (SUSE-internal). Hosts `SUSE:SLE-*`, `SUSE:Devel:*`, internal SUSE products. Requires a separate `osc` configuration (e.g. `osc -A https://api.suse.de` or an `[ibs]` profile in `~/.config/osc/oscrc`) and SUSE-internal network access.

**Cross-instance gotcha:** `osc search` from OBS returns matches from both — `SUSE:SLE-15-SP*:Update` appears alongside `openSUSE:Backports:*` because OBS can read the cross-instance metadata. That visibility is **not** the same as actionability. From an OBS checkout you can only file SRs/MRs to OBS-hosted targets. A submission to `SUSE:SLE-*` requires re-running the entire workflow against IBS. When listing candidate maintenance-update targets to a user from an OBS context, include only `openSUSE:Backports:*:Update` / `openSUSE:Leap:*:Update`; never propose `SUSE:SLE-*:Update` as something you can act on. If the user explicitly wants an IBS submission, flag it up front: "I'd need to switch to IBS — confirm you have access."

## Core directive

**Every time you author, edit, clean, or review a spec file, follow the openSUSE packaging guidelines (`references/specfile-guidelines.md`) and the spec-cleaner rules (the "Reference: what spec-cleaner mechanically rewrites" section in `references/2-update-build.md`).** Apply them pre-emptively — do not write the deprecated form thinking spec-cleaner will fix it later. Concretely, on any non-trivial edit:

1. **Before editing**, scan the spec for which guideline + spec-cleaner rules apply to the section you're touching.
2. **While editing**, write the modern form directly — column-16 alignment, SPDX-modern licenses, `%{macro}` over bare paths, `%make_install` / `%make_build` / `%autosetup`, one-dep-per-line sorted, `pkgconfig(...)` over `*-devel`, `%patch -P N` over `%patchN`, etc.
3. **After editing, ALWAYS run spec-cleaner — HARD RULE, every cleanup, no exceptions.** Run `spec-cleaner --remove-groups --pkgconfig --perl --tex -o /tmp/cleaned.spec foo.spec && diff -u foo.spec /tmp/cleaned.spec`. Any non-empty diff means you missed a rule — fix the source so spec-cleaner produces no diff, then re-run until the diff is empty (a clean spec-cleaner pass is part of the definition of "cleanup done"; never commit a cleanup you haven't run spec-cleaner over). **Always pass `--remove-groups --pkgconfig --perl --tex`** (project policy): strip obsolete `Group:` tags and convert deps to their `pkgconfig(...)`/`perl(...)`/`tex(...)` provider forms. The only legitimate deviations from spec-cleaner's output are the documented semantic-correctness cases (e.g. `%{?with_foo:...}` hoisting, `pkgconfig()` over-expansion trimming, a `-devel` kept for a build *tool* with no `pkgconfig`) — and even then prefer a form that is *also* no-diff stable. See "Checking a spec file" in `references/2-update-build.md` for the full flag list.
4. **Then** run `osc service runall source_validator` as part of cleanup (not only before commit). It catches missing/orphaned sources, unparseable specs, bad license tags, and other source-tree issues that spec-cleaner doesn't check; treat any error as a blocker. Doing it during cleanup means you catch problems while you're still editing instead of at the commit gate.
5. **Then** check guideline items spec-cleaner cannot verify: SPDX license accuracy, presence of `%check`, shared-library subpackage naming, language-specific policy (Python flavours, Perl macro use, etc.), `.changes` entry quality.
6. **Always add a `.changes` entry** for any spec edit, in the same turn as the edit. This is non-optional — every change to a `.spec` must be accompanied by a matching entry in the sibling `<name>.changes` file. **One entry per session**: do not append a new top-of-file entry for each subsequent spec edit; instead, amend the existing session entry by adding a new bullet (and refreshing the timestamp). See "Adding a .changes entry" below for the exact mechanics. Skip the entry only if the user has explicitly said so, or if the spec edit is purely cosmetic (e.g. fixing a typo in a comment).

The order matters: spec-cleaner output is mechanically correct *style*; the wiki rules are *policy*; the `.changes` entry is the *audit trail*. All three must pass.

### Adding a .changes entry

The canonical command is `osc vc`, which opens an editor with a fresh template. Since that's interactive, when working from this skill **write the entry directly** to `<name>.changes` using the format below, derived from the format rules in `references/specfile-guidelines.md` ("Changelog").

Mechanics:

1. Get current UTC time in the changelog format:
   ```
   LC_ALL=C date -u "+%a %b %_d %T UTC %Y"
   ```
   (Force `LC_ALL=C` — the locale-default weekday/month names will mismatch the canonical format and reviewers will reject the entry.)
2. **Author line — HARD RULE: always the full `Full Name <email>` form** (e.g. `Jane Packager <jane@example.com>`), never a bare email. The header line is `<date> - Full Name <email>`. Use the packager's own name/email — the one already used in the file's existing entries, or known from session context. If a source service (`changesgenerate`) stamps the entry with just a bare email, rewrite that author line to the full `Full Name <email>` form before committing.
3. Prepend a new entry at the **top** of the file. Never edit existing entries (especially in official repos — only trivial typo / bug-reference fixes allowed). **Exception — an update still in-flight to Factory:** the top entry describing an update whose SR is still `new`/`review` (not yet *accepted* into Factory) has **not** reached the official repo yet, so when you address reviewer feedback or otherwise fix that same in-flight change, **amend that existing entry** (adjust its bullets) rather than stacking a separate new entry on top. The "never edit" rule protects entries already *accepted/released*; a devel-project commit that hasn't landed in Factory is still your working entry for that update. (Real case: a reviewer asked to drop a bogus `Provides:` on the in-flight bitcoin 31.0 SR — the fix folded into the existing 31.0 entry, no new entry.)
4. Bullets describe what *changed in the package* from a user/reviewer's perspective. Group related changes under one first-level `-` bullet with second-level `*` sub-bullets; don't pad with implementation detail.
5. Wrap at 67 columns. **First-level bullet `-`, second-level `*`, no third level** — this is mandated by the wiki: the `/usr/lib/build/changelog2spec` helper specifically recognizes these two symbols for auto-reindenting, and yast2-qt renders deeper levels badly. Every item is a bullet — never a bare prose paragraph.

Template:

```
-------------------------------------------------------------------
<Wed May 27 16:31:48 UTC 2026> - Full Name <you@example.com>

- Short one-line summary of what changed (≤67 cols):
  * second-level detail
  * second-level detail
- Another top-level change, if independent

```
(Note the blank line at the end, before the previous entry's separator.)

Pair edits with entries in the same turn: if the user asks you to "fix X in the spec", you should produce a `.spec` edit *and* a `.changes` edit before reporting the task done.

**One `.changes` entry per session.** When subsequent spec edits happen within the same session, do **not** prepend a fresh top-of-file entry for each — that produces ugly stacks of tiny entries with consecutive timestamps. Instead:

1. On the **first** spec edit of the session, prepend a new entry at the top of `<name>.changes` with the current timestamp and a first-level `-` bullet (or a header bullet with second-level `*` sub-items if multiple sub-points).
2. On **every subsequent** spec edit in the same session, **amend that same entry**:
   - Refresh the timestamp on the first line to the new current time (so the entry reflects when the work finished, not just when it started).
   - Add a new bullet describing the latest change. If the new change fits thematically under the existing top-level dash (e.g. another guideline-refresh tweak), nest it as an additional `*` under that dash; otherwise add a new top-level `-`.
3. If a previous turn in the same session already prepended a second entry that should have been an amendment, **merge them** — collapse into one entry under the later timestamp, preserving all bullets.

This produces a single coherent entry summarising the session's work rather than a chronological log of micro-edits. Version bumps remain a separate top-level bullet under that one entry — follow the "Version updates" pattern in `references/specfile-guidelines.md` ("Changelog") for the wording.

**`.changes` records net change, not the journey.** The bullet describes what a *consumer* of the package observes (different files installed, different runtime behaviour, different ABI, different deps), not what the packager did during the edit session. Omit bullets for edits with no consumer-visible delta:

- Reverted-to-status-quo changes — e.g. you tried `%make_build` without `-j1`, hit upstream's parallel-build race, restored `-j1`. The net behavioural change is zero; do not write "keep -j1" or "restore -j1" in `.changes`. The spec-internal comment explaining *why* `-j1` stays is the right place to record that learning, and is enough on its own.
- Pure spec comment additions / re-wordings that don't change build behaviour.
- Whitespace, alignment, or spec-cleaner-style rewrites that don't change the produced RPM.
- **`%files` hygiene that doesn't change the installed file set.** Expanding `%{_bindir}/*` into explicit binary names, or `%{_mandir}/man1/*.1%{?ext_man}` into individual manpages, *silences an rpmlint warning* but ships the exact same files in the exact same RPM. No `.changes` bullet. Same for adding `%dir`, fixing a `%doc` vs `%license` mismatch when both still install the file, or hardening a glob that wasn't actually catching extra files.
- Rpmlint-warning silencing where the produced RPM is unchanged.

The corollary: when you add an explanatory comment in the spec but the surrounding code is unchanged, that comment is the entire artefact — don't double-record it in `.changes`. Reviewers reading `.changes` care about user-visible deltas; an unchanged-behaviour-with-better-docs change clutters their signal.

When in doubt, ask: *if I diffed the previous build's RPM contents against this build's RPM contents, would anything differ?* If no — no bullet.

**But don't suppress the changelog entirely when you've done a round of spec cleanup.** The "omit" cases above are about not *padding* an entry with per-line implementation detail and not recording dead-end journeys — they are not a licence to commit a cleanup with an empty `.changes`. When you modernise/tidy a spec (spec-cleaner pass, macro conversions, dropping cruft, `%files` hygiene, etc.), add **one brief umbrella bullet** — e.g. `- Spec cleanup` with a couple of short sub-bullets, or a one-liner like `- Modernize spec file`. This is the norm reviewers expect; a commit that visibly changes the spec but carries no `.changes` line looks like an oversight. Keep it terse (don't enumerate whitespace), but do mention it. (Genuinely consumer-visible changes in the same session — version bump, dropped/added deps, a dropped `Provides`/`Obsoletes` — still get their own explicit bullets alongside the cleanup umbrella.)

**A new submit request must carry a `.changes` entry — this is effectively mandatory.** Any SR that *introduces a change* to the target (a version bump, a new package's initial packaging, a spec change) needs a matching `.changes` entry; reviewers and the Factory tooling expect every content-changing SR to be accompanied by a changelog bullet, and a new package's first SR needs an `- Initial package …` entry. The **only** real exception is a pure *resubmit of unchanged content* — e.g. re-filing an SR that was declined for a transient/infra reason with byte-identical sources — where there is genuinely nothing new to record. If you also did cleanup as part of such a resubmit, that cleanup still earns its brief umbrella bullet (per above), so in practice almost every SR you file should touch `.changes`.

## Fetching the wiki

The wiki blocks ordinary HTML scraping behind an Anubis challenge, but the MediaWiki API is unrestricted. Use:

```
curl -sL -A "Mozilla/5.0" \
  "https://en.opensuse.org/api.php?action=parse&page=PAGE_TITLE&format=json&prop=wikitext"
```

Spaces in titles become `_`. The JSON's `parse.wikitext.*` field is plain wikitext.
