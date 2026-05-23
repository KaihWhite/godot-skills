---
argument-hint: <scope: "full" (default) | path or area name>
---

# Godot Audit SOP

## Objective

Run a project-wide code-quality + doc-drift sweep using **parallel `godot-auditor` sub-agents** sharded by symbol ownership. Output is one merged audit report and a doc vault left in a consistent state.

The pipeline:

```
Phase 0: orient + audits-dir triage (with user)
Phase 1: build symbol catalog
Phase 2: partition + dispatch N parallel auditor shards
Phase 3: collect results (questions surface naturally; no orchestrator blocking)
Phase 4: merge findings + write single report
Phase 5: handoff
```

You MUST keep the heavy work (vault greps, code reads, doc lookups, drift fixes) inside the auditor sub-agents. Your orchestrator context stays focused on partitioning, merging, and report assembly.

## Foundational principle

**Violating the letter of the rules is violating the spirit of the rules.** "The user obviously meant `full`" is not consent to skip Phase 0's AskUserQuestion. "Just one more shard" is not the heuristic. "I'll write the report myself instead of merging" defeats the partitioning. If a phase boundary feels in the way, that's the signal to stop and tell the user, not to bypass it.

## Parameters

| Param | Form | Required | Default | Meaning |
|-------|------|----------|---------|---------|
| `$ARGUMENTS` | Free text — scope hint | No | `full` | `full` (project-wide), or a path / area name (e.g. `combat/`, `autoloads`) to narrow the sweep. |

## When to use

- Milestone-close sweeps ("audit before M2 ships").
- On-demand cross-task drift / quality checks.
- Periodic codebase health audits.

## When NOT to use

- Per-task drift checks → use `Skill → atomic-docs` instead. You MUST decline and redirect.
- Single-file lint or PR-specific review → not the auditor's scope.
- Non-Godot work → out of scope.

## Phase 0 — Orient + audits-directory triage (MUST)

You MUST, in order:

1. Read the project's `CLAUDE.md` to learn vault path + key paths.
2. Probe the filesystem for an existing audits directory in this order:
   - `<vault>/audits/`
   - `<cwd>/.claude/audits/`
   - `<cwd>/audits/`
3. Inspect what each candidate (if any) contains: `_instructions.md`? Prior `audit-*.md` files? Empty?
4. **You MUST ask the user via `AskUserQuestion`** to confirm or choose the audits directory, even when probing finds a single candidate. Present the discovered options + an "Other / specify path" escape. Recommend the first existing candidate.

   The user's answer determines the chosen audits directory.

5. If the chosen directory does NOT yet exist, you MUST create it (`mkdir -p`) before Phase 4.

6. Determine the **template source** for the report (in priority order):

| State of chosen dir | Template source | Note for shards |
|---------------------|-----------------|-----------------|
| Contains `_instructions.md` | Use those instructions verbatim. | Pass `instructions_file` path to each shard. |
| Has prior `audit-*.md` (most recent) but no instructions | Use the most recent prior audit as template. | Pass `template_audit_path` to each shard. |
| Empty / new | Use the default template embedded in this SOP. | No template path needed. |

You MUST NOT skip the AskUserQuestion in step 4 even if a single audits dir is the obvious match — the user owns this decision.

You SHOULD record the chosen path + template source in your scratch context for use in Phases 2 and 4.

## Phase 1 — Build the symbol catalog (MUST)

You MUST construct, before sharding:

- `Grep` for `^class_name ` across `.gd` files → list of class names.
- Read `project.godot` autoload section → list of autoload globals.
- `Glob` `**/*.gd` (excluding `tests/smoke_*.gd`) and `**/*.tres` → file inventory + counts.

You MUST report the catalog size in Phase 5's handoff (gd files, tres files, class_names, autoloads).

If `$ARGUMENTS` is a path/area scope, you MUST filter the catalog to symbols and files under that scope before partitioning.

## Phase 2 — Partition + dispatch parallel shards (MUST)

### Shard count heuristic

You MUST pick the shard count from catalog size:

| Total symbols (class_names + autoloads) | Shards |
|-----------------------------------------|--------|
| ≤ 20 | 1 (no parallelism — just dispatch one auditor) |
| 21–50 | 2 |
| 51–100 | 4 |
| > 100 | 8 |

### Partitioning rule

You MUST partition by **symbol ownership**, not file count. Each shard receives a list of `class_name`s + autoloads it owns; the shard is responsible for code-quality of those symbols' files AND for vault drift fixes for those symbols.

This eliminates vault write races: every doc-vault note has exactly one shard responsible for any given symbol it mentions.

You SHOULD distribute symbols roughly evenly. Round-robin or alphabetical partitioning is fine.

### Dispatch

You MUST spawn shards in a single message containing N parallel `Agent` calls so they run concurrently:

```
Agent({
  description: "Audit shard <i>/<N>",
  subagent_type: "godot-auditor",
  prompt: "Run sharded audit. owned_symbols: [<list>]. audits_dir: <path>. <one of: instructions_file: <path> | template_audit_path: <path> | (omit for default template)>. Return findings JSON + drift count."
})
```

Each shard's prompt MUST include:

- `owned_symbols`: comma-separated list of `class_name`s + autoloads this shard owns.
- `audits_dir`: the chosen directory from Phase 0.
- One of: `instructions_file`, `template_audit_path`, or neither (default template).
- Expected return: a JSON block with `findings`, `drift_fixes_applied`, `patterns_observed`, `open_questions`.

You MUST NOT pre-build per-file sets for shards. Each shard discovers its owned files via `Grep` for its own `class_name` declarations.

## Phase 3 — Collect results (MUST)

Shards run silently to completion. They MUST NOT call `AskUserQuestion` in sharded mode — ambiguous drift fixes go into the shard's `open_questions` JSON field, which surfaces in the report's "Open questions for user" section. The user resolves them after reviewing the report (in a follow-up edit pass or a fresh `/godot-audit` after the answers settle).

Behavior:

- All shards run uninterrupted; the user is not prompted mid-sweep.
- You MUST wait for all shard `Agent` calls to return before Phase 4.
- If a shard fails (timeout, crash), you SHOULD note it in the report's "Open questions for user" section rather than aborting the whole audit.

This trades inline drift closure on ambiguous symbols for a clean uninterrupted sweep. Unambiguous drift is still fixed inline by each shard.

## Phase 4 — Merge + write single report (MUST)

### Merge rules

You MUST:

1. **Concatenate `findings`** from all shards.
2. **Dedupe codebase-wide pattern violations**: if the same `pattern_violated` appears in 3+ files across multiple shards, collapse into a single entry under "Frequently violated" with a file list, instead of N separate findings.
3. **Sum `drift_fixes_applied`** counts.
4. **Union `patterns_observed`** ("Applied well" / "Frequently violated" lists).
5. **Concatenate `open_questions`**.

### Write the report

Path: `<chosen audits_dir>/audit-<YYYY-MM-DD>.md`.

Use the template source from Phase 0 (instructions file, prior audit, or the default schema below).

Default template:

```
---
created: <YYYY-MM-DD>
scope: <full | scope-hint>
codebase:
  gd_files: <N>
  tres_files: <M>
  class_names: <K>
  autoloads: <J>
shards: <N>
findings:
  critical: <count>
  important: <count>
  suggestions: <count>
drift_fixes_applied: <count>
last_updated: <YYYY-MM-DD>
---

# Audit — <YYYY-MM-DD>

## Summary

### Open questions (resolve these first)

> Ambiguous drift fixes that need a human call. Each lists the symbol, the doc note path, and the candidate mappings. Resolve, then optionally re-run `/godot-audit` so the resolutions land as inline fixes on the next sweep.

- <symbol> — `<doc note path>` — candidates: [<option A>] [<option B>]
- (none) ← include this line literally if no shard returned open questions, so the section is unambiguous

### Audit results

- Codebase: N `.gd`, M `.tres`, K `class_name`, J autoloads.
- Sweep: <N> parallel shards.
- Findings: critical X, important Y, suggestions Z.
- Drift fixes applied inline: P.

### Top issues

1. <one-line headline of the most critical finding>
2. ...

## Findings

### Critical
...

### Important
...

### Suggestions
...

## Patterns observed

- **Applied well**: ...
- **Frequently violated**: ...
```

You MUST NOT itemize drift fixes in the report (the count + git diff are the closure).

## Phase 5 — Handoff (MUST)

You MUST print:

```
Audit report: <path>
Sweep: <N> parallel shards.
Findings: critical X, important Y, suggestions Z.
Drift fixes applied inline: P notes touched.
Next step: review the report; if you accept, run Skill → atomic-docs to commit code+doc drift fixes + the report itself in one atomic commit.
```

Then stop. You MUST NOT auto-invoke `atomic-docs` or `git commit` — both belong to the user.

## Examples

### Example 1 — Full sweep, audits dir exists with instructions

```
/godot-audit
```

Phase 0: probes finds `<vault>/audits/` with `_instructions.md` + 3 prior audits → asks user "Use existing `<vault>/audits/`? [Yes (recommended) | Other path]" → user confirms → template source = instructions file.

Phase 1: catalog = 25 class_names + 6 autoloads + 80 .gd + 30 .tres.

Phase 2: 4 shards × ~8 symbols each → spawn 4 parallel auditors, each receiving `owned_symbols` + `audits_dir` + `instructions_file`.

Phase 3: shards run silently to completion. One shard finds an ambiguous rename and routes it into its `open_questions` JSON. No mid-sweep user prompts.

Phase 4: merge → write `<vault>/audits/audit-2026-05-07.md`.

Phase 5: print handoff naming `Skill → atomic-docs`.

### Example 2 — No audits dir found

```
/godot-audit
```

Phase 0: no audits dir found anywhere. AskUserQuestion: "No audits directory found. Create at: [`<vault>/audits/`] [`.claude/audits/`] [`audits/`] [Other]" → user picks `<vault>/audits/` → orchestrator `mkdir -p` → no template source available, default template will be used.

Continues normally.

### Example 3 — Scoped sweep, small project

```
/godot-audit combat/
```

Phase 1 filters catalog to combat-related symbols only → 8 symbols total → Phase 2 picks 1 shard (≤20 threshold) → dispatches a single auditor with the scoped `owned_symbols`. Effectively the same as a non-parallel auditor invocation, but routed through the SOP for consistent handoff.

### Example 4 — Out-of-scope invocation

```
/godot-audit my one-line typo fix
```

Phase 0 detects a per-task scope mismatch → STOP, redirect: "This is a per-task change. Use `Skill → atomic-docs` instead — the auditor SOP is for cross-task / project-wide sweeps."

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| Shard returns malformed JSON | Subagent didn't follow auditor SOP | Note the shard ID under "Open questions for user" in the report; merge what you can from the well-formed shards. |
| Two shards both report patching the same vault note | Partitioning bug — same symbol assigned to both shards | Investigate the partitioning logic; don't re-run the whole audit. The vault state itself is fine (`Edit` is idempotent for the same `old_string` / `new_string` pair, and the second shard's edit will simply error on the now-applied change). |
| One shard hangs while others completed | Subagent is stuck on a long sweep or a runaway lookup | Wait reasonable timeout; if still stuck, note as a failed shard and proceed with N-1 results. |
| Codebase has > 100 symbols and 8 shards still feels slow | Heuristic ceiling | Acceptable; the bottleneck is the per-symbol sweep work, not parallelism. Consider scoping to a subset for the next pass. |
| Two shards report contradictory pattern recommendations | Both consulted patterns skill, drew different conclusions | Surface BOTH recommendations under "Open questions for user"; don't auto-pick. |
| User says "stop" mid-sweep | Hard cancel | You cannot cancel running shards from the orchestrator. Wait for them to return naturally; report partial results. |

## Style

- You MUST keep your own commentary terse — the shards do the heavy lifting.
- You MUST NOT re-summarize a shard's findings in your own words; merge structurally and write the report.
- You MUST NOT spawn shards sequentially. Single message, N parallel `Agent` calls.
