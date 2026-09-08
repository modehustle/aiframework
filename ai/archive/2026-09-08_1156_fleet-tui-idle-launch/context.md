# Task Context

## Plan provenance
- Planned: 2026-09-08
- Based on: HEAD 19879bc
- System: fraim 0.10.0

## Goal
Replace the single atomic `worker-start` fleet launch with a universal lifecycle that
creates the worktree, launches the agent, waits for a confirmed `tui-idle` terminal
state, and only then binds the Dispatch — so no prompt is ever injected into a TUI that
is not ready, and the role's model is actually applied for agents Orca cannot pass
`--model` to (Devin).

## Why
On Orca 1.4.196 / Devin CLI v3000.5.20, `worker-start --agent devin` injects the
orchestration preamble before Devin's TUI is ready: the PTY records `^[[200~` plus the
prompt text before the Devin banner, Orca times out at `dispatch_input` with
`agent_prompt_stalled`, and every worker of the build fails. Separately, Orca's
`--model` flag supports only Claude/Codex/Cursor, so a `devin:glm-5-2:high` role silently
runs on Devin's default model. Both need one structural fix: an explicit
create → launch → wait → dispatch sequence with the model folded into the launch command.
The diagnosis is archived in the youtube project investigation
`ai/archive/2026-09-08_1118_investigate_fleet-agent-prompt-stalled/findings.md`.

## Codebase Context
- `ARCHITECTURE.md` · **whole** — the project map; read first (invariant 0.4)
- `CONVENTIONS.md` · **whole** — house rules + Known Pitfalls the executor must follow
- `installer/lib/fleet.sh` · **whole** — the only file that knows an ADE exists; holds the
  capability cache (`fleet_caps_*`), in-session model command (`fleet_model_command`,
  `fleet_worker_set_model`), and the atomic `fleet_worker_start` being restructured
- `installer/lib/dispatch.sh` · `dispatch_run` launch loop (the `for _dl_id in …` block
  calling `fleet_worker_start` and `fleet_worker_set_model`) — the caller whose reporting
  must show the actually applied model
- `installer/lib/ade.sh` · `ade_cli` — how the Orca CLI executable is resolved
  (`orca-ide` on Linux, `$ORCA_CLI_COMMAND` in Orca-managed sessions); all new Orca calls
  go through `fleet_cli` like the existing ones
- `installer/lib/config.sh` · `config_get` — how machine config keys are read; new
  `launchcmd_<agent>` / timeout keys follow the same pattern as `modelcmd_<agent>`
- `installer/tests/run-tests.sh` · the fleet/ADE section (search for `fleetproj`) — the
  existing stub pattern: a fake `orca-ide` on PATH answers for Orca; new tests extend it
- `installer/tests/run-tests.sh` · `check` helper — how assertions are written and counted

## Orca CLI facts (verified against Orca 1.4.196 help and its bundled orchestration skill)
- `orchestration worker-start --model` supports only Claude, Codex, Cursor provider model
  ids; `--effort` requires `--model`; neither combines with `--terminal`.
- `worker-start --terminal <handle> --worktree <selector>` attaches a SUPERVISED worker to
  an existing terminal: it creates the Dispatch (full task/dispatch provenance,
  worker_done authority, lifecycle preamble) and injects the task input. This is the
  documented supervised path — unlike `orchestration dispatch --inject`, which is
  explicitly unsupervised (no `worker_dispatches` row, `worker-stop`/`worker-abandon`
  never close the process). Use `worker-start --terminal`, NOT `dispatch --inject`.
- Low-level recipe for custom agent argv (documented in Orca's bundled orchestration
  skill): `worktree create` (without `--agent`) → `terminal create --worktree <sel>
  --command "<argv>"` → `terminal wait --terminal <h> --for tui-idle --timeout-ms <n>`
  → `worker-start --task <id> --terminal <h> --worktree <sel>`.
- `terminal wait --for tui-idle` exits 0 only when the state is reached; nonzero on
  timeout. Always pass `--timeout-ms`.
- Cleanup verbs: `orchestration worker-release --dispatch <id>` (idempotent; closes only
  the coordinator-owned agent terminal), `terminal stop --worktree <sel>`,
  `worktree rm --worktree <sel>`. Orca responses carry `"ok": true|false`; ids carry
  their type prefix (`run_`, `task_`, `term_…`, `ctx_`) — extract via `fleet_id`.

## Constraints
- Do NOT modify: `procedures/` (engine-agnostic methodology never imports harness
  specifics), `reports/`, generated `.claude-plugin/` / `installer/claude-plugin/`.
- Must preserve: the six-operations split (dispatch.sh decides, fleet.sh executes); the
  capability cache format (`agent<TAB>fact<TAB>when`); `fleet_worker_show`,
  `fleet_worker_list`, `fleet_worker_release` signatures; Task/Dispatch provenance,
  worker_done, heartbeat, ask/reply, watch, verify — all of these ride on the Dispatch
  that `worker-start --terminal` creates, so switching the launch path must not bypass
  `worker-start`.
- Must preserve: the existing fast path `worker-start --agent <id> --model <m>
  --effort <e>` for agents that accept a launch-time model — it stays the default.
- No fixed `sleep` anywhere in the launch path; readiness is `terminal wait --for
  tui-idle` with a bounded timeout.
- No guessing of in-session model commands for unknown agents: `modelcmd_<agent>` stays
  the only fallback mechanism (built-in for claude, config for everything else).
- Shell style: POSIX `sh`, one library per concern, `installer/bin/fraim` stays a
  dispatcher. User-facing CLI output in Russian; identifiers/comments in English.
- Tests are added to the single suite `installer/tests/run-tests.sh`; run the whole
  suite after the change.

## Decisions and Rationale
- Chose **`worker-start --terminal` after an explicit wait** over `dispatch --inject`:
  `--inject` is unsupervised and loses worker lifecycle state (worker_done, stop/abandon,
  release accounting), which the requirements explicitly preserve.
- Chose **launch command via `terminal create --command`** over teaching Orca each
  agent's model flag: Orca's `--model` is a closed set (Claude/Codex/Cursor); folding the
  model into argv is the only universal mechanism, and it is exactly what Orca's own docs
  prescribe for custom argv.
- Chose **config key `launchcmd_<agent>`** (template with `%s` for the model id, same
  substitution rules as `modelcmd_<agent>`: shell parameter expansion, never printf) over
  a built-in per-agent catalogue: the catalogue treadmill is the failure mode this
  codebase already rejected twice (DECISIONS.md 2026-09-08 role-picker entry; the
  `fleet_caps_*` design in fleet.sh). One built-in exception is still required for Devin
  because the user's role table (`devin:glm-5-2:high`) must work with no extra config:
  built-in launch template for `devin` is `devin --permission-mode bypass --model %s`.
  Unknown agents get NO guessed launch command — they keep the native path.
- Chose **custom path trigger = `launchcmd_<agent>` configured OR capability
  `no-launch-model` known**: an agent that once refused `--model` must not be retried
  with it (existing cache semantics), and it must fall into the same explicit lifecycle
  rather than a Devin-only branch.
- Chose **readiness timeout as config** `fleet_ready_timeout_ms` (default 120000) over a
  hardcoded constant: Devin cold starts vary; a per-deployment override costs one
  `config_get`.
- Chose **cleanup on failed launch: worker-release (if a Dispatch exists) → terminal
  stop --worktree → worktree rm --worktree**, each best-effort and error-tolerant, over
  leaving partial resources for manual cleanup: requirement 6, and Orca's own receipts
  name `residualResources` as the thing a failed start leaves behind. The worktree is
  removed only when THIS call created it (custom path); the native `worker-start` path
  keeps its existing behaviour (Orca reports residual resources in its receipt, which is
  printed on failure as today).
- Rejected: increasing any sleep (masks the race, still racy); a Devin-only special case
  (the next agent hits the same wall); `dispatch --inject` (unsupervised, no provenance);
  guessing `/model …` for unknown agents (silently corrupts the first task line).
- Rejected **always using the custom path for every agent**: it would bypass Orca's
  native `--model/--effort` handling and its `launch.effective` receipt reporting for
  Claude/Codex/Cursor; the native path stays default and the custom path is the
  documented fallback.

## Known Pitfalls
- From CONVENTIONS.md: `roles.sh` sourced standalone has no `ade_timeout_bin`; call sites
  must silence and tolerate its absence.
- From CONVENTIONS.md: pi prints its model table to stderr — pattern-based parsers must
  join streams; relevant only if a new parser is added (not planned here).
- `fleet_id` requires hex after the prefix — state names like `dispatch_input` must never
  be captured as ids (the comment on `fleet_id` explains the colon+hex discipline; keep it
  in any new extraction).
- Under `set -e`, `_x=$(cmd)` assignment carries the exit status — capture failing
  commands through `if` (the comment on `fleet_worker_start` documents this; new code
  must follow it).
- A `worker-start --terminal` receipt may report `ready` while setup is still `running`;
  only exit code and `ok` decide success. Do not parse human text.
- Blind spot of the reference scan: the stub `orca-ide` in tests answers only the
  subcommands it was taught; any new Orca subcommand used by fleet.sh must be added to the
  stub or tests fail for the wrong reason.
- On Linux the real binary is `orca-ide`, never bare `orca` (GNOME screen reader) — tests
  already guard this; do not introduce a direct `orca` call.

## Out of Scope
- Changing Orca itself (the readiness race is Orca's bug; fraim only bypasses it).
- Any change to `roles.sh` model discovery or the roles picker.
- In-session model switching beyond the existing `modelcmd_<agent>` mechanism (it stays
  as the explicitly configured fallback; no new guessing).
- Retrying or requeuing failed builds; watch/verify/accept logic.
