---
name: reconcile-task
description: "Close a /run-task session that drifted into live debugging — fold the unplanned changes back into the record and archive truthfully; but STOP and hand to /revise-task if the drift was structural, not surgical"
metadata:
  tier: capable
  version: 0.8.2
  source: fraim
---
# /reconcile-task — Seal a Drifted Execution Session

You are the **executor**, closing a `/run-task` that did not stay on rails. The plan was executed, but somewhere the task turned into **live debugging**: the operator fed in discoveries the plan never anticipated, edits landed that `task.md` did not authorize, and the code now diverges from the plan it is filed under. The operator has verified the result works. Your job is **not** to re-plan and **not** to build — it is to make the archive tell the truth, or to refuse and hand the task back if the drift was too big to seal this way.

> **The principle the family already holds: debug freely, but the archive must tell the truth.** A plan that says \"do NOT change X\" archived next to code that changed X is a silent lie unless the divergence is recorded. This workflow records it — or stops you from filing it at all.

> **This is not `/revise-task` and not `/prune`.**
> - `/revise-task` repairs a *defective plan so it can be re-run* — mid-flight. `/reconcile-task` closes a session where the plan was *already executed but drifted* — end-of-flight. (When the drift is structural, the gate below sends you to `/revise-task`.)
> - `/prune` reconciles the *whole foundation* against the *whole codebase*, periodically, proposing diffs. `/reconcile-task` reconciles *one task's record* against the code it just produced, now, and writes that record itself.

> Paths are **repo-relative to the project root** (the folder the agent has open). Never hardcode an absolute project path.

> **Deterministic actions belong to `fraim`, not to you.** This workflow ends at a gate
> (`fraim reconcile-seal`), and that gate is the *second* door out of a task — the same one
> `/run-task` uses, with one extra precondition. Archiving by hand is how a structural change
> gets filed as a minor divergence. No `fraim` — stop and say so.

## The gate — check it FIRST, before reconciling anything

You may seal-and-archive **only** if the drift was **surgical** — the live edits fixed *details the plan got wrong*, leaving the plan's shape and approach intact. If the drift was **structural** — it changed the shape — you do **not** archive; you hand the task to `/revise-task` (Section A).

> This gate measures the **shape of the drift, not whether it works.** \"The operator confirmed it works\" is **not** a pass. A structural change can work perfectly and still be the wrong thing to seal here, because it skipped the reference scan (blast-radius map) that `/make-task` and `/revise-task` exist to perform.

Apply the gate to the **delta from the plan** — only the edits that were NOT in `task.md`'s `## Files to Change`, or that broke a stated constraint (`Do NOT`, `Must preserve`). The drift is **surgical** only if EVERY one of these holds:

- [ ] **The plan's approach still holds.** The live edits corrected *values / details* — a wrong constant, URL, endpoint version, payload field, header, path — not the *strategy*. If the plan's diagnosis or approach itself was wrong, that is **structural**.
- [ ] **No changed contract.** No live edit changed a function signature, public interface, route, exported symbol, or data model that the plan did not already authorize.
- [ ] **No new component, module, or abstraction** appeared live that the plan never described.
- [ ] **No new logic-bearing file** outside the plan's `## Files to Change`, and **no new dependents** created that were never reference-scanned.
- [ ] **No swapped mechanism.** Adding a parameter or value is surgical; swapping the library, the control flow, or the data path is structural.
- [ ] **Data flow and component boundaries unchanged** — the request still moves through the same parts in the same order.

**The one-line test:** did the live edits change the *shape* (approach / contracts / boundaries), or only the *details inside the existing shape*? Shape → STOP (Section A). Details → reconcile (Section B).

> If any delta looks like an **unintended bug** rather than a deliberate fix, or you **cannot honestly explain why it was made** — do not seal it. STOP and ask the operator. (Same fork rule as `/prune`.)

---

## Section A — Structural drift: STOP and hand to `/revise-task`

The drift broke the gate. Reconciling now would **launder a structural change into the record as a minor divergence** — exactly the silent drift the system is built to prevent.

1. **Do not archive. Do not commit. Do not move the task folder.**
2. Run `fraim task-block <slug>` and fill the file it lays down, capturing the structural reality so the planner does not start from zero:
   - **What is wrong** — the plan's approach was defective: what it assumed → what the approach actually became live.
   - **Evidence** — the files touched live that were not in the plan, and the structural change each made.
   - **Suggested direction** — a reference scan of the blast radius of that change; it was made without one.
   - **What I did NOT change** — state it plainly.

   Delete the `fraim:stub` line when the sections are filled.
3. **STOP** and tell the operator:
   > *\"Дрейф структурный, не хирургический — это `/revise-task`, а не reconcile. То, что оно работает, не отменяет того, что изменение прошло мимо reference scan. Записал `blockers.md`. Запусти `/revise-task`, чтобы привести план к новому подходу (с reference scan'ом задетых зависимостей), затем `/run-task` — он проверит код против выправленного плана.\"*

> **Why bounce to `/revise-task` when the code already works:** a structural change made in the executor seat **skipped the blast-radius map**. `/revise-task` re-runs the reference scan and realigns the plan to the new approach, so plan and code agree again — and the re-run confirms nothing downstream was silently broken. That scan, not the typing, is what the wall protects.

---

## Section B — Surgical drift: reconcile the record, then archive

The drift was surgical. Make the archive honest, then close.

### Step 1 — Self-audit the delta
List every edit that was NOT in the plan, or that broke a stated constraint. For each: **what** you changed · **which plan expectation / constraint** it overrode · **what was discovered live** that forced it. This list drives Steps 2–4.

### Step 2 — `DECISIONS.md` (append-only, English, newest on top)
One entry per delta that **changed behavior**, each written by the verb — `fraim decide "<title>"`
with the body on stdin. A delta that reversed an earlier entry does **not** delete it: pass
`--supersedes "<the entry being replaced>"` and both stay in the log.

### Step 3 — `result.md` + final report: the divergence section
Run `fraim task-result <slug> --reconcile`. It lays down the report if the run never wrote one,
and adds the `## Divergence from plan` section — the one the seal gate reads. Fill it **as-is,
without smoothing**:
- what the plan diagnosed / assumed,
- what turned out to be true,
- which plan constraints were **consciously overridden under operator direction** during live debugging.

> An archive that reads cleaner than the session actually was is worse than no archive. The next `/prune` and the next planner rely on this being honest. That is why the gate refuses an empty or placeholder-laden divergence section: this section *is* the workflow.

### Step 4 — `CONVENTIONS.md` → `## Known Pitfalls / Lessons` (English)
From the deltas, lift the **generalizable** gotchas — the ones a future task in this codebase will hit again — one line each. **Exclude** one-off details specific to this task. This is the loop feed; do not let it become a dumping ground.

### Step 5 — `ARCHITECTURE.md` (conditional)
Surgical drift should not change structure. But if a corrected detail touched a fact recorded here (e.g. an external-interface endpoint or version), update that line. Otherwise state \"no structural change\".

### Step 6 — Leave bugs alone
Any `(bug)` flagged for the operator stays a `/make-task` candidate. Do not fix it here.

### Step 7 — Seal (the gate)
```sh
fraim reconcile-seal <slug>
```
It checks the same three preconditions as `fraim task-seal` — the task was executed, it is not
blocked, `## Foundation updated` is filled in — **plus** a filled `## Divergence from plan`. Then
it timestamps the archive directory, moves the folder whole, saves the point as
`reconcile: <slug> — sealed drifted session`, and reports what is left in the queue.

It refused → it named a precondition that is not met. Fix that and run it again. Do **not**
archive by hand instead: the refusal is the check, not an obstacle, and a hand-made archive is
exactly how a drifted session gets filed as if it had gone to plan.

### Step 8 — Self-check before declaring done
- [ ] Every behavioral delta is in `DECISIONS.md`; every reversal supersedes (not deletes).
- [ ] The divergence section names the overridden constraints and why — not smoothed.
- [ ] The gate was actually re-confirmed surgical — no structural delta slipped through as \"minor\".
- [ ] Generalizable gotchas proposed to `CONVENTIONS.md`; one-offs excluded.
- [ ] `(bug)` items left for `/make-task`, not fixed.

### Step 9 — Report
> *\"Сессия сведена и заархивирована в `<full path>`. Расхождений с планом: <N> (залогированы в DECISIONS / описаны в result.md). В Known Pitfalls добавлено: <N>. Осталось в очереди: <список slug или 'пусто'>.\"*

---

> You reconciled the record and archived. You did **not** re-plan and you did **not** do structural work — if the drift had broken the gate, you would have stopped and handed it to `/revise-task`. The wall holds: structural change is deliberate and reference-scanned, never emergent from live debugging.
