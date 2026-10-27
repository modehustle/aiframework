---
name: conductor
description: "Only when the human asks for it: act as the conductor — hand pieces of work to workers on cheaper models, or split work of different directions across a fleet; verify each against the tree rather than its own report, then accept the whole build yourself — check, clean up, write the trunk, and report back in words the human answers"
metadata:
  tier: capable
  order: 7
---
# Conductor: working through workers' hands

> **Why this procedure exists.** Normally the agent does the work itself, in conversation with
> the human, and that almost always stays so. A conductor is needed in two cases: when
> **writing is expensive** — the strong model spends tokens on managing, while workers on a
> cheap model write the code — and when the work **clearly splits into directions** that can
> run at the same time. The conductor hands out pieces and **accepts the build itself**: it
> checks each worker, runs the project check, cleans up and takes what was assembled into the
> trunk. The human gets one output, which they read and answer in words. The human types no
> commands here at all.
>
> **Status: one live run completed** (4 workers, build accepted, 95 tests).
> What it broke and what of that has been fixed — see the section
> [What the first live run showed](#what-the-first-live-run-showed).

## When this procedure applies

**Only when the human has asked for it.** There is no longer a project mode that would make
the agent a conductor ([DECISIONS.md, 2026-09-15](../DECISIONS.md)), and the agent has no
right to decide "I think I'll hand this out" on its own — neither by launching it nor by
proposing it. The initiative here always belongs to the human: "do this through the fleet",
"conduct this", "hand it to workers".

The request can come in one of two cases, and the case determines how to build the build:

| | **Savings** | **Different directions** |
|---|---|---|
| what for | tokens: the strong model manages, the cheap one writes | calendar: pieces run at the same time |
| subtasks | often **one** — and that is a normal build | several, see the numbers below |
| workers | one, or a chain of waves with one each | one worker per direction |
| condition | the piece can be described by a summary and a list of files | pieces within a wave share no file at all |

### Where the work comes from

Often from the board: the human wants a task or project from the board done by cheap workers. The card
carries only the intent — what, why, when it is done. **You write the brief for the worker, now**: you read
the foundation and the code, break the work into subtasks with paths and hand them out right away. A build
plan lives for minutes, from writing to handing out, and so it does not go stale — it does not sit in a queue.
An accepted build closes the card: `fraim task-seal <slug> "<outcome>"`.

### Do you make edits yourself

The conductor has the same foundation as any reactive work, so **you may edit** —
but only when that is cheaper than handing out: gluing together what was collected, fixing a typo
that the collect revealed, adding a line to the foundation. The cost of handing out — checkout,
agent start, task, collect — is fixed, and on a three-line edit it is larger than the edit itself.

One constraint is hard: **do not write code that has already been handed out**. While a subtask is in
progress, its paths belong to the worker, and your edit in them is exactly the silent edit that
the collect will reject as foreign.

### Does handing out pay off

There is no "piece longer than half an hour" threshold here: **nobody can measure that time** —
neither you before handing out, nor the human, nor the machine afterwards — and it looked like a
rule while working as an excuse to refuse.

Underneath it there is a real question, and it is not about hours. Handing out has a
**fixed cost**: checkout, agent start, task, collect, merge. It is paid the same for a piece of
ten lines and for a piece of a thousand. Therefore:

> Handing out is worth it when executing a piece costs more than handing it out.

"Costs more" in the savings case means **the strong model's tokens**, not minutes. A piece you
would write yourself for twenty thousand frontier-model tokens is worth handing out, even if it is the only one.

This is **an estimate, and you make it** — you see both the work and the tree. One requirement: **say
your answer out loud**, as one line in the plan, next to the build composition. A silent estimate is
checked by nobody; a spoken one is checked by the human in a second.

The check "is the piece too big" is not about time either: **if a piece cannot be described by one
summary and a list of files, it is not one piece**, but two.

### The numbers that count

Three ceilings, and all of them are derived from one scarcity — **there is one ratification per build**. The
ceiling is set not by the machine and not by the subscription, but by how much work a human can accept in one decision.
There are no lower thresholds: a build of one subtask for one worker is legitimate, the human asked
for it, and there is no point arguing with them with a number.

| | how many | why |
|---|---|---|
| subtasks in a build, total | **≤ 6** | a build of twelve is accepted not by one decision but by twelve |
| subtasks in one wave | **≤ 5** | above five, both coordination and acceptance grow |
| waves in a build | **≤ 3** | four or more is a sequential project, not a build |
| paths per subtask | **≤ 10** | more than ten is probably two pieces |

Width and depth are bounded by the overall ceiling: three waves of five is fifteen subtasks,
that is, a ratification that does not exist. Whichever constraint is stricter is the one that applies.

**The fact that the conductor does the acceptance does not raise the ceiling.** The temptation is direct: since the conductor
checks, cleans up and takes things into the trunk, and the human reads one report — why not twelve subtasks?
No. The report is honest exactly as far as the results are independent: on an intertwined build
it turns into a retelling, and a retelling is not a basis for a decision
([A5](../PRINCIPLES.md#a5-не-пересказывай-то-что-читатель-обязан-прочитать-сам)). The ceiling
is set not by the volume of reading but by verifiability — and that did not grow when the checker changed.

`fraim dispatch check` prints these numbers and warns when they do not add up. **It is a
warning, not a refusal**: the number of files does not measure work, and refusing on such a metric
would mean lying with precision. The check refuses only on what it knows for certain.

---

## How you get here

**By the human's request in an ordinary session.** They say what is needed, and that it should be done through the fleet
("this broke, I want a new module and an admin panel — hand it to workers"); breaking it into blocks,
handing out and verifying is done by you. When the build is over, you are an ordinary agent again in the same session.

You used to get here through a project mode (`fraim mode fleet`), which made the agent a conductor
from the first message. The mode has been removed: raising a worker for a single task is pointless, and
a conductor-by-default agent handed out what would have been cheaper to do itself. If traces of it
remain in the project (a `mode` line in `ai/fraim.conf`, a conductor block in `AGENTS.md`, a
SessionStart hook), `fraim mode` removes them.

## Who is who here

This procedure is executed by the **conductor agent** — not a human. The human says what is needed
("build such-and-such a service") and reads what came out. Everything in between is done by the conductor.

| | conductor (agent) | human |
|---|---|---|
| break the task into blocks | ✅ | — |
| write the build plan | ✅ | looks at the check output |
| raise the fleet, monitor | ✅ | — |
| verify against the tree | ✅ | — |
| **accept the build** — verify, run the project check, clean up | ✅ | — |
| **take it into the trunk** | ✅ | — |
| report in your own words | ✅ | — |
| **say whether it is good** | ❌ | ✅ — reads the output and answers in words |
| type commands | ✅ all | ❌ none |

The rule from which the whole table follows:

> **The human types no commands here.** Not one. If something needs to be launched, cancelled,
> rebuilt — you do it, and you do it on their words, rather than showing them a command
> line.

Acceptance is **work**: checking after the executor, cleaning up, bringing it together and taking it into the trunk.
Work gets delegated, and here it is delegated to you entirely. The human keeps judgement: they read
your output and say whether it is good or not ([B5](../PRINCIPLES.md#b5-ратификация-неприкосновенна)).
It comes **after** the write to the trunk, and that is deliberate
([MODES.md §4](../MODES.md#4-гейт-относительно-ствола-развилка-ab), option B): what was assembled
has to be checked where it will live, and undoing it is one command, `fraim undo`, which
you type as well.

The conductor does not write the code of handed-out subtasks and does not decide whether the build is good. It plans,
hands out, verifies, cleans up, takes into the trunk and reports — and a small edit that is cheaper
to make than to hand out, it makes itself ([Do you make edits yourself](#do-you-make-edits-yourself)).

---

## Step 0. Break down the task

The input is a sentence from the human, not a plan. Turning it into a plan means answering three questions,
and **in this order**:

**1. What already exists?** Read the project's foundation in full — `fraim brief` (map, rules,
active decisions, board in one output) — and look at the tree. Planning a "service" in a project where half is already
written and in an empty one are different tasks.

**2. Which blocks does it fall apart into?** A block is a piece that can be done **without reading
the result of another**. The usual "front end and back end" split works exactly when there is already an
agreement between them — an API schema, an event format. If there is none, it is **not two
parallel blocks but one sequential one**: first the contract, then both sides.

Check yourself with the question: *if I change a decision inside block A, will block B have to be
redone?* Yes — the blocks are not independent, and it is too early to parallelize them.

**3. Which files does each block touch?** This is not a formality but a load-bearing part: overlap
of paths is the only thing a machine can check. If you cannot name a block's files, the
block has not been thought through yet, and it is too early to hand it out.

When all three have an answer, write the plan (step 1). When they do not, **tell the human what is
missing, and do not hand out**. Handing out an unfinished plan costs more than a conversation: the error will come back
after an hour of work by N workers, not after a minute.

### Pieces overlap — four ways out, and "nothing to parallelize" is the last

The most common outcome of step 0 is two pieces laying claim to one file. This is **not a verdict on the build**:
an overlap has four ways out, and they must be tried in this order, because the first two
are free and the third costs an extra launch.

1. **Group.** Merge the overlapping pieces into one subtask. Costs nothing and is often
   right: if two blocks fight over a file, most likely they are one block.
2. **Redraw the boundaries** so that the contested file belongs to exactly one subtask. Also
   free — the path lists change, not the scope of work.
3. **Order them in waves.** A subtask declares `**After**: NAME` and goes **after** the named one —
   in the next wave, from the already collected result. Path overlap **between waves
   is allowed**: they do not run at the same time. The cost is a barrier: a wave waits for its slowest piece.
4. **Say there is nothing to parallelize.** A legitimate answer, but the **last** one, not the first.
   Before giving it, tell the human what did not work in points 1–3.

Point 4 used to come right after point 1, and that made "I can't isolate any pieces"
the conductor's cheapest answer. Now there are three cheap answers, and all of them are work.

---

## Step 1. Write the build plan

The plan is one file. Each subtask declares a **role**, a **summary** and **paths**, and if it
does not go first — also an **order**:

```markdown
## Subtask: errors
**Role**: run-task
**Summary**: bring error messages to the form "function: what is wrong"

### `installer/lib/core.sh`
- why this file

### `installer/lib/clean.sh`
- why this file

## Subtask: messages
**Role**: run-task
**After**: errors
**Summary**: convert the texts to the new form

### `installer/lib/core.sh`
- the same file — but after errors, in the next wave
```

**`**After**: NAME` is order, and only that.** Waves are **derived** from it: a subtask without
`After` goes in the first wave, a subtask with `After` goes one wave later than the one it refers to.
Wave numbers are not written by hand: the block's author knows the dependency, while a number would have to be
recalculated on every plan edit, and no check would see stale numbering.

`After` can name several subtasks separated by commas. A reference to nowhere and a cycle are a refusal at
step 2.

A ready-made sample — [example-build-plan.md](../example-build-plan.md).

**A role is the name of a procedure**, not a new word. We have no ontology of roles of our own and will not
have one ([MODES.md §10](../MODES.md#10-границы-чего-мы-не-строим)): the vocabulary already exists —
`run-task`, `investigate`, `prune`, `make-task`. A subtask with `**Role**: run-task` says
which procedure executes it, and the table says on what.

**A role, not a model.** A plan moves between machines, while `haiku` is a fact about one
person's subscriptions.

The table answers in four steps, and the second makes it nearly free:

| | key | when it applies |
|---|---|---|
| 1 | `role_<procedure>` | this procedure is configured specifically |
| 2 | `tier_<procedure's>` | by the class the procedure itself declares |
| 3 | `role_default` | one answer for everything |
| 4 | built-in | nothing is set |

**The conductor does not choose which subtask deserves an expensive model.** Executors run on
what their procedure declared; what that costs is the human's decision, not the agent's.

**What tier means is not what it seems.** Tier is **what a launch costs you**, not
how smart the model is. If your subscription includes a frontier model at no extra charge, its
place is in `tier_cheap`, and then everything for which "the cheap one will do" goes to it. That is the table
working as intended, not an abuse of it.

Three lines cover all procedures at once, because each declares its model class about itself.
You do not need to remember the format — `fraim roles set` asks for the agent, the model and the effort
one at a time, offering what can be offered:

```
fraim roles set              # pick what to configure from a list
fraim roles set tier_cheap   # or name the key directly
```

A separate procedure is configured when it really matters for it —
`fraim roles set investigate`. What is in effect here and where it came from
is shown by `fraim roles`; the project beats the machine
([MODES.md §11.3](../MODES.md#113-где-живёт-таблица-ролей)).

---

## Step 2. Check the plan before handing out

```
fraim dispatch check PLAN
```

The check refuses in six cases:

- **one file in two subtasks of the same wave.** This is the build's load-bearing check, not a convenience: two
  workers, one file — git will merge both edits silently, without a conflict, and the promise "one
  ratification per build" will turn out to be a lie. It is exactly this check that sets the build's boundary
  ([MODES.md §11.2](../MODES.md#112-что-считается-сборкой), option B).
  **Overlap between waves is allowed**: they do not run at the same time, and the second wave
  starts from what the first has already left;
- **`After` names a subtask that is not in the plan** — otherwise a typo in a name would cost
  a wave of launches;
- **a dependency cycle** — waves cannot be derived from it, the plan must be rewritten;
- **a subtask is incomplete** — no role, summary or paths;
- **the role does not resolve** to an executor on this machine;
- **the role cannot be handed to a worker.** Not every procedure fits: `prune` edits the foundation,
  and under parallelism the foundation is written by the build **once** (invariant 0.4) — two such
  subtasks would collide inside a file that is in no path list. `make-task`
  plans, that is, works before handing out; `conductor` is the conductor itself. A procedure fits
  if it declares `parallel: yes` in its frontmatter: today that is `run-task` and
  `investigate`. The default is "not allowed", so that a procedure added tomorrow does not turn out
  to be hand-outable silently.

A refusal on the first point is fixed by **rewriting the plan**, not by a flag — following the ladder in
the section ["Pieces overlap"](#pieces-overlap--four-ways-out-and-nothing-to-parallelize-is-the-last).

Besides refusals, the check prints the **build composition** (how many subtasks, waves, workers
at once) and warnings about the numbers. A warning is not a refusal: the number of files does not
measure work, and you decide.

The output shows who will execute what with what, and where that answer came from. A "built-in
default" line where the project intended to name a role is something that is visible here and invisible three
hours later.

---

## Step 3. Create the build

```
fraim dispatch PLAN
```

Creates `ai/builds/<build>/` with a copy of the plan and a journal, writes a task for each worker
to `ai/parallel/<build>/<subtask>/task.md` — and creates the **build branch** `fraim/<build>`.

The build branch is not the trunk. Workers branch from it, their results are merged back into it, and
what was assembled is taken into the trunk by acceptance (step 7) — in a single merge and only when everything has come together. Until
the build is accepted, the trunk knows nothing about it.

The task is self-contained ([G1](../PRINCIPLES.md)): the executor has not seen this conversation.
Besides the summary and paths it contains the rule the whole build rests on — **change only the
declared files, and if you need to go beyond them, stop and say so**. An edit outside the list
will not cause a conflict on merge; it will simply silently survive someone else's.

---

## Step 4. Raise the fleet

```
fraim dispatch run BUILD
```

Raises **one wave** — the first one not yet collected. One worker per subtask of the wave:
an isolated checkout **from the build branch**, the named agent on the named model, the task being that
very `task.md`. Prints who started on what.

You do not need to name the wave number: the command takes the first uncollected one itself. Until a wave is collected
(step 5), the next one will not be raised — that is what the barrier consists of.

The environment identifiers (`dispatch_…`) are stored in `ai/builds/<build>/fleet.tsv` with the
time they were taken. This is **a cache, not a registry**: the state of workers is the environment's truth
([MODES.md §10](../MODES.md#10-границы-чего-мы-не-строим)); our truth is what was handed to whom
and what came back, and that is in git.

If some of the workers did not come up, the rest still start — subtasks are independent by
construction, and abandoning what is already running would be worse. What came up is visible in `fleet.tsv`.

```
fraim dispatch watch BUILD
```

Shows what the environment says about each worker. Read it with one caveat, which
Orca states itself: **terminal state is not task status**; a finished task can
keep a terminal alive. And `agentWait`: `null` means "looked, not waiting", while the absence of the field means
"did not look", and that never means "not waiting". A worker waiting for a human's answer is **healthy, not
failed** — the build has not failed, it is blocked on you.

Without an execution environment the step is done by hand: open `ai/parallel/<build>/<subtask>/task.md`
and execute each one in its own checkout.

---

## Step 5. Collect the wave

```
fraim dispatch collect BUILD
```

Bringing the wave's results together into the build branch is a stage that did not exist at all before: workers
finished, and only a human could bring their work together by hand.

The collect goes through the wave's subtasks and **refuses** in four cases:

- **the subtask has no checkout** — there is nothing to collect;
- **the checkout has uncommitted changes** — only a commit can be merged. This has already happened: in
  the first live run a worker finished the work and left it unprepared;
- **an edit outside the declared paths** — that very `outside:` line for whose sake
  verification against the tree exists. Merging it with a warning would make the check decorative;
- **a merge conflict** — within a wave paths do not overlap, and nobody else writes to the build branch,
  so a conflict means an assumption has broken. It is never resolved
  automatically.

A rejected subtask does not get in the way of the others: they are independent by construction. What was collected
is recorded in `collected.tsv`, and a repeated collect will take exactly what is missing.

**At the end, the collect prints the combined diff of the whole wave.** This is not a formality: a divergence
that the path check does not see — two workers named the same thing differently, produced
different error formats, understood a word from the task differently — first becomes visible exactly
here. Look at the diff as a whole, not per subtask.

The merge is done in a separate temporary checkout of the build branch: your working tree is not
switched, and a failed merge does not leave a half-assembled state.

---

## Step 6. Verify against the tree, not the report

```
fraim dispatch verify BUILD SUBTASK [BASE]
```

Prints one line per changed file:

```
inside:installer/lib/core.sh     ← the subtask declared this file
outside:installer/lib/publish.sh ← NOT declared: it strayed into someone else's lane
```

**This is the main step of the procedure.** The conductor acts on agents' reports, and a report is written by the same
side that is being evaluated. So the outcome is taken from the tree
([MODES.md §3](../MODES.md#3-дирижёр--новая-роль-а-не-новый-запрет)): not "the worker wrote that it
succeeded", but "git shows what changed". An `outside:` line is that very silent
edit that the path check could not have let through, and that a prose report would not have shown.

Empty output means nothing changed — also an answer, and usually a bad one.

This is a manual tool for one subtask — for when you need to look at one place. For the whole
build, verification is done by acceptance (step 7), and it does it always, not when you happen to remember.

---

## Step 7. Accept the build

```
fraim dispatch accept BUILD
```

**Acceptance is yours, all of it.** You and only you saw what was handed to whom, what came back and how it
differs from what was declared. One command does five things:

1. **checks after the workers** — whether all subtasks are collected (an uncollected build is not accepted
   at all), what each one changed, and which files in the build branch **no
   subtask declared**. The latter is either the foundation, which under the fleet the build itself writes, or a
   leak, and only you can say which of the two, in words;
2. **runs the project check** — the command from the `build_check` setting in a checkout of the build
   branch. This is a check of **the assembled whole**, and it catches what no
   worker saw: two results, each correct on its own, but not together;
3. **cleans up after the fleet** — removes the subtasks' checkouts and releases the build's workers. Only
   what is provably unneeded: a checkout goes only when its commit is already in the build branch, and
   uncommitted work is a refusal, not `--force`. The list is taken from the build's own records,
   so there is not and will not be a "clean up stray worktrees" here
   ([B6](../PRINCIPLES.md#b6-глагол-трогает-только-то-что-сам-изменил));
4. **takes it into the trunk** — with a single `--no-ff` merge of the build branch into the branch the
   project is on;
5. **prints the report to the output**. Not to a file: a separate `report.md` is an extra artifact,
   which the human reads with their eyes once anyway.

### When it does not go into the trunk

The write to the trunk is the last step of the check, not a decision, and so it **is not made** when
the machine already knows something is wrong:

- the project check returned non-zero or did not run;
- the build did not change a single file;
- the working tree has unsaved changes — the merge would drag in someone else's unrecorded work;
- the project is on the build branch itself or on a detached HEAD;
- the merge conflicts with the trunk.

Then the command prints the reason and exits with a non-zero code, the build branch stays intact, and
you go and sort it out. The human is shown not this, but the result.

### What you tell the human

The command's output is numbers. **Your part is words**, and without them acceptance is not finished:

- what you checked that is not visible in the numbers;
- what you are not sure about;
- what you propose next.

Then they answer — in words, not a command. "Good" — the work is already in the trunk, we move on.
"This part is wrong" — you fix it: undo the merge (`fraim undo MERGE` — the command is printed
in the acceptance output, and you type it), raise another wave, rewrite the plan. Write the reason
the build was turned back into the build journal — the "Conductor lessons" section below; what is said
in the chat will not survive until the next build.

---

## Step 8. Conductor lessons

The build journal has an empty section `## Conductor lessons`. It is about a class of pitfalls that a
worker does not have: two plans constantly overlap on paths, the role's model cannot handle its class of tasks,
a subtask went outside its files three times.

The section is empty on purpose ([MODES.md §11.4](../MODES.md#114-кто-пишет-уроки-в-параллельном-режиме),
option D): a template invented before the first real build would teach the wrong things. Fill it in
in your own words after the human has answered — and always if they turned the build back:
"this part is wrong" is the cheapest lesson a build can give, and the only place
where it will survive until the next one is this section.

---

## What the execution environment does, and what we do

We do not write our own orchestrator ([MODES.md §10](../MODES.md#10-границы-чего-мы-не-строим)):
Orca already has a dependency DAG, inboxes, blocking ask/reply, decision gates and a circuit
breaker. Writing that a second time would take months and be worse. The boundary runs not along "our tools versus
theirs", but along the type of knowledge:

| | whose | where it lives |
|---|---|---|
| terminal handles, worktree checkout ids, worker state | **the environment's** | with it; with us at best a cache |
| launch, supervision, isolation, queue | **the environment's** | its orchestration |
| which subtask was handed to whom and what came back | **ours** | git |
| non-overlap of paths (`dispatch-check`) | **ours** | the environment has no such check |
| verification against the tree instead of the report | **ours** | git |
| build acceptance and the write to the trunk | **the conductor's** | git and the build journal |
| **judgement on the build** | **the human's** | their words in answer to your report |

The last line is the only one where you cannot rely on the environment, even when it has the
mechanism. `gate-resolve` can be called by anyone with the CLI, including the conductor itself, while
[B5](../PRINCIPLES.md#b5-ратификация-неприкосновенна) forbids it to **judge**. Checking,
cleaning up and taking into the trunk it not only may do but must do — that is the line above, and it is its own.
And the record of acceptance is "what came back", that is, our truth, not a cache of someone else's state
([A3](../PRINCIPLES.md#a3-источник-правды-ровно-один)).

## What the first live run showed

Four workers, build accepted, 95 tests green. Seven things broke along the way, and
six of them were in fraim itself — all fixed:

| what broke | how it is fixed |
|---|---|
| the whole fleet went down at start: the `devin` agent does not accept a model at launch | the launch is retried without a model, with an explicit message about which model was not applied |
| the word `dispatch_input` was written to `fleet.tsv` instead of identifiers | an identifier is looked for only among hexadecimal values — the environment names state in words, and words do not pass |
| `verify` checked the project root, while workers worked in their own checkouts | the subtask's checkout is found via `git worktree list` |
| `verify` did not see created files and uncommitted work | untracked files were added to the comparison with the base |
| `run` launched on a folder that was not a build | without a build journal the launch refuses and shows the builds that exist |
| two workers edited `DECISIONS.md` because the project's `AGENTS.md` tells them to | the worker's task explicitly cancels this rule and asks to put it in words in the report |

**If an agent does not take a model by flag,** it is given the model with the first command in the session. Which
command exactly — we know for `claude` (`/model`); for the others, teach it with one line:

```
fraim config set --machine modelcmd_devin "/model %s"
```

To an unfamiliar agent the command is not sent at all: sending `/model X` to one that does not know such a
command is worse than not setting the model — it will read it as the first line of the
task.

The seventh is not in the code: the conductor did not enter the mode right away and did part of the work itself,
even though `AGENTS.md` already said it was the conductor. A hook and a watchdog finding were built against this,
but the opposite turned out to be true: an imposed conductor role is worse than an agent that does it itself. The mode
was removed (2026-09-15), and the conductor now comes only at the human's request.

## What is not here yet

**A session profile.** Right now cost is decided once, by the role table. What is missing is the ability
to say "in this work everything is expensive — both the conductor and the executors" or "in this one let everything be
cheap", without rewriting the table. A tier field on the subtask was built and removed: choosing
what here deserves an expensive model is not the conductor's decision. A profile solves the same problem
at the right level (the whole session, the human decides), but designing it before the first real
runs is premature.

---

## Transitions

→ ordinary work in the same session — if there is nothing to hand out, tell the human so and do it yourself
→ [/run-task](run-task.md) — its "Fleet worker" section — the rules by which a worker executes the brief
→ [MODES.md](../MODES.md) — why the conductor is built this way
