---
name: fraim
description: Control panel for the fraim workflow system. Use when the user asks where a project stands, what needs attention, what to do next, which projects have drifted, or how to install and update the workflow procedures. Routes to the right procedure and reads the deterministic project watchman.
metadata:
  version: 0.8.2
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

The JSON answer carries three things, and procedures read them instead of probing the
filesystem: `foundation` — each file as `missing` / `stub` / `filled` (a `stub` is an
empty scaffold: reading it means guessing, so stop); `tasks` — every queued slug with
`blocked` / `done` / `runnable`; `findings` — what needs a human, each with the action.

A `shape` finding means the project's foundation predates the current standard — laid down
before `AGENTS.md`/`CLAUDE.md`, before `ai/fraim.conf`, or before a section the verbs write
into. `fraim upgrade` brings it up to standard: additive, never overwriting content.

Exit codes: `0` healthy · `1` something needs the human · `2` project is not
under the system.

Report the verdict as-is. **Do not act on it** — name the procedure the user should
run and stop there. The one exception is housekeeping the user asks for: `fraim clean`
closes the loose ends whose answer is computable (foundation behind the standard,
investigations with an outcome, abandoned investigations, executed-but-unsealed tasks,
an unsaved foundation) and deliberately touches nothing that needs judgement — stale
plans, the queue, foundation drift. It prints its plan and asks before doing anything. Every mutating procedure in this system ends by asking the human,
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
| find out where a bug is, or whether X is feasible | `/investigate` | strong |
| reconcile the foundation with reality | `/prune` | strong |
| re-enter a project after a break | `/orient` | any |
| bring an existing project under the system | `/onboard` | strong |

The procedures are separate skills — invoke them by name. This skill does not
contain their text and must not paraphrase it.

## Working without a procedure

Most sessions are not a planned task — a question, a small fix, a look around, a change
whose shape appeared while doing it. **That is legitimate.** Do not force it into
`/make-task`, and do not announce a procedure you are not running. What still holds:

- invariant 0.4 — read the foundation first, fix it if the change made it wrong;
- **behaviour changed → `fraim decide "<title>"`** with the body on stdin; pure cosmetics need
  no entry. Do not hand-write the heading or the date — placement and format are the verb's;
- **save as you go**: when a coherent piece is done, not at the end of the session,
  `fraim commit fix \"<what changed>\" <path> <path>`. Those commits are the record of
  reactive work; there is no second log to keep.

Reactive work has **no size limit**. `/make-task` is not for \"this got big\" — it is for
**handing the work to someone outside this conversation** (a fresh chat, a cheaper
executor, tomorrow's user). That call is the human's, never yours. You are about to
change something you do not understand → `/investigate`.

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
| `fraim plan-seal SLUG` | checking a finished plan before it goes to an executor — **it can refuse** |
| `fraim decide "TITLE"` | writing an entry into `DECISIONS.md` (body on stdin, never argv) |
| `fraim pitfall "LINE"…` | adding lessons to `## Known Pitfalls / Lessons` in `CONVENTIONS.md` |
| `fraim task-seal SLUG` | archiving a finished task — **it can refuse** |
| `fraim reconcile-seal SLUG` | archiving a drifted session — **it can refuse** |
| `fraim investigate-new SLUG` | creating an investigation folder and its provenance stamp |
| `fraim investigate-seal SLUG` | archiving a finished investigation — **it can refuse** |
| `fraim prune-mark` | marking a completed prune by hand |
| `fraim stack-passport` | retyping the STACK.md schema |
| `fraim commit KIND TEXT PATH…` | `git add` + `git commit` by hand |
| `fraim undo [HASH]` | reaching for `git reset` / `git revert` |
| `fraim restore PATH…` | `git restore` / deleting scratch files by hand |

Four of them are **gates**: `plan-seal` will not release a plan with leftover placeholders, a
phrase pointing back at the planning chat, an empty section, empty verification, or a path that
does not exist; `task-seal` will not archive a task whose `result.md` leaves
`## Foundation updated` empty or unfilled; `reconcile-seal` adds a filled
`## Divergence from plan` to that; `investigate-seal` wants exactly one outcome branch and a
report on the cleanup. A refusal is the check doing its job — fix what it names and run it again.
Never archive by hand instead.

`fraim commit` and `fraim restore` take an explicit path list and have no \"everything\"
argument on purpose: a project folder also holds the user's unfinished work, their `.env` and
their data. **A verb touches what it changed, and nothing else.**

Git is a given here, not a skill the user is expected to have: `fraim scaffold` creates the
repository when there is none (never inside someone else's), the verbs make every save point,
and `fraim undo` takes one back as a counter-commit — history is never rewritten. Never tell
the user to run a git command; if something cannot be done through a verb, say so.

If `fraim` is not installed, **stop and say so** rather than reproducing the effect by hand.
A deterministic action has exactly one implementation.

## Other commands

| Command | What it does |
|---|---|
| `fraim init` | install / update / pick up a newly installed harness |
| `fraim upgrade` | bring an existing project's foundation up to the current standard |
| `fraim clean` | close every loose end whose answer is computable, in one pass |
| `fraim config` | what settings are in effect and where each came from |
| `fraim projects` | list, add or remove projects in the registry |
| `fraim doctor` | what is installed where, which version, what diverged |
| `fraim publish` | a copy of the project off this machine: check, create, push, verify |
| `fraim show NAME` | print a procedure's text (for environments without skills) |

`fraim publish` is the one command here that reaches the network, and what it does cannot be
taken back — a repository that was public for a minute was public. `fraim publish --check` is
yours to run freely: no network call, it reports what is installed, whether a copy exists,
whether the setup was ever finished, and whether the history carries a secret that must not
leave the machine. The publish itself is the human's: it prints a plan and asks, and through a
pipe without `--yes` it deliberately does nothing. **Never pass `--yes`, `--force` or
`--private` on your own initiative** — where the copy lives and who may read it is the user's
decision, not a default. `--private` in particular is an assertion about the world ("this
repository is private, and I accept that the findings travel into it"); only the person who owns
the repository can make it. What the command does with a secret found in the history depends on
exactly that: into a private copy it goes with an explicit acceptance, into a public one it does
not go at all.

Two of its refusals hand you a **ready-made brief** — a secret already in the history, and a
remote that carries work this machine does not have. When the user pastes one to you, it is
self-contained and it states its own limits; honour them. Both end in a rewrite or a merge the
system deliberately does not perform for anyone: `fraim` never rewrites history (`fraim undo`
is a counter-commit for exactly that reason), so cleaning a secret out of the past is an
external tool, run once, with the user's explicit yes — and the first step is never git at all,
it is rotating the key that was exposed.

## The one rule for you

The watchman notices; the human decides. Never run `/prune` or `/run-task`
because the status output suggested them — surface the line and wait.
