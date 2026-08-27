---
name: revise-task
description: "Repair a task plan the executor found defective, in place, without losing what was learned"
metadata:
  tier: strong
  version: 0.1.0
  source: fraim
---
# /revise-task — Repair a Defective Plan

You are the **planner**, back to fix a plan that did not survive contact with the code. The executor (`/run-task`) hit a defect, wrote a `blockers.md` into the task's folder, and stopped instead of improvising. Your job: amend that task's files **in place** so the executor can re-run cleanly — not to start over, and not to execute anything yourself.

> This workflow exists so the planner↔executor wall holds **even during correction**. The executor never patches its own plan; you do. You never write code; the executor does.

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
- If the change reverses a recorded decision → note that `DECISIONS.md` will need a superseding entry (the executor appends it as its final step; record the intent under \"Foundation updates\").

> If the user's answer reveals the goal itself changed, say so — that may be a *new* task (`/make-task`), not a revision. Do not silently expand scope.

## Step 3 — Amend the files in place

Edit only what the diagnosis requires. Keep both files self-contained (the executor still will not see this chat — same forbidden phrases as `/make-task`: \"as we discussed\", \"per the blockers\", etc.; fold any needed context inline). Keep planning to the floor: the re-run may land on a different, weaker executor model — do not make the repaired plan rely on inference.

- `context.md` — fix Constraints / Decisions / Codebase Context if the defect was rooted there. If you reverse a prior decision, update the Decisions section AND note the `DECISIONS.md` supersede under the task's \"Foundation updates\".
- `task.md` — fix the wrong steps, paths, Files to Change, Acceptance Criteria, or Verification Commands. Leave the correct parts untouched.

Record what changed at the top of `task.md`:

```markdown
## Revision <N> — <YYYY-MM-DD>
- Defect: <one line from blockers>
- Fix: <what was changed in the plan and why>
```

## Step 4 — Quality self-check (same bar as /make-task)

- [ ] The specific defect(s) in `blockers.md` are each addressed by a concrete change.
- [ ] No `<...>` placeholders; every path is real (re-verify the paths the executor flagged actually exist now).
- [ ] **`## Plan provenance` is refreshed** — new date, and the git ref / file-state the *repaired* plan is now based on — so the re-run is not falsely flagged stale by its own staleness check.
- [ ] No references to this chat or to the blockers — all needed context is inline.
- [ ] Acceptance Criteria and Verification Commands still match the (possibly changed) plan.
- [ ] \"Foundation updates\" still names what the executor must refresh.

If any check fails, fix it before moving on.

## Step 5 — Clear the blocker and hand back

1. Delete `ai/tasks/<slug>/blockers.md` (it is consumed — its content now lives in the revised plan and in the `## Revision` note). Do not archive a live task.
2. Output to the user:
   - The two amended file paths.
   - A 2–4 bullet summary: what was wrong, what you changed.
   - The line: **\"План починен. Запусти `/run-task` снова.\"**

Do not execute the task yourself.
