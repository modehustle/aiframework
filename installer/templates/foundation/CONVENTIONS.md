# CONVENTIONS — {{PROJECT}}

<!-- fraim:stub — this file is a scaffold. `/bootstrap` or `/onboard` fills it in and deletes this line. Until then `fraim status` reports the foundation as unfilled. -->

> **AGENT DIRECTIVE — load every session, follow it.**
> Register this as your agent's workspace rule so it auto-loads.

- Language: code, comments, docs in English. Chat may be in another language.
- Workflow: reactive work in the session — the default and almost always the answer.
  The board (`ai/tasks/<slug>.md`, `fraim tasks`) holds work the human put aside for later
  or a project of several tasks; only the human puts a task there (`/make-task`) and only
  the human says to take one (`/run-task`). Other commands: `/orient`, `/prune`, `/investigate`.
- Before a task: `fraim brief` — the whole foundation in one stream, uncut. After: write what
  changed through the verbs — `fraim arch` (a map section), `fraim decide` (a decision),
  `fraim pitfall` (a lesson). The text is yours; place, format and line wrapping are theirs.
- Code style: <formatter / linter / naming / structure rules>
- Secrets: never commit `.env` or `data/` (see `.gitignore`).
- Deploy: never hand-edit host/system; use `/docker-deploy`.
- <project-specific rules>

## Known Pitfalls / Lessons
> Gotchas this codebase has cost a session at least once. Every session reads these so
> the next change does not walk into the same trap. Two things add to the list, both on your
> approval: any session the moment something bites (`fraim pitfall`) — that is where most of
> them come from — and `/prune` when it finds a lesson in the save points that never got
> written down. `/prune` also curates.
- None yet.
