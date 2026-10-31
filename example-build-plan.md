# Build plan: a sample

> The format of a round for `/conductor`. Checked by `fraim dispatch check example-build-plan.md`,
> which refuses a subtask with no files, one that is neither a board card nor has a summary, a
> project card as a subtask, the same subtask twice, `**After**`, and two subtasks over one path.
>
> On a real board a subtask is usually a card: `## Subtask: <card-slug>` plus `**Files**:`, and the
> card's «What and why» and «Done when» go into the worker's brief by themselves. The subtasks
> below are not on this repository's board, so each carries its own `**Summary**:` and
> `**Done when**:`.

## Contract

Every message the CLI prints to the human comes from the catalog: `t KEY name=value` in the code,
`M_KEY='text'` in `installer/locale/en/<module>.sh` and in each translation, with the same
`{placeholders}`. A worker adds keys to its own modules' catalogs only.

## Subtask: errors
**Summary**: bring the error messages of core and clean to the form «function: what is wrong»
**Done when**: every `die` in the two files reads that way, and the tests still pass
**Files**: installer/lib/core.sh, installer/lib/clean.sh, installer/locale/en/core.sh, installer/locale/en/clean.sh

## Subtask: logs
**Summary**: one format for the debug output of publish
**Done when**: publish prints through say/dim only, never straight to stdout
**Files**: installer/lib/publish.sh, installer/locale/en/publish.sh

## Subtask: docs
**Summary**: a section on the message catalog in the installer's README
**Files**: installer/README.md

---

No path appears in two subtasks — that is what lets the three run at the same time and be accepted
in one decision (MODES.md §11.2, option B). Had `docs` also edited `installer/lib/core.sh`, the
check would refuse, and the ways out, in order, are: merge the two into one subtask, redraw the
boundaries, or leave one for the next round — it starts from what this round left in the trunk.

The translations (`installer/locale/<lang>/…`) are deliberately in nobody's list: a file every
piece would touch a little is the conductor's own edit after the round, not a subtask.
