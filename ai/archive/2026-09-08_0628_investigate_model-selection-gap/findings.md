# INVESTIGATION — model-selection-gap

## Baseline / provenance
- Planned: 2026-09-08
- Based on: HEAD b3bba55
- System: fraim 0.10.0

## Investigation goal
Where exactly is the model-selection gap in parallel mode (role → agent → model → effort),
and is the owner's idea feasible: discover models per provider at setup time, querying
providers directly for agents that carry a provider key (e.g. OpenRouter)?

## Hypothesis register
| # | Hypothesis | Status | Evidence |
|---|---|---|---|
| 1 | The picker's model list is not tied to the chosen agent: the same suggestions are shown regardless of agent, and no check exists that the model is served by that agent's provider | confirmed | `installer/bin/fraim:1145-1153`: agent picked via `roles_agents_available`, then model picked from `roles_models_seen` (config files) + `roles_models_suggested` (3 hardcoded claude ids) + typed value — the agent name is never consulted. `roles_parse` checks shape only (roles.sh:89-103); comment admits "whether THIS machine has that agent is the adapter's question … at launch". |
| 2 | fraim keeps no model catalogue by design (treadmill P0), and nothing live fills the vacuum — so on a first run the user must type provider model ids from memory | confirmed | roles.sh:146-152 "we do not keep a catalogue of the world's models"; `roles_models_suggested` is 3 claude ids (roles.sh:50-57); `roles_models_seen` is empty until the second role is configured (roles.sh:215-226). |
| 3 | The only live discovery channel (ADE `orca account list --json`) knows providers, not models — and only claude/codex; API-key agents (OpenRouter etc.) are invisible to it | confirmed | roles.sh:174-203 parses `orca-ide account list --json`; live run on this machine returned only `claude` (token expired) and `codex` blocks; no model list in the schema. `ade.sh` fixed six operations (§9), none is "list models". |
| 4 | When a model does not apply, failure is silent-ish: launch retries WITHOUT the model and the worker runs on whatever default — selection time never warns | confirmed | fleet.sh:258-271: on `launch-time model` error the launch is retried without `--model` and `no-launch-model` is noted; dispatch.sh:394-404 then tries `modelcmd_<agent>` and only *reports* if the model was not applied. Nothing at `fraim roles set` time. |
| 5 | The owner's idea is feasible within existing principles: ask whoever actually knows, at picker time, per agent — same pattern as `roles_providers` | confirmed | roles.sh already establishes the pattern ("each source below asks whoever actually knows, returns nothing when nobody does"). Providers with a public/cheap models endpoint: OpenRouter `GET /api/v1/models` (public, no key), Anthropic `GET /v1/models` (key), OpenAI `GET /v1/models` (key). A `roles_models_of <agent>` that queries live and falls back to typed value fits without baking a catalogue into fraim. |

## Diagnostic actions
- Read `installer/lib/roles.sh` (whole), `installer/lib/fleet.sh` (model paths), `installer/lib/dispatch.sh` (model application/reporting), `installer/lib/ade.sh` (what the environment can be asked), `installer/bin/fraim` cmd_roles_set (picker flow).
- Ran `orca-ide account list --json` on this machine: providers claude (OAuth token expired) and codex (ok); no model catalogue anywhere in the response.
- Read MODES.md §11.3 (role table design) and §12 (rejected alternatives — a baked catalogue was already rejected once).

## Outcome — fill exactly ONE branch

### DIAGNOSIS
The gap is a **missing middle layer**: model selection has two dead-end sources (a 3-line
hardcoded claude suggestion list + whatever is already in the config files) and one live
source that answers the wrong question (ADE knows *providers*, not *models*). Nothing
connects the chosen agent to the models that agent can actually serve, and nothing queries
a provider for its catalogue. Consequences, all confirmed in code:

1. `fraim roles set` shows claude model ids even when the chosen agent is codex; a
   first-time user has no honest list and must type ids from memory.
2. A wrong model id is not caught until fleet launch — and there it degrades silently:
   the launch is retried *without* the model (fleet.sh:267-271) and the worker runs on the
   agent's default, with only an after-the-fact report line.
3. API-key providers (OpenRouter etc.) are entirely outside the discovery surface: ADE's
   `account list` covers managed claude/codex accounts only.

**Feasibility of the owner's idea: yes, and it fits the existing architecture.** The
pattern already exists in `roles_providers()` — "ask whoever actually knows, return
nothing when nobody does". The fix is a sibling function `roles_models_of <agent>` that,
at picker time, asks the model source that agent actually uses:

- OpenRouter: `GET https://openrouter.ai/api/v1/models` — public JSON, no key needed;
- Anthropic / OpenAI: `GET /v1/models` with the key already in the harness config/env;
- managed claude/codex via ADE: whatever the environment can enumerate (may be nothing —
  a typed value stays the fallback, which keeps an incomplete list harmless, exactly as
  roles.sh:148-152 argues).

Route: **structural → `/make-task`**. It is a new picker source plus an agent→models
contract (per-provider query, key handling, caching policy, offline fallback) — multiple
files (`roles.sh`, `fraim` cmd_roles_set, possibly `ade.sh`), a new network call class,
and a design decision about where provider keys live. Not surgical.

Design constraints to carry into the plan (from PRINCIPLES/MODES, already ratified):
- no catalogue baked into fraim (treadmill P0, roles.sh:146-152) — query live, cache
  nothing or briefly;
- a miss must be silent and harmless — typed value always remains (roles.sh:150-152);
- picker already reads from /dev/tty with the list on stdin (roles_pick) — a new source
  plugs in as another stdin producer, no new mechanism.

### DEAD-END
(not used)

## Touched / created manifest — REPO
- ai/investigations/model-selection-gap/findings.md (created by fraim investigate-new, filled by this session)
- /tmp/devin-overflows-1000/66380c1d/content.txt, /tmp/devin-overflows-1000/5cf4c9f0/content.txt (truncated command output, outside repo)

## State manifest — WORLD
- baseline: read-only session. `orca-ide account list --json` and `orca-ide --help` were
  run read-only; no accounts, rows, leases, workers or files were created or mutated.

## Restored to baseline
repo: only `ai/investigations/model-selection-gap/findings.md` was written (a durable
finding, intentionally kept — it is the artifact); no repo code was touched, `git status`
carries nothing of this session outside `ai/`. world: nothing was mutated — no undo needed.
