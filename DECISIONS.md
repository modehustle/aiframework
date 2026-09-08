# DECISIONS — aiframework  (append-only)

> Newest on top. One entry per decision. Never rewrite history — supersede with a new
> entry, or relocate stale entries to `ai/archive/decisions_log.md` via `/prune`.

## 2026-09-08 — role picker agent list comes from the harness table, not Orca

Context: `roles_agents_available` asked Orca (`orca account list --json`) for the list of agents in the role picker, coupling the picker to a specific execution environment. Devin (a harness fraim installs into) was invisible because Orca doesn't list it as a provider; Kimi (not installed, not in the harness table) appeared because Orca knows it as a provider. The product is environment-agnostic — Orca is one possible ADE, not a dependency.
Decision: `roles_agents_available` now reads from `harness_detect` (harness.sh) — the same table fraim uses to install skills, probed by binary on PATH or home directory. `roles_providers` and `roles_parse_providers` removed as dead code. The picker shows only agents fraim knows and can serve; Orca remains the execution environment for fleet launch (a separate concern).
Consequences: an agent not in the harness table cannot be picked even if Orca can launch it — add it to `harness_table` first. A harness present on the machine but not on PATH appears via its home directory probe.

## 2026-09-08 — role picker models come from per-agent live discovery, not a catalogue

Context: the roles picker offered only hardcoded claude suggestions plus already-configured models; a wrong id surfaced only at fleet launch, where it degraded silently. Investigations (archived findings 2026-09-08) confirmed every installed agent carries its own fresh model data.
Decision: the roles picker discovers models live from the chosen agent itself (roles_models_of): native listing command first (devin, pi, cursor-agent), cache file (codex) or embedded binary catalogue (claude) as fallback, typed value when nothing answers. Effort levels come from the same source where provided. No cache, no provider HTTP APIs, one tolerant parser per source tested against fixtures.
Alternatives: direct provider API queries rejected (keys, network, a second support surface); a baked catalogue rejected (treadmill P0); a single global parser rejected (formats differ per agent and drift independently); a TTL cache rejected (measured source latency 0.06-1.6s makes staleness pointless).
Consequences: an agent update can break its parser — the failure mode is an empty list degrading to the typed value, and fixture tests catch it before production.

## 2026-09-08 — onboarded: foundation derived from existing code

Foundation (ARCHITECTURE.md, CONVENTIONS.md) derived from the existing code: POSIX-shell CLI in installer/, 13 procedures in procedures/, plugin packaging, session traces in reports/. Ratified by the human; root docs (README, MODES, PRINCIPLES, DESIGN, AUDIT*, BACKLOG) treated as design input that may drift.
