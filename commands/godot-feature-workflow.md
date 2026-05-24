---
argument-hint: <task ID or feature description> | <path to existing plan> | resume
---

# Godot Feature Workflow SOP

## Objective

Orchestrate a test-first agent pipeline for non-trivial Godot 4 / GDScript features, systems, and refactors. Each phase ends at an explicit user checkpoint — no auto-chaining, no surprise commits. The SOP keeps the heavy context (Godot 4 docs, project docs, smoke output) inside dispatched sub-agents so the main session stays lean.

The pipeline:

```
Phase 1:   godot-feature-planner ──────────────┐
           (verifies API claims via godot-docs) │
Phase 1.7: [optional, on request] orchestrator  │  independent re-check of the
           → Agent (Explore) re-verifies claims  │  planner's API claims
                                                 ├─→ user review checkpoint
Phase 2:   (user reviews plan)                 ─┘
                                                 ↓
Phase 3:   godot-feature-implementer (one code pass per dispatch) ─┐
           orchestrator runs godot-smoke-runner, loops failures back │
                                                                     ├─→ user verification checkpoint
Phase 4:   (user verifies)                                         ─┘
                                       ↓
Phase 5:   Skill → atomic-docs (drift grep + atomic commit pass)
```

The planner verifies its own API claims against the docs (via the `godot-docs` MCP tools) during planning, so doc verification is NOT a default orchestrator phase. Phase 1.7 is an optional, on-request independent re-check the orchestrator offers at the Phase 2 handoff — useful when a claim is load-bearing or surprising, skipped otherwise.

## Foundational principle

**Violating the letter of the rules is violating the spirit of the rules.** "The user obviously meant to approve" is not approval. "It's just a small inline edit" is not Phase 3 compliance. "Skipping the planner is fine — the task is obvious" means the SOP doesn't fit; exit instead of substituting judgment for a phase. If a phase boundary feels in the way, that's the signal to stop and tell the user, not to bypass it.

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

You MUST perform these steps in order before invoking any agent:

1. You MUST classify `$ARGUMENTS` into one of the accepted forms above.
2. You MUST verify the work matches the "When to use" criteria. If it does not, STOP and report to the user.
3. You MUST create a progress block in your next user-visible message using this exact template, so the user (and any resuming session) can see state at a glance:

   ```
   ## SOP progress — godot-feature-workflow

   - Task: <one-line description>
   - Entry phase: <1 | 3 | 5>
   - Plan path: <path or "(pending — planner will create)">
   - Smoke tests: <paths or "(pending)">
   - Current phase: <number — name>
   - Inquiry rounds: <count, default 0>
   - Doc verification: <planner-verified | re-checked clean | re-checked, N fixed | re-planned | n/a>
   - Last checkpoint: <ISO date or "—">
   - Notes: <free-form, e.g. "user requested edge case X">
   ```

4. You SHOULD also create a TaskCreate entry per remaining phase (1, 3, 5 — checkpoints 2 and 4 belong to the user, not you), and mark them `in_progress` / `completed` as you advance. This is the canonical resumption signal.
5. You MUST NOT skip ahead to a later phase than the one Phase 0 selects, even if the user is impatient — re-route via Phase 0 if scope changes.

## Phase 1 — Planning (MUST when entry phase = 1)

You MUST dispatch the planner via the `Agent` tool exactly as follows:

```
Agent({
  description: "Plan <task ID or short name>",
  subagent_type: "godot-feature-planner",
  prompt: "Plan <task>. Project context lives in CLAUDE.md."
})
```

The planner returns one of two statuses: `questions-pending` (loop to Phase 1.5) or `plan-ready` (advance to Phase 2). When it returns `questions-pending`, you MUST surface the questions verbatim and route to Phase 1.5 — do not collapse, paraphrase, or guess at answers.

The planner verifies its own Godot 4 API claims against the docs via the `godot-docs` MCP tools and records them in the plan's `API references consulted` section. You do NOT repeat that verification by default; Phase 1.7 offers an optional independent re-check on request. During Phase 1 itself you MUST NOT front-run the planner with your own design or doc dives — let it produce the plan first.

When the planner returns, you MUST surface its handoff verbatim (plan path + test paths) and you MUST update the progress block with the new paths before proceeding.

If the planner's Mode B `Process compliance` block reports a non-empty `Edge cases inferred (not user-confirmed)` list, you MUST surface those entries to the user at Phase 2 review and prompt for confirm-or-override. Those are decisions the planner accepted from main-agent inferences in your dispatch prompt rather than user-confirmed inquiry answers — the user gets the final say at Phase 2. If you embed your own inferences in a re-dispatch prompt, mark them with `[inferred]` tags so the planner reports them; reserve `[user]` for verbatim Phase 1.5 picks.

You SHOULD NOT loop the planner more than twice in one session. If the user keeps adjusting, prefer a hand-edit to the plan file.

## Phase 1.5 — Inquiry checkpoint (MUST when planner returns `questions-pending`)

When the planner's handoff begins with `Status: questions-pending`:

1. You MUST surface the questions verbatim — do not paraphrase, do not collapse options.
2. You MUST ask the user via `AskUserQuestion` (reliable at main-agent depth, unlike sub-agent depth where the planner can't rely on it).
3. After the user answers, you MUST re-dispatch the planner with the answers embedded in the prompt:

   ```
   Agent({
     description: "Re-plan <task ID or short name> with answers",
     subagent_type: "godot-feature-planner",
     prompt: "Plan <task>. Project context lives in CLAUDE.md.\n\nAnswers from the user (round <N>):\n1. <selected option>: <verbatim answer>\n2. <selected option>: <verbatim answer>\n..."
   })
   ```

4. The re-dispatched planner should return `Status: plan-ready`. If it returns another `questions-pending`, you MAY do one more roundtrip; cap at 2 inquiry rounds per session. Beyond that, escalate to the user — the design isn't converging in this format.
5. Update the progress block: increment `Inquiry rounds: <count>` after each roundtrip.

You MUST NOT skip Phase 1.5 by guessing answers yourself. The whole point of pattern #2 is that the user decides, not you.

## Phase 1.7 — Optional doc re-verification (OFFER when planner returns `plan-ready`)

The planner has already verified its API claims against the docs and listed them in the plan's `API references consulted` section. This phase is an OPTIONAL independent re-check — a second opinion from a separate agent — not a mandatory gate. The default is to skip it and go straight to Phase 2 review.

1. When you surface the plan-ready handoff, you MUST show the planner's `API references consulted` section so the user can see what was verified and against which doc pages.
2. You MUST offer the optional re-check via `AskUserQuestion` — e.g. "The planner verified N API claims against the docs (listed above). Independent re-check before you review, or proceed to review?" Default / recommended is **proceed** unless a claim is load-bearing or looks surprising. If the user proceeds, advance to Phase 2 and record `Doc verification: planner-verified` — do NOT dispatch Explore.
3. Only if the user opts in, you MUST dispatch one or more read-only `Agent (Explore)` sub-agents to re-verify the listed claims. Batch independent claims into parallel dispatches in a single message:

   ```
   Agent({
     description: "Re-verify <plan slug> API claims",
     subagent_type: "Explore",
     prompt: "Independently re-verify these Godot 4 API / behavior claims against the official docs. The godot-docs MCP tools are deferred — first run ToolSearch(\"select:mcp__godot-docs__get_documentation_tree,mcp__godot-docs__get_documentation_file\") to load them, then use get_documentation_tree to locate the right page and get_documentation_file to read it. For each claim, report confirmed / contradicted / not-found WITH the doc reference (file path + section):\n1. <claim>\n2. <claim>\n...\nProject context lives in CLAUDE.md. Report conclusions only — do not dump doc excerpts."
   })
   ```

   Dispatch discipline (keeps doc pages out of your context, returns trustworthy answers):
   - Parallel by default — 2+ independent claims go in a single message, not serial roundtrips.
   - Give each claim the exact doc path the planner already recorded (e.g. `classes/class_characterbody2d.md`); let the Explore agent fall back to `get_documentation_tree` when none is named.
   - Demand conclusions, not excerpts — `confirmed / contradicted / not-found` plus a one-line doc reference. If an agent returns a doc dump, re-dispatch with a tighter cap rather than accepting it.
   - If a finding points at a second class worth checking, dispatch a follow-up wave rather than reasoning from a half-answer.

4. You MUST surface any re-check findings at the Phase 2 review, flagging any `contradicted` or `not-found` claim explicitly. A clean pass is reportable too ("re-check confirmed all N claims").
5. If a re-check contradicts a claim, you MUST NOT silently patch the plan. Fold the correction back through the planner (re-dispatch with the doc finding embedded, marked `[doc]`) for a load-bearing claim; for a localized factual fix you MAY hand-edit the plan in place and note it at the checkpoint. Treat a contradicted load-bearing claim as a reason to re-plan, not to inline-fix.
6. Update the progress block: set `Doc verification: <planner-verified | re-checked clean | re-checked, N fixed | re-planned | n/a>`.

If the plan's `API references consulted` section reads "(none — no engine API surface)", record `Doc verification: n/a — no engine claims` and proceed; no offer is needed.

## Phase 2 — User review checkpoint (MUST wait)

You MUST stop and wait for an explicit user signal. Do not start Phase 3 on momentum.

User signals and your response:

| Signal | Examples | Action |
|--------|----------|--------|
| Approval | "go", "implement this", "looks good", "ship it", points you at the plan with an action verb | Advance to Phase 3 without re-asking permission. |
| Adjustments | "change X", "rethink Y" | Re-run the planner with the correction OR hand-edit the plan in place, then re-checkpoint. |
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

**Escalation rule.** When the implementer returns `Status: escalation` (a fixture-fragile test, a mis-framed assertion, a harness bug, a stale cross-feature assert, a plan/sequencing doubt), you MUST relay the concern verbatim and wait for user direction. You MUST NOT auto-resolve by inline-editing, by directing the implementer to patch a planner-authored test, or by inline-fixing a stale assert yourself.

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
- The planner produces paths (fill `Plan path` and `Smoke tests`).
- The user requests a scope change recorded in `Notes`.

You SHOULD keep the block at the top of your message when one is present, so a `resume` invocation can find it without scrolling.

## Resumability

When `$ARGUMENTS == "resume"`:

1. You MUST search recent transcript / scratch state for the most recent `## SOP progress — godot-feature-workflow` block.
2. If found, you MUST acknowledge the recovered state to the user before doing anything else, then re-enter at `Current phase`.
3. If not found, you MUST ask the user which task to resume (do not guess from `git status` alone).
4. If a phase was interrupted mid-agent (e.g. implementer crashed), you SHOULD re-dispatch that agent with the same parameters rather than skipping forward.

## What this SOP does NOT do

- Run the Godot engine directly (the orchestrator dispatches `godot-smoke-runner`, which absorbs the verbose engine output; the orchestrator never calls `mcp__godot__run_project` itself).
- Doc-verify by default. The planner verifies its own API claims via the `godot-docs` MCP tools; the orchestrator's Phase 1.7 re-check is optional and on-request only.
- Auto-chain phases past user checkpoints.
- Auto-commit (atomic-docs stages; user approves).

## Examples

### Example 1 — Fresh feature

```
/godot-feature-workflow TASK-F62 raid multipliers
```

Expected flow: Phase 0 classifies as task description → progress block written → Phase 1 dispatches planner → checkpoint → user approves → Phase 3 dispatches implementer → checkpoint → user verifies → Phase 5 atomic-docs.

### Example 2 — Plan already exists

```
/godot-feature-workflow .claude/plans/wander-toggle-2026-05-06.md
```

Expected flow: Phase 0 classifies as plan path → progress block records path, entry phase = 3 → skip planner → Phase 3 dispatches implementer.

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
| "Task is obvious — skip the planner." | If the SOP doesn't fit, exit and tell the user. Don't silently downgrade to a one-liner edit. |
| "I'll just commit; atomic-docs would be a no-op." | The skill decides if it's a no-op, not you. Run it, then wait for explicit user approval before `git commit`. |
| "Smoke is green-ish; close enough." | If a planner-written `_test_*` isn't asserting green, iterate or escalate. No partial passes. |
| "User got impatient — I'll skip ahead." | Phase 0 selects the entry phase. Impatience isn't a re-route signal; only scope changes are. |
| "I read the SOP earlier; I remember the rules." | Skills evolve. Re-load the skill before acting; don't recall from memory. |
| "I can answer the planner's questions myself from conversation context." | Pattern #2 says the user decides. Use `AskUserQuestion` at Phase 1.5; don't substitute your judgment for theirs. |
| "Planner locked a decision in the plan; I'll just adjust at Phase 2 review." | If a decision is user-decidable, the planner shouldn't have locked it. Push back via inquiry handoff or re-plan; don't normalize silent locks. |
| "I'll re-verify the planner's API claims myself to be safe." | The planner already verified them via godot-docs. The Phase 1.7 re-check is opt-in — offer it, don't run it unprompted. |
| "The re-check says a claim is contradicted, but I can just patch the plan." | Load-bearing contradictions go back through the planner. Don't silently inline-fix the plan's design from a doc finding. |

If any of these thoughts appear, STOP, return to the user, and re-state the current phase.

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| Planner asks no design questions | Task is well-specified or out-of-scope for the planner | Verify the plan file still captures edge cases; if too thin, re-run the planner with explicit "ask me about X, Y, Z". |
| Smoke passes but user playtest disagrees | Smoke covers the wrong assertion | Have the implementer add a failing smoke test that captures the user's case (Phase 3 fold-back), then re-run the loop. |
| `Skill → atomic-docs` reports drift in unrelated notes | Earlier work left stale references | Resolve those before committing — do not bypass the drift grep. |
| `resume` cannot find a progress block | Block was scrubbed from context or never written | Ask the user which task to resume; do not infer from `git status`. |
| Phase 1 ↔ Phase 3 ping-pong | Plan keeps changing under implementation | Stop. Raise to user — design is not converged; SOP is not the right tool for an exploratory phase. |
| User says "go" mid-Phase 1 (before planner returns) | Premature approval | Acknowledge but do not advance; the planner has not produced a plan yet. |

## Style

- You MUST keep your own commentary terse — agents do the heavy lifting; your job between phases is to relay, checkpoint, and update the progress block.
- You SHOULD NOT re-summarize an agent's output; surface it verbatim instead.
- You MUST NOT silently substitute one agent for another (e.g. skip the planner because "it's a small feature") — if the SOP doesn't fit, exit and tell the user.
