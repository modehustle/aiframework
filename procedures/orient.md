---
name: orient
description: "Re-enter a project after a break — load the foundation and report current state and the next move"
metadata:
  tier: any
  order: 12
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

- `ai/tasks/<slug>/` — list every task folder in the queue. For each: its `task.md` Summary line; its state — **blocked** (has `blockers.md`, awaiting `/revise-task`), **done, awaiting archive** (has `result.md` and no `blockers.md`), or **runnable**; and for runnable tasks check `## Plan provenance` — if the code has moved since it was planned (other tasks landed on overlapping files), flag the plan as **possibly stale**.
- `ai/archive/` — list the few most recent archived tasks (by directory timestamp) to show recent history.
- `ai/hotfix_log.md` — count the hotfixes since the last `--- pruned ... ---` marker. This is the foundation-drift signal.

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
- **A queued plan looks stale** → \"Задача `<slug>` могла устареть, пока ждала в очереди. Перед `/run-task` стоит проверить её provenance — `/run-task` поймает это сам, либо почини через `/revise-task`.\"
- **Runnable task(s) in the queue** → \"В очереди <N> задач(а). Запусти `/run-task`\" + (if several) \"и выбери, какую исполнять.\"
- **Empty queue** → \"Очередь пуста. Обсуди следующий шаг и запусти `/make-task`, когда план согласован.\"
- **Drift built up** (≥5 hotfixes since last prune, or the foundation looks stale) → \"С последнего прунинга <N> хотфиксов — фундамент мог поплыть. Запусти `/prune`, чтобы свести его с реальностью.\"
- **A trivial fix is all that is needed** → \"Это микро-правка — `/hotfix` (если в пределах потолка), не полный цикл.\"

Then stop and wait for the human. Do not begin work in this session.
