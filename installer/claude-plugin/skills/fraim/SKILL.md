---
name: fraim
description: Control panel for the fraim workflow system. Use when the user asks where a project stands, what needs attention, what to do next, which projects have drifted, or how to install and update the workflow procedures. Routes to the right procedure and reads the deterministic project watchman.
metadata:
  version: 0.4.0
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
| make a running service reachable from outside | `/expose` | capable |
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

## Deterministic verbs — call them, do not reproduce them

Mechanical, repeating actions belong to the CLI, not to you. Where a procedure names one of
these, run it: the format, the paths, the timestamps and the commit are not your business.

| Command | Replaces |
|---|---|
| `fraim scaffold` | hand-building the foundation files and `ai/` |
| `fraim task-new SLUG` | creating a task folder and writing its provenance stamp |
| `fraim task-block SLUG` | retyping the `blockers.md` shape |
| `fraim task-result SLUG` | retyping the `result.md` shape (`--reconcile`, `--reset`) |
| `fraim task-revise SLUG DEFECT FIX` | the revision record, the refreshed stamp, the consumed blocker |
| `fraim task-seal SLUG` | archiving a finished task — **it can refuse** |
| `fraim reconcile-seal SLUG` | archiving a drifted session — **it can refuse** |
| `fraim investigate-new SLUG` | creating an investigation folder and its provenance stamp |
| `fraim investigate-seal SLUG` | archiving a finished investigation — **it can refuse** |
| `fraim hotfix-log FILE DESC yes\|no` | appending to the drift log by hand |
| `fraim prune-mark` | writing the prune marker by hand |
| `fraim stack-passport` | retyping the STACK.md schema |
| `fraim commit KIND TEXT PATH…` | `git add` + `git commit` by hand |

Three of them are **gates**: `task-seal` will not archive a task whose `result.md` leaves
`## Foundation updated` empty or unfilled; `reconcile-seal` adds a filled
`## Divergence from plan` to that; `investigate-seal` wants exactly one outcome branch and a
report on the cleanup. A refusal is the check doing its job — fix what it names and run it again.
Never archive by hand instead.

`fraim commit` takes an explicit path list and has no \"everything\" argument on purpose: a
project folder also holds the user's unfinished work, their `.env` and their data. **A verb
saves what it changed, and nothing else.**

If `fraim` is not installed, **stop and say so** rather than reproducing the effect by hand.
A deterministic action has exactly one implementation.

## Other commands

| Command | What it does |
|---|---|
| `fraim init` | install / update / pick up a newly installed harness |
| `fraim config` | what settings are in effect and where each came from |
| `fraim projects` | list, add or remove projects in the registry |
| `fraim doctor` | what is installed where, which version, what diverged |
| `fraim show NAME` | print a procedure's text (for environments without skills) |

## The one rule for you

The watchman notices; the human decides. Never run `/prune`, `/run-task` or
`/hotfix` because the status output suggested them — surface the line and wait.
