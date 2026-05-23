---
argument-hint: <task ID or feature description> | <path to existing plan> | resume
---

# Godot Feature Workflow SOP

## Objective

Orchestrate a test-first agent pipeline for non-trivial Godot 4 / GDScript features, systems, and refactors. Each phase ends at an explicit user checkpoint — no auto-chaining, no surprise commits. The SOP keeps the heavy context (Godot 4 docs, project docs, smoke output) inside dispatched sub-agents so the main session stays lean.

The pipeline:

```
Phase 1: godot-feature-planner  ─┐
                                  ├─→ user review checkpoint
Phase 2: (user reviews plan)    ─┘
                                  ↓
Phase 3: godot-feature-implementer ─┐
         └─ delegates → godot-smoke-runner
                                    ├─→ user verification checkpoint
Phase 4: (user verifies)          ─┘
                                    ↓
Phase 5: Skill → atomic-docs (drift grep + atomic commit pass)
```

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

You MUST NOT pre-empt the planner by reading Godot 4 API docs yourself; doc reads belong to its delegated `Agent (Explore)` sub-agents.

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

You MUST dispatch the implementer via the `Agent` tool with the plan path:

```
Agent({
  description: "Implement <plan slug>",
  subagent_type: "godot-feature-implementer",
  prompt: "Implement using the plan at <plan path>."
})
```

You MUST NOT run the engine yourself; the implementer delegates smoke runs to `godot-smoke-runner`.

You MUST NOT edit project source files directly during this phase — let the implementer own the diff so it can iterate against the smoke harness.

When the implementer returns, you MUST surface its status report verbatim (files changed, smoke status, drive-by fixes) and update the progress block (`Last checkpoint: <date>`).

If the implementer escalates a concern about a planner-authored artifact (a fixture-fragile test, a mis-framed assertion, a harness bug, etc.) — via mid-flight `AskUserQuestion` or surfaced in its Step 9 report — you MUST relay the concern verbatim and wait for user direction. You MUST NOT auto-resolve by inline-editing or by directing the implementer to patch.

If the implementer reports a smoke still failing after its own iteration budget, you MAY re-invoke it once with explicit guidance from the user. Beyond that, escalate to the user instead of looping further.

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

- Run the Godot engine directly (delegated to `godot-smoke-runner`).
- Read Godot 4 API docs directly (delegated to planner's `Agent (Explore)` sub-agents).
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

If any of these thoughts appear, STOP, return to the user, and re-state the current phase.

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| Planner asks no design questions | Task is well-specified or out-of-scope for the planner | Verify the plan file still captures edge cases; if too thin, re-run the planner with explicit "ask me about X, Y, Z". |
| Implementer reports smoke green but user playtest disagrees | Smoke covers the wrong assertion | Add a failing smoke test that captures the user's case, then re-invoke implementer (Phase 3 fold-back). |
| `Skill → atomic-docs` reports drift in unrelated notes | Earlier work left stale references | Resolve those before committing — do not bypass the drift grep. |
| `resume` cannot find a progress block | Block was scrubbed from context or never written | Ask the user which task to resume; do not infer from `git status`. |
| Phase 1 ↔ Phase 3 ping-pong | Plan keeps changing under implementation | Stop. Raise to user — design is not converged; SOP is not the right tool for an exploratory phase. |
| User says "go" mid-Phase 1 (before planner returns) | Premature approval | Acknowledge but do not advance; the planner has not produced a plan yet. |

## Style

- You MUST keep your own commentary terse — agents do the heavy lifting; your job between phases is to relay, checkpoint, and update the progress block.
- You SHOULD NOT re-summarize an agent's output; surface it verbatim instead.
- You MUST NOT silently substitute one agent for another (e.g. skip the planner because "it's a small feature") — if the SOP doesn't fit, exit and tell the user.
