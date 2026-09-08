# Current Task

## Summary
Add a per-agent model-discovery layer to `fraim roles set`: the model and effort pickers
are fed live from the chosen agent's own source (native command, cache file, or embedded
catalogue), with the typed value remaining as the always-present fallback.

## Files to Change

### `installer/lib/roles.sh`
- **Action:** modify
- **Must be true after:** a discovery table maps each known agent to its model source and
  parser; a `roles_models_of AGENT` function returns that agent's model ids (one per line,
  bare ids suitable for `--model`), printing nothing when the source is absent or
  unparseable; a `roles_efforts_of AGENT MODEL` function returns effort levels from the
  source where it provides them and falls back to the existing `roles_efforts` rungs
  otherwise; every parser is split into its own function taking text on stdin (testable
  without the agent installed), following the `roles_parse_providers` precedent.
- **Pattern reference:** `installer/lib/roles.sh` (`roles_providers` / `roles_parse_providers`)
  and `installer/lib/ade.sh` (`ade_table` / `ade_query`) for the table + timeout discipline.

### `installer/bin/fraim` (cmd_roles_set)
- **Action:** modify
- **Must be true after:** after the agent is chosen interactively, the model picker is fed
  with `roles_models_seen` output PLUS the live `roles_models_of AGENT` output (deduplicated),
  then the hardcoded suggestions; the effort picker is fed with `roles_efforts_of AGENT MODEL`;
  the non-interactive form and the final `roles_parse` validation are unchanged.
- **Pattern reference:** `installer/bin/fraim` · `cmd_roles_set`

### `installer/tests/run-tests.sh`
- **Action:** modify
- **Must be true after:** each new parser has tests against saved fixture text (captured
  real output of the source, committed as test data or inline heredocs), including one
  malformed/empty-input case per parser asserting empty output and exit 0; all existing
  tests still pass.
- **Pattern reference:** `installer/tests/run-tests.sh` · existing roles tests (grep for
  `roles_` to find them)

## Step-by-step Implementation
1. Read the two archived findings named in `context.md` (Codebase Context) — they hold the
   per-agent sources table this step implements.
2. In `installer/lib/roles.sh`, add the discovery table (same shape as `ade_table`):
   one row per agent — `devin` (command `devin models list`), `pi` (command
   `pi --list-models`), `cursor-agent` (command `cursor-agent models`), `codex` (file
   `~/.codex/models_cache.json`), `claude` (embedded catalogue in the claude binary,
   resolved via `command -v claude` then `readlink -f`).
3. Write one parser function per source, text-on-stdin → bare model ids on stdout:
   devin/cursor-agent/pi parse their text tables (strip headers, aliases, prices, effort
   suffixes — the id must be exactly what that agent accepts in `--model`); codex parses
   the JSON cache (slugs from the `models` array); claude greps the binary for the
   embedded catalogue entries (`{id:"claude-...` pattern) and prints the `id` fields.
   Every parser: empty or malformed input → empty output, exit 0.
4. Add `roles_models_of AGENT`: resolve the agent's row, run the source under a timeout
   (reuse the `ade_query` timeout discipline), pipe through the parser. Agent not in the
   table or source missing → empty output, exit 0.
5. Add `roles_efforts_of AGENT MODEL`: codex — effort levels from the model's
   `supported_reasoning_levels` in the cache; devin — effort rungs implied by the model
   family output; otherwise fall back to the existing `roles_efforts`.
6. In `cmd_roles_set`, replace the model-picker input with
   `{ roles_models_of "$_rs_agent"; roles_models_seen "$_rs_root"; roles_models_suggested "$_rs_tier"; } | sort -u`
   and the effort-picker input with `roles_efforts_of "$_rs_agent" "$_rs_model"`.
7. In `installer/tests/run-tests.sh`, add fixture tests per parser (real captured output
   as heredoc; assert exact id list) plus empty/malformed-input cases; run the suite.

## Acceptance Criteria
- [ ] `fraim roles set` (interactive, on a machine with the agents) offers, at the model
      step, the live catalogue of the chosen agent — verified for at least codex and devin.
- [ ] Each new parser returns exactly the expected id list on its fixture and empty output
      with exit 0 on empty and malformed input.
- [ ] `roles_models_of` for an unknown agent prints nothing and exits 0.
- [ ] The non-interactive form `fraim roles set KEY agent:model:effort` still works and
      still validates via `roles_parse`.
- [ ] `installer/tests/run-tests.sh` passes in full.
- [ ] Operator confirmed: run `fraim roles set`, pick codex, confirm the model menu lists
      the slugs from the codex cache (e.g. the gpt-5.6 family) rather than only claude ids.

## Verification Commands
```bash
sh installer/tests/run-tests.sh
```

## Foundation updates (executor's final step — invariant 0.4)
- `ARCHITECTURE.md`: Components table — the roles row gains "per-agent model discovery";
  Data flow gains the discovery step. One line each.
- `DECISIONS.md`: append one entry — "role picker models come from per-agent live sources
  (native command, cache file, embedded binary catalogue), no cache, provider HTTP APIs
  rejected".
- `CONVENTIONS.md`: propose a Known Pitfall line about the claude embedded-catalogue
  pattern being version-dependent (ask the human before writing).

## Executor Rules — read before starting
- already written by `fraim task-new` — leave it alone.
