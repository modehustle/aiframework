# CONVENTIONS — {{PROJECT}}

<!-- fraim:stub — this file is a scaffold. `/bootstrap` or `/onboard` fills it in and deletes this line. Until then `fraim status` reports the foundation as unfilled. -->

> **AGENT DIRECTIVE — load every session, follow it.**
> Register this as your agent's workspace rule so it auto-loads.

- Language: code, comments, docs in English. Chat may be in another language.
- Workflow: planner→executor→reviser. Task queue in `ai/tasks/<slug>/`; archive to `ai/archive/`.
  Commands: `/make-task`, `/run-task`, `/revise-task`, `/reconcile-task`, `/orient`, `/hotfix`, `/prune`.
- Before a task: read `ARCHITECTURE.md` + this file (including Known Pitfalls below).
  After: update them if changed; append any non-obvious choice to `DECISIONS.md`.
- Solo-operator note: you may be both planner (`/make-task`) and executor (`/run-task`),
  sometimes even running a strong model as executor. The temptation to improvise as
  executor is strongest then, because you remember the plan's intent. Resist it — if the
  plan is wrong, that is `blockers.md` + `/revise-task`, even on your own plan.
- Queue discipline: keep the queue shallow. If two queued tasks touch the same files they
  are NOT independent — sequence them explicitly or merge them, or the second plan goes
  stale when the first lands.
- Code style: <formatter / linter / naming / structure rules>
- Secrets: never commit `.env` or `data/` (see `.gitignore`).
- Deploy: never hand-edit host/system; use `/docker-deploy`.
- <project-specific rules>

## Known Pitfalls / Lessons
> Gotchas this codebase has cost an execution at least once. `/make-task` reads these so
> the planner does not walk a new task into the same trap. `/run-task` proposes additions
> here (on your approval) from its `(pitfall)` observations. `/prune` curates the list.
- None yet.
