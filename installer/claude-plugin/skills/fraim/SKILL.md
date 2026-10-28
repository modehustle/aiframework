---
name: fraim
description: How to work in a project under the fraim workflow system — read this whenever a project has ARCHITECTURE.md / AGENTS.md / ai/, and whenever the user mentions tasks, the board, a project of several tasks, the backlog or open questions, decisions, the foundation, or asks where things stand and what to do next. Lists the CLI verbs that read and write the foundation, maps the user's words to procedures, and reads the deterministic watchman.
metadata:
  version: 0.10.0
  source: fraim
---
# fraim — how to work here

`fraim` keeps a project's context durable across chats and weeks. Each project
carries a **foundation** (`ARCHITECTURE.md`, `CONVENTIONS.md`, `DECISIONS.md`,
`ai/`). Work is reactive — the human writes, you do it in this session — and a few
procedures exist for work of a particular shape.

**Start with `fraim brief`.** It prints the whole foundation, the board and the list of
verbs in one stream, uncut, and says so at the end. Look things up with `fraim find`
(2–4 keys, both languages, word stems). Write the foundation through the verbs below, never
by hand.

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
empty scaffold: reading it means guessing, so stop); `tasks` — every open card with its
`kind` (`task` / `master`) and `parent`; `findings` — what needs a human, each with the action.

A `shape` finding means the project's foundation predates the current standard — laid down
before `AGENTS.md`/`CLAUDE.md`, before `ai/fraim.conf`, or before a section the verbs write
into. `fraim upgrade` brings it up to standard: additive, never overwriting content.

Exit codes: `0` healthy · `1` something needs the human · `2` project is not
under the system.

Report the verdict as-is. **Do not act on it** — name the procedure the user should
run and stop there. The one exception is housekeeping the user asks for: `fraim clean`
closes the loose ends whose answer is computable (foundation behind the standard,
investigations with an outcome, abandoned investigations, tasks in the old format,
an unsaved foundation) and deliberately touches nothing that needs judgement — the
board, foundation drift. It prints its plan and asks before doing anything. Every mutating procedure in this system ends by asking the human,
by design.

## What the human wants

The human talks; they do not type commands. Recognise the intent:

| The human's intent | What it means |
|---|---|
| set work aside to do later, not now | `/make-task` — an ordinary task |
| start something large that will take several tasks (a project) | `/make-task` — a master task |
| know what is pending, planned or in progress | `fraim tasks` — report it |
| work on a specific task from the board | `/run-task` |
| keep an open question without acting on it | `fraim backlog-new` after the human confirms / `fraim backlog` to review |
| have work done by cheaper models, or split into parallel directions | `/conductor` |
| get back into the project after a break | `/orient` |
| understand a behaviour nobody can explain, or check that something is feasible | `/investigate` |
| bring the documents back in line with the code | `/prune` |

Judge the intent, in whatever language and wording it comes. Anything else the human asks for is work to do now, in this session. Unsure whether they mean now or later — do it now, or ask one question.

## Procedures

| The work | Procedure | Model tier |
|---|---|---|
| decide what to build, before any code exists | `/design-session` | strong |
| lay the foundation of a new authored project | `/bootstrap` | strong |
| box a stack in Docker and write its passport | `/docker-deploy` | capable |
| make a running service reachable from outside | `/expose` | capable |
| put work on the board for later, or open a project (the human asked) | `/make-task` | cheap |
| take a task from the board (the human asked) | `/run-task` | capable |
| conduct: cheap workers, or a split across directions (the human asked) | `/conductor` | capable |
| find out where a bug is, or whether X is feasible | `/investigate` | strong |
| reconcile the foundation with reality | `/prune` | strong |
| re-enter a project after a break | `/orient` | any |
| bring an existing project under the system | `/onboard` | strong |

The procedures are separate skills — invoke them by name. This skill does not
contain their text and must not paraphrase it.

## Working without a procedure

Most sessions are not a planned task — a question, a small fix, a look around, a change
whose shape appeared while doing it. **That is legitimate.** Do not turn it into a task,
and do not announce a procedure you are not running. What still holds:

- invariant 0.4 — read the foundation first (`fraim brief`), fix it if the change made it
  wrong (`fraim arch "<section>"`);
- **behaviour changed → `fraim decide "<title>"`** with the body on stdin; pure cosmetics need
  no entry. Do not hand-write the heading or the date — placement and format are the verb's;
- **open questions at the end** — list them and ask which to keep; approved ones go to
  `fraim backlog-new`;
- **save as you go**: when a coherent piece is done, not at the end of the session,
  `fraim commit fix \"<what changed>\" <path> <path>`. Those commits are the record of
  reactive work; there is no second log to keep.

Reactive work has **no size limit**. A task on the board is work **put aside for later**, or a
project made of several tasks — and only the human puts it there; never propose it. The same
goes for `/conductor`. You are about to
change something you do not understand → `/investigate`.

## Deterministic verbs — call them, do not reproduce them

Mechanical, repeating actions belong to the CLI, not to you. Where a procedure names one of
these, run it: the format, the paths, the timestamps and the commit are not your business.

| Situation | Command | Notes |
|---|---|---|
| reading the foundation whole | `fraim brief` | the map, house rules, living decisions, STACK.md and the board, uncut; once per session |
| looking something up | `fraim find KEY…` | 2–4 keys, both languages, word stems (cache кэш); returns whole entries with their heading |
| finished a coherent piece | `fraim commit KIND "WHAT" PATH…` | a save point over exactly the paths you changed — never "everything" |
| changed what the program does | `fraim decide "TITLE" [--supersedes "OLD"]` | body on stdin; goes on top; --supersedes moves the replaced entry to the archive |
| changed structure, components or data flow | `fraim arch "SECTION" [--new] [--in FILE]` | rewrites one section of ARCHITECTURE.md (or CONVENTIONS.md / STACK.md); body on stdin |
| something bit you that would trap the next change | `fraim pitfall "LINE"…` | propose the line first; write it only on the human's yes |
| need to undo your own uncommitted edit | `fraim restore PATH…` | back to the last save point; a created file is removed |
| open questions remain, important but not for now | `fraim backlog-new SLUG [--from WHERE]` | list them, ask; only approved ones; body on stdin: # title, ## Question, ## Why it matters |
| finished a task taken from the board | `fraim task-seal SLUG "RESULT" [--dropped]` | closes the card into the archive with one line of outcome; a master task only on the human's word |
| wants to know where things stand | `fraim status` | the watchman's verdict; report it, do not act on it |
| wants to know what is planned | `fraim tasks` | open tasks, projects with progress, age of each card |
| wants work set aside, or a project opened | `fraim task-new SLUG --task \| --master \| --parent M [--after S] [--from Q]` | via /make-task; the kind is required; body on stdin: # title, ## What and why, ## Done when, ## Links; a project brings its subtasks in ## Subtasks |
| says a task is really a project | `fraim task-master SLUG` | turns an open task into a master task |
| wants to review open questions | `fraim backlog` | the backlog; a question that stops mattering → fraim backlog-drop |
| drops an open question | `fraim backlog-drop SLUG "WHY"` | closes it into the archive with the reason |
| a save point must be taken back | `fraim undo [HASH]` | lists the save points; undoes one with a counter-commit, never rewrites history |
| starting / closing an investigation | `fraim investigate-new SLUG` | inside /investigate |
| closing an investigation with an outcome | `fraim investigate-seal SLUG` | inside /investigate; refuses without an outcome and a cleanup report |
| a stack was boxed | `fraim stack-passport` | inside /docker-deploy |
| a prune is finished | `fraim prune-mark` | inside /prune |
| `fraim scaffold` | lay the foundation files and `ai/` — never by hand |

Some of them **refuse**: `task-new` will not write a card without its kind (`--task`,
`--master` or `--parent`), a title, «What and why» and «Done when» — and not one card of a
project when any of its subtasks is wrong; `task-seal` will not close a project while its
subtasks are open;
`investigate-seal` wants exactly one outcome branch and a report on the cleanup. A refusal is the check doing its job — fix what it names and run it again.
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
| `fraim init` | lay the skills out again / pick up a newly installed harness |
| `fraim update` | bring in a new version and lay it out (`--check` only reports) |
| `fraim upgrade` | bring an existing project's foundation up to the current standard |
| `fraim clean` | close every loose end whose answer is computable, in one pass |
| `fraim config` | what settings are in effect and where each came from |
| `fraim projects` | list, add or remove projects in the registry |
| `fraim doctor` | what is installed where, which version, what diverged |
| `fraim publish` | a copy of the project off this machine: check, create, push, verify |
| `fraim show NAME` | print a procedure's text (for environments without skills) |

`fraim publish` is the one command here that reaches the network and cannot be taken back
(`fraim update` and `fraim doctor` also touch it, but they only ever read, and only about
fraim itself). What publish does cannot be taken back — a repository that was public for a minute was public. `fraim publish --check` is
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
