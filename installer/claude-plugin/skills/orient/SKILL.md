---
name: orient
description: "Re-enter a project after a break — load the foundation and report current state and the next move"
metadata:
  tier: any
  version: 0.8.2
  source: fraim
---
# /orient — Re-enter With Context

You are returning to a project — possibly weeks later, certainly in a fresh chat. This workflow is the **read-only** counterpart to the whole family: it does not plan, build, or change anything. It loads the persistent context the other workflows left behind and tells the human (and itself) **where things stand and what to do next**.

> Strictly read-only. No code, no file edits, no commands that change state. The only output is a spoken state summary. If the user wants to act, point them at the right workflow — do not start acting.

## Step 0 — Ask the watchman first

If the `fraim` CLI is on PATH, run it before reading anything:

```sh
fraim status --json
```

It is deterministic — file reads, `git log` and mtimes; no model, no network, nothing
written — so its verdict is **fact, not impression**, and it costs nothing. Exit `0`
healthy, `1` something needs the human, `2` the project is not under the system.

Use its findings as the source for `## Foundation health` and for the recommendation in
Step 4, and read the files below for the narrative it cannot give you.

If the CLI is absent — a container, a CI job, a web session — derive the same signals by
hand from Step 2. The watchman makes this workflow exact; it is not a prerequisite for it.

## Step 1 — Load the foundation

Read whatever exists, in this order, and note what is missing:
1. `ARCHITECTURE.md` — what the project is, components, data model, interfaces.
2. `CONVENTIONS.md` — how work is done here; the house rules; the `## Known Pitfalls / Lessons` accrued so far.
3. `DECISIONS.md` — the decision trail (read at least the most recent entries).
4. `STACK.md` — the deploy passport, if the project has been boxed (`docker-deploy.md`).
5. `README.md` — entry point / run instructions.

If none of these exist, this project has not been bootstrapped:
> Tell the user: \"Нет файлов фундамента. Это не bootstrap-проект — начни с `design-session.md` → `bootstrap.md`.\" Then stop.

## Step 2 — Read the task queue and the drift signals

- `ai/tasks/<slug>/` — list every task folder in the queue. For each: its `task.md` Summary line; its state — **blocked** (has `blockers.md`, awaiting `/revise-task`), **done, awaiting archive** (has `result.md` and no `blockers.md`), or **runnable**; and for runnable tasks read the watchman's `stale-plan` finding from Step 0 rather than re-deriving it: `attention` means a file the plan stands on moved after it was written, `info` means the code moved past those files. No CLI → compare `git diff --name-only <Based on>..HEAD` against the plan's `## Codebase Context` and `## Files to Change`, and flag **possibly stale** only on an overlap. A diff that lands entirely in `ai/` is the queue sealing itself, not divergence — every verb commits, so queued plans push each other away from HEAD with no code changing.
- `ai/archive/` — list the few most recent archived tasks (by directory timestamp) to show recent history.
- **Foundation drift** — count the code commits since `ARCHITECTURE.md` last changed (`git log -1 --format=%H -- ARCHITECTURE.md`, then commits after it touching anything but `*.md`). The count resets at the nearer of two anchors: the map itself moving, and the last `prune: ` commit. The threshold is not a constant to remember: `fraim config` holds `foundation_lag_commits` and the watchman already compared against it in Step 0 — this manual count is only for when the CLI is absent.

## Step 3 — Report state

Give a tight briefing, not a wall of text:

```
## What this project is
<1–2 sentences from ARCHITECTURE.md> · Deploy: <access mode from STACK.md, or \"not deployed\">

## Task queue
<For each queued task: `<slug>` — Summary line — [runnable | possibly STALE: re-check provenance | BLOCKED: awaiting /revise-task | DONE: awaiting archive]. \"Empty.\" if none.>

## Recent history
- <YYYY-MM-DD_HHMM_slug> — <one line from its result.md if present>
- ...

## Foundation health
<The watchman's findings verbatim if you had it (drift count, blockers, stale plans, foundation lag), else derived by hand. Plus anything inconsistent that only reading can reveal: ARCHITECTURE mentions a component not in the code, DECISIONS contradicts CONVENTIONS. \"Looks consistent.\" if none.>
<If `fraim status` reported the plan was written by a different fraim version than the one installed, say so: a plan written by an older `/make-task` executed by a newer `/run-task` is exactly the silent drift this system exists to catch.>
```

## Step 4 — Recommend the next move

Based on state, name the single most likely next command — do not run it:

- **A task is blocked** → \"Задача `<slug>` заблокирована. Запусти `/revise-task`, затем `/run-task`.\"
- **A task is done, awaiting archive** → \"Задача `<slug>` исполнена и ждёт архивации. Запусти `/run-task` и попроси заархивировать её (Шаг 10), когда будешь готов.\"
- **An investigation is finished and not archived** → \"Расследование `<slug>` доведено до исхода и ждёт архивации — `fraim investigate-seal <slug>`.\"
- **An investigation has been open for days with no outcome** → \"Расследование `<slug>` открыто <N> дней без исхода. Доведи его через `/investigate` или признай тупик — за незакрытым расследованием могут стоять неубранные строки в базе.\"
- **A queued plan looks stale** → \"Задача `<slug>` могла устареть, пока ждала в очереди. Перед `/run-task` стоит проверить её provenance — `/run-task` поймает это сам, либо почини через `/revise-task`.\"
- **Runnable task(s) in the queue** → \"В очереди <N> задач(а). Запусти `/run-task`\" + (if several) \"и выбери, какую исполнять.\"
- **Empty queue** → \"Очередь пуста. Обсуди следующий шаг и запусти `/make-task`, когда план согласован.\"
- **Drift built up** (the watchman reported `drift` at attention level, or the foundation looks stale) → \"С последнего прунинга <N> хотфиксов — фундамент мог поплыть. Запусти `/prune`, чтобы свести его с реальностью.\"
- **A trivial fix is all that is needed** → \"Это микро-правка — сделай прямо в этой сессии и поставь точку сохранения, полный цикл тут ни к чему.\"

Then stop and wait for the human. Do not begin work in this session.
