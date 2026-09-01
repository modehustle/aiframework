#!/bin/sh
# context.sh — the pointer block written into AGENTS.md / CLAUDE.md.
#
# The context layer is the weaker but wider half of the delivery: 30+ agents
# read AGENTS.md, and for the ones whose skills do not auto-trigger, this block
# is the only thing that tells them the procedures exist at all. It is a
# pointer, never a copy — the procedure text lives in the skills.

CTX_BEGIN='<!-- fraim:begin — managed by `fraim init`, do not edit inside -->'
CTX_END='<!-- fraim:end -->'

context_block() {
    cat <<'BLKEOF'
## Workflow procedures (fraim)

This machine runs the **fraim** workflow system. Where the work has a shape worth
planning, it moves through an explicit procedure, invoked as a skill. Not all work
has that shape — see *Working without a procedure* below.

**Invariant 0.4 — the golden rule.** In a project that has them, `ARCHITECTURE.md`
and `CONVENTIONS.md` are read FIRST before any task and updated LAST after it,
without being asked. `DECISIONS.md` is append-only. A stale foundation is a bug.

| Situation | Procedure |
|---|---|
| deciding what to build, before any code exists | `/design-session` |
| new authored project, foundation not laid yet | `/bootstrap` |
| packaging a stack into Docker | `/docker-deploy` |
| making a running service reachable from outside | `/expose` |
| a feature or a notable change was just agreed | `/make-task`, then `/run-task` |
| the executor reported the plan is defective | `/revise-task` |
| the run drifted into live debugging and is done | `/reconcile-task` |
| where is this bug / is X even feasible | `/investigate` |
| the documents drifted from the code | `/prune` |
| returning to a project after a break | `/orient` |
| a project that existed before this system | `/onboard` |

### Working without a procedure

Most sessions are not a planned task: a question, a small fix, a look around, a change
whose shape only appeared while doing it. **That is legitimate** — do not force it into
`/make-task`, and do not announce a procedure you are not running. Two things still hold:

- **Invariant 0.4 applies anyway.** Read the foundation first; if the change made it
  wrong, fix it before you finish.
- **Behaviour changed → one line in `DECISIONS.md`.** Any change to what the program does
  leaves a trail. Pure cosmetics — a comment, a log string, formatting — need no entry.
- **Save as you go.** When a coherent piece is done — not at the end of the session, a
  session can die — put down a save point naming the paths you changed:
  `fraim commit fix "<what changed>" <path> <path>`. Those commits **are** the record of
  reactive work; there is no separate log to keep.

Reactive work has **no size limit** — a long session with a human in it is not a failure
mode. `/make-task` is not the procedure for "this got big"; it is the procedure for
**handing the work to someone who is not in this conversation** — a fresh chat, a cheaper
executor, tomorrow's you. Size does not decide that, and neither do you: the human does.
You are about to change something you do not understand → `/investigate`.

`fraim status` gives a deterministic verdict on the current project — drift count,
blockers, stale plans, foundation freshness. It reads files only and costs nothing.

**The system's own rule:** the watchman notices, the human decides. Do not start a
mutating procedure because a status line suggested it.
BLKEOF
}

# The block written into the PROJECT's own AGENTS.md, as opposed to the machine's.
#
# The two are not the same text and must not be merged. The machine block routes to
# procedures installed on this machine; this one describes THIS project to whatever agent
# opened it, including one that has never heard of fraim — a web session, a cloud agent,
# CI, another person's harness. That is the case it exists for: the foundation travels in
# the repository, but until now the instruction to honour it did not, so the invariant held
# only on the machine that ran the installer.
#
# Hence it names no slash-commands and assumes no CLI: it states the invariant, then says
# what to do with fraim and what to do without it.
context_project_block() {
    cat <<'BLKEOF'
## Project foundation

This project keeps a persistent foundation. Read it before you change anything, and update
it as the last step of your change — without being asked.

- `ARCHITECTURE.md` — what this project is: components, data model, interfaces.
- `CONVENTIONS.md` — the house rules, plus `## Known Pitfalls / Lessons`.
- `DECISIONS.md` — the decision log. **Append-only**, newest on top; never rewrite or
  delete an entry. If a decision is superseded, add the new one saying so.
- `ai/` — the working folder: task queue, archive, investigations.
- `STACK.md` — the deploy passport, if this project is packaged.

**The golden rule.** `ARCHITECTURE.md` and `CONVENTIONS.md` are read FIRST, before any task,
and updated LAST, after it. A stale foundation is a bug, not cosmetics. If your change made
the map wrong, fixing the map is part of the change, not follow-up work.

**Behaviour changed → one line in `DECISIONS.md`.** A change to what the program does, with
no trail anywhere, is not allowed. Pure cosmetics (a comment, a log string, formatting) need
no entry.

**Save as you go.** When a coherent piece is done, put down a save point naming the paths you
changed — not at the end of the session, a session can die. Save the paths you actually
touched, never "everything": secrets, data and unfinished work do not belong in the history.

If the `fraim` CLI is on PATH, it does the mechanical half:

```sh
fraim status                                  # deterministic verdict on this project
fraim commit <kind> "<what changed>" <path>…  # a save point over the named paths
```

If it is not installed, do the same with ordinary git — the rules above are the point, the
CLI is only the convenience.
BLKEOF
}

# Harness-specific context files (CLAUDE.md and friends) get a pointer, not a copy.
# One text, one place: a second copy would drift from AGENTS.md the first time either
# is edited, and A3 says the source of truth is exactly one.
context_pointer_block() {
    cat <<'BLKEOF'
## Project foundation

The rules for this project live in `AGENTS.md`, next to this file. Read it first.

@AGENTS.md
BLKEOF
}

# Write or refresh the block in a file, between markers, leaving everything
# else untouched. Idempotent: running init twice changes nothing.
context_install() {
    _target=$1
    _blockfn=${2:-context_block}
    _dir=$(dirname -- "$_target")
    mkdir -p "$_dir" || return 1

    _tmp="$_target.fraim.$$"
    if [ -f "$_target" ] && grep -qF "$CTX_BEGIN" "$_target" 2>/dev/null; then
        # Replace the existing block in place.
        awk -v b="$CTX_BEGIN" -v e="$CTX_END" '
            $0 == b { skipping = 1; print "@@FRAIM@@"; next }
            $0 == e { skipping = 0; next }
            !skipping { print }
        ' "$_target" > "$_tmp" || return 1
    else
        if [ -f "$_target" ]; then
            cat "$_target" > "$_tmp" || return 1
            printf '\n' >> "$_tmp"
        else
            : > "$_tmp"
        fi
        printf '@@FRAIM@@\n' >> "$_tmp"
    fi

    _blk="$_target.fraim.blk.$$"
    { printf '%s\n' "$CTX_BEGIN"; "$_blockfn"; printf '%s\n' "$CTX_END"; } > "$_blk"

    _out="$_target.fraim.out.$$"
    awk -v blk="$_blk" '
        $0 == "@@FRAIM@@" {
            while ((getline line < blk) > 0) print line
            close(blk)
            next
        }
        { print }
    ' "$_tmp" > "$_out" || return 1

    mv "$_out" "$_target" || return 1
    rm -f "$_tmp" "$_blk"
    return 0
}
