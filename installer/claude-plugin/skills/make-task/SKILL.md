---
name: make-task
description: "Only when the human wants work set aside for later or a project opened (judge the intent, in any language): formulate WHAT and WHY and how we will know it is done, and save it as a card in ai/tasks/ — an intent, never a plan with the code's context"
metadata:
  tier: cheap
  version: 0.10.0
  source: fraim
---
# /make-task — put a task on the board

You put a task on the project's board. A task is an **intent**: what to do, why, and how we will
know it is done. Not a plan. The code's context does not go into it: whoever takes the task will
gather it — from the tree as it will be on that day.

> Paths are relative to the project root. The card is written and saved by `fraim task-new`; the
> file is not created by hand.

---

## RULES

- **R1 — Only on the human's intent.** A task is put on the board when the human wants to **defer**
  work until later or **start a project** — however they phrase it and whatever language they
  write in. Judge by the intent, not by the words. You do not offer to turn work into a task and
  you do not put one on the board on your own — reactive work is done here and now. Unclear
  whether it is "now" or "later" — do it now or ask one question. (why: N1)
- **R2 — Intent, not context.** The card has no paths, patterns, steps, signatures, retelling of
  the code. It has: what, why, the sign of done, links to materials. (why: N2)
- **R3 — A master task only on the human's intent.** A project (master task) is started when the
  human themselves speaks of the work as a big undertaking made of many tasks. You do not turn a
  task into a project yourself, even if it seems big. (why: N3)
- **R4 — Do not execute.** Put it on the board — stop. Taking a task is `/run-task`, and the human
  decides that.

---

## ORDER

### Step 1 — Formulate

1.1 From the conversation, pick out: **what** to do, **why**, **how we will know it is done**.
1.2 Any of the three is missing → ask the human one question. Do not invent the "why" for them.
1.3 "Done when" is checkable: something you can open, run, see. "The code is clean" is not a
    sign.
1.4 There are materials — an investigation (`ai/investigations/…`), a design brief, an issue, a
    discussion — they go into "Links" as an address, not a retelling.

### Step 2 — Decide where it goes

2.1 Look at the board: `fraim tasks`.
2.2 The human wants to start a project → it is a master task (`--master`). Its "Done when" is
    about the project as a whole.
2.3 The task is part of an open project as the human intends it (they named the project or it is
    clearly about it) → `--parent <project slug>`. In doubt — ask.
2.4 The same task is already on the board → say so and do not put up a second one.
2.5 Slug: Latin letters, digits, hyphens, up to 40 characters, meaningful (`add-rate-limiter`).

### Step 3 — Put it on the board

```sh
fraim task-new <slug> [--master | --parent <master>] <<'EOF'
# <What to do — in one line>

## What and why
<1–3 sentences: what is needed and why it matters>

## Done when
<a checkable sign — one or more items>

## Links
<optional: addresses of materials>
EOF
```

3.1 The verb writes the frontmatter itself (`kind`, `created`, `parent`), puts the card in
    `ai/tasks/<slug>.md` and makes a save point. A refusal names what is missing — fix it and
    call again.
3.2 The human called an ordinary task a project → `fraim task-master <slug>`.

### Step 4 — Answer

4.1 In one line: what was put on the board and where (`ai/tasks/<slug>.md`, into a project or
    standalone).
4.2 That's all. Do not offer to take it on.

---

## NOTES

**N1 — Why only the human puts a task on the board.** Work is reactive: the human writes — the
agent does it in this same session, with no size limit. A task on the board is work **for later**
or a project, that is, a decision about the future. It is not yours. An agent that proposes
"let's make it a task" drags the conversation into a ceremony nobody asked for.

**N2 — Why without context.** A task used to be a plan: a snapshot of the code it was written
against — paths, patterns, a dependency list, a version stamp. The snapshot starts going stale the
moment it is written, and half of the system was machinery for noticing that: stale plans,
blockers, revisions, reconciliations. The living context is the foundation and the code. Whoever
takes the task reads them fresh. An intent goes stale slowly and visibly to the eye: "is this
still needed?".

**N3 — Why a project is an explicit word.** An ordinary task and a project behave differently
when they are taken: a task is done whole in one session, a project is broken into subtasks that
are taken one at a time. If the type were computed by itself ("it has children"), a big task
without children would look ordinary, and an agent that decided it was "too big" would turn it
into a project without asking.
