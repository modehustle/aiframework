---
name: make-task
description: "Capture the agreed plan into a new task folder under ai/tasks/ for handoff to a fresh-chat executor model"
metadata:
  tier: strong
  order: 5
---
# /make-task — Plan Handoff

You are the **planner**. You and the user have just agreed on a plan in this chat. Serialize it
into a new task folder `ai/tasks/<slug>/` holding two self-contained files — `context.md` and
`task.md` — so a different model, in a fresh chat that never saw this conversation, can execute
it correctly.

**How to read this file:** check `## GATES` before you write anything, then follow `## PROCEDURE`
in order. Each numbered line is one action. `(why: N…)` points to the reasoning in `## NOTES` —
read a note to understand a step, not in order to perform it. `## TEMPLATES` holds the exact
shape of both files you write.

> Paths are **repo-relative to the project root** (the folder the agent has open).
> Never hardcode an absolute project path.

---

## GATES

- **G1 — Self-containment.** The executor will NOT see this conversation. Every decision, path,
  constraint, and rationale must live in the files. Banned phrases: \"as we discussed\", \"the plan
  above\", \"the approach we chose\", \"per the conversation\". Context you cannot avoid referencing
  is context you must write into the files. (why: N1)
- **G2 — Plan to the floor.** Write for the **weakest plausible executor**. Do not rely on the
  executor to figure out a gap, infer an unstated step, or reason around an ambiguity.
  Over-specification is the safe error. (why: N2)
- **G3 — Add, never replace.** The queue may already hold tasks. You add one. Other task folders
  are not yours to touch, edit, or clean up.
- **G4 — Never execute.** You write the plan. Running it is `/run-task`'s job, in another chat.
- **G5 — A defective plan is `/revise-task`.** If an existing task came back blocked, it is
  repaired in place — not replaced by a fresh `/make-task`. (why: N3)

---

## PROCEDURE

### Step 0 — Load the foundation

0.1 Read `ARCHITECTURE.md` — the map; its components and data model anchor Codebase Context and
    Constraints.
0.2 Read `CONVENTIONS.md` — the house rules the executor must follow.
0.3 Read `## Known Pitfalls / Lessons` in `CONVENTIONS.md` and fold every entry relevant to this
    task into its Constraints or Known Pitfalls. (why: N4)
0.4 Read `DECISIONS.md`. Do not contradict a recorded decision silently.
0.5 No foundation files exist → tell the user the project was never bootstrapped, and continue
    only if they confirm that is intentional.

### Step 1 — Name the task, check the queue

1.1 Derive a slug for THIS task from its goal: lowercase, hyphens, ascii, ≤40 chars
    (e.g. `add-rate-limiter`).
1.2 List every folder in `ai/tasks/`.
1.3 `ai/tasks/<slug>/` already exists and this is a different task → pick a more specific slug.
1.4 `ai/tasks/<slug>/` already exists and this is the SAME task being reworked → STOP. Tell the
    user this is `/revise-task`, or that the old task must be finished or archived first.
1.5 Another folder holds a `blockers.md` → do not touch it, and say:
    *\"Задача `<other-slug>` ждёт `/revise-task`.\"*
1.6 Another folder holds a `result.md` and no `blockers.md` → do not touch it, and say:
    *\"Задача `<other-slug>` ждёт архивации.\"*
1.7 This task touches files another queued task also touches → they are not independent.
    Either state the ordering inside this plan (\"assumes `<other-slug>` has NOT yet landed\"),
    or tell the user the two should be merged. (why: N5)
1.8 Run `fraim task-new <slug>`. It creates `ai/tasks/<slug>/` and stamps `## Plan provenance`
    with today's date, the current git ref and the system version. Do not write that block
    by hand — those three values are what `/run-task` later uses to detect a stale plan,
    and they are exactly the kind of thing that gets forgotten. (why: N12)

### Step 1b — Reference scan

1b.1 This task creates only new files and touches nothing that exists → skip to Step 2.
1b.2 Search the codebase for every reference to each existing symbol, function, type, route,
     config key, or interface this task modifies, renames, moves, or changes. (why: N6)
1b.3 Put every dependent file the scan found into `Files to Change`.
1b.4 A dependent that must stay untouched goes into Constraints as \"must preserve\" instead.
1b.5 Record the scan's blind spots in Known Pitfalls: grep finds textual references but not
     dynamic dispatch, reflection, string-built calls, or cross-language boundaries. Name any
     that are plausible here, so the executor re-checks at runtime.

### Step 2 — Write the two files

2.1 Write `ai/tasks/<slug>/context.md` from TEMPLATE C.
2.2 Write `ai/tasks/<slug>/task.md` from TEMPLATE T.
2.3 Fill every section of both templates. Leave no `<...>` placeholder in the final files.

### Step 3 — Self-check before saving

Verify each line against the files you just wrote. Any failure → fix the file before continuing.

3.1 No reference to \"this chat\", \"above\", \"discussed\", or \"we decided\" — all rationale is inline.
3.2 Every path mentioned is concrete; no placeholders remain.
3.3 `## Plan provenance` is exactly as `fraim task-new` wrote it (Step 1.8) — date, basis,
    system version. You do not edit it and you do not retype it; if it is missing, the task
    folder was not created by the verb, and that is a defect to fix rather than to patch.
3.4 For a change to existing code: the Step 1b scan was run, and **every** dependent it found is
    in Files to Change or in Constraints.
3.5 Every `Files to Change` entry has Action, What, and Pattern reference.
3.6 Every Acceptance Criterion is objectively verifiable.
3.7 Verification Commands run as-is from the repo root.
3.8 Codebase Context lists every file the executor must read to understand the patterns — not
    only the files being changed.
3.9 No step relies on the executor inferring something unstated. (see G2)
3.10 The Decisions section says why the rejected alternatives were rejected. (why: N7)
3.11 `Foundation updates` names which `ARCHITECTURE.md` section to refresh, or states that no
     structural change is expected.
3.12 `Verification Commands` holds at least one command that exits non-zero on failure — or, if
     this change genuinely cannot be checked by a command, the manual check is written out AND
     an `Operator confirmed:` line is in Acceptance Criteria. The section is never empty. (why: N8)

### Step 4 — Confirm to the user

4.1 Print both file paths: `ai/tasks/<slug>/context.md` and `ai/tasks/<slug>/task.md`.
4.2 Summarize what got captured, in 3–5 bullets.
4.3 The queue now holds more than one task → list the queued slugs, and flag any overlap in files
    between them.
4.4 Say, verbatim: **\"Готово. Открой новый чат и запусти `/run-task`.\"**

---

## TEMPLATES

### TEMPLATE C — `ai/tasks/<slug>/context.md`

```markdown
# Task Context

## Plan provenance
- Planned / Based on / System: **already written by `fraim task-new`** — leave them alone.
  Without git, replace `Based on` with the list of files this plan assumes the state of.
<This is the snapshot the plan was written against. The executor re-checks it before running,
so it can detect a plan that went stale while sitting in the queue behind another task.>
<The System line snapshots the workflow system itself, not the code. Under a global install
the procedures update underneath a queued plan, so a plan written by an older /make-task can
be executed by a newer /run-task without anyone noticing. This line is what makes that
visible — the same staleness detection the system already applies to code, applied to itself.>

## Goal
<One sentence. The outcome that defines success.>

## Why
<2–4 sentences. Business reason, user value, or architectural motivation. Enough that the
executor can make small judgment calls correctly without re-deriving intent.>

## Codebase Context
<Files the executor MUST read before writing code, each with a reason. Exact repo-relative paths.>
- `ARCHITECTURE.md` — the project map; read first (invariant 0.4)
- `CONVENTIONS.md` — house rules + Known Pitfalls the executor must follow
- `path/to/file.ext` — existing pattern for X; mirror its structure
- `path/to/dir/` — module being extended; understand its public API
- <every dependent file surfaced by the Step 1b reference scan>

## Constraints
- Do NOT modify: <exact paths or globs>
- Must preserve: <APIs, behaviors, public contracts>
- Stack / version requirements: <if any>
- Style / conventions to follow: <linter, formatter, naming>

## Decisions and Rationale
<Technical choices already made. The executor does NOT revisit these.>
- Chose **X** over Y because <reason>.
- Using approach **A**, NOT approach B — B would seem reasonable but breaks <thing>.

## Known Pitfalls
<Things that look fine but will break, or non-obvious gotchas — including relevant entries lifted
from CONVENTIONS.md's Known Pitfalls, and any blind spots of the Step 1b scan. Keep the section
and write \"None known.\" if empty.>

## Out of Scope
<Tempting adjacent improvements the executor must NOT do.>
```

### TEMPLATE T — `ai/tasks/<slug>/task.md`

```markdown
# Current Task

## Summary
<One sentence describing what is being built or changed.>

## Files to Change
<Every file the Step 1b reference scan surfaced — not only the primary one.>

### `path/to/file1.ext`
- **Action:** create | modify | delete
- **What:** <specific, surgical description of the change>
- **Pattern reference:** <file from Codebase Context to mirror, or \"n/a\">

### `path/to/file2.ext`
- **Action:** ...
- **What:** ...
- **Pattern reference:** ...

## Step-by-step Implementation
1. <Concrete step with file path and action>
2. <Concrete step>

## Acceptance Criteria
<Each item objectively, mechanically checkable. No \"code looks clean\".>
- [ ] <criterion 1>
- [ ] <criterion 2>
- [ ] Operator confirmed: <what to look at, and what \"correct\" looks like>
      <Use this line only for a check no command can make. It moves verification to the human
      explicitly, instead of leaving it unstated.>

## Verification Commands
<At least one command that exits non-zero on failure, run from repo root. Never empty.
If this change genuinely cannot be checked by a command, write the manual check here instead,
and add a matching `Operator confirmed:` line to Acceptance Criteria above.>
\\`\\`\\`bash
<command 1>
<command 2>
\\`\\`\\`

## Foundation updates (executor's final step — invariant 0.4)
- `ARCHITECTURE.md`: <which section to update if structure, components, or data flow changed,
  or \"no structural change expected\">
- `DECISIONS.md`: <append an entry if a non-obvious choice is made — note the expected decision,
  or \"none expected\">

## Executor Rules — read before starting
- Follow this plan **literally**. The plan is the authority — not because a stronger model wrote
  it, but because it is explicit and verifiable. Do not improvise.
- Read `ARCHITECTURE.md` + `CONVENTIONS.md` before touching code (invariant 0.4).
- Where the plan diverges from the code in front of you, **reality wins**: stop and record a
  `blockers.md` — do not defer to the plan, and do not improvise around it.
- If anything is ambiguous, **STOP and ask the user**. Do not guess.
- If the plan itself is wrong (bad path, contradicts reality, unverifiable), do **NOT** patch it —
  record findings in this task's `blockers.md` and stop for `/revise-task`.
- If you see improvements outside this plan, do **NOT** implement them — list them in your report.
- Touch only files listed in \"Files to Change\". Anything else requires asking.
- Do not change tests, configs, or dependencies unless this file says so.
- If you find a bug in existing code, note it for the report; do not fix it.
- Final step: update `ARCHITECTURE.md` / append `DECISIONS.md` per \"Foundation updates\".
```

---

## NOTES

**N1 — Why self-containment is absolute.** The executor runs in a fresh chat, on a different
model, possibly weeks later. A plan that leans on this conversation is a plan that only works
today, for you. Every phrase pointing outward is a hole the executor will fall through.

**N2 — Why plan to the floor.** You do not choose who executes this plan — the user picks the
model at run time, and it may be small and cheap, or it may be strong. A strong model executing
an over-specified plan loses almost nothing; a weak model executing an under-specified plan
fails. This is also why the executor follows the plan literally: authority comes from the plan
being explicit, self-contained, and mechanically verifiable — not from who wrote it. Make it
worthy of that authority.

**N3 — Why a blocked task is not a new task.** A fresh `/make-task` would throw away the
`blockers.md` and everything the executor paid to learn, along with the parts of the plan that
were already right. `/revise-task` amends in place and keeps both.

**N4 — Why Known Pitfalls feed planning.** Those entries are gotchas earlier executions paid
for. A plan that walks a new task into a known trap is a defective plan, and the executor will
pay for it a second time.

**N5 — Why overlapping queued tasks are not independent.** Whichever lands first moves the code
under the other, and the second plan's provenance check will then flag it stale — or worse, it
will not, and the executor will mirror a pattern that no longer exists. Keep the queue shallow.

**N6 — Why the reference scan is mandatory.** This is the single biggest source of ping-pong:
the executor trips over a dependency the plan never listed, writes `blockers.md`, you fix it, it
trips on the next one. Mapping the blast radius once, before writing `Files to Change`, is what
prevents the whole cycle.

**N7 — Why record the rejected alternatives.** Without them, a capable executor will look at
approach B, find it reasonable, and \"improve\" the plan by reverting your decision — silently,
and with good intentions.

**N8 — Why verification can never be empty.** \"Empty if truly not applicable\" is an escape a
weak model under pressure will take, and a plan with no check produces a report whose ✓ marks
mean nothing — which `/prune` will later read as ground truth. There is no such thing as an
unverifiable task; there are tasks whose verification belongs to the human. Saying that out loud
in an `Operator confirmed:` line is honest. Silence is not.
