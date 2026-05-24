# godot-skills

A bundle of Claude Code skills, slash commands, and sub-agents for working on Godot 4 / GDScript projects. The directory layout mirrors `~/.claude/` so it can be dropped back in as-is.

## Layout

```
godot-skills/
├── skills/
│   └── godot-gdscript-patterns/
│       ├── SKILL.md
│       └── references/advanced-patterns.md
├── commands/
│   ├── godot-audit.md
│   └── godot-feature-workflow.md
└── agents/
    ├── godot-auditor.md
    ├── godot-feature-implementer.md
    ├── godot-feature-planner.md
    └── godot-smoke-runner.md
```

## Contents

### Skill

| Name | When it fires |
| --- | --- |
| `godot-gdscript-patterns` | Writing, reviewing, or designing GDScript in Godot 4 — nodes/scenes/resources, signals, autoloads, state machines, component patterns, refactors, perf. Skipped for non-code work and feature orchestration. |

### Slash commands

| Command | Purpose |
| --- | --- |
| `/godot-feature-workflow <task \| plan path \| resume>` | Orchestrates a test-first agent pipeline (planner → optional doc re-check → user checkpoint → implementer, with the orchestrator owning the code→smoke→fix loop) for non-trivial features. Keeps heavy context inside sub-agents. |
| `/godot-audit <scope>` | Project-wide code-quality + doc-drift sweep using parallel `godot-auditor` sub-agents sharded by symbol ownership. Produces one merged report. |

### Agents

| Agent | Role |
| --- | --- |
| `godot-feature-planner` | Phase 1 of `/godot-feature-workflow`. Resolves design ambiguities, consults patterns, verifies its API claims against the docs (`godot-docs` MCP), writes failing smoke tests, exits with a plan file. |
| `godot-feature-implementer` | Phase 3 of `/godot-feature-workflow`. Codes one pass per dispatch against the plan; the orchestrator runs `godot-smoke-runner` and loops failures back until smoke tests are green. |
| `godot-smoke-runner` | Runs ONE smoke scene per invocation; returns a JSON failure summary. Absorbs verbose engine output so the caller's context stays lean. Dispatched by the orchestrator during Phase 3. |
| `godot-auditor` | Project-wide quality + doc-drift sweep for milestone-close. Walks every `class_name`, autoload, and public symbol. Not for per-task work. |

## Install

Copy each subdir into the matching location under `~/.claude/`:

```bash
cp -r skills/godot-gdscript-patterns ~/.claude/skills/
cp commands/*.md                     ~/.claude/commands/
cp agents/*.md                       ~/.claude/agents/
```

Or symlink the bundle's subdirs in if you want a single source of truth.

## Source

These files were copied from `~/.claude/` on 2026-05-22, last synced back on 2026-05-24. The originals under `~/.claude/` remain authoritative; sync changes here whenever they're edited.
