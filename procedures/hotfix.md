---
name: hotfix
description: "Apply a surgical micro-fix directly, bypassing the full make→run→archive cycle, within a strict mechanical ceiling"
metadata:
  tier: capable
  order: 8
---
# /hotfix — Surgical Micro-Fix

You are applying a **micro-fix** directly, without the full planner→executor ceremony. This is the system's deliberate pressure-relief valve: for a typo, a flipped operator (`AND`→`OR`), a wrong constant, a misspelled string, the full `/make-task`→`/run-task`→archive loop is absurd overhead. You read the rules, make one surgical change, log it, and commit.

> This valve trades documentation rigor for speed. The debt it creates is paid down later by `/prune`, which reconciles hotfix-era drift back into the foundation. That is why every hotfix is logged (below) — `/prune` and `/orient` count them.

> Paths are **repo-relative to the project root** (the folder the agent has open). Never hardcode an absolute project path.

## The ceiling — check it FIRST, before touching anything

A hotfix is allowed **only** if the change fits inside every one of these mechanical gates. These are not judgment calls — they are checks. If the change breaks **any** gate, it is not a hotfix → **STOP and tell the user to run `/make-task`.**

- [ ] **Single file.** The change touches exactly one file. Two or more files = a coordinated change with dependencies = `/make-task`.
- [ ] **No new functions, classes, or modules.** Adding an abstraction is a feature, not a fix.
- [ ] **No changes to a function signature, public interface, route, or exported contract.** Those ripple through the codebase and need a reference scan.
- [ ] **No new imports or dependencies.** A new import = a new capability = not a hotfix.
- [ ] **No new control structures** (no added `if`/`else` branches, loops, try/catch). Flipping an existing operator or condition is fine; adding new branching is not.
- [ ] **Soft tripwire: ~10 changed lines.** Not a hard limit — a \"stop and think\" signal. Over it, ask yourself honestly whether this is still a fix or has become a change. When in doubt, `/make-task`.

> The ceiling measures **blast radius, not importance.** A one-character edit to a security check passes the ceiling mechanically — its *importance* is caught separately by the mandatory `DECISIONS.md` line below.

> **Start strict.** When the ceiling sends a borderline case to `/make-task`, that is the safe error — slower, not dangerous. Loosen these gates later only once you have a feel for where they actually get in your way.

## Step 1 — Load the minimum context

- Read `CONVENTIONS.md` — the house rules, including `## Known Pitfalls / Lessons`. A one-line fix can still walk into a known gotcha.
- Read **only the relevant section** of `ARCHITECTURE.md` that covers the file you are touching — not the whole file. Enough to be sure the fix does not contradict the intended design.

If `CONVENTIONS.md` is missing, this project was never bootstrapped — STOP and tell the user.

## Step 2 — Make the change

Apply the surgical edit. Nothing else. The hard rules of `/run-task` still hold in spirit: no refactoring \"while you're here\", no adjacent cleanup, no fixing of other bugs you notice (note those for the user instead).

If, mid-change, you discover the fix actually needs a second file or a signature change — **stop.** It just broke the ceiling. Revert what you started and tell the user this is a `/make-task`, not a hotfix.

## Step 3 — Did it change behavior?

Two outcomes, and they decide whether `DECISIONS.md` is touched:

- **Pure cosmetic / typo** (comment, log string, formatting, dead-code removal — no change to what the program *does*): no `DECISIONS.md` entry needed.
- **Behavior changed** (any change to logic, output, validation, a value the program acts on — `AND`→`OR` qualifies): **append a one-line entry to `DECISIONS.md`** (append-only, newest on top). Ghost changes — behavior altered with no trail — are not allowed.

  ```markdown
  ## <YYYY-MM-DD> — hotfix: <one line>
  - Decision: <what changed and why, in one sentence>
  ```

## Step 4 — Log the hotfix (always)

Run whatever quick check is relevant first (the file still parses / the obvious command still works). Then log the fix — **every** hotfix, including pure typos:

```sh
fraim hotfix-log <file> "<one-line description>" <yes|no>
```

The last argument is whether behavior changed. The command appends the line in the exact format the drift counter reads, tells you how close you are to the pruning threshold, and commits the edited file together with the log and any `DECISIONS.md` line.

Do not write that line by hand. The watchman counts these entries and `/prune` resets them with a marker; an improvised format silently breaks the drift counter, and nobody notices until the foundation has already rotted.

## Step 5 — Report
- Report to the user in 2–4 lines: what file, what changed, behavior yes/no, log + DECISIONS updated, committed. No task folder, no archive — this path is intentionally lightweight.

> If the fix later turns out to have been bigger than a hotfix should have been, that is a signal to tighten how you judge the ceiling — and a hint that `/prune` is due.
