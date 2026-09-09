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
- **Something bit you → one line in `## Known Pitfalls / Lessons`** (in `CONVENTIONS.md`).
  Not every surprise: only the kind that would trap the next change too — a call that fails
  silently, a config that means the opposite of what it reads, an order of operations that
  must not be swapped. Propose the line, let the human approve, edit or skip it, and save it
  with the same save point. This is the only way a lesson from a session with no procedure
  ever reaches the next one — `/make-task` reads that section before planning, and nothing
  else in reactive work writes to it.
- **Save as you go.** When a coherent piece is done — not at the end of the session, a
  session can die — put down a save point naming the paths you changed:
  `fraim commit fix "<what changed>" <path> <path>`. Those commits **are** the record of
  reactive work; there is no separate log to keep.

Reactive work has **no size limit** — a long session with a human in it is not a failure
mode. `/make-task` is not the procedure for "this got big"; it is the procedure for
**handing the work to someone who is not in this conversation** — a fresh chat, a cheaper
executor, tomorrow's you. Size does not decide that, and neither do you: the human does.
**Never write a task for yourself to then execute in the same session**: that is the
ceremony without the handoff it exists for. Just do the work and save it.
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
# The project root whose block is being written. Set by the caller before context_install,
# because the block functions take no arguments and sh has no locals. Empty means "do not
# know" — the mode section is then omitted rather than guessed.
CTX_ROOT=${CTX_ROOT:-}

# The fleet-mode section of the project block.
#
# This is how the mode reaches the agent at all: it reads AGENTS.md on entering the
# project, and that is where it learns whether it is a conductor here. No command starts
# the mode — the mode IS the answer to "who am I in this project", which is exactly what
# MODES.md §1 says a mode is.
#
# What a switch may and may not do: it selects which of the two defined modes is in
# force; it does NOT hand out authority. The wall and the ratification of each mode live
# in MODES.md and are not configurable — a conductor does not become allowed to RATIFY
# because someone flipped a key. (Accepting the fleet's work — checking behind the workers,
# cleaning up, reporting — is his job and always was work rather than authority; the
# judgement over that report is the part no key moves.) That distinction is what keeps this
# on the right side of §1 ("mode is not a setting") and of B5.
context_mode_block() {
    cat <<'BLKEOF'

## Fleet mode is on in this project — read this before anything else

You are the **conductor** here. Not "also a conductor": that is the whole of your role in
this project until the mode is switched off.

**Before your first tool call, do these two things in order.** They are not advice.

1. Read the `conductor` skill. It is the procedure for this mode, and every step below
   assumes you have it.
2. Answer, in your reply, which of the two you are doing: **dispatching this to a fleet**,
   or **telling the human why it cannot be split**. There is no third option, and "I'll
   just do this part first" is not one of them.

The failure this is written against is real and it is the default one: on the first live
build the conductor read this block, agreed it was the conductor, and then wrote the
project skeleton itself. Four workers sat idle while it did. Writing the code yourself is
the single most likely way for this mode to fail, and it never announces itself as a
mistake — it feels like being helpful.

`fraim status` reports it deterministically: a fleet-mode project with changed files
and no sealed build is flagged as work going around the fleet. If you see that line about
your own work, you have already drifted — stop and dispatch.

**Empty project?** Laying the foundation is not fleet work (`bootstrap` does not declare
`parallel: yes`, and under this mode the foundation is written by the build, once). Say so
to the human and let them decide, rather than quietly doing it and calling it groundwork.

The short version, so you do not start in the wrong place:

- **Do not write the subtasks' code yourself.** Your job is planning, dispatch and
  verification. Writing the code is what the fleet is for.
- **Two blocks run in the same wave only if neither reads the other's result.** "Frontend
  and backend" qualifies only when the contract between them already exists; without it the
  contract is the first wave and both sides are the second.
- **Paths collide → four ways out, in this order.** Group the colliding pieces into one
  subtask; or redraw the boundaries so the file belongs to exactly one; or order them with
  `**After**:` so they run in different waves (paths may collide across waves — they do not
  run at the same time); and only then say the work does not split. The last one is a legal
  answer and the LAST one: name what failed in the first three before you give it.
- **Judge the work by the tree, never by the workers' reports.** A report is written by
  the party being judged. `fraim dispatch verify` shows what git says actually changed.
- **The acceptance is yours, the ratification is not.** `fraim dispatch accept СБОРКА` is
  your stage: it checks behind every worker, runs the project's own check on the assembled
  branch, cleans up what the fleet created and writes the report. Then you fill in the
  report's «Словами дирижёра» section — what you checked that the numbers do not show, what
  you are unsure about, what you recommend — and hand it to the human. What you never do is
  decide that the build is good, or write it to the trunk: that is the human's, over your
  report. If they hand it back, write down why: `fraim dispatch return СБОРКА "…"`.
- **Checking is not judging.** «I checked everything, so I may as well merge it» is the one
  hole this mode is built around. Show the report and wait.

Mechanics: `fraim dispatch check ПЛАН` before anything is handed out, then
`fraim dispatch ПЛАН`, `fraim dispatch run СБОРКА` (one wave — the first uncollected one),
`fraim dispatch watch СБОРКА`, `fraim dispatch collect СБОРКА` (merges the wave into the
build branch, refuses on uncommitted work, on a file outside the declared paths, and on a
conflict; then prints the wave's combined diff — read it whole, that is where a divergence
the path check cannot see shows up), then the next `run`,
`fraim dispatch verify СБОРКА ПОДЗАДАЧА` to look at one subtask, and finally
`fraim dispatch accept СБОРКА` — which refuses while any subtask is uncollected, and exits
non-zero when the report has findings. The human's part is reading that report.
BLKEOF
}

# ---------------------------------------------------------------------------
# Starting the mode, rather than asking for it
#
# A context block is a file the agent MAY read. The first live build proved what that is
# worth: the conductor read the block, agreed it was the conductor, and then wrote the
# project skeleton itself. A watchman finding after the fact is diagnosis, not a start —
# nobody reads `fraim status` in the middle of being helpful.
#
# A SessionStart hook is different in kind. The harness runs it before the agent's first
# turn and puts `additionalContext` INTO the context — the agent does not choose to read
# it, the same way it does not choose to read the system prompt. That is the closest thing
# to a deterministic start a harness offers.
#
# This is DETERMINISM.md's own plan: "хуки харнеса ложатся вторым поясом там, где среда
# даёт: SessionStart может сам прогнать fraim status, чтобы вердикт приезжал в контекст
# без единого нажатия". The gate in the CLI stays the first belt for environments with no
# hooks; this is the second, and for the mode it is the one that matters.
# ---------------------------------------------------------------------------

# What the hook prints. Read by the harness, not by a human.
context_hook_payload() {
    _chp_root=$1
    [ "$(mode_get "$_chp_root")" = fleet ] || return 1
    if command -v python3 >/dev/null 2>&1; then
        context_mode_block | python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": sys.stdin.read(),
}}, ensure_ascii=False))'
        return 0
    fi
    return 1
}

CTX_HOOK_MARK='fraim mode --hook'

# Add or remove the hook in the project's .claude/settings.json.
#
# Merged, never replaced: the file belongs to the project and may already carry hooks and
# permissions somebody depends on. Where no JSON-safe editor exists we touch nothing and
# say so — the same rule the permission hint follows.
context_hook_set() {
    _chs_root=$1; _chs_on=$2
    command -v python3 >/dev/null 2>&1 || return 2
    mkdir -p "$_chs_root/.claude" 2>/dev/null || return 1
    python3 - "$_chs_root/.claude/settings.json" "$_chs_on" "$CTX_HOOK_MARK" <<'PY'
import json, sys
path, on, mark = sys.argv[1], sys.argv[2] == "on", sys.argv[3]
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except (json.JSONDecodeError, OSError):
    sys.exit(1)
if not isinstance(data, dict):
    sys.exit(1)

hooks = data.setdefault("hooks", {})
starts = hooks.setdefault("SessionStart", [])
# Drop any entry of ours, so this is idempotent and `task` is a clean removal.
starts[:] = [
    g for g in starts
    if not (isinstance(g, dict) and any(
        isinstance(h, dict) and mark in str(h.get("command", ""))
        for h in g.get("hooks", [])))
]
if on:
    starts.append({"hooks": [{"type": "command", "command": mark, "timeout": 10}]})
if not starts:
    hooks.pop("SessionStart", None)
if not hooks:
    data.pop("hooks", None)

with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
}

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

**Something bit you → one line in `## Known Pitfalls / Lessons`** (in `CONVENTIONS.md`). Only
the kind of surprise that would trap the next change too — something that fails silently,
reads as the opposite of what it does, or must happen in an order nobody would guess. Propose
the line, let the human approve, edit or skip it, then save it with the change. A lesson that
stays in the chat is paid for twice.

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

    # Appended only where the project actually runs the fleet. In reactive mode the block
    # is byte-identical to what it has always been, so switching a project into the fleet
    # mode and back leaves no trace in AGENTS.md.
    if [ -n "$CTX_ROOT" ] && [ "$(mode_get "$CTX_ROOT")" = fleet ]; then
        context_mode_block
    fi
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
