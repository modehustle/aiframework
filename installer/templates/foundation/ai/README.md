# ai/ — the planner→executor→reviser loop

`tasks/<slug>/` is the queue: `context.md` (WHY) + `task.md` (WHAT), plus `blockers.md`
if the executor found the plan defective. Several tasks may sit here, but only one is in
flight at a time. `/make-task` fills a folder; `/run-task` executes it; `/revise-task`
repairs it; `fraim task-seal <slug>` archives it to `archive/`.

`hotfix_log.md` counts drift — one line per `/hotfix`. `/prune` resets the count with a
`--- pruned <date> ---` marker and relocates superseded `DECISIONS.md` entries into
`archive/decisions_log.md`.

Nothing here is secret: it is tracked in git so the decision and task trail travels with
the repository.
