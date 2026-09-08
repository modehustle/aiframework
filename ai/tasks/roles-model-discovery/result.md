# Result

## Status
⚠️ complete with caveats

Caveat: the test suite carries 8 failures that pre-exist on the base commit (verified
by running the suite on clean HEAD: 357 passed / 8 failed before, 368 / 8 after —
this task added 11 passing checks and broke nothing). They are stale expectations
from before the 13th procedure (`onboard`) landed; listed under Out-of-plan observations.

## Changed files
- `installer/lib/roles.sh` — per-agent discovery table, five parsers (devin, pi,
  cursor-agent, codex, claude), `roles_models_of`, `roles_efforts_of`
- `installer/bin/fraim` — `cmd_roles_set` feeds the model picker with the live
  catalogue of the chosen agent (+ seen + suggested, deduplicated) and the effort
  picker with `roles_efforts_of`; the "(недоступен: …)" strip moved before the
  model lookup, which keys on the bare agent name
- `installer/tests/run-tests.sh` — fixture tests per parser + empty/malformed-input
  cases + unknown-agent case

## Verification
- [x] Live catalogue at the model step, codex and devin — `roles_models_of codex`
      returns the 8 slugs from `~/.codex/models_cache.json`; `roles_models_of devin`
      returns 191 ids; pi 246, cursor-agent 217, claude 19 (junk entries filtered by
      requiring `,family:` after the id).
- [x] Each parser: exact id list on fixture; empty output, exit 0 on empty and
      malformed input — 11 `ok` lines in the suite's `roles: discovery моделей` section.
- [x] `roles_models_of` for an unknown agent prints nothing, exits 0 (`rc=0`).
- [x] Non-interactive form unchanged — `roles_parse` validation untouched; the
      existing suite sections covering `fraim roles set KEY VALUE` still pass.
- [x] `installer/tests/run-tests.sh`: 368 passed, 8 failed — all 8 pre-existing
      (see caveat).
- [ ] Operator confirmed: run `fraim roles set`, pick codex, confirm the model menu
      lists the codex cache slugs (gpt-5.6 family), not only claude ids.

## Command output
```
roles: discovery моделей
  ok   парсер devin: только id, без заголовков и aliases
  ok   парсер cursor-agent: id до дефиса, без заголовка
  ok   парсер pi: поле модели, без заголовка и тильды
  ok   парсер codex: slug из JSON-кэша (pretty и одной строкой)
  ok   парсер claude: id из embedded-каталога бинарника
  ok   парсер …: пустой/битый вход — пусто, код 0   (×5)
  ok   roles_models_of неизвестного агента пуст и без ошибки
368 пройдено, 8 провалено
```

## Foundation updated
- `ARCHITECTURE.md`: Components table (roles row) and Data flow gained the
  per-agent live model discovery; one line each.
- `DECISIONS.md`: appended "role picker models come from per-agent live discovery,
  not a catalogue" (via `fraim decide`).

## Out-of-plan observations
- (pitfall) `pi --list-models` prints its table to **stderr**, not stdout — a blind
  `2>/dev/null` around a command source silently empties it. Command sources in
  `roles_models_of` join the streams and let the pattern-based parser filter.
- (pitfall) `roles.sh` sourced standalone has no `ade_timeout_bin` (it lives in
  `ade.sh`); the call site silences and tolerates its absence, but a test harness
  that sources only `roles.sh` will not have the timeout wrapper.
- (bug) `installer/tests/run-tests.sh` expects 12 procedures and 12/13 skills —
  stale since `onboard` became the 13th procedure; 8 failures across the suite
  trace to these counts (also `голый ~/.gemini — это не Antigravity` and two
  fleet-environment checks). For the user to schedule via `/make-task`.
- (bug) `verb_section_filled` (installer/lib/verbs.sh) treats ANY non-whitespace
  text as a filled section and any `<...>` as an unfilled placeholder — it
  mis-landed an investigation outcome as DEAD-END earlier today and rejects
  legitimate prose containing angle brackets. Needs a stricter contract.

## Questions for the user
- The `Operator confirmed` criterion is open: run `fraim roles set` in a terminal,
  pick codex, and confirm the model menu shows the codex cache slugs.
- Approve the two `(pitfall)` lines for `## Known Pitfalls / Lessons`?
