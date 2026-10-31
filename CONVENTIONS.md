# CONVENTIONS — aiframework

> **AGENT DIRECTIVE — load every session, follow it.**
> Register this as your agent's workspace rule so it auto-loads.

- Workflow: reactive work in the session by default — almost always the answer. The board
  (`ai/tasks/<slug>.md`, `fraim tasks`) holds work the human put aside or a project; only the
  human puts a task there (`/make-task`) or says to take one (`/run-task`); the agent never
  routes itself into `/make-task` and never proposes it. Parallel writing — two or more
  subagents changing code at once, on the human's word or the harness's own decision — goes
  through `/conductor`; subagents that only read do not need it.
- A task card carries an intent (what, why, done-when), never the code's context: no paths,
  patterns, steps or snapshots. Whoever takes it reads the foundation and the code fresh.
- Before a task: `fraim brief` (the whole foundation, uncut). After: write what changed
  through the verbs — `fraim arch` for a map section, `fraim decide` for a decision,
  `fraim pitfall` for a lesson. Hand-editing the foundation is for this repo's own
  development of those verbs, not for agents working in a project.
- Verb text never goes through `awk -v` (it expands backslash escapes). A short value (a
  heading, a name) travels through `ENVIRON`; text that can be long (a body, an entry, lines
  from stdin) travels through a file — `fnd_text_file` plus `slurp()` from `FND_SLURP` —
  because Linux caps one environment string at 128 KiB. Helpers called from a verb prefix
  their variables (`_md_`, `_ac_`, `_tf_`) — POSIX sh has no locals.
- Language: the product is English inside — code, comments, procedures, data formats (card
  headings), everything the CLI writes into a project (cards, journals, briefs, commit
  messages) and everything addressed to the agent (brief, skills, AGENTS.md block). What the
  CLI says to the HUMAN (messages, refusals, the watchman's verdict, `fraim help`, the screen)
  comes from the message catalog: `$(t key name=value)` and `$(tp N key)` for plurals, the text
  in `installer/locale/en/<module>.sh` and its translations in `installer/locale/<lang>/`. Never
  hardcode an operator message — a test refuses Cyrillic in the code outside known data. A new
  key goes into `en` and every shipped language with the same `{placeholders}`; a key name
  must not end in `_one`, `_few`, `_many` or `_other` unless it is a plural form. Keys chosen at
  run time (`t "cfg_label_$k"`) are not seen by the key rail: check them by hand. Project docs
  (README, MODES, PRINCIPLES, AUDIT*, DESIGN*, BACKLOG, installer/*.md) may stay Russian during
  development and are translated before a public release. The human talks to the agent in any
  language.
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
- POSIX printf with more arguments than conversions reprocesses the surplus as FORMAT (dash) — build the string in a variable, then `printf '%s\n'` it
- Projects switched into the retired fleet mode carry a SessionStart hook that runs `fraim mode --hook` on every session start: that invocation must stay a silent exit 0 forever, or removing the verb breaks sessions in projects nobody is looking at
- A pipeline's exit status is its LAST command's: `helper … | cut` (and `… | awk`) reported the filter's success and turned a refused plan into a confident answer — take the output into a variable first, then filter it. It survived one review
- `sh -c '…$VAR…'` inside single quotes runs in a child shell that has none of the caller's variables: the test harness must `export` every path it passes that way, or the child silently works on an empty path and the assertion fails somewhere else
- Worker checkouts are isolated by FILES only — ports, databases, caches and anything outside the repository are shared, and no check sees it (BACKLOG §6)
- Anything that must know "is this build finished" asks positively (every subtask present in `collected.tsv`), never by the absence of something left to do: an unreadable plan gives the same empty answer — the shape of the pipeline-exit bug above
- `read` with IFS set to a tab collapses empty fields and shifts the rest left (an empty `parent`
  moved every later field of a board line) — a record with possibly empty fields needs a
  non-whitespace separator (`\037`)
- POSIX sh has no local variables: a helper called from a verb overwrites the verb's own variables
  (`decide` lost its `_entry` to `fnd_move_decision`) — helpers prefix theirs (`_md_`, `_ac_`)
- A background command in a non-interactive shell reads /dev/null, not the caller's stdin — pass the
  descriptor explicitly (`exec 3<&0; cat <&3 &`), or the read silently gets nothing
- A build id made from the time to the second collides when two builds start within one second — the
  second overwrote the first's plan and journal; make it unique, with a suffix that cannot be read
  as part of a later `<build>-<subtask>` name (a letter glued on, not «-2»)
- `git branch -d` checks a branch against the CURRENT branch: a branch already merged into another
  one (the build branch, before it reaches the trunk) is refused and silently stays — delete it with
  `-D`, and only after checking its commit is an ancestor of where it was merged
