# godot-skills

A bundle of Claude Code skills, slash commands, and sub-agents for working on Godot 4 / GDScript projects. The directory layout mirrors `~/.claude/` so it can be dropped back in as-is.

## Layout

```
godot-skills/
├── skills/
│   └── godot-gdscript-patterns/
│       ├── SKILL.md
│       ├── assets/
│       │   ├── smoke_harness.gd
│       │   └── run_smoke.sh
│       └── references/advanced-patterns.md
├── commands/
│   ├── godot-audit.md
│   └── godot-feature-workflow.md
└── agents/
    ├── godot-auditor.md
    ├── godot-feature-implementer.md
    ├── godot-feature-reviewer.md
    └── godot-smoke-runner.md
```

## Contents

### Skill

| Name | When it fires |
| --- | --- |
| `godot-gdscript-patterns` | Designing, planning, writing, testing, or reviewing GDScript in Godot 4, in any workflow — nodes/scenes/resources, signals, autoloads, state machines, component patterns, refactors, perf. Ships the canonical smoke harness (`assets/smoke_harness.gd` + `assets/run_smoke.sh`). Skipped for non-code work. |

### Slash commands

| Command | Purpose |
| --- | --- |
| `/godot-feature-workflow <task \| plan path \| resume>` | Orchestrates a test-first pipeline for non-trivial features: the main agent plans in-session (writing back its understanding, offering 2-3 approaches, asking design questions inline, verifying API claims via Explore sub-agents, then writing interface stubs + failing smokes, self-reviewing, and confirming red via the smoke runner) → user checkpoint → implementer, with the orchestrator owning the code→smoke→fix loop → independent review and one fix pass → user checkpoint. Delegates heavy doc + engine work to sub-agents. |
| `/godot-audit <scope>` | Project-wide code-quality + doc-drift sweep using parallel `godot-auditor` sub-agents sharded by symbol ownership. Produces one merged report. |

### Agents

| Agent | Role |
| --- | --- |
| `godot-feature-implementer` | Phase 3 of `/godot-feature-workflow`. Codes one pass per dispatch against the plan; the orchestrator runs `godot-smoke-runner` and loops failures back until smoke tests are green. |
| `godot-feature-reviewer` | Phase 3 of `/godot-feature-workflow`, once smokes are green. Read-only review of the changed files against the plan, the patterns skill and its Common Pitfalls, and the red-checked smoke hashes; returns must-fix / should-fix / note findings that the orchestrator routes to one implementer fix pass. |
| `godot-smoke-runner` | Runs ONE smoke scene per invocation; returns a JSON failure summary. Absorbs verbose engine output so the caller's context stays lean. Uses the Godot MCP when available, else `tools/run_smoke.sh`. Dispatched by any orchestrating session (e.g. `/godot-feature-workflow`'s Phase 1 red check and Phase 3 loop). |
| `godot-auditor` | Project-wide quality + doc-drift sweep for milestone-close. Walks every `class_name`, autoload, and public symbol. Not for per-task work. |

## Install

Copy each subdir into the matching location under `~/.claude/`:

```bash
cp -r skills/godot-gdscript-patterns ~/.claude/skills/
cp commands/*.md                     ~/.claude/commands/
cp agents/*.md                       ~/.claude/agents/
```

Or symlink the bundle's subdirs in if you want a single source of truth.

## Keeping in sync

`sync.sh` mirrors this repo against an installed copy so the two don't drift:

```bash
./sync.sh check   # report drift, exit non-zero if any (default)
./sync.sh diff    # show the actual differences
./sync.sh push    # repo  -> installed copy
./sync.sh pull    # installed copy -> repo
```

It only touches the files this bundle owns, so the shared `agents/` and
`commands/` directories keep their other contents. Deploy locations default to
`~/.claude` (and `~/.agents` for the skill); override with the `CLAUDE_DIR` and
`AGENTS_DIR` environment variables if yours differ.
