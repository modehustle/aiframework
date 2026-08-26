---
description: Re-enter a project after a break — load the foundation and report current state and the next move
---

# /orient — Re-enter With Context

You are returning to a project — possibly weeks later, certainly in a fresh chat. This workflow is the **read-only** counterpart to the whole family: it does not plan, build, or change anything. It loads the persistent context the other workflows left behind and tells the human (and itself) **where things stand and what to do next**.

> Strictly read-only. No code, no file edits, no commands that change state. The only output is a spoken state summary. If the user wants to act, point them at the right workflow — do not start acting.

## Step 1 — Load the foundation

Read whatever exists, in this order, and note what is missing:
1. `ARCHITECTURE.md` — what the project is, components, data model, interfaces.
2. `CONVENTIONS.md` — how work is done here; the house rules; the `## Known Pitfalls / Lessons` accrued so far.
3. `DECISIONS.md` — the decision trail (read at least the most recent entries).
4. `STACK.md` — the deploy passport, if the project has been boxed (`docker_deploy_workflow.md`).
5. `README.md` — entry point / run instructions.

If none of these exist, this project has not been bootstrapped:
> Tell the user: "Нет файлов фундамента. Это не bootstrap-проект — начни с `design_session_workflow.md` → `project_bootstrap_workflow.md`." Then stop.

## Step 2 — Read the task queue and the drift signals

- `ai/tasks/<slug>/` — list every task folder in the queue. For each: its `task.md` Summary line; its state — **blocked** (has `blockers.md`, awaiting `/revise_task`), **done, awaiting archive** (has `result.md` and no `blockers.md`), or **runnable**; and for runnable tasks check `## Plan provenance` — if the code has moved since it was planned (other tasks landed on overlapping files), flag the plan as **possibly stale**.
- `ai/archive/` — list the few most recent archived tasks (by directory timestamp) to show recent history.
- `ai/hotfix_log.md` — count the hotfixes since the last `--- pruned ... ---` marker. This is the foundation-drift signal.

## Step 3 — Report state

Give a tight briefing, not a wall of text:

```
## What this project is
<1–2 sentences from ARCHITECTURE.md> · Deploy: <access mode from STACK.md, or "not deployed">

## Task queue
<For each queued task: `<slug>` — Summary line — [runnable | possibly STALE: re-check provenance | BLOCKED: awaiting /revise_task | DONE: awaiting archive]. "Empty." if none.>

## Recent history
- <YYYY-MM-DD_HHMM_slug> — <one line from its result.md if present>
- ...

## Foundation health
<Drift: <N> hotfixes since last prune. Plus anything stale or inconsistent you noticed: e.g. ARCHITECTURE mentions a component not in the code, DECISIONS contradicts CONVENTIONS, a queued plan looks stale. "Looks consistent." if none.>
```

## Step 4 — Recommend the next move

Based on state, name the single most likely next command — do not run it:

- **A task is blocked** → "Задача `<slug>` заблокирована. Запусти `/revise_task`, затем `/run_task`."
- **A task is done, awaiting archive** → "Задача `<slug>` исполнена и ждёт архивации. Запусти `/run_task` и попроси заархивировать её (Шаг 10), когда будешь готов."
- **A queued plan looks stale** → "Задача `<slug>` могла устареть, пока ждала в очереди. Перед `/run_task` стоит проверить её provenance — `/run_task` поймает это сам, либо почини через `/revise_task`."
- **Runnable task(s) in the queue** → "В очереди <N> задач(а). Запусти `/run_task`" + (if several) "и выбери, какую исполнять."
- **Empty queue** → "Очередь пуста. Обсуди следующий шаг и запусти `/make_task`, когда план согласован."
- **Drift built up** (≥5 hotfixes since last prune, or the foundation looks stale) → "С последнего прунинга <N> хотфиксов — фундамент мог поплыть. Запусти `/prune`, чтобы свести его с реальностью."
- **A trivial fix is all that is needed** → "Это микро-правка — `/hotfix` (если в пределах потолка), не полный цикл."

Then stop and wait for the human. Do not begin work in this session.
