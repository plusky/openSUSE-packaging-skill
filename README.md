# openSUSE-packaging skill

A Claude Code [skill](https://docs.claude.com/en/docs/claude-code/skills) for authoring,
updating, building, reviewing, and submitting openSUSE / SUSE RPM packages via OBS and the
Git packaging workflow (src.opensuse.org / Gitea).

## Layout

```
SKILL.md                     orchestrator — the three-block pipeline + cross-cutting rules
references/                  per-block + domain depth documents, loaded on demand —
                             see SKILL.md's block pointers for what to load when
scripts/                     reusable osc / Repology / bugzilla / Gitea / distro helpers —
                             see SKILL.md "Bundled scripts" for the catalog
agents/                      forkable delegation playbooks for the three blocks
```

## Install

Copy (or symlink) the repo contents to `~/.claude/skills/openSUSE-packaging/`. To make the
three block agents spawnable as `subagent_type`s, symlink them into `~/.claude/agents/`:

```sh
for a in triage:osc-triage update-build:osc-update-build submit-watch:osc-submit-watch; do
  ln -sfn "$PWD/agents/${a%%:*}.md" ~/.claude/agents/"${a##*:}.md"
done
```
