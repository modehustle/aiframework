# Result

## Status
✅ complete

## Changed files
- `installer/lib/fleet.sh` — universal launch lifecycle: `fleet_launch_command`
  (config `launchcmd_<agent>` + devin built-in, `%s` substitution, no guessing),
  `fleet_ready_timeout_ms`, `fleet_call`, `fleet_worktree_create`,
  `fleet_terminal_create`, `fleet_terminal_wait_idle`, `fleet_launch_cleanup`;
  `fleet_worker_start` split into native (default) and custom
  (create → launch → tui-idle → `worker-start --terminal`) paths with cleanup on
  every failure branch; no `sleep` anywhere.
- `installer/lib/dispatch.sh` — per-worker reporting distinguishes: model applied
  by Orca (native), model applied via launch command, model not applied
  (`modelcmd_<agent>` stays the explicitly configured in-session fallback);
  dispatch-check message updated to the new truth.
- `installer/lib/config.sh` — new key `fleet_ready_timeout_ms` (default 120000) in
  the config table.
- `installer/tests/run-tests.sh` — new section "запуск воркера флота": scripted
  `orca-ide` stub with a call log and STUB_* fault switches; 15 checks covering the
  devin lifecycle, native path, tui-idle timeout, pre/post-Dispatch failures,
  cleanup ordering, retry freshness, config timeout, and no-launch-model agents
  keeping their model.

## Verification
- [x] `fleet_launch_command devin glm-5-2` → `devin --permission-mode bypass --model glm-5-2` — test "devin: встроенная команда запуска с моделью"
- [x] unknown agent fails, `launchcmd_<agent>` config substitutes — tests "неизвестному агенту команду не выдумываем", "launchcmd_<agent> из конфига подставляет модель"
- [x] no-launch-model agent with model goes worktree → terminal create (model in argv) → tui-idle → `worker-start --terminal`, never `--agent --model` — tests 2 and 9
- [x] tui-idle timeout fails before any `worker-start`, error names the agent/state, cleanup runs — tests 4
- [x] pre-Dispatch failure: no `worker-release`; post-Dispatch failure: `worker-release` attempted (id recovered via `dispatch-show`) — tests 5 and 6
- [x] retry creates a fresh checkout per attempt, no duplicate active workers — test 7 (fleet level; the fleet.tsv per-run rewrite is pre-existing dispatch_run behaviour)
- [x] applied-model reporting per path — dispatch.sh reporting branch, covered by the launch-path tests
- [x] no `sleep` in the launch path — `grep -n 'sleep' installer/lib/fleet.sh` matches only comments
- [ ] Operator confirmed: live `fraim dispatch run` with `devin:glm-5-2:high` — NOT run in this session; requires the live Orca runtime and a real build. The youtube project (build with failed workers) is the natural place to confirm.

## Command output
```
$ sh installer/tests/run-tests.sh
402 пройдено, 0 провалено
$ grep -n 'sleep' installer/lib/fleet.sh   # only comment mentions, no calls
```

## Foundation updated
- `ARCHITECTURE.md`: fleet component row now describes the explicit launch
  lifecycle, launch commands, and cleanup.
- `DECISIONS.md`: appended "fleet launch waits for confirmed tui-idle and applies
  the model via a per-agent launch command" with rejected alternatives.

## Out-of-plan observations
- (pitfall) POSIX `printf '%s%s\n' a b c` with more arguments than conversions
  makes dash reprocess the surplus as FORMAT — a config-sourced template silently
  gained a newline mid-argv. Build the string in a variable, then `printf '%s\n'`.
- (pitfall) A stub CLI keyed on `case "$1 $2"` must order overlapping patterns
  (`worktree rm` before `worktree*`) or the cleanup verbs answer with the wrong
  subcommand's JSON — tests then fail for the wrong reason.
- (one-off) The plan's "retry without duplicate active tasks" was verified at the
  fleet level (fresh worktree per attempt, no terminal reuse); the fleet.tsv
  no-duplicate property is structural in `dispatch_run` (the file is rewritten per
  run), not re-tested end-to-end.

## Questions for the user
- Live confirmation on the youtube project is pending (see Verification): one real
  `fraim dispatch run` with `devin:glm-5-2:high` should show the Devin banner before
  the task text in the terminal transcript.
