---
name: run-task
description: "Take a task from the board (ai/tasks/) when the human says so — or a fleet worker's brief from ai/parallel/ — and do it as an ordinary working session: read the foundation and the code fresh, do the work, save, close the card with one line of outcome"
metadata:
  tier: capable
  order: 6
  parallel: yes
---
# /run-task — take a task

You take a task from the board and do it. This is an **ordinary working session**: the card says
what is needed, why, and when it will be done, and you gather the context yourself — from the
foundation and the code, as they stand today. There is no plan, nothing to execute literally.

If you were given a **build subtask brief** (`ai/parallel/<build>/<subtask>/task.md`), you are a
fleet worker, and different rules apply to you: the [«Fleet worker»](#fleet-worker) section at
the end.

> Paths are relative to the project root. The mechanics are in the `fraim` verbs: the card is
> closed by `fraim task-seal`, a save point is made by `fraim commit`. No `fraim` — say so and do
> the same with ordinary git.

---

## RULES

- **R1 — The human takes it.** A task is taken when the human wants to work on a task from the
  board — however they phrase it. You do not go to the board on your own, even if it is visible
  in `fraim status`.
- **R2 — Fresh context.** Everything you know about the code comes from files read in this
  session. The card carries no context, and that is not a gap but the design.
- **R3 — The project's usual rules.** Foundation first and last; behaviour changed — an entry in
  `DECISIONS.md`; a save point for every finished piece; pitfalls — propose them to the human as
  one line.
- **R4 — Size is no reason to change the genre.** The task turned out bigger than it seemed —
  keep working and keep the human informed. Only the human can turn it into a project.

---

## ORDER

### Step 1 — Choose

1.1 `fraim tasks` — the board.
1.2 The human named a task → that one. Did not name one and only one is open → that one. Several →
    list them and ask.
1.3 The task is a **master task** (`◆`, `kind: master`):
    - there are open subtasks → show them and offer the ones the board marks as free to take
      («можно брать»); a subtask that waits (`ждёт: …`) is taken only on the human's word. Ask
      which one. From then on you work with it;
    - there are no subtasks → propose, as a list, how to break the project into tasks. The human
      approves or edits; put each approved one on the board via
      `fraim task-new <slug> --parent <master> [--after <slug>]` (body — as in `/make-task`). Then
      ask which one to take. The project as a whole is not done in one session.
1.4 The task is older than a month (the age is visible on the board) → one line: «This task is N
    days old — is it still relevant?» Answer "no" → `fraim task-seal <slug> --dropped "<why>"`, and
    that's it.

### Step 2 — Gather context

2.1 Read the card `ai/tasks/<slug>.md` in full. A subtask → also read the project's card
    (`parent`): the whole "why" is there.
2.2 Read the foundation: `fraim brief` — the map, the rules with Known Pitfalls, the active
    decisions and the board in one output, untruncated. If you already called it in this session
    and the foundation has not changed since — do not repeat it.
2.3 What is relevant to the topic — `fraim find` with 2–4 keys: both languages, word stems
    (`кэш cache`). It returns entries in full.
2.4 Read what the card links to, and the code the task touches.
2.5 Tell the human in 3–6 points how you understood the task and what you are going to change.
    If it is unclear what "done" means — ask now, not at the end.

### Step 3 — Do it

3.1 Work as in an ordinary session: you make the decisions yourself; forks that change the
    meaning of the task go to the human.
3.2 A finished piece → a save point over the paths you changed:
    `fraim commit task "<slug> — <what was done>" <path> <path>…`
3.3 Behaviour changed → `fraim decide "<title>"` (body on stdin).
3.4 Check against "Done when": for each item — what confirms it (command output, behaviour, a
    file). It cannot be confirmed → it is not done, say so plainly.

### Step 4 — Update the foundation

4.1 The structure, components or data flow changed → rewrite the affected section of the map:
    `fraim arch "<section>"` (body on stdin). The foundation is not edited by hand.
4.2 Something bit you that will catch the next one too → propose a line for Known Pitfalls; the
    human approved → `fraim pitfall "<line>"`.
4.3 Save: `fraim commit task "<slug> — foundation" <foundation files>`.

### Step 5 — Close

5.1 Show the human the result: what was done, what confirms each "Done when" item, what was left
    out of scope.
5.2 The human agrees → `fraim task-seal <slug> "<outcome line>"`. The verb moves the card to the
    archive, appends the date, the outcome and the commit, and saves. For a subtask it shows the
    project's progress and what can be taken next — pass that on to the human.
5.3 The human decided the task is not needed → `fraim task-seal <slug> --dropped "<why>"`.
5.4 Only the human closes a master task: even when all subtasks are closed, you say
    «no subtasks left — shall we close the project?» and wait.
5.5 Open questions remain — important, but not for this task → list them and ask which ones to
    record in the backlog. The approved ones — `fraim backlog-new <slug> --from <task slug>`. No
    questions — say nothing.

---

## Fleet worker

The brief `ai/parallel/<build>/<subtask>/task.md` was written by the conductor — minutes ago,
against this very tree. It does not go stale in a queue, because it does not sit in a queue.
Here, unlike with a card, execution is **literal**, because other workers are working alongside:

- **W1 — Only your own files.** You change only the paths from the brief's `## Files to Change`.
  You need a file outside the list → do not touch it, stop and say so: the conductor will replan
  the build.
- **W2 — Nothing beyond the brief.** No neighbouring refactoring, no fixes along the way, no
  dependencies or configs unless the brief mentions them. What you find goes into the report, in
  words.
- **W3 — Reality beats the brief.** The brief and the code diverge → stop and describe the
  divergence. Do not bend the code to fit the brief, nor the brief to fit the code.
- **W4 — The foundation is not yours.** You do not touch `ARCHITECTURE.md`, `CONVENTIONS.md`,
  `DECISIONS.md` — the build writes them, once, after acceptance. What would be worth recording
  there goes into the report.
- **W5 — Commit.** Everything you did goes into a commit in your own checkout: the build is
  assembled by merging branches.

There is nothing to close: a build subtask has no card, there is one acceptance per build, and the
conductor does it.
