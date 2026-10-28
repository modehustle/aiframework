# CONVENTIONS — aiframework

> **AGENT DIRECTIVE — load every session, follow it.**
> Register this as your agent's workspace rule so it auto-loads.

- Workflow: reactive work in the session by default — almost always the answer. The board
  (`ai/tasks/<slug>.md`, `fraim tasks`) holds work the human put aside or a project; only the
  human puts a task there (`/make-task`) or says to take one (`/run-task`). The agent never
  routes itself into `/make-task` or `/conductor`, and never proposes them.
- A task card carries an intent (what, why, done-when), never the code's context: no paths,
  patterns, steps or snapshots. Whoever takes it reads the foundation and the code fresh.
- Before a task: `fraim brief` (the whole foundation, uncut). After: write what changed
  through the verbs — `fraim arch` for a map section, `fraim decide` for a decision,
  `fraim pitfall` for a lesson. Hand-editing the foundation is for this repo's own
  development of those verbs, not for agents working in a project.
- Verb text travels through `ENVIRON`, never `awk -v` (which expands backslash escapes), and
  helpers called from a verb prefix their variables (`_md_`, `_ac_`) — POSIX sh has no locals.
- Language: the product is English inside — code, comments, procedures, data formats (card
  headings), everything the CLI writes into a project (cards, journals, briefs, commit
  messages) and everything addressed to the agent (brief, skills, AGENTS.md block). Russian is
  the operator's locale only: what the CLI says to the human (messages, refusals, the
  watchman's verdict, `fraim help`). It is still hardcoded in the code and will move into a
  message catalog (`locale/ru`) so other languages can be added. Project docs (README, MODES,
  PRINCIPLES, AUDIT*, DESIGN*, BACKLOG, installer/*.md) may stay Russian during development
  and are translated before a public release. The human talks to the agent in any language.
  The write verbs enforce it (`lang.sh`): text they would put into a project — a decision,
  a pitfall, a map section, a card, a backlog question, a result line, a commit message,
  findings — is refused when it is not English; quoted words are not measured. `fraim
  commit` refuses to add such text to the foundation, cards or code comments (strings in
  code are the operator's and are not checked), and `fraim status` reports what is there.
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
> Gotchas this codebase has cost a session at least once. Every session reads these so the
> next change does not walk into the same trap. Two things add to the list, both on your
> approval: any session the moment something bites (`fraim pitfall`), and `/prune` when it
> finds a lesson in the save points that never got written down. `/prune` also curates.
- pi --list-models prints its model table to stderr, not stdout — a blind 2>/dev/null around a command source silently empties it; join streams and let pattern-based parsers filter
- roles.sh sourced standalone has no ade_timeout_bin (it lives in ade.sh); call sites must silence and tolerate its absence
- POSIX printf with more arguments than conversions reprocesses the surplus as FORMAT (dash) — build the string in a variable, then printf '%s
- '
- A stub CLI keyed on "$1 $2" must order overlapping patterns (worktree rm before worktree*) or cleanup verbs answer with the wrong subcommand's JSON
- Projects switched into the retired fleet mode carry a SessionStart hook that runs `fraim mode --hook` on every session start: that invocation must stay a silent exit 0 forever, or removing the verb breaks sessions in projects nobody is looking at
- A pipeline's exit status is its LAST command's: `dispatch_waves … | cut` (and `… | awk`) reported the filter's success and turned a refused plan (cycle, ghost After) into a confident answer — take the output into a variable first, then filter it. Both helpers had the bug; it survived one review
- `sh -c '…$VAR…'` inside single quotes runs in a child shell that has none of the caller's variables: the test harness must `export` every path it passes that way, or the child silently works on an empty path and the assertion fails somewhere else
- Worker checkouts are isolated by FILES only — ports, databases, caches and anything outside the repository are shared, and no check sees it (BACKLOG §6)
- `build_next_wave` answers "nothing left" both when every wave is collected and when the plan cannot be read — the same shape as the pipeline-exit bug above. Anything that must know "is this build finished" asks positively (every subtask present in `collected.tsv`), never by the absence of a next wave
- `read` with IFS set to a tab collapses empty fields and shifts the rest left (an empty `parent`
  moved every later field of a board line) — a record with possibly empty fields needs a
  non-whitespace separator (`\037`)
- POSIX sh has no local variables: a helper called from a verb overwrites the verb's own variables
  (`decide` lost its `_entry` to `fnd_move_decision`) — helpers prefix theirs (`_md_`, `_ac_`)
- A background command in a non-interactive shell reads /dev/null, not the caller's stdin — pass the
  descriptor explicitly (`exec 3<&0; cat <&3 &`), or the read silently gets nothing
