---
name: make-task
description: "Only when the human wants work set aside for later or a project opened (judge the intent, in any language): formulate WHAT and WHY and how we will know it is done, and save it as a card in ai/tasks/ (a project together with its subtasks) — an intent, never a plan with the code's context"
metadata:
  tier: cheap
  order: 5
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
  task into a project yourself, even if it seems big. Unsure whether the human means one task or
  a project — ask one question; do not fall back to an ordinary task. (why: N3)
- **R5 — A project's breakdown lives on the board.** The parts of a project are its subtasks,
  put on the board together with it — each an intent like any card. The breakdown has no other
  home. (why: N4)
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
    about the project as a whole. Otherwise it is an ordinary task (`--task`). The verb does not
    guess: without one of the two (or `--parent`) it refuses.
2.3 A project → propose its breakdown as a list: for each subtask a slug, a title, what and why,
    a checkable "done when", and — only where one part truly needs another finished first — which
    earlier parts it comes after. The human approves or edits the list; it goes into the same call
    (Step 3). The human wants the breakdown later → put the master alone; it is broken down when
    taken (`/run-task`).
2.4 The task is part of an open project as the human intends it (they named the project or it is
    clearly about it) → `--parent <project slug>`. In doubt — ask. It must wait for another part of
    that project → `--after <slug>[,<slug>]`.
2.5 The same task is already on the board → say so and do not put up a second one.
2.6 Slug: Latin letters, digits, hyphens, up to 40 characters, meaningful (`add-rate-limiter`).

### Step 3 — Put it on the board

```sh
fraim task-new <slug> --task | --master | --parent <master> [--after <slug>] <<'EOF'
# <What to do — in one line>

## What and why
<1–3 sentences: what is needed and why it matters>

## Done when
<a checkable sign — one or more items>

## Subtasks
<only with --master: the approved breakdown, one block per subtask, in order>

### <subtask-slug> — <Title>
What and why: <1–2 sentences>
Done when: <a checkable sign>
After: <optional: slugs of subtasks above it>

## Links
<optional: addresses of materials>
EOF
```

3.1 The verb writes the frontmatter itself (`kind`, `created`, `parent`, `after`), puts the card
    in `ai/tasks/<slug>.md` — and each subtask in a card of its own — and makes one save point.
    The «Subtasks» section does not stay on the master: the cards are the breakdown. A refusal
    names what is missing — fix it and call again; nothing of the project is written until every
    card in it is right.
3.2 The human called an ordinary task a project → `fraim task-master <slug>`.

### Step 4 — Answer

4.1 In one line: what was put on the board and where (`ai/tasks/<slug>.md`, into a project or
    standalone); for a project — how many subtasks and which can be taken first.
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
into a project without asking. The same holds the other way: a project the human asked for and
the agent put down as one ordinary card loses its breakdown — so the verb makes the kind a choice,
never a default.

**N4 — Why the breakdown goes on the board.** An agent that splits a project in its head has to
put the split somewhere. When the card had no place for it, it landed in a file of the agent's
choosing, where no verb, board or later session would find it. Subtasks are that place: each is
an intent, the board shows them as the project's queue, and `after` says which must wait —
nothing in it describes the code, so it does not go stale any faster than the project itself.
