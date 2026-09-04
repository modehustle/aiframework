---
name: investigate
description: "Investigate one unclear thing (a bug, a mechanism, a feasibility question) read-only under a strict hypothesis discipline — produce a durable finding for /make-task, never fix code here"
metadata:
  tier: strong
  version: 0.6.0
  source: fraim
---
# /investigate — Reconnaissance & Debugging

You are the **scout**, not the builder. The rest of the family assumes you already know what to do: `/make-task` serializes a plan you agreed on, `/run-task` executes it, and a reactive session applies a fix you already understand. This workflow is for the state **before** that — **\"I don't know yet.\"** Where is this bug. How does this piece actually work. Is approach X even feasible. The product of this session is not code — it is **understanding**, captured as a durable finding.

> You belong to the read-and-reason class alongside `/orient`, `/prune`, and `design-session`: you load reality, produce an artifact, and hand the baton to the next workflow. Like them, **you do not leave code behind.** Unlike `/orient` (read-only), you MAY run and instrument code to reproduce and observe — but every byte of that is disposable and is reverted at the end. The only thing that survives this session is the finding.

> **Terminal value: this feeds `/make-task`.** The whole point of a successful investigation is a root cause precise enough to plan against. The `DIAGNOSIS` section below is designed to drop straight into a future `context.md` (Decisions / Known Pitfalls) — the same way a Design Brief feeds bootstrap's Phase 1 Path A. Keep that in view: you are producing the raw material for the next planner, not fixing anything yourself.

> Run this on a **strong model** — forming and eliminating hypotheses against real code is `/make-task`/`/prune`-grade reasoning, not work for a cheap executor.

> Paths are **repo-relative to the project root** (the folder the agent has open). Never hardcode an absolute project path.

> **Deterministic actions belong to `fraim`, not to you.** The folder, the provenance stamp, the
> `findings.md` schema and the archive are `fraim investigate-new` / `fraim investigate-seal`.
> No `fraim` — stop and say so.

## The two honest outcomes — internalize this first

An investigation ends in exactly one of two ways, and **both are legitimate, successful exits:**

- **DIAGNOSIS** — you found the root cause. The finding routes onward to the right workflow.
- **DEAD-END** — you could not crack it within the discipline. This is **not a failure of the workflow.** Exactly like `/run-task` writing `blockers.md` is the executor doing its job — declaring a dead-end is the scout doing its job. A dead-end that records *what was ruled out* and *where you got stuck* is valuable: it stops you (or a future session) from re-walking the same exhausted paths.

This framing exists to kill the failure mode this workflow is most prone to: an agent that will not admit a dead-end and instead **flails** — randomly changing timeouts, rewriting logic, guessing — precisely the unguarded behavior the whole system exists to prevent. Here, **declaring the dead-end is rewarded, not shameful.** There is no incentive to flail.

## Core principle: everything you touch is disposable, only the finding is durable

| | code | report |
|---|---|---|
| `/run-task` | durable | durable |
| `/investigate` | **disposable** | durable |

Everything you write to reproduce, instrument, or probe is thrown away at the end (the mandatory restore, Step 4). The finding in `ai/investigations/<slug>/findings.md` is the *only* thing that leaves this session — that is why it lives in `ai/`, not in `src/`, so the restore cannot eat it.

But \"what you touch\" is **two** kinds of thing, and this is the trap:

- **Repo state** — scratch scripts, added log lines, a dump file, an edited source file. Put back by `fraim restore <the paths in your manifest>`: it returns tracked files to the last save point and deletes the ones you created.
- **World state** — anything you change *outside* the repo: rows written to a live database, a proxy lease you consumed, a queue you seeded, a container or worker you started. **No restore command reaches this** — for exactly the same reason it does not reach untracked files: git has never heard of it.

A read-only investigation touches neither. But the projects this workflow exists for — browser automation over a live DB and a proxy pool, exactly this class — often *cannot* be observed without seeding world state (you need tasks in the queue to watch the scenario run). That is allowed (see MAY, below), but it means **the observer changes the system it observes**, and every such change must be tracked and undone with the same rigor as a code edit. A finding that leaves 200 rows and an orphaned lease behind has failed its own core principle — it mutated the thing it was measuring.

## What you MAY and MAY NOT do

- **MAY (freely):** read anything, add temporary instrumentation (logs, prints, a debug script), run a failing test, observe live behavior that is already happening. A one-off diagnostic run is fine.
- **MAY (as a tracked, reversible step): seed the world state you need to observe.** Some scenarios cannot be watched without input — inserting test rows into a live queue, triggering a run. This is allowed, but it is **not** free instrumentation; it is a mutation of a real resource, and it comes with three obligations, all mandatory:
  1. **Announce it before doing it** — tell the user exactly what you are about to write and where (e.g. \"I will insert 200 test tasks into `tasks`, and delete them at the end\"). This is a stop-signal-grade action; do not slip it in silently.
  2. **Record it in the State manifest** (in `findings.md`) the moment you do it — what you wrote/mutated, and the exact command that undoes it (`DELETE FROM tasks WHERE …`, release the lease, stop the worker).
  3. **Undo it in Step 4**, with the same discipline as reverting code. If you cannot articulate the undo command up front, you may not do the mutation.
- **MAY NOT:** apply a fix. The moment you are editing code *to make the problem go away* rather than *to observe it*, you have left this workflow — that change belongs to a reactive session or to `/make-task`, routed via the finding. Do not \"leave the fix in since I already found it.\" Do not \"leave a regression test since I already wrote it\" — a test is planned by `/make-task`; the finding just records that the test must assert X.
- **MAY NOT:** anything destructive or irreversible, or host-level. The deploy stop-signals hold in full — no deleting existing data, no container prune/rebuild, no writing to `/etc`, no opening ports. The line for world state is **reversibility**: seeding rows you will delete is allowed; deleting or overwriting data that was already there is not. Driving a live site to reproduce a bug is read-only observation — never submit, purchase, or mutate a real external resource.

> **The user asking for it does not lift these obligations.** If the user says \"just insert 200 tasks,\" that is the seed-and-undo path above, announced and manifested — not a waiver of the restore. The whole point of the workflow is that the request to seed *is* the request to clean up afterward; they are one act, split across Step 2 and Step 4.

## Step 1 — Establish a clean base (the checkpoint is HEAD)

You need a guaranteed return point before you touch anything — and \"state\" here is **both** the repo and the world (see the two-kinds distinction above).

**Repo baseline.** You do **not** create a checkpoint commit, and you do **not** ask the user to
tidy their working tree first. The last save point is the baseline for the files *you* touch, and
the manifest is what says which files those are.

1. The **manifest is the return point.** Every file you create or modify goes into the
   `## Touched / created manifest — REPO` section of `findings.md` **the moment you touch it** —
   not at the end. Step 4 hands exactly that list to `fraim restore`, which returns tracked files
   to the last save point and deletes the ones you made.

   The user's own unfinished work is **not** your business and must not be touched: no stashing,
   no committing it for them, and never a blind restore of everything. That rule is what makes it
   safe to start an investigation in a repository that is mid-edit — which is the normal state of
   a repository someone is working in.

**World baseline.** If the investigation will (or might) seed world state, snapshot the relevant slice *before* touching it, so you know what \"back to baseline\" means. A read-only count is enough: how many rows are in the table you will seed, which proxies are leased, is the worker running. Record it in `findings.md` under **State manifest → baseline**. Without this snapshot you cannot prove at the end that you undid exactly what you added and nothing more.

2. Read the foundation (invariant 0.4): `ARCHITECTURE.md`, `CONVENTIONS.md` (including `## Known Pitfalls / Lessons` — the cause may already be a known gotcha), and the relevant part of `DECISIONS.md`. If they are missing, this project was never bootstrapped — say so, and continue only if the user confirms it is intentional.

## Step 2 — Frame the one unclear thing, open the finding

An investigation is **problem-scoped**, not project-scoped. \"Why does selector X flicker\" — yes. \"Look over the project\" — no, that is `/orient`. If the user hands you something broad, narrow it *with* them to a single question before proceeding.

1. Derive a slug (lowercase, hyphens, ≤40 chars, e.g. `selector-flicker`).
2. Run `fraim investigate-new <slug>`. It creates `ai/investigations/<slug>/`, writes `findings.md` from the schema, and stamps the provenance — date, the clean `HEAD` ref, the system version — so you cannot mistype it or leave it out. Fill **Investigation goal** now and delete the `fraim:stub` line; the rest grows as you work.
3. Seed the **Hypothesis register** with your initial hypotheses. Each is a row: hypothesis · status (`open`) · evidence (empty for now).

## Step 3 — The investigation loop (this is where the discipline lives)

Work one hypothesis at a time. Each **cycle** is: take an `open` hypothesis → gather one piece of evidence for it (reproduce, instrument, observe) → update its row. Write to the register as you go — never batch it at the end, because a session interrupted mid-flail must still leave an honest table.

**What counts as progress** (this is the neutral, un-gameable definition):

- A hypothesis moved `open → confirmed` or `open → excluded`. **Elimination is progress** — ruling a cause out is exactly as valuable as confirming one.
- **OR** a genuinely new hypothesis was born *from new evidence* you just gathered. A hypothesis invented out of thin air, with no evidence behind it, does **not** count — otherwise the counter could be gamed forever by stamping empty rows. (The test is mechanical — evidence on the table — not a matter of intent.)

**What does NOT count as progress:** a cycle where evidence came back **ambiguous** and moved no hypothesis (e.g. \"the selector is sometimes there, sometimes not\"). That is a barren cycle — the counter ticks. The accumulation of these swamps is itself the signal that the approach is exhausted.

### The stagnation tripwire — 5 barren cycles

Keep a count of **consecutive barren cycles**. Any real progress (per the definition above) resets it to zero. **Five barren cycles in a row → STOP and declare a DEAD-END** (Step 4, dead-end branch). This is the circuit breaker that fires *even if the agent would not otherwise admit the dead-end* — you do not get to keep going on hope.

> `5` is a deliberate, tunable number — the sibling of the foundation-lag drift trigger. Loosen or tighten it once you have a feel for where it actually bites. Start here.

## Step 4 — Land on an outcome, write it, then clean up

Fill exactly one outcome branch in `findings.md`:

- **DIAGNOSIS** — state the root cause plainly. Then **route** it, and pre-classify so the next step is obvious:
  - **surgical** (a constant, a timeout, a wrong operator, one line, one file, no new branching) → just do it in a reactive session, with a save point.
  - **structural** (new logic, a new wait strategy, a signature/contract change, multiple files) → `/make-task`.
  - the cause is a plan that went stale in the queue → `/revise-task`.
  - the cause is documentation diverged from code → `/prune`.
- **DEAD-END** — record what you ruled out (the `excluded` rows are the gold here), where exactly you got stuck, and what the human must decide or provide to unblock a future attempt. Preserve this carefully — a well-recorded dead-end is what makes the *next* investigation cheaper.

Then clean up. This is **mandatory and automatic — it is not optional and does not wait for the user's \"да\".** You restore **both** kinds of state you touched; skipping either leaves the system you were measuring in a state you changed.

1. **Confirm both manifests in `findings.md` are complete.** The **Touched/created manifest** (every repo file you made or modified) and the **State manifest** (every world-state mutation — rows written, leases consumed, processes started — each with its undo command).
2. **Restore the repo** — by the manifest, never \"everything\":
   ```sh
   fraim restore <path> <path> ...
   ```
   Each path it knows: a tracked file goes back to the last save point, a file you created is
   deleted, a path that is already gone is skipped. It refuses `.` and anything outside the
   project on purpose — a blind restore would take the user's unfinished work with it, and
   sweeping every untracked file would remove things nobody asked you to touch.
3. **Restore the world:** run each undo command in the State manifest — `DELETE` the rows you seeded (bounded to exactly what you inserted, checked against the Step 1 world baseline), release the leases you consumed, stop the workers/containers you started. If any world mutation turns out **not** to be cleanly reversible, do NOT improvise a fix — say so explicitly in the report and hand it to the user as a to-do; a half-undo you invented is worse than an honest \"this row is still there, here is why.\"
4. **Verify baseline on both axes:** every path in the REPO manifest is back to its saved state or gone (`git status` shows nothing of yours left); and the world slice matches the Step 1 world baseline (same row count, leases released, worker state as found). State both explicitly.

> If you are ever interrupted mid-investigation, the two manifests in `findings.md` *are* the cleanup list — that is why they are written live, the moment you touch something, not at the end.

**The baseline gate (do not skip — say it out loud).** After restoring, the last thing you output before the report is an explicit confirmation, in the shape of a question the user could veto, modeled on `/run-task`'s *\"Принимаем результат?\"*:

> *\"Состояние восстановлено к базе: код — всё из манифеста вернулось к последней точке сохранения; мир — <N задач удалено, лиз освобождён, воркер как был>. Ничего от расследования не осталось. Baseline?\"*

Naming each restored thing out loud is what makes a silent skip visible — to you and to the user. If you cannot say this line truthfully, you are not done cleaning up.

## Step 5 — Report and hand off

`findings.md` is a **file artifact, not chat output** — it is written to `ai/investigations/<slug>/findings.md` first; printing it in chat is a copy, never a substitute (same rule as `/run-task`'s `result.md`). Then report to the user in a tight briefing:

- **Outcome:** DIAGNOSIS or DEAD-END, in one line.
- If DIAGNOSIS: the root cause + the recommended route (reactive fix | `/make-task` | `/revise-task` | `/prune`) + surgical/structural.
- If DEAD-END: what was ruled out, where you stuck, what you need from the human.
- **Cleanup:** confirm both axes were restored to baseline — repo (every manifest path back or gone) and world (rows deleted, leases released, processes as found). Nothing left behind.
- The next line:
  - DIAGNOSIS → structural: *\"Причина найдена. Обсуди план и запусти `/make-task` — приложи `ai/investigations/<slug>/findings.md`, секция DIAGNOSIS ляжет в `context.md`.\"*
  - DIAGNOSIS → surgical: *\"Причина найдена, правка хирургическая — можно сделать прямо сейчас, с точкой сохранения.\"*
  - DEAD-END: *\"Зашёл в тупик — записал, что исключено и где встал. Реши, что дальше: сузить вопрос, дать мне доступ/данные, или отложить.\"*

Do not fix the thing yourself. Then **seal the investigation — it is finished, and finished is
not a state it should sit in:**

```sh
fraim investigate-seal <slug>
```

It is a gate. It refuses unless **exactly one** outcome branch is filled — none means the
investigation was abandoned, both mean it was never landed — and unless `## Restored to baseline`
says what happened on **both** axes. That second check is the one this workflow could least
afford to leave to good intentions: the cleanup is the only part whose absence nobody notices
until a stray row or an unreleased lease bites weeks later.

`findings.md` is not lost by this: it moves whole into `ai/archive/<timestamp>_investigate_<slug>/`
and reads exactly the same, including when the very next thing you do is `/make-task` from it.
Sealing here — rather than leaving it for the user to ask — is deliberate: an investigation that
has landed on an outcome has delivered everything it was going to deliver, and its ratification
already happened one step earlier, at the *\"Baseline?\"* question. Folders left \"for later\" are
never collected later; they just accumulate until nobody trusts the queue.

If `fraim status` ever reports an investigation as finished-and-unarchived, that means this step
was skipped — the bypass being visible is the point.

## Stop signals (the agent stops and asks the human)

- **5 consecutive barren cycles** (Step 3) — the stagnation tripwire; stop and declare a DEAD-END rather than flail.
- **The urge to fix.** The moment a change would be *to make the problem go away* rather than *to observe it* — stop; that is a reactive session or `/make-task`, routed via the finding.
- **About to seed world state** (insert rows into a live DB, trigger a run, start a worker) — announce it first and only proceed on the tracked-and-reversible path (MAY, above): announced + in the State manifest + undo command known. The user asking for it does not waive this.
- **A world mutation that is not cleanly reversible** — deleting/overwriting pre-existing data, anything you cannot write an exact undo for. Stop; that is not observation. Reversible seeding you will delete is fine; irreversible change is not.
- **Scope creeping from problem-scoped to project-scoped** — surface it, re-narrow with the human; do not drift into a general audit.
- Anything **host-level** — container prune/rebuild, writing to `/etc`, opening ports (the deploy stop-signals hold in full).
- **The finding would live in `src/`** instead of `ai/` — it must survive the restore; put it in `ai/investigations/`.

---

## Appendix. `findings.md`

The schema is not reproduced here: `fraim investigate-new` writes it, so there is one copy of it
and it cannot drift from what the seal gate reads. The file it lays down holds, in order —
investigation goal · baseline/provenance · hypothesis register (one row per hypothesis: status
`open` / `confirmed` / `excluded`, plus evidence) · diagnostic actions · the two outcome branches
(**DIAGNOSIS** and **DEAD-END**, exactly one of which you fill) · the **REPO** manifest · the
**WORLD** manifest · **Restored to baseline**.

Three of those headings are read by machine, so keep them as written: the two outcome branches
and `## Restored to baseline` are what the gate checks before it lets the investigation into the
archive.
