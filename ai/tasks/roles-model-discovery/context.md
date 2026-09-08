# Task Context

## Plan provenance
- Planned: 2026-09-08
- Based on: HEAD 357888d
- System: fraim 0.10.0

## Goal
In `fraim roles set`, the model and effort steps offer a live, self-refreshing list pulled
from the chosen agent itself, so the user always picks from a menu and never has to type a
model id from memory.

## Why
Parallel mode resolves roles to `agent:model:effort`, but the picker's model list has no
connection to the chosen agent: it shows three hardcoded claude ids plus whatever is already
in the config files. A first-time user has no honest list; a wrong id surfaces only at fleet
launch, where it degrades silently (launch retried without the model). Two investigations
(archived findings referenced below) confirmed every installed agent carries fresh,
machine-local model data in its own form — the missing piece is a per-agent discovery layer
in the picker.

## Codebase Context
- `ARCHITECTURE.md` · **whole** — the project map; read first (invariant 0.4)
- `CONVENTIONS.md` · **whole** — house rules + Known Pitfalls the executor must follow
- `installer/lib/roles.sh` · `roles_providers`, `roles_parse_providers`, `roles_pick`, `roles_models_seen`, `roles_efforts` — the module being extended; mirror its conventions: ask whoever actually knows, an empty answer is legal, parsers split out and testable against saved fixtures
- `installer/lib/ade.sh` · `ade_table`, `ade_query` — the table pattern (agent → how to ask) and the timeout discipline to copy
- `installer/bin/fraim` · `cmd_roles_set` — the picker flow the new sources plug into
- `ai/archive/2026-09-08_0628_investigate_model-selection-gap/findings.md` · **whole** — the gap being closed: what is broken and why
- `ai/archive/2026-09-08_0633_investigate_models-from-binaries/findings.md` · **whole** — the discovery mechanism: per-agent sources table and design shape

## Constraints
- Do NOT modify: `installer/lib/ade.sh`, `installer/lib/fleet.sh`, `installer/lib/dispatch.sh`, `procedures/`, `installer/templates/`
- Must preserve: `roles_resolve` / `roles_parse` behaviour and the `agent:model:effort` value format; `roles_pick` contract (list on stdin, prompt on stderr, answer on stdout, typed value always accepted); non-interactive form `fraim roles set KEY VALUE` unchanged
- Stack: POSIX sh compatible; no new dependencies; no network calls initiated by fraim itself (only invoking installed agent CLIs and reading their files)
- Style: mirror roles.sh — Russian user-facing strings, English identifiers/comments, one function per concern, `set -e`-safe patterns (see the `roles_list` comment about `[ -n ] &&` under `set -e`)

## Decisions and Rationale
- Chose **per-agent discovery table** (one row per agent: native command → parser) over a single global parser — id formats differ per agent and each agent updates its own format; one parser breaks at the first agent update.
- Chose **native command first, binary/catalogue fallback** over HTTP queries to provider APIs — the agent already maintains its own catalogue (self-refreshing, authenticated); provider APIs would add keys, network and a second support surface. No agent today lacks both a command and an embedded catalogue.
- Chose **live query at picker time, no cache** — measured costs: `devin models list` ~1.2 s, `pi --list-models` ~1.1 s, `cursor-agent models` ~1.6 s, grep over the claude binary ~0.06 s, codex is a file read. A cache would reintroduce the staleness treadmill this design exists to avoid.
- Chose **tolerant parsers tested against fixtures** — an agent update that breaks a parser must surface as a test failure, not as an empty list in production; and an empty list in production must degrade to the typed value, never to an error.
- Effort levels come from the source where it provides them (codex cache, devin output), falling back to the existing `roles_efforts()` rungs — the picker stays honest where the source is richer, unchanged where it is not.

## Known Pitfalls
- The claude catalogue lives inside a minified binary; the extraction pattern is version-dependent. A miss must be silent and fall back — never an error. Candidate for `## Known Pitfalls / Lessons` after this task lands.
- `verb_section_filled` (installer/lib/verbs.sh) treats any non-whitespace text as a filled section and any `<...>` as an unfilled placeholder — avoid angle brackets in generated prose; irrelevant to runtime but bit this project's own gates twice.
- `set -e` + `[ -n "$x" ] && …` inside `$( )` kills the subshell — see the comment at `roles_list` in roles.sh; same trap applies to any new compound command.
- Reference-scan blind spot: `cmd_roles_set` builds the model list inline in installer/bin/fraim; grep found no other consumer of `roles_models_seen`/`roles_models_suggested`, but the executor should re-grep at runtime in case new call sites appeared.

## Out of Scope
- Validating the chosen model at dispatch/launch time (the `no-launch-model` silent-retry path).
- Querying provider HTTP APIs (OpenRouter etc.) directly.
- Any caching layer or TTL.
- Changing the `roles` listing output (`fraim roles` without `set`).
