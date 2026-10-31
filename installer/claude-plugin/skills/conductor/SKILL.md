---
name: conductor
description: "When two or more subagents will write code at the same time — the human handed over several board tasks or projects at once, asked for work in parallel, or your harness splits the work itself: plan the round from the board, let fraim check the split, raise your own subagents, then collect and accept the round yourself — the project check, one merge into the trunk with the round's cards closed in it — and report in words the human answers"
metadata:
  tier: capable
  version: 0.10.0
  source: fraim
---
# Conductor: a round of parallel work, checked before and accepted after

> **Why this procedure exists.** Your harness can raise subagents and run them at the same time —
> every serious harness can by now. What it cannot do is make parallel *writing* safe: two
> subagents on one file merge silently, and nobody checks the whole before it lands. fraim does
> that part. You split the work and launch your own subagents the way your harness does it;
> fraim checks the split before the round, and after it verifies each result against the tree,
> runs the project's check on the assembled whole and takes the round into the trunk in one
> merge that one command undoes. The human types no commands here at all.
>
> **Status: rewritten 2026-10-31.** The launcher of our own (Orca, driving agents through a
> terminal) was the slowest and most expensive part of both live builds and is gone. Workers are
> your harness's own subagents ([DECISIONS.md](../DECISIONS.md), 2026-10-31).

## When this procedure applies

- **Parallel writing.** Two or more of your subagents will **write code at the same time** —
  because the human handed over several tasks or projects from the board at once, said "in
  parallel", or because your harness itself decides to split the work. Then the round goes
  through this procedure.
- **Not for reading.** Subagents that only read — explore a module, read logs, review a diff —
  need no conductor: their result is a report, not a change to the tree. It is the cheapest
  and safest use of subagents; use it freely.
- **Not for one task.** One task you do yourself, in the session, or through `/run-task`. A
  single worker writing alone needs no round — unless the human asked for exactly that (a
  cheaper model writing a piece the project's tests check).

Say it in one line when you start — «running in parallel: four tasks in the first round, as
subagents» — and go. Do not ask: the human already asked for the work; the line is so they know.

### Does it pay off

Parallel work buys **calendar time**, not tokens. Every worker reads the project afresh (a cold
start cost about 37 thousand tokens per worker in the live runs), and you read what comes back.
It pays when the pieces are truly independent and each is checked by the project's own check
(`build_check` — tests, a build, a linter) rather than by you reading every diff. A cheaper model
writing pays off only for mechanical work the check covers; otherwise you read everything you
saved on writing.

### Models

There are no settings for this. A worker runs on **your own model**, unless the human named
another one in words ("workers on haiku") — then pass it when you raise the subagent, or put it
in the subagent's definition where your harness takes a model only there. Which piece deserves
an expensive model is not yours to judge: cost is the human's call.

### Do not hand the round to your harness's own fleet

Some harnesses carry a conductor of their own — `/fleet` in Copilot CLI, `droid exec --mission`,
agent teams. They plan and merge by themselves, and the plan check and the acceptance below
would be bypassed. Use plain subagents.

---

## Who is who here

| | conductor (you) | human |
|---|---|---|
| choose the round, split it into subtasks with files | ✅ | — |
| raise the subagents, wait for them | ✅ | — |
| collect, verify against the tree | ✅ | — |
| **accept the round** — the project check, cleanup, the merge into the trunk | ✅ | — |
| report in your own words | ✅ | — |
| **say whether it is good** | ❌ | ✅ — reads the output and answers in words |
| type commands | ✅ all | ❌ none |

Acceptance is **work** — checking after the workers, cleaning up, bringing it together, taking it
into the trunk — and it is yours. The human keeps judgement: they read your report and say
whether it is good ([B5](../PRINCIPLES.md#b5-ратификация-неприкосновенна)). It comes **after**
the merge, on purpose ([MODES.md §4](../MODES.md#4-гейт-относительно-ствола-развилка-ab)): what
was assembled is checked where it will live, and undoing it is one command you type as well.

---

## Rounds

A build is **one round**: subtasks that run at the same time, none waiting for another. Order
lives on the board — a card's `after:` — not in the plan: what depends on this round goes into
the next one, taken once this one is in the trunk, so its workers start from it.

`fraim tasks` names, under each project, the children nobody waits on — the ready ones. That is
the first round. After each accepted round, `fraim tasks` again: the next round is what became
ready. Work that is not on the board is split the same way — the pieces that can run at once
are a round; what has to wait for them is the next one.

Up to about **six subtasks per round** (`dispatch check` warns above that): one acceptance is one
decision, and a report over twelve interleaved results is a retelling, not a basis for one.

---

## Step 0. Choose the round and split it

Three questions, **in this order**:

1. **What already exists?** `fraim brief`, then the code. Planning in a project where half is
   written and in an empty one are different jobs.
2. **Which pieces?** A piece is one that can be done **without reading the result of another**.
   Check yourself: *if I change a decision inside A, will B have to be redone?* Yes — they are
   not independent yet. Either write the agreement between them down first (the contract,
   step 1), or put them in different rounds.
3. **Which files does each piece touch?** The only thing a machine can check is that two pieces
   never share a path. If you cannot name a piece's files — directories are fine — it has not
   been thought through, and it is too early to hand it out.

When two pieces claim one file, there are four ways out, in this order — the first two are free:

1. **Group** them into one subtask. Two pieces fighting over a file are most likely one piece.
2. **Redraw the boundaries** so the file belongs to exactly one of them.
3. **Leave one for the next round.** It starts from what this round left.
4. **Say there is nothing to parallelize** — legitimate, but the last answer, not the first;
   tell the human what did not work in 1–3, and do the work yourself.

A file every piece would touch a little — a list of languages, an index, a registry — is usually
**your own edit**, made after the round, not anybody's subtask.

## Step 1. Write the plan

```markdown
## Contract
POST /api/login {email, password} → 200 {token} | 401

## Subtask: login-form
**Files**: web/login/

## Subtask: auth-api
**Files**: api/auth.ts, api/session.ts
```

- **`## Subtask: <slug>` is a card on the board.** Its «What and why» and «Done when» go into the
  worker's brief by themselves; you add only what a card never holds — the files. A piece that
  is not on the board carries its own `**Summary**:` (one line) and, if it can, `**Done when**:`.
- **`**Files**:`** — comma-separated; a path ending with `/` is a directory, and everything under
  it belongs to the subtask (a worker may add a new file there). `### \`path\`` headings with a
  line of why are accepted too.
- **`## Contract`** goes verbatim into **every** brief. Write it whenever the pieces share an
  interface — an API, an event format, DOM ids, names. The second live build failed exactly
  here: three pieces, each right on its own, all three rejected for a different API.

A ready-made sample — [example-build-plan.md](../example-build-plan.md).

## Step 2. Check the plan

```
fraim dispatch check PLAN
```

Refuses, before a single worker starts, on what the machine knows exactly: a subtask with no
files; one that is neither a card nor has a summary; a project card as a subtask (a project is
done through its tasks — take its ready ones); the same subtask twice; `**After**` (order lives
on the board now); and **two subtasks over one path** — the same file, or a file inside the
other's directory. A refusal is fixed by rewriting the plan, following the ways out above.

Warns, and does not refuse, on size (more than six subtasks, more than ten paths in one) and on
several subtasks without a contract. Then it prints, per subtask, where its intent comes from —
the board or the plan.

## Step 3. Create the build

```
fraim dispatch PLAN
```

Creates `ai/builds/<build>/` with a copy of the plan, the journal and **one brief per subtask**
(`<subtask>.md`), and the build branch `fraim/<build>` — the round is assembled there, and the
trunk knows nothing of it until acceptance. The brief is self-contained ([G1](../PRINCIPLES.md)):
the worker never sees this conversation. It carries the card's intent and done-when, the files,
the contract and the worker's rules.

## Step 4. Raise your subagents

**One subagent per brief, all at once, each writing in its own worktree:**

- your harness isolates them itself — Claude Code: `isolation: "worktree"` on the call or in the
  subagent's definition; other harnesses: their own worktree option. The worker ends its report
  with `Branch: <name>`;
- your harness has no isolation → `fraim dispatch prepare BUILD` makes a checkout per subtask
  (`.fraim/worktrees/<build>-<subtask>`, from the build branch), and you give each subagent its
  checkout's path.

The prompt is short: the brief's absolute path — «you are a fleet worker; read
`<project>/ai/builds/<build>/<subtask>.md` and do exactly that» — plus the checkout path when
`prepare` made it. Wait for them the way your harness lets you: it tells you when a subagent is
done. **Do not poll.**

No subagents in your harness at all → there is no round: do the tasks one after another yourself.

## Step 5. Collect the round

```
fraim dispatch collect BUILD [SUBTASK=BRANCH …]
```

For subagents in your harness's worktrees, name each branch (the worker's `Branch:` line);
checkouts `prepare` made are found by themselves. Each result is merged into the build branch in a
throwaway checkout — your working tree is not switched. Refused, one by one:

- **no result** — name its branch, or prepare a checkout;
- **uncommitted work** — only a commit can be merged;
- **a file outside its paths** — the silent overlap the whole check exists for; never merged
  with a warning;
- **a merge conflict** — paths cannot overlap inside a round, so an assumption broke; never
  resolved automatically.

A refused worker: send it back with the refusal — resume the same subagent if your harness can, it
keeps its context — and collect again; what was collected stays collected. A subtask that «changed
nothing» is looked at again on the next collect. If the project's own checkout changed inside the
round's paths, collect says so: a worker wrote there instead of its own worktree — move it.

At the end collect prints **the combined diff of the round**. Read it as a whole: two workers
naming one thing differently first becomes visible here.

`fraim dispatch verify BUILD SUBTASK [BRANCH]` shows one result's files — `inside:` or `outside:`
— before you collect it.

## Step 6. Accept the round

```
fraim dispatch accept BUILD
```

Be on the trunk with a clean working tree. Acceptance is yours, whole:

- refuses while any subtask is uncollected;
- names the files no subtask declared;
- runs the project's check (`build_check`) on the assembled branch — no check configured, and the
  report says nobody ran what was assembled;
- removes the checkouts `prepare` made, once their work is in the build branch (a harness's own
  worktrees are the harness's to clean);
- merges the round into the branch the project root is on with one `--no-ff` commit, **the
  round's board cards closed in that same merge** — `fraim undo <merge>` takes back the code and
  reopens the cards together;
- prints the report.

It does **not** write the trunk — loudly, exit 1 — on a red check, an empty build, a dirty working
tree, a conflict or a detached HEAD. Those are facts, not judgements, so no human is called for
them: fix the cause and accept again.

### What you tell the human

- **They said "do it all yourself"** — accept each round and go on to the next; report once at the
  end: every round with its merge (each one undone by one command), what is left, what you are
  unsure of.
- **Otherwise** — a short report after each round, in your own words: what the numbers do not
  show, what you are unsure of. The human answers in words; "not like this" means
  `fraim undo <merge>`, typed by you.

## Step 7. The next round, and the end

`fraim tasks` → what became ready → step 0. When the work is done, write the foundation **once**:
`fraim decide`, `fraim arch`, the pitfalls the workers reported (on the human's yes) — under the
fleet the build writes the foundation, not the workers. A project card is closed by the human
only.

Conductor lessons — the traps of dispatching, not of the code — go into the build journal
(`ai/builds/<build>/journal.md`, «Conductor lessons»).

---

## What the live runs showed

- **Two builds through Orca** (2026-09): the first, four workers, accepted — six of its seven
  breakages were in fraim's launcher; the second, three pieces, all three rejected for a contract
  mismatch, ten of fourteen dispatches were rework, and about 40% of the conductor's context went
  to the launcher — help texts, bookkeeping, polling. The launcher is gone; the contract has a
  section of its own.
- **This repository's localization** (2026-10-31): nine Claude Code subagents in their own
  worktrees — fast and cheap; and six of them edited one shared file, the conflict resolved by
  hand at merge. `dispatch check` refuses such a plan before launch: the shared file is the
  conductor's own edit.

## Transitions

→ ordinary work in the same session — if there is nothing to parallelize, say so and do it
→ [/run-task](run-task.md), its «Fleet worker» section — the rules a worker follows
→ [MODES.md](../MODES.md) — the background of the conductor (its launcher part is history now)
