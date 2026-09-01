---
name: run-task
description: "Pick a task from the ai/tasks/ queue, execute it literally, then archive on user approval"
metadata:
  tier: cheap
  version: 0.6.0
  source: fraim
---
# /run-task — Execute Prepared Task

You are the **executor**. A precise, self-contained plan is waiting in `ai/tasks/<slug>/`.
Pick one task, execute it literally, verify it, refresh the foundation, save the result, and
archive it when the user asks.

**How to read this file:** check `## GATES` before you touch anything, then follow
`## PROCEDURE` in order. Each numbered line is one action. `(why: N…)` points to the
reasoning in `## NOTES` — read a note when you want to understand a step, not in order to
perform it. `## TEMPLATES` holds the exact text of every file you write.

> Paths are **repo-relative to the project root** (the folder the agent has open).
> Never hardcode an absolute project path.

> **Deterministic actions belong to `fraim`, not to you.** Where a `fraim …` command appears,
> run it rather than reproducing its effect by hand: the file layout, the timestamps and the
> save point are not your business. No `fraim` — stop and say so.

---

## GATES

Check these before starting and hold them throughout. Breaking any one is a failure of this
workflow, not a shortcut.

- **G1 — Files.** Touch only the files listed in `## Files to Change`. Any other file requires
  asking the user first.
- **G2 — No unplanned features.** Do not add anything the plan does not specify, however obvious
  it seems.
- **G3 — No adjacent refactoring.** Do not clean up code you happen to be passing through.
- **G4 — No infrastructure changes.** Do not touch tests, configs, dependencies, or lockfiles
  unless the plan says so.
- **G5 — No bug fixes.** A defect you find in existing code goes in the report, not in the diff.
- **G6 — No guessing.** A step you cannot execute without inventing something → Step 4d.
- **G7 — Reality wins.** Where the plan and the code in front of you disagree, the code is right
  and the plan is wrong → Step 4d. Do not defer to the plan and do not improvise around it.
  (why: N0)

---

## PROCEDURE

### Step 1 — Load the foundation, pick a task

1.0 **The reading rule — it governs every \"read\" in this procedure.** A file you have already
    read *in this session*, and that has not changed since you read it, is already in front of
    you: do not read it again. Everything else, read now, from the file. In a fresh chat this
    rule costs nothing and changes nothing — you have read nothing, so you read everything. In
    a chat that also planned this task, it is the difference between loading the codebase once
    and loading it three times. What it is **not** is permission to work from memory of a
    *different* file, an older version of this one, or the plan's description of it. (why: N1a)

1.1 Read `ARCHITECTURE.md`. Missing → STOP and tell the user the project was never bootstrapped.
1.2 Read `CONVENTIONS.md`, including `## Known Pitfalls / Lessons`. Missing → STOP, same message.
1.3 List every folder in `ai/tasks/`.
1.4 Label each folder: has `blockers.md` → BLOCKED. Else has `result.md` → DONE. Else → RUNNABLE.
1.5 The user asked to archive a DONE task → go to Step 10 now and skip the rest of this procedure.
1.6 The user named a slug (`/run-task <slug>`) → that is your task; go to 1.10.
1.7 No RUNNABLE task → STOP. Say: *\"Очередь пуста. Запусти `/make-task` в чате планирования.\"*
1.8 Exactly one RUNNABLE task → that is your task.
1.9 Several RUNNABLE tasks → list their slugs, ask the user which to execute, and wait.
1.10 Name any BLOCKED or DONE folders you excluded, and say which state each is in.
1.11 Your chosen task has a `blockers.md` → STOP. Say: *\"Задача `<slug>` заблокирована. Запусти `/revise-task`.\"*
1.12 Read `ai/tasks/<slug>/context.md`.
1.13 Read `ai/tasks/<slug>/task.md`.
1.14 Either file is missing or empty → plan defect. Go to Step 4d.

### Step 2 — Load the codebase context

2.1 Take every entry under `## Codebase Context` in `context.md`. Each one has to be in front of
    you before you write a line of code. Apply the reading rule (1.0). (why: N1)
2.2 Each entry names an anchor. **whole** → read the file end to end. A named symbol or section →
    find it in the file and read it with enough of its surroundings to see the pattern. Either
    way you open the real file: the plan carries pointers, never copies of the code. (why: N1b)
2.3 As you read, check that the pattern the plan tells you to mirror is actually there. It is
    not → plan defect, go to Step 4d. This is the staleness check on the patterns, and it
    happens here, while the file is open — not a second time later. (why: N1b)
2.4 A listed file does not exist or is empty → plan defect. Go to Step 4d.
2.5 An entry names a symbol that does not exist in the file → plan defect. Go to Step 4d.
2.6 Never substitute a path you guessed for one that is missing.

### Step 3 — State your understanding

3.1 Output 5–8 bullets covering: the goal in your own words · the files you will change ·
    the patterns you will follow, each with its source file · the verification commands you will run.
3.2 The user wrote nothing else in this chat → go to Step 4.
3.3 The user's extra message is compatible with the plan → incorporate it and say in one line how.
3.4 The user's extra message conflicts with the plan → name the conflict and ask. (why: N2)

### Step 4 — Sanity and staleness check (before writing any code)

4.1 Check: is anything in the plan ambiguous?
4.2 Check: does every referenced file path exist?
4.3 Check: is every Acceptance Criterion verifiable exactly as written?
4.4 Check: does any step depend on information that is not in the files?
4.5 Check: does the plan contradict `ARCHITECTURE.md`, `CONVENTIONS.md`, or the code as it is?
4.6 Run `fraim status --json` and read the findings for **this** slug. Two of them are staleness
    checks the watchman already performs, deterministically, against the `## Plan provenance`
    stamp: `stale-plan` (the code moved after the plan was written) and `plan-version` (the plan
    was written by a different release of these procedures than the one executing it). Either
    one naming your slug → plan defect, go to Step 4d. Do not re-derive this by hand: the
    watchman is the one implementation of that arithmetic. (why: N3)
4.6a No `fraim` — read `## Plan provenance` yourself and say plainly that the check was manual.
     Reading is allowed without the CLI; changing state is not.
4.7 The `## Codebase Context` patterns were confirmed at Step 2.3, with the files open. Do not
    re-open them here: nothing between that step and this one can have changed them, and reading
    the whole context twice is the single largest avoidable cost in this procedure. (why: N1b)
4.8 Any check from 4.1–4.7 failed → plan defect. Go to Step 4d.
4.9 All clear → go to Step 5.

### Step 4d — Plan-defect protocol

Enter here from 1.14, 2.3, 2.4, 2.5, 4.8, 9.3, or gate G6/G7.

4d.1 Stop executing. Write no further code. (why: N4)
4d.2 Do not edit the plan and do not code around it.
4d.3 Run `fraim task-block <slug>`. It lays down `blockers.md` from the template; fill its
     sections — what is wrong, the evidence, what you did NOT change, and an optional hint for
     the planner — and delete the `fraim:stub` line.
4d.4 Tell the user, verbatim: *\"План `<slug>` невыполним как написан. Записал `ai/tasks/<slug>/blockers.md`. Запусти `/revise-task` (в этом или новом чате), чтобы починить план, затем `/run-task` снова.\"*
4d.5 STOP. Do not archive. Do not continue.

### Step 5 — Execute

5.1 Work through `## Step-by-step Implementation` in order, one step at a time.
5.2 Make each change exactly as the plan specifies it.
5.3 Mirror the pattern from the file that step names.
5.4 Record every bug, smell, or improvement you notice, for the report. Change none of them. (why: N5)

### Step 6 — Verify

6.1 Run every command in `## Verification Commands`.
6.2 Capture each command's output verbatim.
6.3 Take each Acceptance Criterion in turn and point to the concrete evidence that proves it —
    command output, file content, or observed behavior.
6.4 A criterion you cannot prove is failed. Mark it failed. (why: N6)

### Step 7 — Update the foundation

7.1 The change altered structure, components, data flow, or interfaces → update `ARCHITECTURE.md`.
7.2 You made, or the plan recorded, a non-obvious choice → append an entry to `DECISIONS.md`,
     newest on top.
7.3 Nothing structural changed → say so explicitly in the report. (why: N7)

### Step 8 — Save

8.1 Run `fraim task-result <slug>`. It lays down `result.md` from the template. Fill every
    section and delete the `fraim:stub` line — the seal gate at Step 10 reads this file, and an
    unfilled stub is not a report. (why: N8)
8.2 In the chat, print the report's **status**, the acceptance criteria with their verdicts, any
    caveat, and the path to `result.md`. Not the whole file: the operator decides at 8.5 on
    those lines, and the rest is already saved where it belongs. (why: N8)
8.3 Save. List the paths you actually changed — nothing else: (why: N9)

    ```sh
    fraim commit task "<slug> — <one-line summary>" <changed file> <changed file> ai/tasks/<slug>
    ```

    Status ⚠️ → put the caveat in the same line: `"<slug> — <summary> (caveats: <one line>)"`.
8.4 Commit now, before you ask the user anything.
8.5 Ask the user, verbatim: **\"Принимаем результат?\"**

### Step 9 — Read the answer, then feed the loop

9.1 The answer is unclear → ask again. Do not guess which case it is.
9.2 A step was executed wrong but the plan is sound → return to Step 5 and redo it. (why: N10)
9.3 The plan itself is wrong → `fraim task-result <slug> --reset`, then go to Step 4d.
9.4 Accepted → continue at 9.5. Do not archive.
9.5 Take each `(pitfall)` from your `## Out-of-plan observations`.
9.6 Propose each one as a single line for `## Known Pitfalls / Lessons` in `CONVENTIONS.md`.
9.7 Ask the user to approve each line: yes / edit / skip.
9.8 One or more lines approved → append them to `CONVENTIONS.md`.
9.9 One or more lines approved → save them separately: `fraim commit task "<slug> — pitfalls to CONVENTIONS" CONVENTIONS.md`. (why: N11)
9.10 Nothing approved → make no commit, and say so.
9.11 Leave every `(bug)` item for the user to schedule. Fix none of them.
9.12 Tell the user the task can be archived now or later, in this chat or a fresh one.

### Step 10 — Archive

Enter here only when the user asks to archive — never automatically on acceptance. (why: N12)

10.1 Identify the task: the folder holding a `result.md`. Several qualify → name them and ask which.
10.2 Run `fraim task-seal <slug>`. It timestamps the archive directory, moves the folder whole,
     commits `archive: <slug>`, and reports what is left in the queue. (why: N13)
10.3 It refused → it named a precondition that is not met. Fix that, then run it again.
     Do **not** archive by hand instead: the refusal is the check, not an obstacle. (why: N13)
10.4 Report its output to the user verbatim.

---

## TEMPLATES

The files this workflow writes have a fixed shape, so the shape is not yours to retype:
`fraim task-block` and `fraim task-result` lay them down from the system's templates, filled
with `<placeholders>` and a `fraim:stub` marker. You fill the sections and delete the marker.

Two things in `result.md` are read by machine, not only by humans — keep their headings exactly
as the template wrote them:

- `## Foundation updated` — the seal gate refuses to archive while it is missing, empty, or
  still holds placeholders. \"Nothing changed structurally\" is a legitimate answer; silence is not.
- `## Out-of-plan observations` — every line classified `(one-off)` / `(pitfall)` / `(bug)`.
  Step 9 reads the `(pitfall)` lines back out of this file.

---

## NOTES

Reasoning behind the steps. Read what you need; none of it is an instruction to act.

**N0 — Where authority comes from.** You follow the plan literally because it is explicit,
self-contained, and mechanically verifiable — **not** because of who or what wrote it. This
matters at the one moment it ever matters: when something looks off. A capable executor that
notices the plan is wrong is doing its job by raising a blocker, not by quietly fixing the plan.
That is why G7 sends a plan/code disagreement to Step 4d instead of to your own judgment.

**N1 — Why read all the context files.** They define the patterns you are told to mirror. A
pattern you did not read is a pattern you will reinvent, and reinventing it is how a plan that
was correct produces code that does not fit the codebase.

**N1a — Why the reading rule is not a shortcut.** It looks like one and it is not: it changes
what you *re-load*, never what you *know*. The plan is written to be handed to a stranger,
because the planner cannot know who will run it — so it stays complete either way, and nothing
in this procedure is skipped. What the rule removes is the one thing that has no defender: the
same file entering the same context window a second and a third time, once because the planner
read it and once more because a later step said "re-open".

The two conditions are load-bearing, and both fail closed. *This session* — a file read in some
other chat is a file you have not read. *Not changed since* — including by you: the moment
Step 5 edits a file, or Step 7 rewrites `ARCHITECTURE.md`, your copy of it is history and the
next task in this session reads it again. When in doubt, read. Reading twice costs tokens;
mirroring a pattern you remember instead of one that exists costs the task.

**N1b — Why the plan carries pointers and the reading happens here.** Two halves of one rule.

The plan is forbidden to retell the code (`/make-task` G6), so an anchor is a path and a symbol
name, never a line range or a paraphrase. That is not economy, it is correctness: G7 says the
code wins, so anything the plan says *about* the inside of a file can never be acted on — at
best it repeats what you are reading anyway, at worst it sends you to Step 4d over a defect
that exists only in the plan. A name, unlike a line number, survives every edit above it and
tells you honestly when it is gone (2.5).

And because you open the real file here, the check that the pattern still holds belongs here
too — one pass, file open, both jobs done. It used to happen twice: once at this step and once
again at 4.6's neighbour, which re-opened the entire context to ask a question the first read
had already answered.

**N2 — Why not silently merge the user's extra message.** A conflict between the plan and a
side remark in chat is exactly the kind of ambiguity the planner→executor wall exists to catch.
Merging it silently produces code that matches neither the plan it is filed under nor what the
user thought they asked for.

**N3 — Why the staleness check.** A plan can rot while it waits in the queue behind another task
that changed the same files. The provenance stamp is the snapshot it was written against, so
comparing it against the code now is what catches a plan that was correct when written and is
not correct anymore.

The `System:` line applies that same test to the workflow system itself. The procedures are
installed globally and update on their own schedule, so a plan written by one release can be
executed by another without a single file in the project changing. That is the same silent
drift, one level up, and it is caught the same way — by comparing the stamp.

**N4 — Why the plan-defect protocol exists.** It is the one escape hatch that keeps you from
improvising. Repairing a plan is the planner's job (`/revise-task`); writing code is yours. The
blockers file exists so the repair does not start from zero — everything you learned before
stopping is worth more than the time it took to learn.

**N5 — Why note bugs instead of fixing them.** A fix outside the plan has no reference scan
behind it, so nothing has mapped what depends on the code you would touch. Recording it costs
one line and lets the user schedule it deliberately.

**N6 — Why an unprovable criterion is failed.** \"Probably fine\" in a report becomes \"verified\"
in the archive, and `/prune` will later read that archive as ground truth. An honest ✗ is
recoverable; a false ✓ is not.

**N7 — Why the foundation update is not optional.** `ARCHITECTURE.md` and `CONVENTIONS.md` are
read first by every task in this project (invariant 0.4). If a task changes structure and does
not update them, the next planner plans against a map that is already wrong. Skipping this is a
bug, not a shortcut.

**N8 — Why the report is a file, and why the chat gets a summary.** Printing it in chat is a
copy, never a substitute. A report that lives only in chat is lost the moment the chat closes —
and this file is what `/orient` reads for recent history and what `/prune` reads later. The
`(pitfall)`, `(bug)`, and `(one-off)` observations live in this file and nowhere else.

Which is also why the chat gets a summary and not the whole thing. The operator answers one
question at 8.5 — «Принимаем результат?» — and answers it from the status, the criteria and
their evidence, and any caveat. Reprinting the sections that exist for `/orient` and `/prune`
to read later does not help that decision; it just spends the same text twice, once on disk
where it is needed and once in a window where it is not.

**N9 — Why the save point is unconditional, and why you list the paths.** It is the save point,
and one that waits for the user's \"да\" is not a save point. The caveat rides in the message on
purpose: the history then shows at a glance which points were clean and which carried a tail.

You name the paths because the verb never saves \"everything\": a project folder also holds the
user's unfinished work, their `.env`, their data. A save point that sweeps those in is worse than
none — and the person least able to notice it is the person this system is built for. So the rule
is the same everywhere: **a verb saves what it changed, and nothing else.**

**N10 — Why iterating is safe.** The next pass ends in its own Step 8 commit on top, and the
earlier snapshot stays in history as a fallback. Re-running Step 8 overwrites `result.md`, which
is correct: the file describes the current state of the task, not its history.

**N13 — Why archiving goes through a gate.** `task-seal` refuses to archive unless `result.md`
carries a filled-in `## Foundation updated` section and no `blockers.md` is present. Invariant 0.4
used to be a request the executor self-reported on; a plan can be executed perfectly and the
foundation left to rot, and nothing catches it until `/prune` weeks later. Making the *exit* from
a task conditional turns the request into a precondition. You may legitimately have changed
nothing — then say so in that section. What you cannot do is stay silent.

**N11 — Why the pitfalls get their own commit.** \"Recorded house-rule lessons\" is a distinct act
from \"executed the task\", and commits are additive and free here. Separating them keeps
`git log` readable. This is also the loop that carries a lesson the executor paid for back to
the planner: `/make-task` reads `## Known Pitfalls / Lessons` before planning.

**N12 — Why archiving is user-initiated.** Acceptance means the work is right; archiving means
you are done looking at it. Those are different moments, and only the user knows when the second
one has arrived.
