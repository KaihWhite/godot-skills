---
description: Test-first pipeline for non-trivial Godot 4 / GDScript features, systems and refactors — plan with failing smoke tests, implement via godot-feature-implementer, verify via godot-smoke-runner, with user checkpoints.
argument-hint: <task ID or feature description> | <path to existing plan> | resume
---

# Godot Feature Workflow SOP

## Objective

Orchestrate a test-first pipeline for non-trivial Godot 4 / GDScript features, systems, and refactors. Each phase ends at an explicit user checkpoint — no auto-chaining, no surprise commits.

You (the main agent) do the planning yourself in Phase 1 — there is no separate planner sub-agent. This keeps the full planning context in your session, so asking the user a design question mid-plan is a normal inline `AskUserQuestion`, not a sub-agent restart that discards everything explored so far. To keep your context lean, you delegate the two heavy, mechanical jobs to sub-agents: Godot 4 doc verification (read-only `Explore`) and engine smokes (`godot-smoke-runner`). Implementation stays in a dedicated `godot-feature-implementer` sub-agent so the diff has a single owner, and a read-only `godot-feature-reviewer` gives the green result an independent read before the user sees it.

The pipeline:

```
Phase 1:   YOU plan (orient → patterns skill → Round 1: write back understanding
           + choose approach → Round 2: design + edge questions → verify API claims
           via Explore sub-agents → write plan + stubs + failing smokes
           → self-review → red check via godot-smoke-runner)
                                                 ↓
Phase 2:   (user reviews plan) ──────────────────┐
                                                 ↓
Phase 3:   godot-feature-implementer (one code pass per dispatch) ─┐
           orchestrator runs godot-smoke-runner, loops failures back │
           green → godot-feature-reviewer → one fix pass, re-smoke   │
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
- **Plan path** — e.g. `.claude/plans/wander-toggle-2026-05-06.md` (absolute or relative). Skips Phase 1 planning, but runs the plan intake (Phase 0 step 6) before Phase 3.
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
   - Entry phase: <1 | 3 | 3 (after plan intake) | 5>
   - Plan path: <path or "(pending — Phase 1 will create)">
   - Smoke tests: <paths or "(pending)">
   - Current phase: <number — name>
   - Inquiry rounds: <count, default 0>
   - Doc verification: <verified via Explore (N claims) | n/a — no engine API surface>
   - Red check: <clean — N/N tests CHECK FAILED | pending>
   - Review: <pending | clean | N fixed, M declined, K open | stopped — test-integrity>
   - Last checkpoint: <ISO date or "—">
   - Notes: <free-form, e.g. "user requested edge case X">
   ```

4. You SHOULD also create a TaskCreate entry per remaining phase (1, 3, 5 — checkpoints 2 and 4 belong to the user, not you), and mark them `in_progress` / `completed` as you advance. This is the canonical resumption signal.
5. You MUST NOT skip ahead to a later phase than the one Phase 0 selects, even if the user is impatient — re-route via Phase 0 if scope changes.
6. **Plan intake (MUST when `$ARGUMENTS` is a plan path).** A plan you didn't just write has never been red-checked by this session — it may predate the red check, have been hand-edited, or have tests that changed since. Read the plan and its smokes, then:
   - **No smoke tests** → it isn't a workflow plan. Treat it as the task description and enter at Phase 1; the plan is input to Step 1, and Round 1 reflects it back.
   - **Smokes exist** → run Phase 1 Step 8B (write any missing stubs — when the plan has no `Interface stubs` section, derive the interface surface from what the smokes call), Step 9 (self-review), and Step 10 (red check). Always, even when the plan already records a clean `Red check` — one runner spawn per smoke is cheap next to implementing against tests that can't fail.
   - If intake changed only stubs and the `Red check` line → set `Entry phase: 3 (after plan intake)` and continue to Phase 3. If it changed tests, signatures, or plan content, or the red check shows tests already passing (implementation may already exist) → stop at the Phase 2 checkpoint and say what changed.

## Phase 1 — Planning (MUST when entry phase = 1)

You plan the feature yourself, in this session. The output is a plan file, failing smoke tests, and the interface stubs those smokes need to parse — with the red state confirmed by an actual smoke run. You MUST NOT write feature behavior in this phase — stubs carry signatures only (Step 8B), and behavior is Phase 3's job. You MUST NOT run the engine yourself; the one engine run in this phase is the Step 10 red check, dispatched to `godot-smoke-runner`. Work the steps in order.

Because you are at main-agent depth, `AskUserQuestion` is reliable here: when you hit a genuine design ambiguity, ask the user directly and keep going with the answer in hand. There is no inquiry handoff and no restart — the whole point of planning in-session is that a question costs you a roundtrip, not your accumulated context.

Phase 1 has exactly two planned inquiry rounds: Round 1 (Step 3) confirms what you're building and how; Round 2 (Step 4) resolves the details of that approach. Questions in Round 2 often depend on the approach chosen in Round 1 — that is why they are separate.

### Step 1 — Orient (MUST)

The project docs are the source of truth for design intent, conventions, and architecture — you plan *against* them, not just alongside them. Read to absorb what the project has already decided, not to tick a box: a convention you skim past here becomes a wrong assumption baked into the plan, and the patterns skill (Step 2) and Godot docs (Step 5) confirm the *generic* answer, never the project-specific one. You MUST read, in this order:

1. The project's `CLAUDE.md` (root) — points to design docs, vault paths, implementation plan, active deviations file.
2. The design scratchpad if one exists (e.g. `<vault>/design/Thoughts.md`). This is **read-only**.
3. The relevant feature / component note(s) named in CLAUDE.md or implied by the task.
4. The implementation plan entry for the named task.

You SHOULD NOT speculatively read the entire source tree — only files the task names or that the design notes flag as touched.

Reconcile the task against what you read. Where the request conflicts with a documented convention or an established design direction, that conflict MUST be surfaced in Step 3 — do not silently resolve it in the plan's favor or the doc's.

### Step 2 — Consult patterns skill (MUST)

You MUST invoke `Skill → godot-gdscript-patterns` BEFORE proposing approaches, not at exit — the candidate approaches in Step 3 are built from these patterns. From the skill output, identify which patterns are candidates (state machine, signals, scene composition, resources, object pool, etc.). The final Apply / Skip lists go into the plan once Step 3 settles the approach.

### Step 3 — Round 1: write back understanding + propose approaches (MUST)

Send ONE message containing the write-back as text, followed by an `AskUserQuestion` for the approach choice. Increment `Inquiry rounds` afterwards.

**A. Write back your understanding.** A short note the user can assess and correct:

- **Outcome** — what the feature does, in player- or developer-observable terms.
- **Success criteria** — the observable end states that prove it works. These become the Step 6 assertion list, so make them concrete.
- **Constraints** — from CLAUDE.md / design notes, with the note named.
- **Said vs. assumed** — separate what the user stated from what you inferred. Every inference is a correction opportunity; list it.
- **Conflicts** — any request-vs-documented-convention conflict found in Step 1.

When `$ARGUMENTS` and the docs already supply the purpose and constraints, reflect them back rather than re-asking — keep the note concise. The user corrects via the question's notes or "Other"; you MUST incorporate any correction before Round 2.

**B. Propose 2-3 approaches.** Always — even when one looks obvious. Each approach is a distinct architecture (e.g. component node vs. autoload service vs. Resource-driven data; signals vs. direct calls across a boundary), not a variation in values:

- Lead with your recommendation, labeled "(Recommended)", and say why in one line.
- Give honest tradeoffs for each: fit with project conventions, testability as a smoke, scene/signal coupling, persistence impact.
- Use `AskUserQuestion` option `preview`s for a scene-tree sketch or key signatures when that makes the difference clearer than prose.
- Alternatives MUST be credible — something a competent Godot developer might actually pick. When the project docs already fix the architecture, the documented approach is the recommendation and the alternatives show what it rules out; never pad with straw men to reach the count.
- YAGNI: strip speculative extensibility from every approach.

If the chosen approach rests on an engine behavior you haven't verified, you MAY dispatch a Step 5-style Explore check before Round 2 rather than building questions on a false premise.

### Step 4 — Round 2: resolve design questions inline (MUST)

With the approach settled, you MUST identify 2-4 genuine ambiguities in it. Decisions to ask about typically include: mechanical timing, threshold values, UI placement, persistence boundaries, error behavior, schema boundaries — anything the design doc deliberately defers or where you can name 2+ reasonable answers.

For any ambiguity NOT already resolved in `$ARGUMENTS`, Round 1, or earlier in the conversation, you MUST ask the user via `AskUserQuestion` — neutral options, honest tradeoffs, one option labeled "(Recommended)" only when there is strong reason. Ask before drafting the plan; bundle Step 7 edge-case prompts into the same roundtrip so one set of questions resolves both (see Step 7). Increment `Inquiry rounds` in the progress block after the roundtrip.

You MUST verify each question is genuinely open BEFORE asking. Sanity check: can you name 2+ reasonable answers without strain? If you find yourself constructing options to justify a preconceived constraint, the constraint IS the answer — lock it and document it in the plan body rather than asking. Manufactured questions (false constraints framed as "must resolve" choices) waste the user's time and signal over-engineering. Example that surfaced as a false constraint in a past run: "4→3 archetype mismatch must resolve" (it didn't — schemas can have different archetype counts).

You MUST NOT lock a user-decidable decision silently. If you catch yourself rationalizing "the user probably meant X" or "the prompt strongly hinted at Y so I'll lock it" on a choice with 2+ reasonable answers, that's an `AskUserQuestion`, not a lock. Decisions you do lock by your own inference (rather than a user answer) MUST be surfaced at the Phase 2 review as "inferred, not confirmed" so the user can override.

If Round 1 answered everything and no genuine ambiguity remains, skip the Round 2 roundtrip and say so in the progress block `Notes` — do not manufacture questions to fill it.

### Step 5 — API verification via Explore sub-agents (MUST when applicable)

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
- If a claim comes back `contradicted`, the design rests on a false premise — revise the plan (and re-open a Step 3 or Step 4 question if the correction is user-decidable) rather than papering over it.

Self-confidence is the same trap as silent locking: bias toward verifying. A claim you confirm against the page costs one Explore dispatch; a wrong assumption buried in prose costs a re-plan. `known` claims backed by in-codebase evidence (specific function references, fallback chains, prior usage) do NOT need a dispatch — but you MUST cite that evidence in the plan. "Everything was in scope" without citations is not evidence; verify it.

In the plan's `API references consulted` section, record each verified item: the class / signal / property, the doc path the Explore agent read (or the in-codebase citation for a `known` claim), and the fact confirmed. If the plan touches no Godot 4 API surface (e.g. a pure refactor of project-local code), write "(none — no engine API surface)" and set `Doc verification: n/a — no engine API surface` in the progress block.

### Step 6 — Test design (MUST)

Smoke tests follow `godot-gdscript-patterns` § Testing GDScript — the canonical harness:

- `tests/smoke_<feature>.tscn` — root Node with a script attached. You MUST omit `uid="..."` from the `[gd_scene format=3]` header (Godot regenerates on first scan; hand-authored UIDs leave parent `ext_resource` references stale).
- `tests/smoke_<feature>.gd` — `extends SmokeHarness`; `_tests()` returns `[[label, Callable], ...]`; each `_test_*` calls `_check(cond, message)`.

If the project already has its own harness, follow it. If it has none, Step 8 copies the skill's bundled harness in. If the project uses a different framework entirely (e.g. GUT), you MUST ask the user via `AskUserQuestion` rather than assuming.

You MUST draft the assertion list — what observable end state proves the feature works — starting from the success criteria confirmed in Round 1. For each test, name the behavior that is missing today and would make it fail; a test you can't say that about pins existing behavior and either isn't needed or is a deliberate regression guard (mark it as one in the plan).

You MUST also list the **interface surface** the smokes touch that doesn't exist yet — every new `class_name`, method, signal, exported / public property, and preloaded scene, with exact typed signatures. These become the Step 8B stubs and the implementer's contract.

### Step 7 — Edge-case integration (MUST)

Anticipate edge-case categories (boundary values, save/load roundtrip, signal ordering, multi-frame timing, error states, race conditions, large/empty inputs) at Step 4 inquiry time, so the Round 2 roundtrip resolves both design questions and edges. With the answers in hand, append confirmed edges to the test list. If a Step-6-emergent edge truly needs user input that Round 2 missed, you MAY ask one more roundtrip — but minimize this.

### Step 8 — Write deliverables (MUST)

#### A. Test files

You MUST create:

- `tests/smoke_<feature>.tscn` — root Node with the script attached, no hand-authored `uid`.
- `tests/smoke_<feature>.gd` — `SmokeHarness` subclass with `_test_*` functions. Tests MUST fail until Phase 3 codes the feature — red means `CHECK FAILED` lines, not a parse error. That is the TDD red state, and Step 10 proves it.
- **Project has no harness yet** → also copy the skill's `assets/smoke_harness.gd` to `scripts/tests/helpers/` and `assets/run_smoke.sh` to `tools/`.

#### B. Interface stubs

A smoke that calls `WanderController.new()` before `WanderController` exists is a parse error, not a red. For every item on the Step 6 interface-surface list, you MUST write a signature-only stub so the smokes parse and fail on their checks:

- **New script** — `class_name` + `extends`, typed method signatures exactly as the plan states them, bodies of `pass` or the return type's zero value (`false`, `0`, `0.0`, `""`, `null`, `[]`, `{}`), each marked `# STUB — Phase 3 implements`.
- **New method on an existing script** — append the stub method only; nothing else in that file changes.
- **Signals and exported / public properties** the smokes reference — declare them with their defaults. Never emit a signal or mutate state in a stub.
- **New scene the smoke preloads** — a minimal `.tscn` (root node + stub script), no hand-authored `uid`.

Stubs carry no behavior. If a stub body needs a branch, a loop, a signal emit, or a call into other project code to make the smoke parse, that's implementation — stop and restructure the smoke instead. Stubs are implementation files, not tests: the implementer owns and replaces them in Phase 3, and the plan-authored-test read-only rule does not apply to them.

#### C. Plan file

Path: `<cwd>/.claude/plans/<slug>-<YYYY-MM-DD>.md`. If `<cwd>/.claude/` doesn't exist, fall back to `<cwd>/plans/`, then `~/.claude/plans/`. Slug: lowercase-hyphenated, task ID + 1-3 keywords (e.g. `task-f46-wander-toggle-2026-05-06.md`).

**Archive policy (MUST when re-writing a plan for the same task).** When you produce v2+ of a plan (a prior version exists at the active path), you MUST archive the prior version to `<cwd>/.claude/plans/archive/<slug>-<prior-date>-v<N>.md` before writing the new plan. Use today's date in the new filename if the prior version was written on a different day. NEVER overwrite an active plan in place — the archive preserves history for the user and for resumability. Stubs and smokes are not archived: reconcile them to the v2 plan (see Phase 2 Adjustments).

Plan template:

```
# Plan: <task>

**Created:** <date>
**Scope:** <task ID + one-line summary>

## Goal
<concise outcome>

## Understanding (confirmed in Round 1)
- Success criteria: <observable end states>
- Constraints: <from which doc>
- Assumptions: <each marked "confirmed" or "inferred, not confirmed">

## Approach
- Chosen: <approach> — <why; user's Round 1 answer>
- Rejected: <approach> — <why not>

## Design decisions
- <decision> — <reason from user's AskUserQuestion answer or design doc>

## Pattern alignment (godot-gdscript-patterns)
- Apply: <pattern names + where>
- Skip: <patterns considered + why>

## API references consulted (via Explore + godot-docs MCP)
- <class/signal/property> — <doc path read, or in-codebase citation for a `known` claim> — <fact confirmed>

## Interface stubs (written in Phase 1 — implementer replaces)
- `<path>` — <new file | stub appended to existing> — `<exact typed signature>`

## Files to touch
- `<path>` — <new vs edit vs fill stub; what changes>

## Test specification
- Smoke harness: `tests/smoke_<feature>.tscn` + `.gd` (failing versions already written)
- Test cases:
  - `_test_<X>()` — checks <end state> — fails today because <missing behavior>
- Edge cases (user-confirmed):
  - <edge> — covered by `_test_<Y>()`
- Red check: <date> — <N/N tests CHECK FAILED; runner summary>
  - sha256: `<smoke path>` = `<hash>` (one line per smoke `.gd` and `.tscn`)

## Implementation sequencing
<order; deferrals via call_deferred or signals; new class_name → runner needs new_class_name: true>

## Risks + mitigations
- <risk> — detect via <signal/log/assertion>; mitigate by <approach>

## Out of scope
<explicit non-goals to prevent drift>

## Handoff
> Use the `godot-feature-implementer` agent with the plan at <plan path>.
```

### Godot pitfalls to encode in the plan (MUST)

`godot-gdscript-patterns` wins over training intuition, and its § Common Pitfalls is the canonical list (shadowed built-ins, `_ready` order, CanvasLayer overlays, `.tscn` UIDs, debug-grant guards, warning placement). The stubs and smokes you write follow it too. For each pitfall the touched code is exposed to, name it in the plan's `Implementation sequencing` or `Risks + mitigations` at the point it applies, so the implementer meets it where it matters.

Workflow-specific:

- **New `class_name` → class-registry refresh** before the smoke can resolve the type; the runner does it when passed `new_class_name: true`. Stub `class_name`s are registered by the Step 10 red check, so Phase 3 only needs it for classes the implementer adds beyond the stubs.

### Step 9 — Plan self-review (MUST)

Before the red check, re-read the plan, stubs, and smokes together with fresh eyes. This is a checklist you run yourself — not a sub-agent dispatch:

1. **Coverage.** Every Round 1 success criterion, design decision, and confirmed edge case maps to a named `_test_*` — or is listed in `Out of scope`, or flagged "playtest-only" with the reason it can't be smoked. List any gaps and close them.
2. **Placeholder scan.** No "TBD", "TODO", "handle edge cases", "add appropriate error handling", "similar to above", or a `Files to touch` entry that doesn't say what changes. Fix them.
3. **Name and signature consistency.** Every class, method, signal, and property is spelled and typed identically across the plan, the stubs, and the smokes. Every symbol a smoke calls exists in a stub or in existing code (cite the file). A `get_wander()` in the smoke and a `get_wandering()` in the stub is a bug.
4. **API coverage.** Every engine API named in `Files to touch`, `Implementation sequencing`, or the stubs appears in `API references consulted` (or is cited as `known`).
5. **Approach fidelity.** `Pattern alignment` and `Files to touch` implement the approach chosen in Round 1, not one of the rejected ones.

Fix issues inline — no need to re-review afterwards. If a fix changes a user-confirmed decision, that's a question for the user, not an inline fix.

### Step 10 — Verify red (MUST)

You MUST watch the smokes fail before handing off. A smoke that was never run hasn't been shown to test anything: it might parse-error, or pass against the stubs because it pins behavior that already exists.

Dispatch one `godot-smoke-runner` per smoke scene. Pass `new_class_name: true` if the stubs added any `class_name`:

```
Agent({
  description: "Red check <smoke slug>",
  subagent_type: "godot-smoke-runner",
  prompt: "Run <smoke_scene>. new_class_name: <true|false>. This is a pre-implementation red check — failures are expected."
})
```

The red check passes only when the runner returns `status: fail` and:

- every failure is `type: assertion` (`CHECK FAILED`) — no `compilation-error`, no `runtime-error`; and
- every test case in the plan's `Test specification` appears among the failures, except ones the plan explicitly marks as regression guards.

Act on anything else — you own the plan-authored tests and stubs in this phase, so fix them yourself:

| Runner result | Meaning | Action |
|---------------|---------|--------|
| `compilation-error` | A smoke or stub doesn't parse, or a stub symbol is missing | Fix the smoke / stub (and re-run Step 9 check 3), re-dispatch |
| `runtime-error` | A stub default (e.g. `null`) crashes the test before it reaches `_check` | Restructure the test to `_check` the precondition first (e.g. `_check(x != null, ...)` then return) — never put behavior in the stub |
| A planned test missing from `failures` | It passes against the stubs — it pins behavior that already exists or a stub default happens to satisfy it | Tighten the assertion so it fails for the missing behavior, or mark it a regression guard in the plan with a reason |
| `pass` | Nothing is red | The tests don't exercise the feature. Return to Step 6 |

Cap at ~3 red-check iterations. If it still isn't a clean red, STOP and raise it to the user with the latest runner JSON. Record the result in the plan's `Red check` line and set `Red check:` in the progress block.

Once the red is clean, record a SHA-256 of every smoke `.gd` and `.tscn` under the `Red check` line (`shasum -a 256 <file>`, or `sha256sum`). The Phase 3 reviewer compares against these to confirm the implementer left the tests alone. If you later change a smoke (Phase 2 adjustments, plan intake), re-run the red check and re-record.

### Step 11 — Hand off to the user (MUST)

When the plan, stubs, and failing tests are written and the red check is clean, you MUST surface to the user, in one message:

- The plan path, the test file paths, and the stub files.
- The red-check result (which tests fail, and the runner's one-line summary).
- The `API references consulted` section (so the user sees what was verified and against which doc pages).
- Any design decision or assumption you locked by your own inference rather than a user answer, flagged "inferred, not confirmed."

Then update the progress block (`Plan path`, `Smoke tests`, `Doc verification`, `Red check`, `Current phase: 2`) and advance to Phase 2. You MUST NOT continue into implementation.

You SHOULD NOT re-plan from scratch more than twice in one session. If the user keeps adjusting, prefer a hand-edit to the plan file — then re-run Steps 9-10 if the edit touched tests, stubs, or signatures.

## Phase 2 — User review checkpoint (MUST wait)

You MUST stop and wait for an explicit user signal. Do not start Phase 3 on momentum.

User signals and your response:

| Signal | Examples | Action |
|--------|----------|--------|
| Approval | "go", "implement this", "looks good", "ship it", points you at the plan with an action verb | Advance to Phase 3 without re-asking permission. |
| Adjustments | "change X", "rethink Y" | Re-work the plan (re-run the relevant Phase 1 steps) OR hand-edit the plan in place, then re-checkpoint. If the interface surface changed, reconcile the stubs first: delete stubs nothing calls any more, update changed signatures, then re-run Steps 9-10. |
| Rejection | "no", "stop", "different approach" | STOP. You MUST NOT auto-pivot to a different design. Run the rejection cleanup below, then return to the user. |

Ambiguous signals (e.g. user just asks a question about the plan) → answer the question, do not advance.

**Rejection cleanup (MUST).** Phase 1 left files in the tree, and stub `class_name`s are registered with Godot, so they can collide with a later design. List everything Phase 1 wrote — smokes, new stub files, stub methods appended to existing files, any harness copies — and ask via `AskUserQuestion` whether to remove them or keep them. Remove nothing without that answer. When removing:

- Delete new smoke and stub files outright.
- For stubs appended to existing files, remove only the appended stub methods. Never `git checkout` / `git restore` the file — it may hold the user's uncommitted work.
- Keep harness copies (`smoke_harness.gd`, `run_smoke.sh`) unless the user says otherwise — they're shared infrastructure, not part of the rejected design.
- Leave the plan file in place, and note `rejected` plus the date in its header so a later run doesn't mistake it for an active plan.

Record the outcome in the progress block `Notes` and set `Current phase: stopped — plan rejected`.

## Phase 3 — Implementation (MUST when entry phase ≤ 3)

The implementer codes ONE pass per dispatch and does NOT run the engine. It starts from the Phase 1 stubs and the clean red check; its job is to replace every stub with behavior until the same smokes go green. **You own the code → smoke → fix loop:** dispatch the implementer, run `godot-smoke-runner` on the params it returns, hand any failure back to the implementer, repeat until the smoke passes.

1. Dispatch the implementer with the plan path:

   ```
   Agent({
     description: "Implement <plan slug>",
     subagent_type: "godot-feature-implementer",
     prompt: "Implement using the plan at <plan path>."
   })
   ```

2. The implementer returns one of three statuses:
   - `Status: smoke-ready` — it coded a pass; the handoff carries the smoke params (`smoke_scene`, `new_class_name`, and `log_path` for legacy log-file smokes only), any additional smokes, files changed, and deviations.
   - `Status: escalation` — a test-boundary / stale-assert / plan / scope concern. You MUST relay it verbatim and wait for user direction (see escalation rule below). Do NOT advance or auto-resolve.
   - `Status: test-needed` — it found behavior the plan requires but no smoke covers, and stopped before coding it. Run [New tests after planning](#new-tests-after-planning-must) with its proposed assertions and interface, then re-dispatch it. A test-needed round doesn't count toward the step 5 iteration cap.

3. On `smoke-ready`, run each reported smoke via `godot-smoke-runner` — one spawn per scene:

   ```
   Agent({
     description: "Run <smoke slug>",
     subagent_type: "godot-smoke-runner",
     prompt: "Run <smoke_scene>. new_class_name: <true|false>.[ Log: <log_path> — legacy log-file smokes only]"
   })
   ```

   You MUST NOT run the engine yourself (`mcp__godot__run_project` / `get_debug_output` / `stop_project`, or `tools/run_smoke.sh`) — the runner absorbs the verbose engine output so your context stays lean across iterations. The runner returns a JSON block with `status` (`pass` / `fail` / `compilation-error`), a `failures` list, and a 1-line `summary`.

4. Act on the runner's result:
   - `pass` (all reported smokes green) → go to step 6 (review).
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

6. **Review (MUST once green).** Dispatch the reviewer with the plan path and the changed-file list — the union of every implementer pass's `Changed this pass`, plus the plan's stubs and smokes:

   ```
   Agent({
     description: "Review <plan slug>",
     subagent_type: "godot-feature-reviewer",
     prompt: "Review the implementation of the plan at <plan path>. Changed files:\n<list>"
   })
   ```

   Route its verdict:

   - `clean` → go to the Phase 4 handoff below.
   - `stop` (a smoke's hash no longer matches its red-check record) → relay the finding verbatim and wait for the user. Don't re-dispatch anyone.
   - `changes-requested` →
     - `coverage` findings → run [New tests after planning](#new-tests-after-planning-must) for each (its scope check applies). Never send these to the implementer.
     - `must-fix` and `should-fix` findings → re-dispatch the implementer for one review-fix pass with the findings embedded:

       ```
       Agent({
         description: "Review fixes <plan slug>",
         subagent_type: "godot-feature-implementer",
         prompt: "Continue the plan at <plan path>. Review-fix pass — address these findings per your review-fix rules:\n<findings>"
       })
       ```

     - Then re-run the smokes (steps 3–4; a failure there is an ordinary fix loop). When they're green, return here instead of starting a fresh review: re-review only if there were `must-fix` findings, passing the prior findings and the implementer's per-finding response; otherwise go to the Phase 4 handoff. At most 2 review rounds in total.
     - Anything still open after the cap, any finding the implementer declined, and all `note`s go into the Phase 4 report. Don't loop to settle a disagreement — the user arbitrates.

   **Phase 4 handoff.** Surface the implementer's report, the green smoke summaries, and the review outcome (fixed / declined with reasons / open / notes) verbatim, set `Review:` and `Last checkpoint: <date>` in the progress block, and advance to Phase 4.

   A Phase 4 fold-back that ends green runs this step again, scoped to the files that fold-back changed.

You MUST NOT edit project source files directly during this phase — let the implementer own the diff. Your role in the loop is to run the runner and courier its JSON back, not to patch. The one exception is [New tests after planning](#new-tests-after-planning-must): new smokes plus signature-only stubs, never behavior.

**Escalation rule.** When the implementer returns `Status: escalation` (a fixture-fragile test, a mis-framed assertion, a harness bug, a stale cross-feature assert, a plan/sequencing doubt), you MUST relay the concern verbatim and wait for user direction. You MUST NOT auto-resolve by inline-editing, by directing the implementer to patch a plan-authored test, or by inline-fixing a stale assert yourself.

### New tests after planning (MUST)

Every test must be seen failing before the code that makes it pass exists — the same rule Phase 1 Step 10 enforces. So after Phase 1, a new smoke is always written by you (never the implementer) and red-checked before the implementer codes against it. This applies to an implementer `test-needed` handoff and to a Phase 4 playtest bug alike.

1. **Scope check.** If the behavior to pin is outside the approved plan's `Goal` and `Design decisions`, it's a scope change — ask the user via `AskUserQuestion` before writing anything.
2. **Write the test.** Add `_test_*` cases to a new smoke under `tests/`, following Phase 1 Steps 6 and 8A. For a playtest bug, the test reproduces the user's case. Add signature-only stubs per Step 8B for any symbols that don't exist yet.
3. **Red check** the new smoke per Phase 1 Step 10. A new test that passes on its first run was written after the code — the behavior already exists. Don't discard it: mark it `written after the code — never seen red` in the plan and surface that at the Phase 4 checkpoint.
4. **Record it.** Hand-edit the plan's `Test specification` (and `Interface stubs`), including the new smoke's sha256 lines — no archive needed for an addition. The new smoke is now read-only for the implementer like every other orchestrator-authored test.
5. **Dispatch.** Re-dispatch the implementer with the plan path, naming the new smoke, then run the normal Phase 3 loop.

## Phase 4 — User verification checkpoint (MUST wait)

You MUST wait for the user to review the diff and / or playtest. Signals:

| Signal | Action |
|--------|--------|
| Approval | Advance to Phase 5. |
| Bug or wrong behavior found in playtest | Pin it first: run [New tests after planning](#new-tests-after-planning-must) so a failing smoke reproduces it, then fold back into Phase 3. Never send the implementer a bug without a red test. |
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

Expected flow: Phase 0 classifies as task description → progress block written → Phase 1: you orient, consult the patterns skill, write back your understanding and offer 2-3 approaches (Round 1), ask design + edge questions for the chosen approach (Round 2), dispatch Explore sub-agents to verify the API claims, write the plan + interface stubs + failing smokes, self-review, confirm red via `godot-smoke-runner` → Phase 2 checkpoint → user approves → Phase 3 dispatches implementer, loops smokes to green, runs the reviewer and one fix pass → checkpoint → user verifies → Phase 5 atomic-docs.

### Example 2 — Plan already exists

```
/godot-feature-workflow .claude/plans/wander-toggle-2026-05-06.md
```

Expected flow: Phase 0 classifies as plan path → progress block records path → plan intake writes any missing stubs, self-reviews, and red-checks the smokes → clean and unchanged, so entry phase = 3 (after plan intake) → Phase 3 dispatches implementer.

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
| "I can answer the design questions myself from conversation context." | If a choice has 2+ reasonable answers, the user decides. Use `AskUserQuestion` in Round 1 or Round 2 (Steps 3-4); don't substitute your judgment for theirs. |
| "The prompt strongly hinted at X, so I'll lock it in the plan." | A user-decidable choice is a Step 3 or Step 4 question, not a silent lock. If you must infer, flag it "inferred, not confirmed" at Phase 2. |
| "Only one approach makes sense here — skip the alternatives." | Step 3 always offers 2-3 credible approaches. If the docs dictate one, recommend it and show what it rules out — the user confirms. |
| "The smokes obviously fail — no need to run them before handoff." | A smoke you never watched fail may parse-error or pass against the stubs. Step 10 is mandatory. |
| "I'll fill in this stub while I'm here — it's one line." | Stubs carry signatures only. Behavior in Phase 1 means the smoke never proved it can fail. |
| "The implementer can write the regression test along with the fix." | Then nobody watched it fail. New tests after planning come from you and are red-checked first. |
| "Smokes are green — the review is a formality." | Smokes prove the assertions, not the design, the pitfalls, or the tests' integrity. Step 6 runs every time Phase 3 goes green. |
| "I'll keep re-dispatching until the reviewer and implementer agree." | Two review rounds, then the disagreement goes to the user at Phase 4. |
| "Self-review is a formality — I just wrote this." | Step 9 catches the name drift and coverage gaps that otherwise surface as Phase 3 escalations. Run the checklist. |
| "I'll just read the doc page myself to verify this API." | Phase 1 verification is delegated to Explore sub-agents — conclusions only, doc pages stay out of your context. Dispatch, don't read whole pages. |

If any of these thoughts appear, STOP, return to the user, and re-state the current phase.

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| You asked no design questions | Task is well-specified, or you skipped Step 4 | Re-check Step 4: can you name 2+ reasonable answers to any open decision? If the plan is thin on edge cases, ask before writing it. |
| User's Round 1 correction changes the outcome or success criteria | Your write-back missed intent | Update the understanding, re-offer approaches if the correction invalidates them, then go to Round 2. Don't carry Round 2 questions written for the old understanding. |
| Red check returns `compilation-error` for a stub `class_name` | Class registry not refreshed | Re-dispatch the runner with `new_class_name: true`. |
| Red check keeps returning a planned test as passing | The assertion pins existing behavior or a stub default | Tighten the assertion to the missing behavior, or mark it a regression guard in the plan with a reason — don't put behavior in the stub. |
| An Explore agent returns a huge doc dump | Prompt didn't cap the response | Re-dispatch with "report conclusions only — confirmed / contradicted / not-found + one-line doc reference, no excerpts". |
| Smoke passes but user playtest disagrees | Smoke covers the wrong assertion | Write a smoke that reproduces the user's case and red-check it ([New tests after planning](#new-tests-after-planning-must)), then fold back into Phase 3. |
| `Skill → atomic-docs` reports drift in unrelated notes | Earlier work left stale references | Resolve those before committing — do not bypass the drift grep. |
| `resume` cannot find a progress block | Block was scrubbed from context or never written | Ask the user which task to resume; do not infer from `git status`. |
| Reviewer returns `stop` on a hash mismatch | A smoke changed after its red check — the implementer edited it, or you changed it without re-recording | Relay to the user. If the change was yours (a Phase 2 adjustment), re-run the red check and re-record the hashes, then re-review. |
| Reviewer `should-fix` findings change behavior when applied | Finding mis-classified, or the fix overreached | Smokes catch it as a failure; if the fix needs new behavior, it was a `must-fix` or a coverage gap — route it accordingly. |
| Phase 1 ↔ Phase 3 ping-pong | Plan keeps changing under implementation | Stop. Raise to user — design is not converged; SOP is not the right tool for an exploratory phase. |
| User says "go" mid-Phase 1 (before the plan is written) | Premature approval | Acknowledge but do not advance; the plan file doesn't exist yet. |

## Style

- You MUST keep your own commentary terse — sub-agents do the heavy lifting in Phases 3+; in Phase 1 you plan, in the gaps you relay, checkpoint, and update the progress block.
- You SHOULD NOT re-summarize a sub-agent's output; surface it verbatim instead.
- You MUST NOT silently downgrade the SOP (e.g. skip planning because "it's a small feature") — if the SOP doesn't fit, exit and tell the user.
