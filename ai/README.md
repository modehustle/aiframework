# ai/ — the board, the archive, the investigations

`tasks/<slug>.md` is the board: one card per task — what, why, and how we will know it is
done. No plan and no snapshot of the code: whoever takes a card reads the foundation and the
code fresh. A card with `kind: master` is a project; its subtasks point at it with `parent`.
Only the human puts work here (`/make-task`); `/run-task` takes a card; `fraim task-seal`
closes it into `archive/tasks/` with one line of outcome. `fraim tasks` shows the board.

Drift is not counted here: it is code commits since `ARCHITECTURE.md` last moved, which
`fraim status` reads straight from git. `/prune` relocates superseded `DECISIONS.md`
entries into `archive/decisions_log.md` and leaves a `prune: ` commit as the anchor.

Nothing here is secret: it is tracked in git so the decision and task trail travels with
the repository.
