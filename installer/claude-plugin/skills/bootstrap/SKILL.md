---
name: bootstrap
description: "Lay the development foundation of an authored project from a Design Brief: foundation documents plus a minimal running skeleton, so the project can be re-entered weeks later with full context instead of guesswork."
metadata:
  tier: strong
  version: 0.5.0
  source: fraim
---
# Project Bootstrap Workflow for AI Agents (universal)

> A step-by-step playbook for laying the **development foundation** of an **authored** project — one that contains your own source code that you will keep changing — so that you and the AI agent can re-enter it weeks later with full context instead of guessing.
> Sibling to `docker-deploy.md`. That one builds and documents the **box** (the Docker stack). This one establishes the **code foundation** that lives inside the box.
> Purpose: persistent context for AI coding agents.
> The agent **follows the phases in order** and does not skip the design phase.

> **Детерминированные действия делает `fraim`, не ты.** Где стоит команда `fraim …`,
> выполняй её, а не воспроизводи результат руками: формат, пути и коммит — не твоя забота.
> Нет `fraim` — **остановись и скажи об этом**, как `/docker-deploy` останавливается на
> хостовых действиях. У детерминированного действия ровно одна реализация.


## When to use this file (a human decision, made before attaching)

> This section is for **you, the human**, deciding *whether to attach this workflow at all* — it is not an agent step. By the time this file is in the session, the decision below is already \"yes\".

Ask one question about the thing you are about to create:

> **Does this stack contain my own code that I will keep developing?**

- **No** — it is an off-the-shelf service (n8n, Postgres, Redis, Ollama, Whisper). Use **`docker-deploy.md` alone**. It produces the box + a `STACK.md` passport, and that is the whole story. **Do not use this workflow.**
- **Yes** — it is an authored project (a backend, an app, a data pipeline you write). Use **this workflow first** to lay the foundation, **then** `docker-deploy.md` to box it.

This workflow is engine- and language-agnostic. The concrete shape of the project (stack, framework, datastore, entities) is decided in Phase 1 with the human and recorded — never assumed.

## How this fits with the deploy workflow

Two complementary layers, never duplicates:

| Layer | Workflow | Output | Answers |
|---|---|---|---|
| **Code** (yours) | this one | `README.md`, `ARCHITECTURE.md`, `CONVENTIONS.md`, `DECISIONS.md`, `ai/`, code skeleton | *What is this project, how is the code organized, why, how do we work on it* |
| **Box** (infra) | `docker-deploy.md` | secure stack + `STACK.md` passport | *What image/network/ports/data, how is it deployed* |

Canonical order for an authored project from scratch:

1. Create the project folder wherever this operator keeps projects, and open it in your agent.
2. **Design session** with the human (`design-session.md`) → the agreed architecture, captured as a Design Brief. This is the authored-project equivalent of a per-stack prompt, but it is a *design artifact*, not a one-line deploy instruction.
3. This workflow (Phases 2–3) → foundation files + a minimal runnable code skeleton.
4. `docker-deploy.md` (when there is something to run) → the box + `STACK.md`.
5. Forever after: the planner→executor loop (`/make-task`, `/run-task`) operates inside `ai/` and keeps the foundation current (Phase 5).

## Standard layout (environment invariant)

Same as the deploy workflow: the project is **its own folder**, and that folder is the root the agent has open (`.`). Where it lives on disk is the operator's choice. The foundation files and `ai/` live in that root, alongside `docker-compose.yml`, `.env`, and the source code.

```
<project>/                     # the folder the agent has open
├── README.md          # entry point (this workflow)
├── ARCHITECTURE.md    # the map + the design (this workflow)
├── CONVENTIONS.md     # how we work here / agent rules (this workflow)
├── DECISIONS.md       # append-only decision log (this workflow)
├── .gitignore         # excludes .env, data/, deps (this workflow)
├── .env.example       # (this workflow) — real .env is filled by the human
├── ai/                # planner→executor task structure (this workflow)
├── src/ (or app/…)    # your code (this workflow scaffolds the skeleton)
├── docker-compose.yml # the box (docker-deploy)
└── STACK.md           # the box passport (docker-deploy)
```

---

## 0. Hard rules (invariants — must not be broken)

Checked ALWAYS, regardless of the task:

1. **This workflow is for authored projects only.** Pure off-the-shelf services use `docker-deploy.md` alone. (See \"When to use\".)
2. **Architecture is decided WITH the human and RECORDED before any code is written.** The agent never invents an architecture and silently commits it. No code in Phases 0–1.
3. **Every authored project has, in its root:** `README.md`, `ARCHITECTURE.md`, `CONVENTIONS.md`, `DECISIONS.md`, and an `ai/` directory. The deploy is not the foundation; this is.
4. **`ARCHITECTURE.md` and `CONVENTIONS.md` are read FIRST on every task** and **updated as the FINAL step, unprompted,** whenever the task changes structure, components, or conventions. `DECISIONS.md` is append-only (supersede, never rewrite). A stale foundation is a bug. (This mirrors deploy invariant 0.8 for `STACK.md`.)
5. **This workflow lays code foundation only.** The box and its `STACK.md` passport come from `docker-deploy.md` — they are not created or duplicated here.
6. **All artifacts in English** (code, comments, docs, file contents). Chat with the human may be in another language.
7. **The foundation stays lean.** Fixed-schema, roughly half a page each; not a wiki. The high-value files are the ones the agent reads every task (`ARCHITECTURE`, `CONVENTIONS`) and the decision log — keep exactly those sharp, add nothing speculative. Drift and bloat are reconciled periodically by `/prune` (Phase 5).
8. **Secrets and data are never committed.** `.gitignore` covers `.env`, `data/`, and reproducible deps (`node_modules`, `venv`, `__pycache__`). Real secrets live only in `.env` (`chmod 600`), tracked by `.env.example` with empty values.

---

## 1. Phase: design (the planner step) — DECIDE before you build

This is the phase that prevents \"I came back a week later and remember nothing\". The architecture is not improvised by the executor — it is agreed on with the human, and the output of this phase *becomes* `ARCHITECTURE.md` and the founding entries of `DECISIONS.md`.

The design checklist below must be satisfied before Phase 2 — but **how** it gets satisfied depends on what was attached:

### Path A — a design artifact is already attached (the common case)

If a design artifact / pre-stack prompt produced in a separate **design session** (see `design-session.md`, Appendix A — the Design Brief) is attached, **Phase 1 is essentially already done** — that artifact *is* its output. The agent does **not** re-run the design session. Instead it:

1. **Validates** the artifact against the checklist below and lists any items it does not cover.
2. Surfaces gaps/contradictions to the human (do not fill them silently).
3. Once the human confirms (or fills the gaps), proceeds to Phase 2 — the artifact becomes the basis of `ARCHITECTURE.md` + the founding `DECISIONS.md` entries.

### Path B — no design artifact (start from scratch)

If nothing was pre-designed, the agent runs the design session here, converging with the human on the checklist below.

### The design checklist (both paths)

- **Purpose & scope of v1** — what it does, and what is *explicitly out of scope* for now. (Bounding scope counters over-planning; out-of-scope items go to a \"later\" note, not into v1.)
- **Stack** — language/framework, datastore, key libraries — each with a one-line rationale (rationale is recorded in `DECISIONS.md`).
- **Core entities / data model** — the main nouns and their relationships, sketched.
- **Components & responsibilities** — the few moving parts and what each owns; the data/control flow between them.
- **External interfaces** — the API surface or integrations, at a high level.
- **Deployment intent** — access mode A/B/C (feeds the later deploy and `STACK.md`).

> **STOP — human confirms the design before Phase 2.** On Path A, show the validation result (covered vs. gaps) and wait for an explicit \"yes\". On Path B, show the proposed architecture as a short summary and wait for \"yes\". No files, no code until the shape is agreed. If the human says \"I don't know yet what it'll be\" — that is the signal to *stay in this phase and decide*, not to start scaffolding a guess.

---

## 2. Phase: lay the foundation files

**First lay the skeleton — do not hand-build it:**

```sh
fraim scaffold
```

That creates the four foundation files, the whole `ai/` tree, a minimal `.gitignore` and `ai/fraim.conf`, all from fixed templates, and registers the project. It never overwrites anything that already exists. The shape of a project is a fixed structure, so it is not yours to re-derive — improvising it is how two projects laid down a month apart end up disagreeing about their own section names.

**Then fill it.** Each scaffolded file carries an `fraim:stub` marker line. Replace the placeholders with the real decisions from Phase 1 and **delete the marker line** from every file you filled — until it is gone, `fraim status` correctly reports the foundation as unfilled. Add `.env.example` yourself: its contents depend on the stack, so no template can guess it.

No placeholders left as placeholders.

- `README.md` — entry point: what it is, how to run it (dev), pointer to `STACK.md` for deploy, pointer to `ARCHITECTURE.md` and the `ai/` loop.
- `ARCHITECTURE.md` — purpose/scope, stack, components, data model, data flow, interfaces. Carries the read-first/update-last directive.
- `CONVENTIONS.md` — how we work here; the agent rules; the Known Pitfalls store; carries the load-every-session directive.
- `DECISIONS.md` — append-only log, seeded with the founding decisions from Phase 1 (stack choice, key trade-offs). Write each one with `fraim decide "<title>"`, body on stdin — the verb owns placement, heading and date, and it drops the `fraim:stub` marker once a real decision is in.
- `.gitignore`, `.env.example` — per invariant 0.8.
- `ai/` — the planner→executor structure (Appendix A).

> Show all generated files to the human before moving on.

**Then save the point.** `fraim scaffold` made this a repository if it was not one, so there is
somewhere to save to:

```sh
fraim commit bootstrap "<project> — foundation" README.md ARCHITECTURE.md CONVENTIONS.md DECISIONS.md .gitignore ai
```

Name the paths; the verb has no \"everything\" argument, which is what keeps `.env` and data out
of the history without anyone having to check. From here on every workflow leaves its own save
point, and `fraim undo` can take any of them back.

---

## 3. Phase: scaffold the code skeleton

Create the **minimal runnable skeleton** that the agreed architecture implies — not the whole application. Enough to prove the shape and give the executor a frame to fill in later tasks.

- Directory layout matching `ARCHITECTURE.md` (`src/`, modules per component).
- Dependency manifest (`requirements.txt` / `pyproject.toml` / `package.json`).
- An entrypoint that starts and a trivial **health endpoint** (so the later deploy's `healthcheck` has something to hit).
- A `Dockerfile` if the project is built rather than pulled (this is the bridge to the deploy workflow).
- Nothing host-level. Installing system packages, opening ports, touching `/etc` — all deferred to `docker-deploy.md` and its stop signals.

> Keep the skeleton honest: a \"hello world\" that genuinely matches the architecture beats a large generated app no one decided on.

---

## 4. Phase: hand off to the deploy workflow

When there is something to run, box it. Attach `docker-deploy.md` + a per-stack prompt and run it as normal. It produces the secure stack and the `STACK.md` passport.

- `README.md`'s \"Run / deploy\" pointer should reference `STACK.md`.
- `ARCHITECTURE.md`'s \"Deployment\" line records the access mode; the box details live in `STACK.md`, not duplicated in `ARCHITECTURE.md`.

> Deploy can happen early (to get a dev box) or late (once there is real functionality) — but the foundation (Phases 1–2) always comes first, so the box is never built around an undecided architecture.

---

## 5. Phase: the ongoing loop (how the foundation stays alive)

Bootstrap is a **one-time** act — it puts up the shelf. Keeping context current forever is the job of the **planner→executor loop** you already use, now operating on this foundation:

- `/make-task` (planner) writes a new task folder `ai/tasks/<slug>/`; `/run-task` (executor) picks a task from the queue, executes it, and archives the folder to `ai/archive/`; `/revise-task` (planner) repairs a plan the executor found defective; `/orient` re-loads context when you return after a break.
- **Reactive work needs no procedure at all**: a question, a small fix, a change whose shape appeared while doing it. It is the most frequent mode and it is legitimate at any size, as long as invariant 0.4 holds, a behaviour change leaves a line in `DECISIONS.md`, and each coherent piece gets its own save point. `/make-task` is not an escalation from it — it is the separate act of handing work to someone outside the conversation.
- `/reconcile-task` is the **drift valve at the close of execution**: when a `/run-task` session turned into live debugging and the code diverged from the plan, it folds the unplanned changes back into the record (a `DECISIONS` entry per behavioral delta, a divergence note in the task's `result.md`, generalizable gotchas into `CONVENTIONS`) and archives truthfully — but **only if the drift was surgical** (details the plan got wrong: a constant, URL, endpoint version, payload field, header). If the live edits were **structural** (changed approach, contracts, signatures, or component boundaries), it STOPS and hands the task to `/revise-task`, because a structural change made in the executor seat skipped the reference scan. The principle: *debug freely, but the archive must tell the truth.*
- `/prune` is the **gardener**: run every 2–4 weeks, or when the watchman reports the drift threshold reached (`fraim config` shows it), it reconciles the foundation against ground truth (code for `ARCHITECTURE`/`CONVENTIONS`/`DECISIONS`; infra for `STACK.md`), proposing diffs the human approves. It relocates superseded `DECISIONS` entries to `ai/archive/decisions_log.md` (append-only is preserved — relocate, never delete) and curates the Known Pitfalls store.
- **Every task reads `ARCHITECTURE.md` + `CONVENTIONS.md` first** (invariant 0.4) — that is how the agent re-enters with context instead of re-deriving it.
- **Every task that changes structure updates `ARCHITECTURE.md` as its final step**, and **appends a decision to `DECISIONS.md`** when it made a non-obvious choice — unprompted.
- **The executor's lessons feed the planner.** A generalizable gotcha the executor discovers (`(pitfall)` in its report) is proposed, on the user's approval, into `CONVENTIONS.md`'s `## Known Pitfalls / Lessons` — which `/make-task` reads. That closes the loop from execution back to planning quality.
- This is what gives you \"always-current context\": the bootstrap built the structure, the loop maintains it, the gardener keeps it lean.
- **The planner↔executor wall holds even during correction.** If the plan turns out wrong, the executor never improvises a fix — it records why in the task's `blockers.md` and hands back to `/revise-task`. (See the correction loop in those workflows.) The one legitimate in-seat exception is **operator-driven live debugging** — when *you*, consciously, feed live discoveries into a running `/run-task` — and even that is not a licence to leave a silent trail: the session is sealed honestly by `/reconcile-task`, which folds surgical drift into the record and refuses anything structural (sending it to `/revise-task`).

### Making it stick without you having to remember

The same approach as the deploy passport: the directives live *inside* the files the agent reads anyway. For zero-attachment safety, also register the rule wherever your agent auto-loads context — `AGENTS.md`, `CLAUDE.md`, a workspace rule: *\"Treat `ARCHITECTURE.md` and `CONVENTIONS.md` as authoritative, read them at session start, keep them current.\"* `fraim init` writes exactly such a block for every harness it finds.

---

## 6. Stop signals (the agent stops and asks the human)

- **Writing any code before the Phase 1 design is confirmed** by the human.
- **Inventing or changing the architecture without recording it** in `ARCHITECTURE.md` + `DECISIONS.md`.
- A scope that has quietly grown beyond the agreed v1 — surface it, do not silently build it.
- Anything host-level or box-level (installing packages, opening ports, editing `/etc`, system services) — that belongs to `docker-deploy.md`, with its own stop signals.
- Committing `.env`, real secrets, or `data/`.
- Deleting or rewriting history in `DECISIONS.md` (it is append-only; supersede instead, or relocate via `/prune`).

---

## Appendix A. What the skeleton contains

The templates are **not** reproduced here. `fraim scaffold` writes them, so there is exactly one
copy of each — a second copy in this document would drift from it, and the copy the model reads
is the one that would win. Read the files it created; each carries its own `AGENT DIRECTIVE`
block and its `fraim:stub` marker.

| File | What you fill in |
|---|---|
| `README.md` | what it is, how to run it in dev, pointers to `STACK.md`, `ARCHITECTURE.md` and the `ai/` loop |
| `ARCHITECTURE.md` | purpose & scope · stack · components & responsibilities · data model · data flow · external interfaces · deployment access mode |
| `CONVENTIONS.md` | house rules, the agent rules, and the `## Known Pitfalls / Lessons` store (starts empty) |
| `DECISIONS.md` | append-only log, seeded with the founding decisions from Phase 1 |
| `ai/` | `tasks/` (the queue, one folder per task) · `investigations/` · `archive/` (finished work under a timestamp, plus `decisions_log.md`) · `fraim.conf` |
| `.gitignore` | the two lines that are about secrets, not about the stack — extend for this project |

Keep each foundation file to about half a page (invariant 0.7), and delete the `fraim:stub` line
from every file you filled — while it is there, `fraim status` correctly calls the foundation
unfilled.

> One **folder per task** (named by a slug). The queue may hold several tasks, but only the one
> being executed is \"in flight\". A task with a `blockers.md` is paused awaiting `/revise-task`.
> Done tasks leave the queue only through a gate (`fraim task-seal`, or `fraim reconcile-seal`
> for a session that drifted), which is what keeps the archive honest.

> `ai/` and its contents are NOT secrets — they are tracked in git, so the decision and task trail
> travels with the repo.
