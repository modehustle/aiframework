---
description: Pick a task from the ai/tasks/ queue, execute it literally, then archive on user approval
---

# /run_task — Execute Prepared Task

You are the **executor** in the project's planner→executor→reviser loop (see `project_bootstrap_workflow.md`, Phase 5). A planning pass — typically a stronger model, though that is not what gives the plan its authority — has written a precise, self-contained plan into the queue at `ai/tasks/<slug>/`. Your job: pick one task, execute it literally, verify it, refresh the foundation, write and commit the result, and archive it when the user asks.

**Where authority comes from.** You follow the plan literally because it is explicit, self-contained, and mechanically verifiable — **not** because of who or what wrote it. This matters at the one moment it ever matters: when something looks off. The rule then is **reality wins** — where the plan diverges from the code in front of you, you do not defer to the plan and you do not improvise around it. You stop and hand it back (see the Plan-defect protocol). A capable executor that notices the plan is wrong is doing its job by raising a blocker, not by quietly "fixing" the plan.

You will NOT improvise. You will NOT "improve" the plan. If anything is unclear, you stop and ask.

> Paths are **repo-relative to the project root** (the folder Cascade has open). Never hardcode an absolute project path.

## Step 1 — Load the foundation, then pick a task

1. Read `ARCHITECTURE.md` + `CONVENTIONS.md` first — the project map and house rules (invariant 0.4). If they are missing, this project was never bootstrapped — STOP and tell the user to run `project_bootstrap_workflow.md`.
2. **Scan the queue** `ai/tasks/` for task folders and choose one:
   - **None** → **STOP.** Tell the user: "Очередь пуста. Запусти `/make_task` в чате планирования."
   - If the user named a task with the command (e.g. `/run_task <slug>`), use `ai/tasks/<slug>/`.
   - **Exactly one runnable task** → use it.
   - **Several** → list the runnable slugs and ask which to execute.
   - A folder containing `blockers.md` is **not runnable** — it is paused awaiting `/revise_task`. Exclude it from the choices and say so.
   - A folder containing `result.md` (and no `blockers.md`) is **not runnable** — it is a finished task awaiting archive (Step 9). Exclude it from the choices and say so. (`blockers.md` takes precedence: if a folder somehow has both, treat it as blocked.)
   - If the user's message asks to **archive** a finished task (a folder with `result.md`, e.g. `/run_task archive <slug>` or just "архивируй `<slug>`"), skip execution and go straight to **Step 9**.
3. For the chosen `<slug>`: if `ai/tasks/<slug>/blockers.md` exists, **STOP** and tell the user to run `/revise_task` on it first.
4. Read, in order: `ai/tasks/<slug>/context.md` (provenance, why, constraints, decisions), then `ai/tasks/<slug>/task.md` (what, files, steps, criteria). If either is missing or empty, treat it as a plan defect (protocol below).

## Step 2 — Load codebase context

Read **every file** listed under `## Codebase Context` in the task's `context.md`. These define the patterns you must mirror. Do not skip any. Do not skim.

If a referenced file does not exist or is empty, this is a **plan defect** — follow the Plan-defect protocol below; do not guess a replacement path.

## Step 3 — Acknowledge and reconcile

Output a brief understanding (5–8 bullets total):
- Goal in your own words.
- Files you will change.
- Patterns you will follow (with source file).
- Verification commands you will run.

If the user wrote any extra message in this chat alongside `/run_task`:
- If compatible with the plan → incorporate it as additional detail, mention how.
- If it conflicts with the plan → **flag the conflict explicitly and ask**. Do not silently merge.

## Step 4 — Sanity check (BEFORE writing any code)

Ask yourself:
- Is anything in the plan ambiguous?
- Does any referenced file path not exist?
- Is any Acceptance Criterion unverifiable as written?
- Does any step depend on information not in the files?
- Does the plan contradict `ARCHITECTURE.md` / `CONVENTIONS.md` / reality of the code?

**Then run the staleness check** — a plan can rot while it waits in the queue behind another task that changed the same files:
- Read `## Plan provenance` in `context.md`. Compare its basis (git ref, or the listed files' current state) against the code now. Has anything the plan depends on changed since it was planned?
- Re-open the `## Codebase Context` files and confirm the **patterns the plan tells you to mirror still hold**. If a pattern the plan relies on has moved or changed, the plan no longer matches reality.

If **YES to any** (including "the plan went stale") → it is a **plan defect**. Do not guess, do not start coding → follow the Plan-defect protocol.

If all clear → proceed.

### Plan-defect protocol (the plan is wrong, not your execution)

This is the one escape hatch that keeps you from improvising. Use it whenever the plan cannot be executed as written (wrong/missing path, ambiguity, unverifiable criterion, contradicts the code or foundation, or went stale against its provenance).

1. **Do not patch the plan and do not code around it.** Repairing the plan is the planner's job.
2. Write `ai/tasks/<slug>/blockers.md` capturing what you learned, so the fix does not start from zero:
   ```markdown
   # Blockers
   ## What is wrong
   - <defect 1: which step/file, and why it cannot be executed as written>
   ## Evidence
   - <command output / actual file contents / the real path that exists instead>
   ## What I did NOT change
   - <state that no code was written, or list exactly what was, if you had already started>
   ## Suggested direction (optional, for the planner)
   - <a hint, not a decision>
   ```
3. **STOP** and tell the user: *"План `<slug>` невыполним как написан. Записал `ai/tasks/<slug>/blockers.md`. Запусти `/revise_task` (в этом или новом чате), чтобы починить план, затем `/run_task` снова."*
4. Do not archive. Do not continue.

## Step 5 — Execute step by step

Work through `## Step-by-step Implementation` in order. For each step:
- Make the change exactly as specified.
- Mirror patterns from referenced files.
- Stay strictly within `## Files to Change`.

Hard rules — violating any is a failure of this workflow:
- **No features not in the plan**, even if obvious.
- **No refactoring of adjacent code** "while you're there".
- **No changes to tests, configs, dependencies, lockfiles** unless the plan says so.
- **No file outside "Files to Change"** without asking the user first.
- **No fixing of existing bugs** — note them for the report instead.
- **No silent assumptions** — if a step is underspecified, stop and ask.

## Step 6 — Verify

Run every command in `## Verification Commands` and capture output verbatim.

Walk through `## Acceptance Criteria` one by one:
- For each, point to concrete evidence (command output, file content, behavior) that proves it.
- If you cannot prove it, mark it failed. Do not pretend.

## Step 6b — Update the foundation (invariant 0.4)

Before reporting, do the `## Foundation updates` from the task's `task.md`, unprompted:
- If the change altered structure, components, data flow, or interfaces → **update `ARCHITECTURE.md`**.
- If you made (or the plan recorded) a non-obvious choice → **append an entry to `DECISIONS.md`** (append-only, newest on top).
- If nothing structural changed, state that explicitly in the report.

This is what keeps context always-current; skipping it is a bug, not a shortcut.

## Step 7 — Write the report, save it, commit (unconditional)

Produce the structured report below. **The report is a file artifact, not chat output.** You write it to `ai/tasks/<slug>/result.md` FIRST; printing it in chat is a *copy* of that file, never a substitute. A report that lives only in chat is lost the moment the chat closes — and this file is exactly what `/orient` reads for "recent history" and what `/prune` reads later. The `## Out-of-plan observations` — every `(pitfall)`, `(bug)`, and `(one-off)` — live in this file and nowhere else, so it is the only durable record of them. Do not treat printing the report in chat as completing this step.

Produce a structured report:

```
## Status
✅ complete | ⚠️ complete with caveats | ❌ blocked

## Changed files
- `path/to/file1` — <one-line summary>
- `path/to/file2` — <one-line summary>

## Verification
- [x/✗] Criterion 1 — <evidence>
- [x/✗] Criterion 2 — <evidence>
...

## Command output
<verbatim, trimmed only if huge>

## Foundation updated
- `ARCHITECTURE.md`: <what changed | no structural change>
- `DECISIONS.md`: <entry appended | none needed>

## Out-of-plan observations
<Improvements / bugs / smells you noticed but did NOT touch. CLASSIFY each one:>
- (one-off) <a detail specific to this task, no wider lesson> — stays in this report only.
- (pitfall) <a generalizable gotcha about THIS codebase the planner should have known, e.g. "X must be registered before Y or it silently no-ops"> — candidate for CONVENTIONS.md.
- (bug) <a real defect in existing code> — for the user to schedule via /make_task; not fixed here.
<Empty if none.>

## Questions for the user
<If any. Empty if none.>
```

**Write it to disk, then commit — do not wait for acceptance.**

1. Write the report above verbatim into `ai/tasks/<slug>/result.md`.
2. Print a copy of it in the chat.
3. **Commit now, unconditionally** — this is the save point that must never be skipped, and it does not depend on the user's "да". Stage the changed code, any `ARCHITECTURE.md` / `DECISIONS.md` updates from Step 6b, and `result.md`. Make one commit:
   - Status ✅ → `task: <slug> — <one-line summary>`
   - Status ⚠️ → `task: <slug> — <one-line summary> (caveats: <one line>)`
   The caveat rides in the commit message on purpose: `git log --oneline` then shows at a glance which save points were clean and which carried a tail. A committed "⚠️ with caveats" snapshot is an honest, recoverable point — strictly better than an uncommitted one.
   If the project does not use git, skip the commit silently.

The report is now saved and committed regardless of what happens next. Then ask: **"Принимаем результат?"**

## Step 8 — Interpret the answer; on acceptance, feed the loop

Wait for the user's response. Distinguish three cases:

- **Execution was imperfect, plan is fine** (a step done wrong, a criterion not met) → iterate from Step 5. The next pass ends in its own Step 7 commit on top; the earlier snapshot stays in history as a fallback. (Re-running Step 7 overwrites `result.md`.)
- **The plan itself is wrong** (scope changed, approach won't work) → follow the Plan-defect protocol from Step 4: write the task's `blockers.md`, and **delete the now-misleading `result.md`** (this task is not done). `blockers.md` then takes precedence in the queue scan, so the task reads as blocked, not done. Hand to `/revise_task`.
- **Accepted** (`да`, `yes`, `ok`, `принято`, etc.; anything ambiguous → ask again) → feed the loop, below. **Do NOT archive** — archiving is a separate, user-initiated step (Step 9).

**Feed the loop (on acceptance).** For each `(pitfall)` in your Out-of-plan observations, propose a single one-line addition to `## Known Pitfalls / Lessons` in `CONVENTIONS.md` and ask the user to approve it (yes / edit / skip). This is how a lesson the executor paid for reaches the next planner — `/make_task` reads that section. `(bug)` items are only listed for the user; do not act on them. `(one-off)` items stay in the report only. Do not let this section grow unreviewed — `/prune` curates it later.

- If one or more lines are approved → append them to `CONVENTIONS.md`, then **commit** them as their own save point: `task: <slug> — pitfalls to CONVENTIONS`. A separate commit is correct here, not waste: "recorded house-rule lessons" is a distinct act from "executed the task", and commits are additive and free in this workflow.
- If nothing is approved (or there were no pitfalls) → no commit; say so.

The task now sits in the queue with its `result.md` — finished, awaiting your archive. Tell the user it can be archived now or later, in this chat or a fresh one (Step 9).

## Step 9 — Archive (user-initiated)

Run this **only when the user asks to archive** (e.g. "архивируй", "archive it") — never automatically on acceptance. This can happen right after Step 8, or in a later/fresh chat where `/run_task` was invoked with an archive request (see Step 1). The task being archived is the one whose folder holds a `result.md` (name it if several qualify).

1. Create directory: `ai/archive/<YYYY-MM-DD_HHMM>_<slug>/` using current local time.
2. Move the whole task folder's contents there: `context.md`, `task.md`, `result.md` (and any leftover `blockers.md`) → `ai/archive/<dir>/`.
3. Remove the now-empty `ai/tasks/<slug>/` folder.
4. Verify `ai/tasks/<slug>/` no longer exists; other queued tasks are untouched.
5. **Commit** the move as a save point: `archive: <slug>`. If the project does not use git, skip silently.
6. Confirm to user: **"Архивировано в `<full path>`. Осталось в очереди: <список slug или 'пусто'>."**

If archiving fails at any step, stop and report the error — do not leave the workspace in a half-archived state.
