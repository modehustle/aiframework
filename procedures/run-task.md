---
name: run-task
description: "Pick a task from the ai/tasks/ queue, execute it literally, then archive on user approval"
metadata:
  tier: cheap
  order: 5
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

2.1 Read every file listed under `## Codebase Context` in `context.md`, in full. (why: N1)
2.2 A listed file does not exist or is empty → plan defect. Go to Step 4d.
2.3 Never substitute a path you guessed for one that is missing.

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
4.6 Read `## Plan provenance` in `context.md` and compare its basis — the git ref, or the listed
    files — against the code as it is now. (why: N3)
4.6a If the block carries a `System: fraim <version>` line, compare it with `fraim version`.
    Different → the plan was written by a different release of these procedures than the one
    executing it. Treat it as a plan defect and go to Step 4d. (why: N3)
4.7 Re-open the `## Codebase Context` files and confirm the patterns the plan tells you to mirror
    still hold.
4.8 Any check from 4.1–4.7 failed → plan defect. Go to Step 4d.
4.9 All clear → go to Step 5.

### Step 4d — Plan-defect protocol

Enter here from 1.14, 2.2, 4.8, 9.3, or gate G6/G7.

4d.1 Stop executing. Write no further code. (why: N4)
4d.2 Do not edit the plan and do not code around it.
4d.3 Write `ai/tasks/<slug>/blockers.md` using TEMPLATE B.
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

8.1 Write the report (TEMPLATE R) to `ai/tasks/<slug>/result.md`. (why: N8)
8.2 Print a copy of the report in the chat.
8.3 Stage: the changed code files, `ARCHITECTURE.md` and `DECISIONS.md` if you touched them,
    and `result.md`.
8.4 Commit using TEMPLATE C. Commit now, before you ask the user anything. (why: N9)
8.5 The project has no git → skip 8.3 and 8.4 silently.
8.6 Ask the user, verbatim: **\"Принимаем результат?\"**

### Step 9 — Read the answer, then feed the loop

9.1 The answer is unclear → ask again. Do not guess which case it is.
9.2 A step was executed wrong but the plan is sound → return to Step 5 and redo it. (why: N10)
9.3 The plan itself is wrong → delete `ai/tasks/<slug>/result.md`, then go to Step 4d.
9.4 Accepted → continue at 9.5. Do not archive.
9.5 Take each `(pitfall)` from your `## Out-of-plan observations`.
9.6 Propose each one as a single line for `## Known Pitfalls / Lessons` in `CONVENTIONS.md`.
9.7 Ask the user to approve each line: yes / edit / skip.
9.8 One or more lines approved → append them to `CONVENTIONS.md`.
9.9 One or more lines approved → commit them separately: `task: <slug> — pitfalls to CONVENTIONS`. (why: N11)
9.10 Nothing approved → make no commit, and say so.
9.11 Leave every `(bug)` item for the user to schedule. Fix none of them.
9.12 Tell the user the task can be archived now or later, in this chat or a fresh one.

### Step 10 — Archive

Enter here only when the user asks to archive — never automatically on acceptance. (why: N12)

10.1 Identify the task: the folder holding a `result.md`. Several qualify → name them and ask which.
10.2 Create `ai/archive/<YYYY-MM-DD_HHMM>_<slug>/` using current local time.
10.3 Move `context.md`, `task.md`, `result.md`, and any leftover `blockers.md` into that directory.
10.4 Delete the now-empty `ai/tasks/<slug>/` folder.
10.5 Confirm `ai/tasks/<slug>/` no longer exists and the other queued tasks are untouched.
10.6 Commit: `archive: <slug>`. No git → skip silently.
10.7 Tell the user: *\"Архивировано в `<full path>`. Осталось в очереди: <slug list, or 'пусто'>.\"*
10.8 Any step from 9.2–9.6 failed → STOP and report the error. Do not leave a half-archived folder.

---

## TEMPLATES

### TEMPLATE B — `ai/tasks/<slug>/blockers.md`

```markdown
# Blockers

## What is wrong
- <defect 1: which step or file, and why it cannot be executed as written>

## Evidence
- <command output / actual file contents / the real path that exists instead>

## What I did NOT change
- <state that no code was written, or list exactly what was, if you had already started>

## Suggested direction (optional, for the planner)
- <a hint, not a decision>
```

### TEMPLATE R — `ai/tasks/<slug>/result.md`

```markdown
## Status
✅ complete | ⚠️ complete with caveats | ❌ blocked

## Changed files
- `path/to/file1` — <one-line summary>
- `path/to/file2` — <one-line summary>

## Verification
- [x/✗] Criterion 1 — <evidence>
- [x/✗] Criterion 2 — <evidence>

## Command output
<verbatim, trimmed only if huge>

## Foundation updated
- `ARCHITECTURE.md`: <what changed | no structural change>
- `DECISIONS.md`: <entry appended | none needed>

## Out-of-plan observations
<Improvements, bugs, and smells you noticed but did NOT touch. Classify every one:>
- (one-off) <a detail specific to this task, no wider lesson> — stays in this report only.
- (pitfall) <a generalizable gotcha about THIS codebase the planner should have known,
  e.g. \"X must be registered before Y or it silently no-ops\"> — candidate for CONVENTIONS.md.
- (bug) <a real defect in existing code> — for the user to schedule via /make-task; not fixed here.
<Empty if none.>

## Questions for the user
<If any. Empty if none.>
```

### TEMPLATE C — the commit message

```
Status ✅ →  task: <slug> — <one-line summary>
Status ⚠️ →  task: <slug> — <one-line summary> (caveats: <one line>)
```

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

**N8 — Why the report is a file, not chat output.** Printing it in chat is a copy, never a
substitute. A report that lives only in chat is lost the moment the chat closes — and this file
is what `/orient` reads for recent history and what `/prune` reads later. The `(pitfall)`,
`(bug)`, and `(one-off)` observations live in this file and nowhere else.

**N9 — Why the commit is unconditional.** It is the save point, and a save point that waits for
the user's \"да\" is not a save point. The caveat rides in the commit message on purpose: `git log
--oneline` then shows at a glance which points were clean and which carried a tail. A committed
\"⚠️ with caveats\" snapshot is honest and recoverable — strictly better than an uncommitted one.

**N10 — Why iterating is safe.** The next pass ends in its own Step 8 commit on top, and the
earlier snapshot stays in history as a fallback. Re-running Step 8 overwrites `result.md`, which
is correct: the file describes the current state of the task, not its history.

**N11 — Why the pitfalls get their own commit.** \"Recorded house-rule lessons\" is a distinct act
from \"executed the task\", and commits are additive and free here. Separating them keeps
`git log` readable. This is also the loop that carries a lesson the executor paid for back to
the planner: `/make-task` reads `## Known Pitfalls / Lessons` before planning.

**N12 — Why archiving is user-initiated.** Acceptance means the work is right; archiving means
you are done looking at it. Those are different moments, and only the user knows when the second
one has arrived.
