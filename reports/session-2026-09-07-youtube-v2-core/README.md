# Session report: first live fraim parallel build (youtube / v2-core)

Date: 2026-09-07 · Project: /data/apps/youtube (YouTube Niche Analyzer v2)
Build: build-20260907-140427 · Base 0598a13 → HEAD 0cc9cd3 (master) · 4 subtasks, 4 workers
Outcome: build accepted, merged, 95 tests pass, real end-to-end pipeline run verified.

## Contents

- `conductor-trace.jsonl` — reconstructed trace of the conductor session (devin CLI does
  not persist transcripts; this is a faithful event reconstruction, secrets redacted).
- `worker-search.jsonl`, `worker-comments.jsonl`, `worker-llm.jsonl`, `worker-pipeline.jsonl`
  — raw JSONL transcripts of the four worker sessions (Claude Code format).
- `journal.md` — the build journal with conductor lessons (as written at acceptance).
- `fleet.tsv.corrupt` — the fleet cache AS WRITTEN BY fraim at launch (dispatch id column
  contains the stage string `dispatch_input` instead of real `ctx_…` ids) — physical
  evidence for the adapter parsing bug.
- `fleet.tsv.fixed` — the same file after manual repair from
  `orca orchestration worker-list --json`.

## Bug summary (priorities)

1. **P0 — fleet_id parsing.** fraim extracts the first `dispatch_…`-shaped token from the
   Orca `worker-start` response; the real dispatch id form is `ctx_…`, and the response
   also contains a stage field `dispatch_input` that matches the pattern. Result: every
   worker recorded with a bogus id → `watch`/`verify`/`accept` chain broken; cache had to
   be repaired manually. (The conductor skill itself predicted this: "первый реальный
   прогон покажет форму dispatch_… и статусов, которых в справках нет".)
2. **P0 — no role preflight at `dispatch check`.** Role `devin:glm-5.2:high` passed
   dispatch-check, then every worker failed at launch: Orca rejects launch-time model
   selection for the `devin` agent. The roles parser also cannot express "agent without
   model" (all three `agent:model:effort` fields must be non-empty), so the config could
   not be fixed without changing agent. Preflight should probe agent×model×environment
   before handing out tasks.
3. **P1 — build id mismatch.** `fraim dispatch ПЛАН` seals journal under
   `build-<timestamp>`, but `run`/`accept` accept any id (`v2-core` worked for run,
   failed for accept with "нет журнала"). Canonical id should be echoed and validated.
4. **P1 — verify does not see worker worktrees.** `dispatch verify` diffs the project
   root, but workers commit in isolated worktrees; the conductor had to verify manually
   per worktree. Also `succeeded` workers can leave work uncommitted — verify should
   check worktree `git status` too.
5. **P2 — diagnostics.** `dispatch run` failure output is one generic warning; per-worker
   stderr (already printed by dispatch_launch) is lost in captured output. `watch` prints
   raw JSON blobs.

## Agent-side lessons (conductor behaviour, for the same report)

- Parallel mode was ON per AGENTS.md, but the conductor wrote the bootstrap skeleton by
  hand; the human had to flag it. Mode check should happen at session start, not after
  foundation work.
- Workers treat `DECISIONS.md` as "theirs": 2 of 4 subtasks edited it though it was not
  in their declared paths. Plans should either declare foundation files in one dedicated
  subtask or state the prohibition more forcefully.
