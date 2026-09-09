# DECISIONS — aiframework  (append-only)

> Newest on top. One entry per decision. Never rewrite history — supersede with a new
> entry, or relocate stale entries to `ai/archive/decisions_log.md` via `/prune`.

## 2026-09-09 — two modes, not three: reactive is the default, fleet is the switch

Context: `MODES.md` described three modes (reactive, task, parallel), but the task mode was never one: by the five-row test in MODES.md §1 it differs from reactive in nothing, and the `mode` config key never switched it on — `task` was literally "not parallel". The name promised authority the code did not implement, and the agent read it as licence to write a task for itself and then execute it in the same session.
Decision: `mode` takes `reactive` (default) and `fleet`. The task ceremony (`/make-task` → `/run-task` → `task-seal`) stays as a PROCEDURE inside the reactive mode — the way to hand work to someone who is not in this conversation — and writing a task for yourself to execute in the same session is now stated as forbidden in the AGENTS.md project block. The legacy values `task` and `parallel` are read as `reactive`/`fleet` (mode_canon in config.sh) but never written; `fraim mode task|parallel` still works and warns. Every "is the fleet on here" test goes through `mode_get`, so a legacy value cannot silently fall back to the default.
Alternatives: renaming without legacy aliases rejected (every installed project carries `mode = parallel` in ai/fraim.conf and would silently lose the mode); keeping `parallel` as the name rejected (the human switches on a fleet, not a property of the work, and `fraim fleet` already exists); dropping `/make-task` along with the mode rejected (the fleet worker IS a `/run-task`, and handing work to another session is a real need).
Consequences: MODES.md §2 is now two modes and keeps the old anchor `#2-три-режима` so existing links do not break; the conductor procedure says `fraim mode fleet`. The refusal class "chunks overlap, cannot split" is untouched by this and is the next piece of work (sequential waves + a collect verb).

## 2026-09-08 — role picker agent list comes from the harness table, not Orca

Context: `roles_agents_available` asked Orca (`orca account list --json`) for the list of agents in the role picker, coupling the picker to a specific execution environment. Devin (a harness fraim installs into) was invisible because Orca doesn't list it as a provider; Kimi (not installed, not in the harness table) appeared because Orca knows it as a provider. The product is environment-agnostic — Orca is one possible ADE, not a dependency.
Decision: `roles_agents_available` now reads from `harness_detect` (harness.sh) — the same table fraim uses to install skills, probed by binary on PATH or home directory. `roles_providers` and `roles_parse_providers` removed as dead code. The picker shows only agents fraim knows and can serve; Orca remains the execution environment for fleet launch (a separate concern).
Consequences: an agent not in the harness table cannot be picked even if Orca can launch it — add it to `harness_table` first. A harness present on the machine but not on PATH appears via its home directory probe.

## 2026-09-08 — fleet launch waits for confirmed tui-idle and applies the model via a per-agent launch command

Context: Orca 1.4.196 + Devin CLI inject the orchestration preamble before the TUI is ready (agent_prompt_stalled at dispatch_input, every worker of a build dies), and Orca's worker-start --model supports only Claude/Codex/Cursor, so role-table models for other agents were silently dropped. Diagnosis archived in the youtube investigation fleet-agent-prompt-stalled.
Decision: fleet_worker_start becomes a two-path lifecycle with one contract. Native path (default): worker-start --agent --model --effort as before. Custom path (when a launch command is known via config launchcmd_<agent> or the devin built-in "devin --permission-mode bypass --model %s", or the agent is known no-launch-model): worktree create -> terminal create --command (model in argv) -> terminal wait --for tui-idle (config fleet_ready_timeout_ms, default 120000) -> worker-start --task --terminal --worktree, which keeps full task/dispatch provenance and worker lifecycle. Failures clean up best-effort: worker-release (dispatch recovered from the receipt or dispatch-show), terminal stop, worktree rm. No sleep anywhere; readiness is the terminal's own state. In-session model switching stays only as explicitly configured modelcmd_<agent>.
Alternatives: increasing sleep rejected (masks the race, still racy); a Devin-only branch rejected (next agent hits the same wall); dispatch --inject rejected (unsupervised, loses worker_done/stop/release accounting); always using the custom path rejected (bypasses Orca's launch.effective reporting for Claude/Codex/Cursor); guessing in-session commands for unknown agents rejected (silently corrupts the first task line).
Consequences: an agent whose launch argv changes needs a launchcmd_<agent> config update; a tui-idle timeout now fails the worker honestly instead of delivering a prompt into an unready TUI; the stub orca-ide in tests must answer the new subcommands.

## 2026-09-08 — role picker models come from per-agent live discovery, not a catalogue

Context: the roles picker offered only hardcoded claude suggestions plus already-configured models; a wrong id surfaced only at fleet launch, where it degraded silently. Investigations (archived findings 2026-09-08) confirmed every installed agent carries its own fresh model data.
Decision: the roles picker discovers models live from the chosen agent itself (roles_models_of): native listing command first (devin, pi, cursor-agent), cache file (codex) or embedded binary catalogue (claude) as fallback, typed value when nothing answers. Effort levels come from the same source where provided. No cache, no provider HTTP APIs, one tolerant parser per source tested against fixtures.
Alternatives: direct provider API queries rejected (keys, network, a second support surface); a baked catalogue rejected (treadmill P0); a single global parser rejected (formats differ per agent and drift independently); a TTL cache rejected (measured source latency 0.06-1.6s makes staleness pointless).
Consequences: an agent update can break its parser — the failure mode is an empty list degrading to the typed value, and fixture tests catch it before production.

## 2026-09-08 — onboarded: foundation derived from existing code

Foundation (ARCHITECTURE.md, CONVENTIONS.md) derived from the existing code: POSIX-shell CLI in installer/, 13 procedures in procedures/, plugin packaging, session traces in reports/. Ratified by the human; root docs (README, MODES, PRINCIPLES, DESIGN, AUDIT*, BACKLOG) treated as design input that may drift.
