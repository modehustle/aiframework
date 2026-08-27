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
| a one-file micro-fix (typo, wrong constant) | `/hotfix` |
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
- **Save as you go.** When a coherent piece is done — not at the end of the session, a
  session can die — put down a save point naming the paths you changed:
  `fraim commit fix "<what changed>" <path> <path>`. Those commits **are** the record of
  reactive work; there is no separate log to keep.

Turn back into the system when the shape appears: it stopped being a fix and became a
story → `/make-task`. You are about to change something you do not understand →
`/investigate`.

`fraim status` gives a deterministic verdict on the current project — drift count,
blockers, stale plans, foundation freshness. It reads files only and costs nothing.

**The system's own rule:** the watchman notices, the human decides. Do not start a
mutating procedure because a status line suggested it.
BLKEOF
}

# Write or refresh the block in a file, between markers, leaving everything
# else untouched. Idempotent: running init twice changes nothing.
context_install() {
    _target=$1
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
    { printf '%s\n' "$CTX_BEGIN"; context_block; printf '%s\n' "$CTX_END"; } > "$_blk"

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
