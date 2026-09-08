# INVESTIGATION — models-from-binaries

## Baseline / provenance
- Planned: 2026-09-08
- Based on: HEAD 836801d
- System: fraim 0.10.0

## Investigation goal
Is the owner's revised idea feasible: instead of asking the ADE (Orca shows only accounts
activated through its own path), discover actual models by reading the globally installed
agent binaries/configs on the machine itself?

## Hypothesis register
| # | Hypothesis | Status | Evidence |
|---|---|---|---|
| 1 | Globally installed agents already carry per-machine model data that fraim can read — each in its own form | confirmed | On this machine (claude, codex, pi, cursor-agent installed): **codex** keeps `~/.codex/models_cache.json` — a full catalogue (8 models, slugs like `gpt-5.6-sol`, display names, `supported_reasoning_levels` low..ultra, `fetched_at`, etag, client_version). **pi** has `--list-models [search]` — live table (provider, model, context, thinking), including the user's OpenRouter catalogue (`openrouter anthropic/claude-*`, `google/gemini-*`, …). **cursor-agent** has `models` subcommand and `--list-models` — account models (`gpt-5.3-codex-*` with effort suffixes). **claude** exposes no list command (`--help` shows only `--model`/`--fallback-model`); its settings.json holds only the alias (`"model": "opus"`). |
| 2 | The discovered data covers BOTH halves of the picker's gap: model ids AND effort levels | confirmed | codex `models_cache.json` carries `supported_reasoning_levels` per model (low/medium/high/xhigh/max/ultra) — exactly what the hardcoded `roles_efforts()` (roles.sh:231) approximates. cursor-agent encodes effort in the model id itself (`gpt-5.3-codex-high`). pi reports thinking support per model. |
| 3 | The id formats differ per agent, so discovery must be per-agent adapters, not one parser | confirmed | codex: bare slugs (`gpt-5.6-sol`). pi: `provider/model` and `~alias` forms (`openrouter/anthropic/claude-sonnet-latest`, `sonnet:high`). cursor-agent: account slugs with effort suffixes. claude: full provider ids (what ROLES_BUILTIN already uses) or aliases. One global parser would be wrong at the first agent update — same lesson as ade.sh's "ask, don't parse guessed field names". |
| 4 | The ADE path (previous investigation) and this path are complementary, not competing | confirmed | Orca `account list` answers "which managed accounts work" (claude OAuth expired, codex ok on this machine); the binaries answer "what models exist". A picker wants both: availability from ADE, catalogue from the agent itself. |

## Diagnostic actions
- Enumerated installed agents: claude, codex, pi (nvm node bin), cursor-agent (~/.local/bin). omp, gemini, qwen, droid, aider absent.
- Read `~/.codex/models_cache.json` (8 models, effort levels, fetched_at 2026-09-08 — refreshed by codex itself), `~/.codex/config.toml` (current `model = "gpt-5.6-sol"`), `~/.claude/settings.json` (`"model": "opus"`).
- Ran read-only: `pi --list-models` (live catalogue incl. OpenRouter), `cursor-agent models` (account models), `--help` on all four.

## Outcome — fill exactly ONE branch

### DIAGNOSIS
The owner's revised idea is **feasible and stronger than the ADE-only path**. Every
globally installed agent already carries fresh, machine-local model data in one of three
forms, and fraim can read it at `fraim roles set` time:

| agent | source | gives |
|---|---|---|
| codex | `~/.codex/models_cache.json` | model slugs + display names + **effort levels** (self-refreshed, etag'd) |
| pi | `pi --list-models` | live catalogue incl. provider-key providers (OpenRouter), thinking flags |
| cursor-agent | `cursor-agent models` | account models, effort encoded in id |
| claude | (none) | typed value fallback — the existing behaviour, harmless |

Design shape for `/make-task` (structural):
- a per-agent **discovery table** in `roles.sh` (same pattern as `ade_table()` in ade.sh:
  agent → read-command), e.g. `roles_models_of AGENT`; each row is a tiny adapter over
  that agent's native format — never one global parser;
- effort levels: replace/extend the hardcoded `roles_efforts()` with per-agent levels
  where the source provides them (codex cache), fallback to the current rungs otherwise;
- keep the ratified constraints from the previous finding: no baked catalogue (treadmill
  P0), empty answer is valid and falls back to a typed value, picker mechanism unchanged
  (`roles_pick` takes the list on stdin);
- ADE stays the availability check (`roles_agents_available`), binaries become the
  catalogue source — the two compose at picker time.

Route: **structural → `/make-task`**, with
`ai/archive/2026-09-08_0628_investigate_model-selection-gap/findings.md` (the gap itself)
and this file (the discovery mechanism) as the two inputs.

### DEAD-END

## Touched / created manifest — REPO
- ai/investigations/models-from-binaries/findings.md (created by fraim investigate-new, filled by this session)

## State manifest — WORLD
- baseline: read-only session. Ran `--help`, `--list-models`, `models` (read-only listings)
  and read agent config/cache files. No accounts, rows, leases, workers or files mutated.

## Restored to baseline
repo: only the findings.md artifact was written (intentionally kept); no repo code touched.
world: nothing mutated — listings and file reads only, no undo needed.
