# CONVENTIONS — aiframework

> **AGENT DIRECTIVE — load every session, follow it.**
> Register this as your agent's workspace rule so it auto-loads.

- Language: code, comments, docs in English. Chat may be in another language.
- Workflow: planner→executor→reviser. Task queue in `ai/tasks/<slug>/`; archive to `ai/archive/`.
  Commands: `/make-task`, `/run-task`, `/revise-task`, `/reconcile-task`, `/orient`, `/prune`.
  Most sessions need none of them: reactive work is the default mode.
- Before a task: read `ARCHITECTURE.md` + this file (including Known Pitfalls below).
  After: update them if changed; append any non-obvious choice to `DECISIONS.md`.
- Solo-operator note: you may be both planner (`/make-task`) and executor (`/run-task`),
  sometimes even running a strong model as executor. The temptation to improvise as
  executor is strongest then, because you remember the plan's intent. Resist it — if the
  plan is wrong, that is `blockers.md` + `/revise-task`, even on your own plan.
- Queue discipline: keep the queue shallow. If two queued tasks touch the same files they
  are NOT independent — sequence them explicitly or merge them, or the second plan goes
  stale when the first lands.
- Language: this is a Russian-language product. Procedure text, commit messages, and
  user-facing CLI output are written in Russian; code identifiers and this foundation
  file's structural prose in English. Chat may be in another language.
- Two-layer split: `procedures/` is the canonical engine-agnostic methodology —
  never import harness specifics there. `installer/` is delivery code; harness
  knowledge lives only there.
- Generated artifacts (`.claude-plugin/` payload, `installer/claude-plugin/`, skills)
  are rebuilt by `fraim build` — do not hand-edit them; change the source and rebuild.
- Shell style: POSIX `sh` compatible; one library per concern in `installer/lib/`;
  the `installer/bin/fraim` entrypoint stays a dispatcher, logic goes into `lib/`.
- Tests: `installer/tests/run-tests.sh` is the single integration suite — run it after
  any CLI change.
- Version bumps are deliberate and rare (`installer/VERSION`); the plugin manifest
  version is separate and generated.
- `reports/` holds session traces as debugging evidence — append-only artifacts, not
  code; never refactor or clean them casually.
- Secrets: never commit `.env` or `data/` (see `.gitignore`).

## Known Pitfalls / Lessons
> Gotchas this codebase has cost an execution at least once. `/make-task` reads these so
> the planner does not walk a new task into the same trap. Three things add to the list, all
> on your approval: `/run-task` from its `(pitfall)` observations, `/prune` when it finds a
> lesson in the save points that never got written down, and any ordinary session the moment
> something bites — that last one is where most of them come from. `/prune` also curates.
- pi --list-models prints its model table to stderr, not stdout — a blind 2>/dev/null around a command source silently empties it; join streams and let pattern-based parsers filter
- roles.sh sourced standalone has no ade_timeout_bin (it lives in ade.sh); call sites must silence and tolerate its absence
- POSIX printf with more arguments than conversions reprocesses the surplus as FORMAT (dash) — build the string in a variable, then printf '%s
- '
- A stub CLI keyed on "$1 $2" must order overlapping patterns (worktree rm before worktree*) or cleanup verbs answer with the wrong subcommand's JSON
- The project mode has legacy values on disk (`task`, `parallel`): compare `mode_get` against `reactive`/`fleet`, never `config_get mode` against a literal — a raw comparison reads a legacy value as "not fleet" and switches the mode off silently
