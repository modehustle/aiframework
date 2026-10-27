---
name: orient
description: "Re-enter a project after a break — load the foundation and report current state and the next move"
metadata:
  tier: any
  order: 10
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

Run `fraim brief`: it prints the whole foundation in one stream — the map, the house rules
with Known Pitfalls, the living decisions condensed, `STACK.md` if there is one, and the
board — and ends with a mark that nothing was cut. Do not read the files one by one with a
line limit; that is how a third of the map goes missing without anyone noticing. Read
`README.md` separately for run instructions.

Without the CLI, read whatever exists, in this order, whole, and note what is missing:
1. `ARCHITECTURE.md` — what the project is, components, data model, interfaces.
2. `CONVENTIONS.md` — how work is done here; the house rules; the `## Known Pitfalls / Lessons` accrued so far.
3. `DECISIONS.md` — the decision trail (read at least the most recent entries).
4. `STACK.md` — the deploy passport, if the project has been boxed (`docker-deploy.md`).
5. `README.md` — entry point / run instructions.

If none of these exist, this project has not been bootstrapped:
> Tell the user: \"Нет файлов фундамента. Это не bootstrap-проект — начни с `design-session.md` → `bootstrap.md`.\" Then stop.

## Step 2 — Read the board and the drift signals

- **The board** — `fraim tasks` (or `fraim tasks --json`): every open card, masters with their progress, and each card's age. No CLI → each `ai/tasks/<slug>.md` is a card; its frontmatter says `kind` (`task` / `master`) and `parent`. A folder `ai/tasks/<slug>/` is a task in the old format — `fraim upgrade` turns it into a card.
- `ai/archive/tasks/` — the few most recently closed cards (by file name date), each with its `result` line from the frontmatter, to show recent history.
- **Foundation drift** — count the code commits since `ARCHITECTURE.md` last changed (`git log -1 --format=%H -- ARCHITECTURE.md`, then commits after it touching anything but `*.md`). The count resets at the nearer of two anchors: the map itself moving, and the last `prune: ` commit. The threshold is not a constant to remember: `fraim config` holds `foundation_lag_commits` and the watchman already compared against it in Step 0 — this manual count is only for when the CLI is absent.

## Step 3 — Report state

Give a tight briefing, not a wall of text:

```
## What this project is
<1–2 sentences from ARCHITECTURE.md> · Deploy: <access mode from STACK.md, or \"not deployed\">

## Board
<For each open card: `<slug>` — title — age; masters with «в работе, N из M». \"Empty.\" if none.>

## Recent history
- <YYYY-MM-DD_slug> — <its `result` line>
- ...

## Foundation health
<The watchman's findings verbatim if you had it (foundation lag, lessons, unsaved files), else derived by hand. Plus anything inconsistent that only reading can reveal: ARCHITECTURE mentions a component not in the code, DECISIONS contradicts CONVENTIONS. \"Looks consistent.\" if none.>
```

## Step 4 — Recommend the next move

Based on state, name the single most likely next command — do not run it:

- **An investigation is finished and not archived** → \"Расследование `<slug>` доведено до исхода и ждёт архивации — `fraim investigate-seal <slug>`.\"
- **An investigation has been open for days with no outcome** → \"Расследование `<slug>` открыто <N> дней без исхода. Доведи его через `/investigate` или признай тупик — за незакрытым расследованием могут стоять неубранные строки в базе.\"
- **Open cards on the board** → \"На доске <N> задач(а): <slugs>. Скажи, какую берём, — или что делаем вместо них.\"
- **A card older than a month** → name it: \"Задача `<slug>` висит <N> дней — ещё актуальна?\"
- **Empty board** → \"Доска пуста. Скажи, что делаем дальше, — сделаю в этой сессии.\"
- **Drift built up** (the watchman reported `drift` at attention level, or the foundation looks stale) → \"С последнего прунинга <N> хотфиксов — фундамент мог поплыть. Запусти `/prune`, чтобы свести его с реальностью.\"
- **A trivial fix is all that is needed** → \"Это микро-правка — сделай прямо в этой сессии и поставь точку сохранения, полный цикл тут ни к чему.\"

Then stop and wait for the human. Do not begin work in this session.
