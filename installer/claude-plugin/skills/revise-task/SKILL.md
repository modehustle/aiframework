---
name: revise-task
description: "Repair a task plan the executor found defective, in place, without losing what was learned"
metadata:
  tier: strong
  version: 0.8.1
  source: fraim
---
# /revise-task — Repair a Defective Plan

You are the **planner**, back to fix a plan that did not survive contact with the code. The executor (`/run-task`) hit a defect, wrote a `blockers.md` into the task's folder, and stopped instead of improvising. Your job: amend that task's files **in place** so the executor can re-run cleanly — not to start over, and not to execute anything yourself.

> This workflow exists so the planner↔executor wall holds **even during correction**. The executor never patches its own plan; you do. You never write code; the executor does.

> **Deterministic actions belong to `fraim`, not to you.** The revision record, the refreshed
> provenance stamp and the consumed blocker are one command (Step 5) — not three things to
> remember. No `fraim` — stop and say so.

## Core principle: amend, don't restart

The point is to preserve everything that was right and the findings the executor paid for. You **edit** `ai/tasks/<slug>/context.md` and `ai/tasks/<slug>/task.md`; you do **not** archive them or create a new task. A fresh `/make-task` would throw away the blockers and the good parts of the plan — that is the wrong tool here.

## Step 1 — Find the blocked task, load everything

1. Read `ARCHITECTURE.md` + `CONVENTIONS.md` + `DECISIONS.md` — the foundation (invariant 0.4). Read the `## Known Pitfalls / Lessons` section too — the defect may already be a known gotcha.
2. **Scan the queue** `ai/tasks/` for folders containing a `blockers.md`:
   - **None** → **STOP.** Tell the user: \"Нет заблокированных задач. Изменить план новой задачи — `/make-task`; исполнить готовую — `/run-task`.\"
   - **One** → that is `<slug>`.
   - **Several** → list the blocked slugs and ask which to repair (or let the user name it: `/revise-task <slug>`).
3. For the chosen `<slug>`, read: `ai/tasks/<slug>/blockers.md` (the executor's findings), then `context.md` and `task.md` (the plan being repaired).

## Step 2 — Diagnose with the user

From the blockers, state plainly **what was wrong and why**, then converge with the user on the fix. Treat the executor's \"Suggested direction\" as a hint, not a decision.

- If the defect is a wrong/missing path or a small ambiguity → likely a surgical edit.
- If the defect is \"the approach won't work\" or scope changed → the fix may touch decisions in `context.md`, not just steps.
- If the defect is \"the plan went stale\" (the code moved under it while it waited in the queue) → re-run the reference scan against the current code; the fix is to realign Codebase Context / Files to Change with reality and refresh the provenance stamp.
  First confirm the staleness is real: `fraim status --json` names the files that moved under this plan. A `stale-plan` finding at severity `info`, or none at all with HEAD simply further along, means the queue moved and this plan's files did not — there is nothing to realign, and re-stamping provenance to hide the distance is the one repair that makes the next check lie.
- If the change reverses a recorded decision → note that `DECISIONS.md` will need a superseding entry (the executor appends it as its final step; record the intent under \"Foundation updates\").

> If the user's answer reveals the goal itself changed, say so — that may be a *new* task (`/make-task`), not a revision. Do not silently expand scope.

## Step 3 — Amend the files in place

Edit only what the diagnosis requires. Keep both files self-contained (the executor still will not see this chat — same forbidden phrases as `/make-task`: \"as we discussed\", \"per the blockers\", etc.; fold any needed context inline). Keep planning to the floor: the re-run may land on a different, weaker executor model — do not make the repaired plan rely on inference.

- `context.md` — fix Constraints / Decisions / Codebase Context if the defect was rooted there. If you reverse a prior decision, update the Decisions section AND note the `DECISIONS.md` supersede under the task's \"Foundation updates\".
- `task.md` — fix the wrong steps, paths, Files to Change, Acceptance Criteria, or Verification Commands. Leave the correct parts untouched.

Do **not** write the revision record or touch `## Plan provenance` by hand — Step 5 writes both,
numbered and stamped, in one command. Your job here is the content of the plan itself.

## Step 4 — Quality self-check (same bar as /make-task)

- [ ] The specific defect(s) in `blockers.md` are each addressed by a concrete change.
- [ ] No `<...>` placeholders; every path is real (re-verify the paths the executor flagged actually exist now).
- [ ] The repaired plan is consistent with the code **as it is now** — Step 5 refreshes the provenance stamp to this moment, and a stamp that says \"now\" over a plan written against last week's code is a lie the staleness check can no longer catch.
- [ ] No references to this chat or to the blockers — all needed context is inline.
- [ ] Acceptance Criteria and Verification Commands still match the (possibly changed) plan.
- [ ] \"Foundation updates\" still names what the executor must refresh.

If any check fails, fix it before moving on.

## Step 5 — Clear the blocker and hand back

1. Close the revision — one command, and the only way this workflow ends:

   ```sh
   fraim task-revise <slug> "<the defect, one line from blockers>" "<what you changed in the plan>"
   ```

   It refuses if there is no `blockers.md` (nothing to repair — that is `/make-task`). Otherwise it
   writes the numbered `## Revision <N>` record at the top of `task.md`, refreshes `## Plan
   provenance` with today's date, the current git ref and the system version, consumes
   `blockers.md` **last**, and saves the repair as one point. Do not do any of that by hand: a
   stale stamp on a repaired plan means the watchman keeps calling it stale, and a blocker removed
   before the stamp is refreshed means an interrupted revision looks runnable when it is not.
2. Output to the user:
   - The two amended file paths.
   - A 2–4 bullet summary: what was wrong, what you changed.
   - The line: **\"План починен. Запусти `/run-task` снова.\"**

Do not execute the task yourself.
