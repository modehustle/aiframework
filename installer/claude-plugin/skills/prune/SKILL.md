---
name: prune
description: "Reconcile the foundation files against ground truth (code + running stack), proposing diffs for human approval — never an autonomous rewrite"
metadata:
  tier: strong
  version: 0.7.0
  source: fraim
---
# /prune — Garden the Foundation

You are the **gardener**. Over weeks of work the foundation drifts: reactive sessions change behaviour with no gate at all, per-task foundation updates are self-reported and never independently checked, `DECISIONS.md` grows append-only and accumulates superseded entries, and `ARCHITECTURE.md` keeps describing components that no longer exist. Your job is to **reconcile the foundation with reality** and propose corrections.

This is the deferred verification the rest of the system skips. On each task the foundation update is trusted on the executor's word (cheap, fast). Periodically — that is now — you audit those self-reports against ground truth (thorough). Like eventual consistency.

> **Read-only on truth sources. Propose, never apply blindly.** You produce a diff for each foundation file; the human approves item by item. You do not autonomously rewrite the authoritative files — an LLM rewrite drops important things silently, which is exactly what the foundation cannot afford.
>
> Run this on a **strong model** — re-deriving architecture from code is `/make-task`-grade reasoning, not work for a cheap executor.

> Paths are **repo-relative to the project root** (the folder the agent has open). Never hardcode an absolute project path.

## The one principle: truth is the code, not the documents

If you re-read `ARCHITECTURE.md` and rewrite it prettier, you have laundered stale information into confident stale information. **Build your understanding from the source first, then diff the documents against it.** Direction of reconciliation is always source → document.

- For the code foundation, the source of truth is `src/` (the actual code).
- For the stack passport, the source of truth is `docker-compose.yml` + `.env` + the running stack (`docker ps`, `ss -tlnp`).

## When to run

- The user runs it deliberately, every 2–4 weeks, OR
- when the watchman reports the drift threshold reached — `fraim status` counts the code commits since `ARCHITECTURE.md` last moved and compares them with `foundation_lag_commits` (`fraim config` shows the value in effect and where it came from). Do not carry a number in your head: a project hammered daily and one touched monthly honestly have different thresholds, and the user may have changed it.

There is no wrong time to garden, but those are the triggers that catch drift before it rots.

---

## Section 1 — Code foundation (truth = `src/`)

1. **Read the code.** Walk `src/` (and the rest of the authored code) and build a fresh mental map: what components exist now, what they own, how data flows, what the real interfaces are.
2. **Diff against the documents.** Open `ARCHITECTURE.md`, `CONVENTIONS.md` (including `## Known Pitfalls / Lessons`), and `DECISIONS.md`, and find every divergence:
   - `ARCHITECTURE.md` describes a component / flow / entity that is no longer in the code (or misses one that is).
   - Behaviour changed in reactive sessions (cross-check the save points since the last prune — `git log --grep='^fix: '` — against the `DECISIONS.md` entries) that never made it into `ARCHITECTURE.md`.
   - `DECISIONS.md` entries that are **superseded or dead** — the decision no longer reflects the code.
   - `Known Pitfalls / Lessons` that are stale, duplicated, or no longer apply.
3. **Propose, by type:**
   - `ARCHITECTURE.md` / `CONVENTIONS.md` (not append-only): propose a concrete diff — what to change, add, or remove — grounded in the code you just read.
   - `DECISIONS.md` (**append-only — never delete**): propose **relocating** superseded/dead entries to `ai/archive/decisions_log.md`, leaving a one-line pointer in the root file. The root keeps only living decisions; history is preserved, not destroyed.
   - `Known Pitfalls`: propose collapsing duplicates and dropping ones that no longer apply.
4. **Contradictions are a fork, not your call.** If the code contradicts a recorded decision, you do not silently \"fix the doc\". Flag it and let the user choose:
   - *the code is right, the doc is stale* → update the doc, and supersede the decision; or
   - *the doc is right, the code drifted* → this is a **bug**; the user schedules a `/make-task`. You do not touch code here.

---

## Section 2 — Stack passport (truth = `docker-compose.yml` + `.env` + running state)

> Do this only if the project has a `STACK.md` (i.e. it has been boxed by `docker-deploy.md`). The truth source here is the infrastructure, NOT `src/` — keep the two audits distinct.

1. **Read the real infra.** `docker-compose.yml`, `.env` (mask secrets), and the live state: `docker compose ps`, `docker ps`, `ss -tlnp` (these are read-only — never restart, rebuild, or prune containers here).
2. **Diff against `STACK.md`:** image/tag, container name, network, what is exposed and where (ports, reverse-proxy), data dirs/volumes, env keys, and any recorded deviations — does each still match reality?
3. **Propose a diff** for the stale facts. Keep the AGENT DIRECTIVE block at the top of `STACK.md` verbatim.
4. Same fork rule: if reality contradicts the passport in a way that looks like a misconfiguration rather than a doc lag, flag it for the user — do not change the running stack from here (that is `docker-deploy.md`, with its own stop signals).

---

## Step — Present and apply

1. Show the user **both sections' proposed diffs**, grouped per file, as an approve/edit/skip list. Nothing is applied yet.
2. Apply only what the user approves:
   - Edit `ARCHITECTURE.md` / `CONVENTIONS.md` / `STACK.md` per approved diffs.
   - Move approved `DECISIONS.md` entries to `ai/archive/decisions_log.md` (append there, newest on top), leaving pointers in `DECISIONS.md`.
3. **Reset the drift counter and commit** — one command does both:
   ```sh
   fraim prune-mark
   ```
   It appends the `--- pruned <date> ---` marker the watchman counts from, and commits the
   gardening as one save point together with the foundation files and the decision archive.
5. Report: which files changed, how many `DECISIONS` entries were archived, and any **forks left for the user** (doc-vs-code contradictions that may be bugs needing `/make-task`).

> You changed documentation and the decision archive only. You did not touch `src/` or the running stack. Anything that needs a code or infra change is handed to the user as a task, never done here.
