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
| the human asks to put work on the board for later, or to open a project | `/make-task` |
| the human asks to take a task from the board | `/run-task` |
| the human asks what is on the board / in the backlog | `fraim tasks` / `fraim backlog` |
| the human asks to conduct: cheap workers, or a split across directions | `/conductor` |
| where is this bug / is X even feasible | `/investigate` |
| the documents drifted from the code | `/prune` |
| returning to a project after a break | `/orient` |
| a project that existed before this system | `/onboard` |

### Working without a procedure

Most sessions are not a planned task: a question, a small fix, a look around, a change
whose shape only appeared while doing it. **That is legitimate** — do not turn it into a
task, and do not announce a procedure you are not running. Two things still hold:

- **Invariant 0.4 applies anyway.** Read the foundation first; if the change made it
  wrong, fix it before you finish.
- **Behaviour changed → one line in `DECISIONS.md`.** Any change to what the program does
  leaves a trail. Pure cosmetics — a comment, a log string, formatting — need no entry.
- **Something bit you → one line in `## Known Pitfalls / Lessons`** (in `CONVENTIONS.md`).
  Not every surprise: only the kind that would trap the next change too — a call that fails
  silently, a config that means the opposite of what it reads, an order of operations that
  must not be swapped. Propose the line, let the human approve, edit or skip it, and save it
  with the same save point. This is the only way a lesson from a session with no procedure
  ever reaches the next one — every session reads that section first, and nothing else in
  reactive work writes to it.
- **English inside.** What you write into the project — foundation, cards, commit
  messages, comments — is English, whatever language you speak with the human; fraim's
  verbs refuse another language.
- **Save as you go.** When a coherent piece is done — not at the end of the session, a
  session can die — put down a save point naming the paths you changed:
  `fraim commit fix "<what changed>" <path> <path>`. Those commits **are** the record of
  reactive work; there is no separate log to keep.

Reactive work has **no size limit** — a long session with a human in it is not a failure
mode. A task on the board (`/make-task`) is work **put aside for later**, or a project made
of several tasks — and only the human puts it there. Never propose turning the work in front
of you into a task, and never write one to execute it yourself in the same session: just do
the work and save it. `fraim tasks` shows the board when the human asks what is on it.
The same holds for `/conductor` (handing pieces to workers on cheaper models, or splitting
work of different directions across a fleet): it runs when the human asks for it, never
on your own initiative.
You are about to change something you do not understand → `/investigate`.

`fraim status` gives a deterministic verdict on the current project — foundation
freshness, unsaved files, open tasks. It reads files only and costs nothing.

In a project under the system, start with `fraim brief` — the whole foundation, the board
and the list of verbs in one stream, uncut — and write the foundation through those verbs
(`fraim arch`, `fraim decide`, `fraim pitfall`), not by hand.

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
# ---------------------------------------------------------------------------
# The retired fleet mode's leftovers
#
# Until 2026-09-15 a project could be switched into a fleet mode: `mode = fleet` in
# ai/fraim.conf, a conductor section in AGENTS.md and a SessionStart hook
# (`fraim mode --hook`) in .claude/settings.json. The mode is gone — the conductor is a
# procedure the human asks for. Refreshing the project block drops the section by itself;
# the hook needs removing, and `fraim mode --hook` stays a silent success so a leftover
# hook never breaks a session start.
# ---------------------------------------------------------------------------
CTX_HOOK_MARK='fraim mode --hook'

# Remove our hook from the project's .claude/settings.json, if it is there.
#
# Merged, never replaced: the file belongs to the project and may carry hooks and
# permissions somebody depends on. Returns 0 when the hook was removed, 3 when there was
# nothing of ours, 2 with no python3 (nothing touched), 1 when the file could not be
# read or written.
context_hook_remove() {
    _chr_file=$1/.claude/settings.json
    [ -f "$_chr_file" ] || return 3
    grep -qF "$CTX_HOOK_MARK" "$_chr_file" 2>/dev/null || return 3
    command -v python3 >/dev/null 2>&1 || return 2
    python3 - "$_chr_file" "$CTX_HOOK_MARK" <<'PY'
import json, sys
path, mark = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
except (json.JSONDecodeError, OSError):
    sys.exit(1)
if not isinstance(data, dict):
    sys.exit(1)

hooks = data.get("hooks", {})
starts = hooks.get("SessionStart", [])
starts[:] = [
    g for g in starts
    if not (isinstance(g, dict) and any(
        isinstance(h, dict) and mark in str(h.get("command", ""))
        for h in g.get("hooks", [])))
]
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

**Start every session with `fraim brief`.** It prints the whole foundation in one stream —
the map (`ARCHITECTURE.md`), the house rules with `## Known Pitfalls / Lessons`
(`CONVENTIONS.md`), the living decisions (`DECISIONS.md`), `STACK.md` if there is one, the
task board — and, first, the list of verbs this CLI has. It ends with a mark that nothing
was cut. Do not read those files with a line limit instead. To look something up:
`fraim find` with 2–4 keys, in both languages and as word stems (`кэш cache`) — it returns
whole entries.

**The golden rule.** The foundation is read FIRST and updated LAST. A stale foundation is a
bug, not cosmetics. If your change made the map wrong, fixing the map is part of the change.

**Write the foundation through the verbs, not by hand.** The text is yours; place, format
and line wrapping are theirs:

- the map changed → `fraim arch "<section>"` (body on stdin) rewrites that one section;
- behaviour changed → `fraim decide "<title>"` (body on stdin), newest on top; replacing an
  earlier decision → `--supersedes "<its heading>"`, and the old entry moves to the archive.
  Pure cosmetics (a comment, a log string, formatting) need no entry;
- something bit you that would trap the next change too — fails silently, reads as the
  opposite of what it does, must happen in an order nobody would guess → propose one line,
  and on the human's yes `fraim pitfall "<line>"`.

**English inside.** Everything you write into the project — the foundation, task cards,
backlog questions, commit messages, code comments — is English, whatever language you speak
with the human. The verbs check it and refuse another language; a name or the human's own
words in another language go in quotes («…») or backticks.

**Save as you go.** When a coherent piece is done — not at the end, a session can die —
`fraim commit <kind> "<what changed>" <path>…` over the paths you actually touched. Never
"everything": secrets, data and unfinished work do not belong in the history.

**Work happens here and now.** The task board (`ai/tasks/`) and the backlog of open
questions (`ai/backlog/`) are filled by the human only: never propose turning the work in
front of you into a task. The human speaks in words, not commands — recognise the intent:

BLKEOF
    vt_intents
    cat <<'BLKEOF'

At the end of a piece of work, if open questions remain — important, not for now — list
them and ask which to keep; the approved ones go to `fraim backlog-new`.

If `fraim` is not installed, do the same with ordinary git and read the files whole — the
rules above are the point, the CLI is only the convenience.
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
