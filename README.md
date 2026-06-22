# openSUSE-packaging skill

A Claude Code [skill](https://docs.claude.com/en/docs/claude-code/skills) for authoring,
updating, building, reviewing, and submitting openSUSE / SUSE RPM packages via OBS and the
Git packaging workflow (src.opensuse.org / Gitea).

## Layout

```
SKILL.md                     orchestrator — the three-block pipeline + cross-cutting rules
references/
  1-triage.md                Block 1 — is a package out of date?
  2-update-build.md          Block 2 — update → build → clean up (+ FTBFS pitfalls)
  3-submit-watch.md          Block 3 — commit → submit → watch → loop back
  specfile-guidelines.md     per-section spec rules (consulted during Block 2)
  git-workflow.md            src.opensuse.org clone / fork / PR
  leap-slfo.md               routing Leap 16.x / SLFO / Backports submissions
  bugzilla-cve-triage.md     bug-driven entry: triage + close assigned (CVE) bugs
scripts/                     reusable osc / Repology / bugzilla / distro helpers
                             (my-packages, my-requests, sr-status, outdated, devel-of,
                             gpg-verify, build-summary, cone-status, leap-sync,
                             bug-scan, distro-survey)
agents/                      forkable delegation playbooks for the three blocks
```

## Install

Copy (or symlink) the repo contents to `~/.claude/skills/openSUSE-packaging/`. To make the
three block agents spawnable as `subagent_type`s, symlink them into `~/.claude/agents/`:

```sh
for a in 1-triage:osc-triage 2-update-build:osc-update-build 3-submit-watch:osc-submit-watch; do
  ln -sfn "$PWD/agents/${a%%:*}.md" ~/.claude/agents/"${a##*:}.md"
done
```
