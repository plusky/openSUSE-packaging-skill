# openSUSE-packaging skill

An agent skill for authoring, updating, building, reviewing, and submitting openSUSE / SUSE
RPM packages via OBS and the Git packaging workflow (src.opensuse.org / Gitea).

It works with **any coding agent that can run shell commands** — the skill is plain markdown
plus POSIX-shell/Python helper scripts. It ships with native packaging for Claude Code
(`SKILL.md` frontmatter + delegation playbooks), and the same files read as ordinary
instruction documents from grok CLI, opencode, codex, gemini-cli, or any other harness.

## Layout

```
SKILL.md                     entry point — the three-block pipeline + cross-cutting rules
references/                  per-block + domain depth documents, loaded on demand —
                             see SKILL.md's block pointers for what to load when
scripts/                     reusable osc / Repology / bugzilla / Gitea / distro helpers —
                             see SKILL.md "Bundled scripts" for the catalog
agents/                      delegation playbooks (role prompts) for the three blocks
```

The YAML frontmatter at the top of `SKILL.md` and `agents/*.md` is metadata for harnesses
with native skill/sub-agent support (e.g. Claude Code); everywhere else it is harmless
plain text — no other file depends on it.

## Install

### Any agent (grok CLI, opencode, codex, gemini-cli, …)

Clone the repo anywhere and point your agent at `SKILL.md` as context — reference it from
your harness's rules/context file (`AGENTS.md`, `.rules`, a system prompt, an
`@`-include, …) or just tell the agent to read it at session start. `SKILL.md` tells the
agent which `references/*.md` to load per work block (don't preload them all) and catalogs
the `scripts/` helpers, which need only `bash`, `python3`, `osc`, and `curl`.

The `agents/*.md` playbooks are role prompts: if your harness supports delegating to
sub-agents/sub-tasks, use one as the sub-agent's instructions; otherwise run the playbook
inline in the main session or paste it as a standalone session prompt.

### Claude Code

Copy (or symlink) the repo contents to `~/.claude/skills/openSUSE-packaging/`. To make the
three block agents spawnable as `subagent_type`s, symlink them into `~/.claude/agents/`:

```sh
for a in triage:osc-triage update-build:osc-update-build submit-watch:osc-submit-watch; do
  ln -sfn "$PWD/agents/${a%%:*}.md" ~/.claude/agents/"${a##*:}.md"
done
```
