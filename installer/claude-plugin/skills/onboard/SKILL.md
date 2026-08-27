---
name: onboard
description: "Bring an EXISTING project or a STACK already running under the system — derive the foundation from reality, ratify it with the human, never redesign or reorganize"
metadata:
  tier: strong
  version: 0.2.0
  source: fraim
---
# /onboard — Bring an Existing Project Under the System

The rest of the family assumes **greenfield**: `design-session` → `bootstrap` → `docker-deploy`, deciding things *before* the code or the box exists. This workflow is the **on-ramp for what already exists** — a codebase you wrote (and evolved) before this discipline, or a stack you deployed before it.

The shape is **reverse bootstrap / reverse deploy**: greenfield goes design → documents → code; onboarding goes the other way — **reality → documents derived from it → ratified by the human**. The artifact on the way out is the same foundation; the direction is flipped. It shares its engine with `/prune` (read reality, build a fresh map) — the difference is that `/prune` *reconciles* a foundation that already exists, while `/onboard` *creates* one from scratch.

> **Non-destructive.** You ADD the foundation files, the `ai/` structure, and a git baseline. You do **NOT** move, rename, or rewrite existing code, and you do NOT touch the running stack. Reorganizing the repo or remediating the box is later, deliberate `/make-task` / `docker-deploy` work — never part of onboarding.
>
> **Derive WITH the human, do not fabricate.** You read reality and propose a draft; the human ratifies and corrects. The human knows what the code cannot show — what is dead, what is load-bearing, what is out of scope.
>
> Run this on a **strong model** — recovering architecture from existing code is `/make-task`/`/prune`-grade reasoning.

> Paths are **repo-relative to the project root** (the folder the agent has open). Never hardcode an absolute project path.

> **Детерминированные действия делает `fraim`, не ты.** Где стоит команда `fraim …`,
> выполняй её, а не воспроизводи результат руками: формат, пути и коммит — не твоя забота.
> Нет `fraim` — **остановись и скажи об этом**, как `/docker-deploy` останавливается на
> хостовых действиях. У детерминированного действия ровно одна реализация.

This is a **one-time** act per project. Afterward the project is a normal citizen: `/make-task`, `/run-task`, `/hotfix`, `/prune` work on it identically, and `/prune` maintains the foundation from there. Think of `/onboard` as the manual first `/prune` that also stands up `ai/` and the git baseline.

## Which sections to run (same routing question as the design session)

- **It contains your own code** → run **Section 1**.
- **It is already deployed (a running box)** → run **Section 2**.
- **Both** (authored code + its deployed box) → run both.
- **A pure off-the-shelf service deployed long ago** (n8n, Postgres, Redis…) → **Section 2 only** — it gets a passport, no code foundation, exactly as in the greenfield split.

---

## Section 1 — Code foundation from existing code (truth = the actual code, wherever it lives)

### Step 1 — Discover the real structure (do NOT assume `src/`)

There is no standard layout to expect. The code may sit flat in the root, nested under one or more app folders, or scattered. **Inventory the tree and classify** what you find — code vs. config vs. data vs. logs vs. docs vs. tests vs. cruft. Then orient yourself by what actually runs and what it depends on, not by folder names:

- **Entrypoints** — `run_*` scripts, `package.json` scripts, `systemd` units, `main`/`app` modules. These reveal the real moving parts.
- **Dependency manifests** — `requirements.txt`, `pyproject.toml`, `package.json`. These reveal the stack.

### Step 2 — Surface ambiguity and cruft to the human — disambiguate, do not guess

Organically-grown repos carry signals the code alone cannot resolve. Flag each and ask, rather than documenting a guess as fact:

- **Parallel / duplicate components** (e.g. two backend dirs) — which is live, which is dead?
- **Versioned filenames** (e.g. `foo_v3_5.py` next to older versions) — which is current?
- **Dead-code graveyards** (e.g. a `trash/` or `old/` dir) — exclude from the map.
- **Pre-existing docs** (`*.md`, a `docs/` dir, deploy guides) — treat as **input, not authority**. Read them, let them inform the derived `ARCHITECTURE.md`, but the human decides what is still true. Some may be stale; some may be superseded by the new foundation.
- **An existing `ai/` folder** — do NOT clobber it. Inspect and reconcile (it may be a half-started adoption).

### Step 3 — Derive the foundation, lean, at useful granularity

- `ARCHITECTURE.md` documents the **actual layout as it is** — not the standard one. The components table is **conceptual** (the real moving parts, pointing at where they live), not a file-by-file listing. Keep it ~half a page (invariant 0.7).
- `CONVENTIONS.md` captures the conventions the code **already follows** (naming, structure, style) + the agent rules + the `## Known Pitfalls / Lessons` section, seeded with any gotchas the human names.
- `DECISIONS.md` starts **near-empty**. You do not know the rationale behind past choices, so do **not** fabricate history. Seed one entry — `## <date> — onboarded: foundation derived from existing code` — plus any decisions the human wants to record going forward. The log accumulates from onboarding onward.

### Step 4 — Ratify with the human, then stand up `ai/`

Show the drafts; the human corrects what the code could not tell you. On confirmation, create the `ai/` structure at the root — `tasks/`, `archive/` (with `decisions_log.md` when first needed), `hotfix_log.md`, `README.md` — without moving any code.

---

## Section 2 — Stack passport from a running box (truth = `docker-compose.yml` + `.env` + live state)

> Do this only for a stack that is already running. **Do not redeploy.** You document what is there.

### Step 1 — Read the live reality (read-only — never restart/rebuild/prune)

`docker-compose.yml` if it exists, `.env` (mask secrets), and the live state: `docker ps`, `docker compose ps`, `ss -tlnp`. If there is **no compose file** (the container was started by hand with `docker run`), reconstruct the intended config from `docker inspect` and record honestly: *\"no compose file — reconstructed from running state; formalize later via docker-deploy.\"*

### Step 2 — Derive `STACK.md` and flag legacy deviations

Fill the passport (Appendix C of `docker-deploy.md`) from what is actually running. A box deployed before the discipline will likely **violate the deploy invariants** — the default `bridge` network, a DB port on `0.0.0.0`, a container running as root, no compose file. Record each in `STACK.md`'s **Deviations / legacy risks** section, marked **accepted** or **should be remediated**.

> You do **NOT** fix the running stack here. Remediation is a deliberate `docker-deploy.md` change, one risk at a time, with its own stop signals (opening a port, restarting, `chown`, etc.). Onboarding gives the human an honest passport plus a risk to-do list — not a silently re-secured prod.

---

## Step — Git baseline (the dangerous step — do it carefully)

Onboarding an existing folder is exactly where `git init` is riskiest: the folder is already full of `.env`, `data/`, `__pycache__`, backup tarballs. A blind `git add .` commits secrets and gigabytes of data.

1. **Detect git.** Is there a `.git`? Does `git status` work?
2. **If NOT in git:** write/fix `.gitignore` **first** (`.env`, `data/`, logs as appropriate, `node_modules`, `venv`, `__pycache__`, `*.tar.gz` and other backup archives). Then run `git init` and `git status`, and **show the human exactly what would be committed.** Verify no secrets, data dirs, or backups are staged. Only then make the baseline commit `onboard: foundation + baseline`. **This is a stop-signal moment — human eyes before the first commit.**
3. **If already in git:** make the baseline commit `onboard: add foundation`. Still check `.gitignore` covers secrets and cruft; if committed cruft already exists (e.g. `__pycache__`, backup archives), note it for the human — purging it from history is out of scope here, but `.gitignore` should at least stop it growing.

---

## Step — Present and finish

1. Show the human: the derived foundation files (Section 1), the derived `STACK.md` + deviations list (Section 2), and the git status. Nothing is final until the human approves.
2. On approval, apply and **commit** as one save point.
3. Report:
   - What was created (`ARCHITECTURE.md` / `CONVENTIONS.md` / `DECISIONS.md` / `ai/` / `STACK.md`).
   - Which ambiguities the human resolved (dead code, live component, stale docs).
   - Which **deviations / legacy risks** remain as to-dos (each a future `docker-deploy` change or `/make-task`).
   - That the project is now a normal citizen — point the user at `/orient` for re-entry and `/make-task` for the first real task.

> Onboarding **documents and ratifies the present**; it does not redesign, reorganize, or remediate. Anything that changes code or the running stack is normal work afterward, never done here.

## Before you derive anything — lay the skeleton

```sh
fraim scaffold
```

It creates the foundation files, the `ai/` tree and `ai/fraim.conf` from fixed templates, and registers the project. **It never overwrites**, so running it on a project that already has some of these files is safe — that is the normal onboarding case.

Now you are not inventing structure, you are filling it: read reality, propose the content of each section to the human, write it in, and **delete the `fraim:stub` marker line** from every file you filled. Until that line is gone, `fraim status` reports the foundation as a scaffold rather than a foundation — which is exactly right, and is why an empty skeleton can never masquerade as a healthy project.
