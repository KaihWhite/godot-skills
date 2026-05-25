---
argument-hint: <task ID or feature description> | <path to existing plan> | resume
---

# Godot Feature Workflow SOP

## Objective

Orchestrate a test-first pipeline for non-trivial Godot 4 / GDScript features, systems, and refactors. Each phase ends at an explicit user checkpoint — no auto-chaining, no surprise commits.

You (the main agent) do the planning yourself in Phase 1 — there is no separate planner sub-agent. This keeps the full planning context in your session, so asking the user a design question mid-plan is a normal inline `AskUserQuestion`, not a sub-agent restart that discards everything explored so far. To keep your context lean, you delegate the two heavy, mechanical jobs to sub-agents: Godot 4 doc verification (read-only `Explore`) and engine smokes (`godot-smoke-runner`). Implementation stays in a dedicated `godot-feature-implementer` sub-agent so the diff has a single owner.

The pipeline:

```
Phase 1:   YOU plan (orient → ask design questions inline → patterns skill
           → verify API claims via Explore sub-agents → write plan + failing smokes)
                                                 ↓
Phase 2:   (user reviews plan) ──────────────────┐
                                                 ↓
Phase 3:   godot-feature-implementer (one code pass per dispatch) ─┐
           orchestrator runs godot-smoke-runner, loops failures back │
                                                                     ├─→ user verification checkpoint
Phase 4:   (user verifies)                                         ─┘
                                       ↓
Phase 5:   Skill → atomic-docs (drift grep + atomic commit pass)
```

API doc verification happens during your planning (Phase 1) via read-only `Explore` sub-agents that return conclusions only — it is not a separate orchestrator phase.

## Foundational principle

**Violating the letter of the rules is violating the spirit of the rules.** "The user obviously meant to approve" is not approval. "It's just a small inline edit" is not Phase 3 compliance. "Skipping planning is fine — the task is obvious" means the SOP doesn't fit; exit instead of substituting judgment for a phase. If a phase boundary feels in the way, that's the signal to stop and tell the user, not to bypass it.

## Parameters

| Param | Form | Meaning |
|-------|------|---------|
| `$ARGUMENTS` | Free text — task ID, feature description, plan path, or the literal word `resume` | Routes the SOP to the correct entry phase (see Phase 0). |

Accepted forms:

- **Task ID / description** — e.g. `TASK-F62 raid multipliers` or `add per-skeleton wander toggle`. Starts at Phase 1.
- **Plan path** — e.g. `.claude/plans/wander-toggle-2026-05-06.md` (absolute or relative). Skips Phase 1, starts at Phase 3.
- **`resume`** — Reads the most recent SOP-progress block (see Progress Tracking) and re-enters at the recorded phase.
- **Empty** — You MUST ask the user one clarifying question to determine the task before proceeding. Do not guess.

## When to use

- Multi-file features, new systems, refactors touching signal flow, scene composition, autoloads, or persistence.
- Behavior changes worth pinning with a smoke test.
- Anything with design ambiguities the user has not already resolved in the prompt.

## When NOT to use

- Typo / magic-number / single-line fix → edit inline; SHOULD NOT invoke this SOP.
- Pure Q&A or exploration sessions that will not touch the tree → MUST NOT invoke.
- Non-Godot work (Python, JS, infrastructure, docs-only) → MUST NOT invoke.

If the user invokes this SOP for an out-of-scope task, you MUST stop at Phase 0 and report the mismatch instead of proceeding.

## Phase 0 — Triage and progress block (MUST)

You MUST perform these steps in order before doing any planning:

1. You MUST classify `$ARGUMENTS` into one of the accepted forms above.
2. You MUST verify the work matches the "When to use" criteria. If it does not, STOP and report to the user.
3. You MUST create a progress block in your next user-visible message using this exact template, so the user (and any resuming session) can see state at a glance:

   ```
   ## SOP progress — godot-feature-workflow

   - Task: <one-line description>
   - Entry phase: <1 | 3 | 5>
   - Plan path: <path or "(pending — Phase 1 will create)">
   - Smoke tests: <paths or "(pending)">
   - Current phase: <number — name>
   - Inquiry rounds: <count, default 0>
   - Doc verification: <verified via Explore (N claims) | n/a — no engine API surface>
   - Last checkpoint: <ISO date or "—">
   - Notes: <free-form, e.g. "user requested edge case X">
   ```

4. You SHOULD also create a TaskCreate entry per remaining phase (1, 3, 5 — checkpoints 2 and 4 belong to the user, not you), and mark them `in_progress` / `completed` as you advance. This is the canonical resumption signal.
5. You MUST NOT skip ahead to a later phase than the one Phase 0 selects, even if the user is impatient — re-route via Phase 0 if scope changes.

## Phase 1 — Planning (MUST when entry phase = 1)

You plan the feature yourself, in this session. The output is a plan file plus failing smoke tests. You MUST NOT touch implementation code or run the engine in this phase — that is Phase 3's job. Work the steps in order.

Because you are at main-agent depth, `AskUserQuestion` is reliable here: when you hit a genuine design ambiguity, ask the user directly and keep going with the answer in hand. There is no inquiry handoff and no restart — the whole point of planning in-session is that a question costs you a roundtrip, not your accumulated context.

### Step 1 — Orient (MUST)

The project docs are the source of truth for design intent, conventions, and architecture — you plan *against* them, not just alongside them. Read to absorb what the project has already decided, not to tick a box: a convention you skim past here becomes a wrong assumption baked into the plan, and the patterns skill (Step 3) and Godot docs (Step 4) confirm the *generic* answer, never the project-specific one. You MUST read, in this order:

1. The project's `CLAUDE.md` (root) — points to design docs, vault paths, implementation plan, active deviations file.
2. The design scratchpad if one exists (e.g. `<vault>/design/Thoughts.md`). This is **read-only**.
3. The relevant feature / component note(s) named in CLAUDE.md or implied by the task.
4. The implementation plan entry for the named task.

You SHOULD NOT speculatively read the entire source tree — only files the task names or that the design notes flag as touched.

Reconcile the task against what you read. Where the request conflicts with a documented convention or an established design direction, that conflict is a Step 2 question — surface it; do not silently resolve it in the plan's favor or the doc's.

### Step 2 — Resolve design questions inline (MUST)

You MUST identify 2-4 genuine ambiguities. Decisions to ask about typically include: mechanical timing, threshold values, UI placement, persistence boundaries, error behavior, schema boundaries, a conflict between the request and a documented convention — anything the design doc deliberately defers or where you can name 2+ reasonable answers.

For any ambiguity NOT already resolved in `$ARGUMENTS` or earlier in the conversation, you MUST ask the user via `AskUserQuestion` — neutral options, honest tradeoffs, one option labeled "(Recommended)" only when there is strong reason. Ask before drafting the plan; bundle Step 6 edge-case prompts into the same roundtrip so one set of questions resolves both (see Step 6). Increment `Inquiry rounds` in the progress block after each roundtrip.

You MUST verify each question is genuinely open BEFORE asking. Sanity check: can you name 2+ reasonable answers without strain? If you find yourself constructing options to justify a preconceived constraint, the constraint IS the answer — lock it and document it in the plan body rather than asking. Manufactured questions (false constraints framed as "must resolve" choices) waste the user's time and signal over-engineering. Example that surfaced as a false constraint in a past run: "4→3 archetype mismatch must resolve" (it didn't — schemas can have different archetype counts).

You MUST NOT lock a user-decidable decision silently. If you catch yourself rationalizing "the user probably meant X" or "the prompt strongly hinted at Y so I'll lock it" on a choice with 2+ reasonable answers, that's an `AskUserQuestion`, not a lock. Decisions you do lock by your own inference (rather than a user answer) MUST be surfaced at the Phase 2 review as "inferred, not confirmed" so the user can override.

### Step 3 — Consult patterns skill (MUST)

You MUST invoke `Skill → godot-gdscript-patterns` BEFORE drafting the plan, not at exit. From the skill output, identify which patterns apply (state machine, signals, scene composition, resources, object pool, etc.) and which you considered then rejected. Both lists go into the plan.

### Step 4 — API verification via Explore sub-agents (MUST when applicable)

You MUST list every Godot 4 class / signal / property / behavior the plan relies on. For each one you don't already know with cited in-codebase confidence, you MUST verify it against the official docs by dispatching a read-only `Explore` sub-agent — never by reading whole doc pages into your own context, and never by running the engine.

Batch independent claims into parallel dispatches in a single message:

```
Agent({
  description: "Verify <plan slug> API claims",
  subagent_type: "Explore",
  model: "sonnet",
  prompt: "Verify these Godot 4 API / behavior claims against the official docs. The godot-docs MCP tools are deferred — first run ToolSearch(\"select:mcp__godot-docs__get_documentation_tree,mcp__godot-docs__get_documentation_file\") to load them, then use get_documentation_tree to locate the right page and get_documentation_file to read it. For each claim, report confirmed / contradicted / not-found WITH the doc reference (file path + section):\n1. <claim>\n2. <claim>\n...\nProject context lives in CLAUDE.md. Report conclusions only — do not dump doc excerpts."
})
```

Dispatch discipline (keeps doc pages out of your context, returns trustworthy answers):

- Use `model: "sonnet"` — doc verification is mechanical extraction, so Sonnet is fast and sufficient; without the override the Explore agent inherits your model (e.g. Opus), wasting capability on a retrieval task.
- Parallel by default — 2+ independent claims go in a single message, not serial roundtrips.
- Name the likely doc path when you know it (e.g. `classes/class_characterbody2d.md`); let the Explore agent fall back to `get_documentation_tree` when you don't.
- Demand conclusions, not excerpts — `confirmed / contradicted / not-found` plus a one-line doc reference. If an agent returns a doc dump, re-dispatch with a tighter cap rather than accepting it.
- If a finding points at a second class worth checking, dispatch a follow-up wave rather than reasoning from a half-answer.
- If a claim comes back `contradicted`, the design rests on a false premise — revise the plan (and re-open a Step 2 question if the correction is user-decidable) rather than papering over it.

Self-confidence is the same trap as silent locking: bias toward verifying. A claim you confirm against the page costs one Explore dispatch; a wrong assumption buried in prose costs a re-plan. `known` claims backed by in-codebase evidence (specific function references, fallback chains, prior usage) do NOT need a dispatch — but you MUST cite that evidence in the plan. "Everything was in scope" without citations is not evidence; verify it.

In the plan's `API references consulted` section, record each verified item: the class / signal / property, the doc path the Explore agent read (or the in-codebase citation for a `known` claim), and the fact confirmed. If the plan touches no Godot 4 API surface (e.g. a pure refactor of project-local code), write "(none — no engine API surface)" and set `Doc verification: n/a — no engine API surface` in the progress block.

### Step 5 — Test design (MUST)

The default project convention is a smoke harness:

- `tests/smoke_<feature>.tscn` — root Node with a script attached. You MUST omit `uid="..."` from the `[gd_scene format=3]` header (Godot regenerates on first scan; hand-authored UIDs leave parent `ext_resource` references stale).
- `tests/smoke_<feature>.gd` — script with `_test_*` functions called via `_safe_run("name", _test_method)` from `_ready`, then `get_tree().quit()`. Each `_test_*` uses `assert(cond, message)`.

If the project does NOT follow this pattern (no `tests/` dir, different framework), you MUST ask the user via `AskUserQuestion` rather than assuming.

You MUST draft the assertion list — what observable end state proves the feature works.

### Step 6 — Edge-case integration (MUST)

Anticipate edge-case categories (boundary values, save/load roundtrip, signal ordering, multi-frame timing, error states, race conditions, large/empty inputs) at Step 2 inquiry time, so a single `AskUserQuestion` roundtrip resolves both design questions and edges. With the answers in hand, append confirmed edges to the test list. If a Step-5-emergent edge truly needs user input that Step 2 missed, you MAY ask one more roundtrip — but minimize this; one roundtrip is the goal.

### Step 7 — Write deliverables (MUST)

#### A. Test files

You MUST create:

- `tests/smoke_<feature>.tscn` — root Node with the script attached, no hand-authored `uid`.
- `tests/smoke_<feature>.gd` — script with `_test_*` functions. Tests MUST fail until Phase 3 codes the feature. That is the TDD red state.

#### B. Plan file

Path: `<cwd>/.claude/plans/<slug>-<YYYY-MM-DD>.md`. If `<cwd>/.claude/` doesn't exist, fall back to `<cwd>/plans/`, then `~/.claude/plans/`. Slug: lowercase-hyphenated, task ID + 1-3 keywords (e.g. `task-f46-wander-toggle-2026-05-06.md`).

**Archive policy (MUST when re-writing a plan for the same task).** When you produce v2+ of a plan (a prior version exists at the active path), you MUST archive the prior version to `<cwd>/.claude/plans/archive/<slug>-<prior-date>-v<N>.md` before writing the new plan. Use today's date in the new filename if the prior version was written on a different day. NEVER overwrite an active plan in place — the archive preserves history for the user and for resumability.

Plan template:

```
# Plan: <task>

**Created:** <date>
**Scope:** <task ID + one-line summary>

## Goal
<concise outcome>

## Design decisions
- <decision> — <reason from user's AskUserQuestion answer or design doc>

## Pattern alignment (godot-gdscript-patterns)
- Apply: <pattern names + where>
- Skip: <patterns considered + why>

## API references consulted (via Explore + godot-docs MCP)
- <class/signal/property> — <doc path read, or in-codebase citation for a `known` claim> — <fact confirmed>

## Files to touch
- `<path>` — <new vs edit; what changes>

## Test specification
- Smoke harness: `tests/smoke_<feature>.tscn` + `.gd` (failing versions already written)
- Test cases:
  - `_test_<X>()` — asserts <end state>
- Edge cases (user-confirmed):
  - <edge> — covered by `_test_<Y>()`

## Implementation sequencing
<order; deferrals via call_deferred or signals; new class_name → launch_editor refresh required>

## Risks + mitigations
- <risk> — detect via <signal/log/assertion>; mitigate by <approach>

## Out of scope
<explicit non-goals to prevent drift>

## Handoff
> Use the `godot-feature-implementer` agent with the plan at <plan path>.
```

### Critical Godot rules to encode in the plan (MUST)

These apply to the test files you write and you MUST reflect them in the plan so the implementer follows them:

- **Skill is source of truth.** `godot-gdscript-patterns` wins over training intuition.
- **Don't shadow GDScript built-ins** as locals: `seed`, `name` (on Node subclasses), `range`, `pi`, `tau`. Default-rename to `entry_seed`, `entry_name`, `attack_range`. Symptom is cryptic `Cannot find member "..." in base "Callable"` parse errors.
- **`_ready` fires bottom-up.** Child `_ready` runs before parent `@onready` resolves. If a child's `_ready` calls into a parent method that derefs `@onready`, plan `call_deferred()` and add an inline comment naming the failure mode.
- **CanvasLayer for overlays.** HUDs/modals/toasts in a scene that activates a `Camera2D` MUST root on `CanvasLayer` (or be wrapped in one) — layer-0 Controls drift with `canvas_transform`.
- **New `class_name` → `launch_editor` refresh** required by the implementer before `run_project` resolves the type. Note in the plan if applicable.
- **Don't hand-author `.tscn` UIDs** for new files. Godot regenerates on first scan; parent `ext_resource` references go stale.
- **Debug grants need `if OS.is_debug_build():`** for any keyboard handler that mutates inventory / currency / XP / progression — guard so they never ship.
- **Action-coupled warnings at the action site only**, not on review/inspection screens.
- **`assert()` halts the smoke harness** — first failure stops every later test in the same file. Order tests so foundational asserts come first.

### Step 8 — Hand off to the user (MUST)

When the plan file and failing test files are written, you MUST surface to the user, in one message:

- The plan path and the test file paths.
- The `API references consulted` section (so the user sees what was verified and against which doc pages).
- Any design decision you locked by your own inference rather than a user answer, flagged "inferred, not confirmed."

Then update the progress block (`Plan path`, `Smoke tests`, `Doc verification`, `Current phase: 2`) and advance to Phase 2. You MUST NOT continue into implementation.

You SHOULD NOT re-plan from scratch more than twice in one session. If the user keeps adjusting, prefer a hand-edit to the plan file.

## Phase 2 — User review checkpoint (MUST wait)

You MUST stop and wait for an explicit user signal. Do not start Phase 3 on momentum.

User signals and your response:

| Signal | Examples | Action |
|--------|----------|--------|
| Approval | "go", "implement this", "looks good", "ship it", points you at the plan with an action verb | Advance to Phase 3 without re-asking permission. |
| Adjustments | "change X", "rethink Y" | Re-work the plan (re-run the relevant Phase 1 steps) OR hand-edit the plan in place, then re-checkpoint. |
| Rejection | "no", "stop", "different approach" | STOP. You MUST NOT auto-pivot to a different design. Return to the user. |

Ambiguous signals (e.g. user just asks a question about the plan) → answer the question, do not advance.

## Phase 3 — Implementation (MUST when entry phase ≤ 3)

The implementer codes ONE pass per dispatch and does NOT run the engine. **You own the code → smoke → fix loop:** dispatch the implementer, run `godot-smoke-runner` on the params it returns, hand any failure back to the implementer, repeat until the smoke passes.

1. Dispatch the implementer with the plan path:

   ```
   Agent({
     description: "Implement <plan slug>",
     subagent_type: "godot-feature-implementer",
     prompt: "Implement using the plan at <plan path>."
   })
   ```

2. The implementer returns one of two statuses:
   - `Status: smoke-ready` — it coded a pass; the handoff carries the smoke params (`smoke_scene`, `log_path`, `new_class_name`), any additional smokes, files changed, and deviations.
   - `Status: escalation` — a test-boundary / stale-assert / plan / scope concern. You MUST relay it verbatim and wait for user direction (see escalation rule below). Do NOT advance or auto-resolve.

3. On `smoke-ready`, run each reported smoke via `godot-smoke-runner` — one spawn per scene:

   ```
   Agent({
     description: "Run <smoke slug>",
     subagent_type: "godot-smoke-runner",
     prompt: "Run <smoke_scene>. Log: <log_path>. new_class_name: <true|false>."
   })
   ```

   You MUST NOT run the engine yourself (`mcp__godot__run_project` / `get_debug_output` / `stop_project`) — the runner absorbs the verbose engine output so your context stays lean across iterations. The runner returns a JSON block with `status` (`pass` / `fail` / `compilation-error`), a `failures` list, and a 1-line `summary`.

4. Act on the runner's result:
   - `pass` (all reported smokes green) → surface the implementer's report + the green smoke summaries verbatim, update the progress block (`Last checkpoint: <date>`), advance to Phase 4.
   - `fail` / `compilation-error` → re-dispatch the implementer with the JSON embedded so it classifies and fixes:

     ```
     Agent({
       description: "Fix <plan slug> smoke failure",
       subagent_type: "godot-feature-implementer",
       prompt: "Continue the plan at <plan path>. The smoke <scene> failed — classify per your Step 7 and fix, or escalate (Mode B) if it's a test-boundary / stale-assert concern:\n<runner JSON>"
     })
     ```

     If the failure is `compilation-error: Could not find type "X"` for a `class_name` the implementer just wrote, set `new_class_name: true` on the next runner spawn.

5. Loop steps 3–4. Cap at ~5 code→smoke iterations. If the smoke still isn't green at the cap, STOP and escalate to the user with the latest failure rather than looping further. You MAY resume the loop once the user gives explicit guidance.

You MUST NOT edit project source files directly during this phase — let the implementer own the diff. Your role in the loop is to run the runner and courier its JSON back, not to patch.

**Escalation rule.** When the implementer returns `Status: escalation` (a fixture-fragile test, a mis-framed assertion, a harness bug, a stale cross-feature assert, a plan/sequencing doubt), you MUST relay the concern verbatim and wait for user direction. You MUST NOT auto-resolve by inline-editing, by directing the implementer to patch a plan-authored test, or by inline-fixing a stale assert yourself.

## Phase 4 — User verification checkpoint (MUST wait)

You MUST wait for the user to review the diff and / or playtest. Signals:

| Signal | Action |
|--------|--------|
| Approval | Advance to Phase 5. |
| Tweaks | Default: fold back into Phase 3 (re-invoke implementer). MAY inline-edit ONLY if ALL of the following hold: (a) ≤3 lines changed, (b) typo / comment / whitespace only — no logic or string-literal change, (c) no new identifier (no new function, class_name, signal, or exported var), (d) no signal / scene / autoload / persistence / Resource-export touch. If any condition is unclear, re-invoke. |
| Concerns about scope or correctness | STOP. Raise to user. |

You MUST NOT auto-advance to atomic-docs.

## Phase 5 — Atomic-docs commit pass (MUST when user signs off)

You MUST invoke the skill rather than paraphrasing its discipline:

```
Skill → atomic-docs
```

The skill walks the drift-prevention grep, present-tense rewrite of touched feature/component notes, `last_updated` restamp on every modified note, atomic stage of code + docs, and drafts a commit message.

You MUST wait for explicit user approval before running `git commit`. Staging is part of the skill; the commit itself is not.

After the commit, you MUST mark the SOP-progress block `Current phase: complete` and clear the matching TaskCreate entries.

## Progress tracking

The progress block from Phase 0 is the single source of truth for SOP state. You MUST update it whenever:

- A phase completes (advance `Current phase`, restamp `Last checkpoint`).
- Planning produces paths (fill `Plan path` and `Smoke tests`).
- The user requests a scope change recorded in `Notes`.

You SHOULD keep the block at the top of your message when one is present, so a `resume` invocation can find it without scrolling.

## Resumability

When `$ARGUMENTS == "resume"`:

1. You MUST search recent transcript / scratch state for the most recent `## SOP progress — godot-feature-workflow` block.
2. If found, you MUST acknowledge the recovered state to the user before doing anything else, then re-enter at `Current phase`.
3. If not found, you MUST ask the user which task to resume (do not guess from `git status` alone).
4. If Phase 3 was interrupted mid-agent (e.g. implementer crashed), you SHOULD re-dispatch that agent with the same parameters rather than skipping forward.

## What this SOP does NOT do

- Run the Godot engine directly (the orchestrator dispatches `godot-smoke-runner`, which absorbs the verbose engine output; the orchestrator never calls `mcp__godot__run_project` itself).
- Read whole doc pages into the main context — Phase 1 API verification is delegated to read-only `Explore` sub-agents that return conclusions only.
- Auto-chain phases past user checkpoints.
- Auto-commit (atomic-docs stages; user approves).

## Examples

### Example 1 — Fresh feature

```
/godot-feature-workflow TASK-F62 raid multipliers
```

Expected flow: Phase 0 classifies as task description → progress block written → Phase 1: you orient, ask design + edge questions via `AskUserQuestion`, consult the patterns skill, dispatch Explore sub-agents to verify the API claims, write the plan + failing smokes → Phase 2 checkpoint → user approves → Phase 3 dispatches implementer → checkpoint → user verifies → Phase 5 atomic-docs.

### Example 2 — Plan already exists

```
/godot-feature-workflow .claude/plans/wander-toggle-2026-05-06.md
```

Expected flow: Phase 0 classifies as plan path → progress block records path, entry phase = 3 → skip Phase 1 → Phase 3 dispatches implementer.

### Example 3 — Resume after a session crash

```
/godot-feature-workflow resume
```

Expected flow: Phase 0 reads the last progress block → reports recovered state ("resuming Phase 3 for TASK-F62; smoke tests at tests/smoke_raid_multipliers.tscn") → re-dispatches the implementer.

### Example 4 — Out-of-scope invocation

```
/godot-feature-workflow fix the typo in the credits screen
```

Expected response: Phase 0 detects this matches "When NOT to use" → reports the mismatch → suggests an inline edit. No agents dispatched.

## Red flags — STOP and re-route through Phase 0

These thoughts mean you're about to rationalize the SOP away:

| Thought | Reality |
|---------|---------|
| "User said go earlier; that covers this phase too." | Approval is per-checkpoint. Phase 2 ≠ Phase 4. Re-confirm. |
| "This tweak is small enough to inline-edit." | Phase 4 caps inline edits at ≤3 lines, typo / comment / whitespace only, no new identifier, no signal / scene / autoload / persistence / Resource-export touch. If any cap is unclear, re-invoke implementer. |
| "Task is obvious — skip planning." | If the SOP doesn't fit, exit and tell the user. Don't silently downgrade to a one-liner edit. |
| "I'll just commit; atomic-docs would be a no-op." | The skill decides if it's a no-op, not you. Run it, then wait for explicit user approval before `git commit`. |
| "Smoke is green-ish; close enough." | If a `_test_*` isn't asserting green, iterate or escalate. No partial passes. |
| "User got impatient — I'll skip ahead." | Phase 0 selects the entry phase. Impatience isn't a re-route signal; only scope changes are. |
| "I read the SOP earlier; I remember the rules." | Skills evolve. Re-load the skill before acting; don't recall from memory. |
| "I can answer the design questions myself from conversation context." | If a choice has 2+ reasonable answers, the user decides. Use `AskUserQuestion` at Step 2; don't substitute your judgment for theirs. |
| "The prompt strongly hinted at X, so I'll lock it in the plan." | A user-decidable choice is a Step 2 question, not a silent lock. If you must infer, flag it "inferred, not confirmed" at Phase 2. |
| "I'll just read the doc page myself to verify this API." | Phase 1 verification is delegated to Explore sub-agents — conclusions only, doc pages stay out of your context. Dispatch, don't read whole pages. |

If any of these thoughts appear, STOP, return to the user, and re-state the current phase.

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| You asked no design questions | Task is well-specified, or you skipped Step 2 | Re-check Step 2: can you name 2+ reasonable answers to any open decision? If the plan is thin on edge cases, ask before writing it. |
| An Explore agent returns a huge doc dump | Prompt didn't cap the response | Re-dispatch with "report conclusions only — confirmed / contradicted / not-found + one-line doc reference, no excerpts". |
| Smoke passes but user playtest disagrees | Smoke covers the wrong assertion | Have the implementer add a failing smoke test that captures the user's case (Phase 3 fold-back), then re-run the loop. |
| `Skill → atomic-docs` reports drift in unrelated notes | Earlier work left stale references | Resolve those before committing — do not bypass the drift grep. |
| `resume` cannot find a progress block | Block was scrubbed from context or never written | Ask the user which task to resume; do not infer from `git status`. |
| Phase 1 ↔ Phase 3 ping-pong | Plan keeps changing under implementation | Stop. Raise to user — design is not converged; SOP is not the right tool for an exploratory phase. |
| User says "go" mid-Phase 1 (before the plan is written) | Premature approval | Acknowledge but do not advance; the plan file doesn't exist yet. |

## Style

- You MUST keep your own commentary terse — sub-agents do the heavy lifting in Phases 3+; in Phase 1 you plan, in the gaps you relay, checkpoint, and update the progress block.
- You SHOULD NOT re-summarize a sub-agent's output; surface it verbatim instead.
- You MUST NOT silently downgrade the SOP (e.g. skip planning because "it's a small feature") — if the SOP doesn't fit, exit and tell the user.
