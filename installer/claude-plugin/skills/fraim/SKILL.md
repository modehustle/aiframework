---
name: fraim
description: Control panel for the fraim workflow system. Use when the user asks where a project stands, what needs attention, what to do next, which projects have drifted, or how to install and update the workflow procedures. Routes to the right procedure and reads the deterministic project watchman.
metadata:
  version: 0.1.0
  source: fraim
---
# fraim — control panel

`fraim` keeps a project's context durable across chats and weeks. Each project
carries a **foundation** (`ARCHITECTURE.md`, `CONVENTIONS.md`, `DECISIONS.md`,
`ai/`) and work moves through explicit procedures instead of improvisation.

**Invariant 0.4** — the foundation is read FIRST before any task and updated LAST
after it. `DECISIONS.md` is append-only. A stale foundation is a bug, not cosmetics.

## When the user asks "where do things stand"

Run the watchman. It is deterministic — file reads, `git log` and mtimes, no model,
no network — so it is free to call every time.

```sh
fraim status          # human-readable verdict for the current project
fraim status --json   # same verdict, machine-readable
```

Exit codes: `0` healthy · `1` something needs the human · `2` project is not
under the system.

Report the verdict as-is. **Do not act on it** — name the procedure the user should
run and stop there. Every mutating procedure in this system ends by asking the human,
by design.

## Routing table

| The user wants | Procedure | Model tier |
|---|---|---|
| decide what to build, before any code exists | `/design-session` | strong |
| lay the foundation of a new authored project | `/bootstrap` | strong |
| box a stack in Docker and write its passport | `/docker-deploy` | capable |
| plan an agreed feature for a fresh-chat executor | `/make-task` | strong |
| execute a prepared plan from the queue | `/run-task` | cheap |
| repair a plan the executor called defective | `/revise-task` | strong |
| close a run that drifted into live debugging | `/reconcile-task` | capable |
| a one-file micro-fix, no ceremony | `/hotfix` | capable |
| find out where a bug is, or whether X is feasible | `/investigate` | strong |
| reconcile the foundation with reality | `/prune` | strong |
| re-enter a project after a break | `/orient` | any |
| bring an existing project under the system | `/onboard` | strong |

The procedures are separate skills — invoke them by name. This skill does not
contain their text and must not paraphrase it.

## Other commands

| Command | What it does |
|---|---|
| `fraim init` | install / update / pick up a newly installed harness |
| `fraim projects` | list, add or remove projects in the registry |
| `fraim doctor` | what is installed where, which version, what diverged |
| `fraim show NAME` | print a procedure's text (for environments without skills) |

## The one rule for you

The watchman notices; the human decides. Never run `/prune`, `/run-task` or
`/hotfix` because the status output suggested them — surface the line and wait.
