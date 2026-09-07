#!/bin/sh
# fleet.sh — the six operations of MODES.md §9 against an execution environment.
#
# This is the only file that knows an ADE exists. dispatch.sh decides what to run and
# what actually changed; this file makes it happen. The split is what let the conductor's
# logic be written and tested on a machine with no ADE at all.
#
# We do NOT wrap the environment's vocabulary (MODES.md §10 forbids it: `fraim worktree
# create` as an alias for `orca worktree create` makes our dictionary equal to theirs and
# therefore redundant). What this file does is translate a BUILD — our object, which the
# environment has no word for — into their calls, and read back only what the conductor
# needs. Their orchestration does the scheduling, supervision and isolation; we do not
# reimplement any of it.
#
# Identifiers: Orca's ids carry their own type as a prefix — run_395fe5e76507,
# task_1a05eb1321c1, term_aabf0418-…, and we extract them by that shape rather than by
# the field they sit in. ade.sh states the reason: "the environment's own JSON schema is
# not documented, and code written against guessed field names breaks silently on the
# first release that renames one." A prefix is part of the value, so a renamed field
# cannot break it, and neither can pretty-printing.

FLEET_ADE=orca

# The command word for the environment, or failure when it is not on this machine.
fleet_cli() { ade_cli "$FLEET_ADE" 2>/dev/null; }

fleet_present() { fleet_cli >/dev/null 2>&1; }

# Is the runtime answering? Orca's own help says most commands need a running app, and a
# failure here is worth one clear sentence rather than six confusing ones later.
fleet_ready() {
    _fr_cmd=$(fleet_cli) || return 1
    ade_alive "$_fr_cmd"
}

# Pull one typed identifier out of a response. Reads stdin, prints the first id of that
# type, fails when there is none.
#
# The colon is what makes this correct, and leaving it out is a mistake I made and the
# test caught: searching for `"run_…"` alone matches the FIELD NAME `"run_id"` and returns
# the string `run_id` as though it were an identifier. An id is always a VALUE, so it is
# always preceded by a colon; a field name never is.
fleet_id() {
    _fi_kind=$1
    tr -d '\n' 2>/dev/null |
        grep -o ":[[:space:]]*\"${_fi_kind}_[0-9a-zA-Z][0-9a-zA-Z-]*\"" 2>/dev/null |
        head -1 | sed 's/^:[[:space:]]*//; s/"//g'
}

# Every Orca response carries `"ok": true|false`. This is the one field name we do rely
# on, because it is the envelope rather than the payload, and because the alternative —
# trusting the exit code alone — loses the distinction their own help draws between a
# failure and an unknown outcome.
fleet_ok() {
    tr -d '\n' 2>/dev/null | grep -q '"ok"[[:space:]]*:[[:space:]]*true'
}

# --- the six operations ------------------------------------------------------

# A Run is Orca's namespace and inbox — "it never schedules or places workers". One per
# build: it is the handle under which every worker of this build can be listed later.
fleet_run_create() {
    _frc_cmd=$(fleet_cli) || return 1
    _frc_out=$("$_frc_cmd" orchestration run-create --objective "$1" --json 2>&1) || {
        printf >&2 'run-create не удался:\n%s\n' "$_frc_out"; return 1
    }
    printf '%s' "$_frc_out" | fleet_ok || {
        printf >&2 'run-create отказал:\n%s\n' "$_frc_out"; return 1
    }
    _frc_id=$(printf '%s' "$_frc_out" | fleet_id run)
    [ -n "$_frc_id" ] || { printf >&2 'run-create: в ответе нет run_… идентификатора\n'; return 1; }
    printf '%s\n' "$_frc_id"
}

# §9.3 — hand over the assignment. The spec IS the worker's task file: the executor never
# saw the conductor's conversation (G1), so everything it needs travels here.
fleet_task_create() {
    _ftc_run=$1; _ftc_title=$2; _ftc_spec=$3
    _ftc_cmd=$(fleet_cli) || return 1
    _ftc_out=$("$_ftc_cmd" orchestration task-create \
        --run "$_ftc_run" --task-title "$_ftc_title" --spec "$_ftc_spec" --json 2>&1) || {
        printf >&2 'task-create не удался:\n%s\n' "$_ftc_out"; return 1
    }
    printf '%s' "$_ftc_out" | fleet_ok || {
        printf >&2 'task-create отказал:\n%s\n' "$_ftc_out"; return 1
    }
    _ftc_id=$(printf '%s' "$_ftc_out" | fleet_id task)
    [ -n "$_ftc_id" ] || { printf >&2 'task-create: в ответе нет task_… идентификатора\n'; return 1; }
    printf '%s\n' "$_ftc_id"
}

# §9.1 + §9.2 in one call: an isolated checkout AND a named agent on a named model.
# Orca creates the worktree as part of starting the worker ("new worktrees use agent-first
# creation"), so there is no separate step to keep in sync.
#
# --model and --effort are omitted together when no model is named: their help says
# "--effort requires --model", and passing an empty --model is not the same as passing
# none. The role table always yields all three, so this is the defensive branch, not the
# usual path.
#
# Their exit code is meaningful here and we pass it through: "the call exits 0 only for
# ready. Failed or outcome_unknown exits 1."
fleet_worker_start() {
    _fws_task=$1; _fws_agent=$2; _fws_model=$3; _fws_effort=$4
    _fws_name=$5; _fws_root=$6; _fws_base=$7

    _fws_cmd=$(fleet_cli) || return 1
    if [ -n "$_fws_model" ]; then
        _fws_out=$("$_fws_cmd" orchestration worker-start \
            --task "$_fws_task" --agent "$_fws_agent" \
            --model "$_fws_model" --effort "$_fws_effort" \
            --worktree new-top-level --name "$_fws_name" \
            --repo "path:$_fws_root" --base-branch "$_fws_base" --json 2>&1)
    else
        _fws_out=$("$_fws_cmd" orchestration worker-start \
            --task "$_fws_task" --agent "$_fws_agent" \
            --worktree new-top-level --name "$_fws_name" \
            --repo "path:$_fws_root" --base-branch "$_fws_base" --json 2>&1)
    fi
    _fws_rc=$?

    if [ "$_fws_rc" -ne 0 ]; then
        printf >&2 'worker-start не поднял воркера %s:\n%s\n' "$_fws_name" "$_fws_out"
        return 1
    fi
    _fws_id=$(printf '%s' "$_fws_out" | fleet_id dispatch)
    [ -n "$_fws_id" ] || {
        printf >&2 'worker-start: в ответе нет dispatch_… идентификатора:\n%s\n' "$_fws_out"
        return 1
    }
    printf '%s\n' "$_fws_id"
}

# §9.4 and §9.5 — the raw observation, for the caller to read.
#
# Returned whole rather than reduced to a verdict on purpose. Their help draws a
# distinction we must not flatten: an ABSENT observation field means Orca never looked —
# an older host, an unreadable pane, a probe that timed out — and "never means the worker
# is not waiting". Collapsing that into a boolean would manufacture certainty we do not
# have, which is the failure §9.5 exists to prevent.
fleet_worker_show() {
    _fwh_cmd=$(fleet_cli) || return 1
    "$_fwh_cmd" orchestration worker-show --dispatch "$1" --json 2>&1
}

# §9.6 — clean up exactly what we created. Their help: "closes only the exact
# coordinator-owned agent terminal of that worker… never closes setup terminals,
# configured tabs, reused or pre-existing terminals, user-taken-over terminals".
# That is B6 already implemented on their side, which is why we call it rather than
# killing anything ourselves.
#
# Idempotent by their contract: "repeating the call reports already_released. Only
# release_unknown exits 1."
fleet_worker_release() {
    _fwr_cmd=$(fleet_cli) || return 1
    "$_fwr_cmd" orchestration worker-release --dispatch "$1" --json 2>&1
}

# All workers of one build, as the environment accounts for them.
#
# Note the trap their help spells out: "terminal state is process accounting and is
# reported separately from Task status; a completed Task can still own a live terminal."
# So this answers "what terminals does this build still hold", NOT "is the work done" —
# the second question is answered by the tree (dispatch_verify_tree), which is the whole
# point of §3.
fleet_worker_list() {
    _fwl_cmd=$(fleet_cli) || return 1
    "$_fwl_cmd" orchestration worker-list --run "$1" --json 2>&1
}
