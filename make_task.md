---
description: Capture the agreed plan into a new ai/tasks/<slug>/ folder for handoff to a fresh-chat executor model
---

# /make_task — Plan Handoff

You are the **planner** in the project's planner→executor→reviser loop (see `project_bootstrap_workflow.md`, Phase 5). The user and you have just agreed on a plan in this chat. Your job now: serialize that plan into a **new task folder** `ai/tasks/<slug>/` holding two self-contained files (`context.md` + `task.md`), so a different model, in a fresh chat without this conversation, can execute it correctly. The queue may already hold other tasks — you **add** one, you do not replace them.

> Paths are **repo-relative to the project root** (the folder Cascade has open, i.e. `/data/apps/<project>/`). Never hardcode an absolute project path.

## Step 0 — Load the foundation (invariant 0.4)

Before writing anything, read the project foundation if it exists:
- `ARCHITECTURE.md` — the map; its components/data model anchor your Codebase Context and Constraints.
- `CONVENTIONS.md` — the house rules the executor must follow. Read its `## Known Pitfalls / Lessons` section in particular: those are gotchas earlier executions paid for, and a plan that walks into a known pitfall is a defective plan. Fold the relevant ones into Constraints / Known Pitfalls of this task.
- `DECISIONS.md` — past decisions; do not contradict them silently.

If the project has no foundation files, it has not been bootstrapped — tell the user to run `project_bootstrap_workflow.md` first, and continue only if they confirm this is intentional (e.g. a throwaway).

## Core principle: self-containment

The executor will **NOT** see this conversation. Every decision, path, constraint, and rationale must live in the files. Forbidden phrases: "as we discussed", "the plan above", "the approach we chose", "per the conversation". State everything explicitly. If you find yourself referencing context that isn't in the files, write that context into the files.

## Core principle: plan to the floor

You do **not** choose who executes this plan — the user picks the executor model at run time, and it may be a small, cheap model with weak reasoning (and on another task it may be a strong one). Write the plan for the **weakest plausible executor**. A strong model executing an over-specified plan loses almost nothing; a weak model executing an under-specified plan fails. So do not rely on the executor to "figure out" a gap, infer an unstated step, or reason its way around an ambiguity — spell it out. Over-specification is the safe error here.

This is also why the executor follows the plan **literally**: not because a smarter model wrote it, but because the plan is explicit, self-contained, and mechanically verifiable. Make it worthy of that authority.

## Step 1 — Name the task and pre-flight

1. **Derive a slug** for THIS task from its goal: lowercase, hyphens, ascii, ≤40 chars (e.g. `add-rate-limiter`). It names the folder `ai/tasks/<slug>/`.
2. **Scan the queue** `ai/tasks/`:
   - If `ai/tasks/<slug>/` already exists — either pick a more specific slug, or, if this is really the *same* task being reworked, **STOP**: that is `/revise_task` (or finish/archive the old one first), not a new `/make_task`.
   - If any existing task folder contains a `blockers.md`, that task is paused awaiting correction. Mention it (*"Задача `<other-slug>` ждёт `/revise_task`."*) but **do not touch it** — you are only adding a new task.
   - If any existing task folder contains a `result.md` (and no `blockers.md`), that task is finished and awaiting archive — not runnable, not your concern here. Mention it (*"Задача `<other-slug>` ждёт архивации."*) but **do not touch it**.
   - Several queued tasks are normal. Adding one is fine — but mind the queue-staleness rule: if this task touches files that another queued task also touches, they are **not independent**. Either sequence them explicitly in the plan ("assumes `<other-slug>` has NOT yet landed") or tell the user the two should be merged. Keep the queue shallow.
3. Create the folder `ai/tasks/<slug>/`. Write `context.md` (Step 2) and `task.md` (Step 3) into it.

## Step 1b — Reference scan (mandatory for any change to existing code)

If this task **creates only new files** and touches nothing that already exists, skip this step.

Otherwise — i.e. the task modifies, renames, moves, or changes the signature/behavior of any **existing symbol, function, type, route, config key, or interface** — you must map its blast radius BEFORE writing `Files to Change`. This is the single biggest source of the "ping-pong" failure (executor trips over a dependency the plan never listed, writes `blockers.md`, you fix, it trips on the next one).

1. Search the codebase for every reference to the thing you are changing (`grep`/ripgrep, symbol search, import analysis).
2. Record the result. **Every dependent file the scan finds goes into `Files to Change`** (or, if it must stay untouched, into Constraints as "must preserve") — not just the primary file.
3. Note the scan's blind spots in Known Pitfalls: `grep` finds textual references but not dynamic dispatch, reflection, string-built calls, or cross-language boundaries. If any of those are plausible here, say so, so the executor double-checks at runtime instead of trusting the file list as complete.

## Step 2 — Write `ai/tasks/<slug>/context.md`

Fill this template completely. No placeholders left in the final file.

```markdown
# Task Context

## Plan provenance
- Planned: <YYYY-MM-DD>
- Based on: <git ref, e.g. `HEAD a1b2c3d`> — OR, if not using git: <list of the files this plan assumes the current state of>
<This is the snapshot the plan was written against. The executor re-checks it before running, so it can detect a plan that went stale while sitting in the queue behind another task.>

## Goal
<One sentence. The outcome that defines success.>

## Why
<2–4 sentences. Business reason, user value, or architectural motivation. Enough that the executor can make small judgment calls correctly without re-deriving intent.>

## Codebase Context
<Files the executor MUST read before writing code, each with a reason. Use exact repo-relative paths.>
- `ARCHITECTURE.md` — the project map; read first (invariant 0.4)
- `CONVENTIONS.md` — house rules + Known Pitfalls the executor must follow
- `path/to/file.ext` — existing pattern for X; mirror its structure
- `path/to/dir/` — module being extended; understand its public API
- <every dependent file surfaced by the Step 1b reference scan>
- ...

## Constraints
- Do NOT modify: <exact paths or globs>
- Must preserve: <APIs, behaviors, public contracts>
- Stack / version requirements: <if any>
- Style / conventions to follow: <linter, formatter, naming>

## Decisions and Rationale
<Technical choices already made. The executor does NOT revisit these.>
- Chose **X** over Y because <reason>.
- Using approach **A**, NOT approach B — B would seem reasonable but breaks <thing>.
- ...

## Known Pitfalls
<Things that look fine but will break, or non-obvious gotchas — including relevant entries lifted from CONVENTIONS.md's Known Pitfalls, and any blind spots of the Step 1b scan. Leave the section but write "None known." if empty.>
- ...

## Out of Scope
<Tempting adjacent improvements the executor must NOT do.>
- ...
```

## Step 3 — Write `ai/tasks/<slug>/task.md`

```markdown
# Current Task

## Summary
<One sentence describing what is being built/changed.>

## Files to Change
For each, exact path + action + what + pattern reference. Include EVERY file the Step 1b reference scan surfaced — not only the primary one.

### `path/to/file1.ext`
- **Action:** create | modify | delete
- **What:** <specific, surgical description of the change>
- **Pattern reference:** <file from Codebase Context to mirror, or "n/a">

### `path/to/file2.ext`
- **Action:** ...
- **What:** ...
- **Pattern reference:** ...

## Step-by-step Implementation
1. <Concrete step with file path and action>
2. <Concrete step>
3. ...

## Acceptance Criteria
<Each item must be objectively, mechanically checkable. No "code looks clean".>
- [ ] <criterion 1>
- [ ] <criterion 2>
- [ ] <criterion 3>

## Verification Commands
<Exact shell commands to run from repo root. Empty if truly not applicable.>
\`\`\`bash
<command 1>
<command 2>
\`\`\`

## Foundation updates (executor's final step — invariant 0.4)
<What the executor must refresh after the change, so the foundation never goes stale.>
- `ARCHITECTURE.md`: <which section to update if structure/components/data flow changed, or "no structural change expected">
- `DECISIONS.md`: <append an entry if a non-obvious choice is made — note the expected decision, or "none expected">

## Executor Rules — read before starting
- Follow this plan **literally**. The plan is the authority — not because a stronger model wrote it, but because it is explicit and verifiable. Do not improvise.
- Read `ARCHITECTURE.md` + `CONVENTIONS.md` before touching code (invariant 0.4).
- Where the plan diverges from the code in front of you, **reality wins**: stop and record a `blockers.md` — do not defer to the plan, and do not improvise around it.
- If anything is ambiguous, **STOP and ask the user**. Do not guess.
- If the plan itself is wrong (bad path, contradicts reality, unverifiable), do **NOT** patch it — record findings in this task's `blockers.md` and stop for `/revise_task`.
- If you see improvements outside this plan, do **NOT** implement them — list them in your final report.
- Touch only files listed in "Files to Change". Anything else requires asking.
- Do not change tests, configs, or dependencies unless this file says so.
- If you find a bug in existing code, note it for the report; do not fix it.
- Final step: update `ARCHITECTURE.md` / append `DECISIONS.md` per "Foundation updates".
```

## Step 4 — Quality self-check before saving

Before declaring the files written, verify each:

- [ ] No references to "this chat", "above", "discussed", "we decided" — all rationale is inline.
- [ ] Every path mentioned is concrete (no `<...>` placeholders).
- [ ] `## Plan provenance` is filled (date + git ref or file list).
- [ ] For a change to existing code: the Step 1b reference scan was run, and **every** dependent it found is in Files to Change or Constraints.
- [ ] Every "Files to Change" entry has Action + What + Pattern reference.
- [ ] Every Acceptance Criterion is objectively verifiable.
- [ ] Verification Commands are runnable as-is from repo root.
- [ ] Codebase Context lists every file the executor needs to read to understand patterns — not just files being changed.
- [ ] The plan is written for a weak executor: no step relies on the executor inferring something unstated.
- [ ] Decisions section explains why alternative approaches were rejected (so executor doesn't "improve" by reverting them).
- [ ] "Foundation updates" names which `ARCHITECTURE.md` section to refresh (or states no structural change), so the foundation cannot silently go stale.

If any check fails, fix the file before moving on.

## Step 5 — Confirm to user

After writing both files, output:
1. The two file paths (`ai/tasks/<slug>/context.md`, `ai/tasks/<slug>/task.md`).
2. A 3–5 bullet summary of what got captured.
3. If the queue now holds more than one task, list the queued slugs so the human knows what is pending — and flag any overlap in files between them.
4. The line: **"Готово. Открой новый чат и запусти `/run_task`."**

Do not start executing the task yourself. If the executor later reports the plan is defective (a `blockers.md` appears in the task folder), the fix path is `/revise_task`, not a fresh `/make_task`.
