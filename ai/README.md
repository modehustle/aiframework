# ai/ — the planner→executor→reviser loop

`tasks/<slug>/` is the queue: `context.md` (WHY) + `task.md` (WHAT), plus `blockers.md`
if the executor found the plan defective. Several tasks may sit here, but only one is in
flight at a time. `/make-task` fills a folder; `/run-task` executes it; `/revise-task`
repairs it; `fraim task-seal <slug>` archives it to `archive/`.

Drift is not counted here: it is code commits since `ARCHITECTURE.md` last moved, which
`fraim status` reads straight from git. `/prune` relocates superseded `DECISIONS.md`
entries into `archive/decisions_log.md` and leaves a `prune: ` commit as the anchor.

Nothing here is secret: it is tracked in git so the decision and task trail travels with
the repository.
