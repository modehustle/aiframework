# Current Task

## Summary
Restructure the fleet worker launch into a universal lifecycle — worktree create →
agent launch → confirmed `tui-idle` wait → `worker-start --terminal` dispatch — with a
per-agent launch command that carries the model, so Devin (`glm-5-2`) and any future
agent without Orca-native `--model` support launch correctly and no prompt is ever
injected into an unready TUI.

## Files to Change

### `installer/lib/fleet.sh`
- **Action:** modify
- **Must be true after:**
  - A new `fleet_launch_command <agent> <model> <root>` exists: returns the launch
    command for the agent or fails. Resolution order: config `launchcmd_<agent>`
    (template, `%s` = model id, substituted by shell parameter expansion like
    `fleet_model_command`), then a built-in template for `devin`
    (`devin --permission-mode bypass --model %s`), else failure. No guessing for
    unknown agents.
  - A new `fleet_ready_timeout_ms <root>` exists: prints config `fleet_ready_timeout_ms`
    with default `120000`.
  - New low-level helpers exist and use `fleet_cli` + `fleet_ok` + `fleet_id` like the
    existing ones: `fleet_worktree_create` (worktree create without `--agent`, with
    `--name/--repo path:<root>/--base-branch`; prints the worktree selector),
    `fleet_terminal_create` (terminal create `--worktree <sel> --command "<argv>"`;
    prints the `term_…` handle), `fleet_terminal_wait_idle` (terminal wait `--for
    tui-idle --timeout-ms <n>`; exit code is the verdict, no output parsing).
  - `fleet_worker_start` implements two paths with the same signature and return
    contract (prints the `ctx_…` dispatch id, exit 0 only on success):
    - **native path** (default): exactly today's behaviour — `worker-start --agent
      --model --effort`, with the existing `no-launch-model` refusal learning; on a
      model refusal it now falls into the custom path below instead of retrying without
      the model.
    - **custom path** (taken when `launchcmd_<agent>` resolves, OR the agent is already
      known `no-launch-model`, OR the native attempt just refused the model): run
      `fleet_worktree_create` → `fleet_terminal_create` with the resolved launch
      command (model omitted from the template when the role named no model — a
      template without `%s`, or with the model empty, is sent as configured) →
      `fleet_terminal_wait_idle`; on wait timeout, clean up (see below), print a clear
      Russian error naming the agent and the timeout, and fail WITHOUT creating a
      Dispatch; on success run `worker-start --task <id> --terminal <handle>
      --worktree <sel>` (no `--model/--effort`) and print the `ctx_…` id.
  - A new `fleet_launch_cleanup` exists: best-effort, error-tolerant cleanup taking the
    dispatch id (may be empty), worktree selector and terminal handle —
    `worker-release` when a dispatch id is given, then `terminal stop --worktree`, then
    `worktree rm --worktree`; every step tolerated to fail, none aborts the next.
  - No `sleep` appears in any launch path.
- **Pattern reference:** `installer/lib/fleet.sh` itself (comment discipline, `if`
  capture of failing commands, `fleet_id` hex discipline, Russian stderr messages)

### `installer/lib/dispatch.sh`
- **Action:** modify
- **Must be true after:** the `dispatch_run` launch loop reports the actually applied
  model per worker: native path success → `агент модель усилие` as today; custom path
  success → states the model was applied via the launch command; custom path with no
  model → states no model was applied; `fleet_worker_set_model` / `modelcmd_<agent>`
  remains only as the explicitly configured in-session fallback after a successful
  launch (its existing call site and messages stay).
- **Pattern reference:** `installer/lib/dispatch.sh` `dispatch_run` loop (existing
  reporting style)

### `installer/tests/run-tests.sh`
- **Action:** modify
- **Must be true after:** a new test section (extending the existing fleet/ADE stub
  section around `fleetproj`) covers, via a scripted fake `orca-ide` whose responses
  the tests control:
  1. Devin with model `glm-5-2`: the fake records the calls; assert the sequence is
     worktree create → terminal create with command `devin --permission-mode bypass
     --model glm-5-2` → terminal wait tui-idle → worker-start with `--terminal` and
     WITHOUT `--model`, and the reported dispatch id lands in the fleet file.
  2. A second agent that accepts the model natively (e.g. claude + a model): assert
     `worker-start --agent … --model … --effort …` is called directly and no
     worktree/terminal create happens.
  3. An agent that never reaches `tui-idle` (fake `terminal wait` exits nonzero):
     assert the run fails, NO `worker-start` call was made, and the error names the
     agent.
  4. A launch failure before any Dispatch exists (fake `terminal create` fails):
     assert the run fails, no `worker-start`, and cleanup ran (`terminal stop` /
     `worktree rm` attempted — the fake records them).
  5. A prompt-send failure after the Dispatch exists (fake `worker-start` fails):
     assert the run fails and `worker-release` was attempted for the created dispatch.
  6. A retry of the whole `dispatch run` after a failed first attempt: assert no
     duplicate active rows for the same subtask in the fleet file (the second run
     writes one row per worker; failed first-attempt rows are not re-added as active).
  7. The applied-model reporting: assert the run output names the model for the
     custom-path worker (applied via launch command) and for the native worker.
  8. Cleanup invocation: assert `fleet_launch_cleanup` calls `worker-release`, 
     `terminal stop`, `worktree rm` in that order (fake records the call log).
- **Pattern reference:** the existing fleet/ADE section of the same file (stub `orca-ide`
  writing a call log to a file, `check` assertions)

## Step-by-step Implementation
1. Read `installer/lib/fleet.sh` and `installer/lib/dispatch.sh` in full; read the
   fleet/ADE test section of `installer/tests/run-tests.sh`.
2. Add `fleet_launch_command`, `fleet_ready_timeout_ms`, `fleet_worktree_create`,
   `fleet_terminal_create`, `fleet_terminal_wait_idle`, `fleet_launch_cleanup` to
   `installer/lib/fleet.sh`, following the file's existing comment and naming style.
3. Restructure `fleet_worker_start` into native + custom paths per the obligation above;
   keep the signature and the `ctx_…` output contract unchanged.
4. Update the `dispatch_run` loop's per-worker reporting in `installer/lib/dispatch.sh`
   to distinguish applied-model cases; keep the `modelcmd_<agent>` fallback call site.
5. Extend the fake `orca-ide` in the test section so it records every invocation to a
   log file and can be pre-programmed per test (env or per-test stub rewrite, matching
   how the existing section already varies stub behaviour).
6. Add the eight test groups listed under `installer/tests/run-tests.sh`.
7. Run the full suite; fix until green.

## Acceptance Criteria
- [ ] `fleet_launch_command devin glm-5-2 <root>` prints `devin --permission-mode bypass --model glm-5-2` without any config.
- [ ] `fleet_launch_command unknownagent glm-5-2 <root>` fails (non-zero) with no config; with `launchcmd_unknownagent` set it prints the substituted command.
- [ ] For a `no-launch-model` agent with a model, the launch goes through worktree → terminal create (model in argv) → tui-idle wait → `worker-start --terminal`, never `worker-start --agent --model`.
- [ ] A `tui-idle` timeout fails the launch before any `worker-start` call, with a Russian error naming the agent, and triggers cleanup.
- [ ] A failure before Dispatch creation and a failure after Dispatch creation each trigger the correct subset of cleanup (no `worker-release` in the first case; `worker-release` in the second).
- [ ] A retried `dispatch run` does not duplicate active fleet rows for the same subtask.
- [ ] The run output states which model was actually applied for each worker path.
- [ ] No `sleep` call exists in the launch code path of `fleet.sh`.
- [ ] Operator confirmed: on the live machine, one real `fraim dispatch run` against the youtube project with role `devin:glm-5-2:high` reaches `tui-idle` before prompt injection and the Devin banner appears before the task text in the terminal transcript.

## Verification Commands
```bash
sh installer/tests/run-tests.sh
grep -n 'sleep' installer/lib/fleet.sh && exit 1 || exit 0
```

## Foundation updates (executor's final step — invariant 0.4)
- `ARCHITECTURE.md`: update the `installer/lib/*.sh` component line (fleet row) to
  mention the confirmed-readiness launch lifecycle and per-agent launch commands.
- `DECISIONS.md`: append one entry — "fleet launch waits for confirmed tui-idle and
  applies the model via a per-agent launch command" — with the rejected alternatives
  from the task context.
- `CONVENTIONS.md`: propose (for human approval) a Known Pitfall line if the executor
  hit a silent-failure surprise in the Orca stub or receipt parsing.

## Executor Rules — read before starting

Your rules are `/run-task` itself — the procedure you are executing right now:
`## GATES` G1–G7, the plan-defect protocol at Step 4d, and Step 7 on the
foundation. They are not copied here on purpose: a copy in the plan is a second
source of truth that no one updates.
