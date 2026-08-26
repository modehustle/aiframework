# Design Session Workflow for AI Agents (universal)

> A step-by-step playbook for the **thinking session that comes first** — deciding *what* you are about to stand up and *why*, before any folder, code, or container exists.
> The **front door** of the family. It routes to one of the two downstream playbooks and hands each the exact artifact it expects:
> - `project_bootstrap_workflow.md` — for an **authored** project (your own code). Input: a **Design Brief** (Appendix A).
> - `docker_deploy_workflow.md` — for an **off-the-shelf** stack (n8n, Postgres, Redis…). Input: a **per-stack prompt** (Appendix B).
> Purpose: persistent context for AI development assistants (Windsurf Cascade, etc.).
> The agent is a **thinking partner here, not a builder** — it challenges, explores, and converges; it does not write code or create files beyond the single output artifact.

## How to use this file

This session is **divergent then convergent** by nature, so the process below is deliberately about *thinking*, not mechanical steps. What is rigid is the **output**: a single artifact in a fixed schema that the next workflow consumes verbatim. The whole point of the session is to fill that schema *with the human*, not to guess it.

Run this **before** opening a project folder. There is no `/data/apps/<project>/` yet — the session produces an artifact you carry into the *next* session (where bootstrap or deploy actually creates the folder). The artifact is the contract between this workflow and the next.

> Engine-, language-, and domain-agnostic. Any concrete stack/framework/service named below is an **example**, never a default.

## How this fits with the other workflows

Three layers, one direction of flow:

| Stage | Workflow | Output | Answers |
|---|---|---|---|
| **Decide** (this) | this one | a Design Brief **or** a per-stack prompt | *What are we standing up, and why; which path does it take* |
| **Foundation** (authored only) | `project_bootstrap_workflow.md` | foundation files + code skeleton | *How is the code organized, why, how do we work on it* |
| **Box** (infra) | `docker_deploy_workflow.md` | secure stack + `STACK.md` passport | *What image/network/ports/data, how is it deployed* |

Canonical flow from a cold start:

1. **This session** with the human → the routing decision + the matching artifact.
2a. **Authored** → `project_bootstrap_workflow.md` Phase 1 **Path A** validates the Design Brief, then lays the foundation and skeleton; deploy boxes it later.
2b. **Off-the-shelf** → `docker_deploy_workflow.md` consumes the per-stack prompt directly.

---

## 0. Hard rules (invariants — must not be broken)

Checked ALWAYS, regardless of the topic:

1. **No building in this session.** No code, no scaffolding, no folder creation, no commands that change the system. The only output is one design artifact. (Building is the next workflow's job.)
2. **Decide WITH the human, never FOR them.** The agent proposes and challenges; the human chooses. A design is not "done" until the human says so explicitly.
3. **Challenge vagueness — do not paper over it.** Ambiguous or hand-wavy requirements are surfaced as open questions, not silently resolved with a guess. "I don't know yet" is a reason to *keep thinking*, not to pick something arbitrary.
4. **Every decision carries a rationale and the rejected alternatives.** This is what later seeds `DECISIONS.md`. A choice without "why" and "why not the others" is incomplete.
5. **Scope is bounded explicitly.** v1 / out-of-scope / later are separated on purpose. Over-planning is a failure mode; park future ideas in "later", do not fold them into v1.
6. **The output schema is a contract.** The artifact matches the consuming workflow's input exactly — Appendix A mirrors bootstrap's Phase 1 checklist; Appendix B mirrors deploy's per-stack prompt. Do not invent extra fields or drop required ones.
7. **All artifacts in English** (the brief, the prompt). Chat with the human may be in another language.
8. **The artifact stays lean.** Half a page to a page; decisions and rationale, not a spec novel. The downstream workflow expands it into files — this session only fixes the shape.

---

## 1. Phase: frame the problem (before any solution)

Resist jumping to a stack. First establish, with the human:

- **The problem / goal** — what need does this serve, for whom, and what does "it works" look like.
- **Constraints** — hard limits (existing infra, budget, languages the team knows, latency, data residency, deadlines).
- **Knowns vs unknowns** — write the unknowns down explicitly; they drive the questions in the next phases.

> Do not propose technology yet. A solution chosen before the problem is framed is a guess wearing a suit.

---

## 2. Phase: the routing decision (which downstream path)

Ask the one question that sends the work down the right pipe:

> **Will this stack contain my own code that I will keep developing?**

- **Yes** → **authored project**. The session targets the **Design Brief** (Appendix A) → feeds `project_bootstrap_workflow.md`.
- **No** → **off-the-shelf** service run as-is. The session targets the **per-stack prompt** (Appendix B) → feeds `docker_deploy_workflow.md` directly. The remaining phases shrink to "pick the image and the access mode"; there is no architecture to design.

> If it is a mix (your code + bundled off-the-shelf services), it is **authored** — the off-the-shelf parts become components in the Design Brief.

---

## 3. Phase: diverge (explore the option space)

For an authored project, lay out real alternatives before narrowing — at least where the choice is non-obvious:

- **Stack** — candidate languages/frameworks/datastores, with the trade-off each buys.
- **Shape** — candidate architectures (monolith vs services, sync vs event-driven, etc.) sketched at a high level.
- **Risks & unknowns** — what could make a given option wrong; what would need a spike to find out.

> Breadth here is cheap and prevents tunnel vision. Two or three viable options beat one unexamined default.

---

## 4. Phase: converge (decide, with reasons)

Narrow to a single choice per dimension and record **why**:

- **Stack** chosen + one-line rationale + what was rejected and why.
- **Core entities / data model** — the main nouns and their relationships, sketched.
- **Components & responsibilities** — the few moving parts, what each owns, the flow between them.
- **External interfaces** — the API surface or integrations, high level.
- **Deployment intent** — access mode A/B/C (this is what the box will need later).

> Each converged decision is a future `DECISIONS.md` entry. Keep the rationale and the rejected alternatives — that is the part you will thank yourself for in a month.

---

## 5. Phase: bound the scope

Split the work explicitly:

- **v1** — the smallest thing that proves the shape and delivers the goal.
- **Out of scope for now** — deliberately not built yet.
- **Later** — parked ideas, captured so they are not lost and not silently built.

> If v1 keeps growing during this phase, that is the signal to cut, not to expand the brief.

---

## 6. Phase: emit the artifact

Assemble the decisions into the artifact for the chosen path — **Appendix A** (authored) or **Appendix B** (off-the-shelf) — and hand it to the next session.

> **STOP — human confirms before the session ends.** Show the full artifact as a short summary and wait for an explicit "yes". Then state the next step plainly: *"Open the project folder and run `project_bootstrap_workflow.md` with this brief attached"* (or `docker_deploy_workflow.md` with this per-stack prompt). The artifact is the only thing that leaves this session.

---

## 7. Stop signals (the agent stops and asks the human)

- **Proposing technology before the problem is framed** (Phase 1 skipped).
- **Resolving a vague requirement by guessing** instead of surfacing it as an open question.
- **Recording a decision without rationale or rejected alternatives.**
- **v1 quietly growing** beyond what the human agreed — surface it, do not absorb it.
- **Starting to build** — any code, file, folder, or system-changing command in this session.
- Emitting an artifact that **does not match** the consuming workflow's schema (missing or invented fields).

---

## Appendix A. Design Brief (authored → `project_bootstrap_workflow.md`)

This is the artifact that bootstrap's **Phase 1, Path A** validates against. Fill every section from the converged decisions. Keep it to about a page.

````markdown
# DESIGN BRIEF — <project>

> Output of a design session. Feeds `project_bootstrap_workflow.md` (Phase 1, Path A).
> The agent there VALIDATES this against its Phase 1 checklist — do not leave gaps.

## Purpose & scope
<what v1 does, for whom> · Out of scope for now: <list> · Later: <parked ideas>

## Stack
<language/framework> · <datastore> · <key libs>
- Rationale: <why this> · Rejected: <what and why> — (each becomes a DECISIONS.md entry)

## Core entities / data model
<main nouns + relationships, sketched>

## Components & responsibilities
| component / dir | responsibility |
|---|---|
| <...> | <...> |
Data/control flow: <request/event → … → response/storage>

## External interfaces
<API surface / integrations, high level>

## Deployment intent
Access mode: <A internal | B HTTP-to-internet | C non-HTTP-to-other-machines>.
(Feeds the later deploy + `STACK.md`.)

## Open questions
<anything still unresolved that the human must answer before/early in bootstrap> | none
````

---

## Appendix B. Per-stack prompt (off-the-shelf → `docker_deploy_workflow.md`)

When the routing decision is "off-the-shelf", the session's output is the per-stack prompt that `docker_deploy_workflow.md` consumes (its Appendix A). The minimum to specify:

- **Image and tag** (`<image:tag>`), project/container name.
- **Access mode** (A/B/C) and port(s).
- **Resources:** `mem_limit`, `cpus`.
- **Volumes:** what to mount and where inside the image.
- **Environment variables / secrets:** which ones, what goes into `.env`.
- **Healthcheck command** for this image.
- **Engine specifics:** process UID, required `cap_add`, custom config, tuning.
- **Mode B:** the domain. **Mode C:** which private network/VPN and trusted sources.
- **Stateful?** Whether it holds irreplaceable data in `./data` (so the passport records it).

> This is an **input** to deploy; the `STACK.md` passport is deploy's **output**, not produced here.
