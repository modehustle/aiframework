#!/bin/sh
# roles.sh — the role table: role → agent → model → effort.
#
# MODES.md §11.3, closed as C: both levels, project beats machine. There is no new
# mechanism here on purpose — config.sh already resolves a key through project file,
# machine file, then built-in default, and a role is just a key. Adding a third config
# file for roles would have been a second implementation of a thing that works (B2).
#
# A role lives under the `role_` prefix and its value is three colon-separated fields:
#
#     role_refactor = claude:haiku:medium
#     role_design   = claude:opus:high
#                     ^agent  ^model ^effort
#
# Why the plan names a ROLE and not a model: a plan travels between machines, and a
# model name is a fact about one person's subscriptions. `**Role**: refactor` still
# resolves on a machine where the cheap tier is a different product entirely.
#
# The unknown role is not an error here — it falls back to role_default — because the
# alternative is a plan that cannot run on a machine that never heard of "migration".
# What IS an error is a malformed value, and it is caught before dispatch, not on the
# third worker.

# Built-in fallback, used when neither config file names the role and no role_default
# is set. Deliberately the middle tier: an unknown role is an unknown cost, and the
# cheap tier failing a task it cannot do is more expensive than the middle tier doing it.
ROLES_BUILTIN='claude:sonnet:medium'

# Split one `agent:model:effort` value. Prints three tab-separated fields, or fails.
# The check is on shape only — whether THIS machine has that agent is the adapter's
# question, and it answers it at launch with a real probe rather than a guess here.
roles_parse() {
    _rp_v=$1
    case $_rp_v in
        *:*:*) ;;
        *) return 1 ;;
    esac
    _rp_agent=${_rp_v%%:*}
    _rp_rest=${_rp_v#*:}
    _rp_model=${_rp_rest%%:*}
    _rp_effort=${_rp_rest#*:}
    # A trailing or embedded empty field means a typo, not a default.
    [ -n "$_rp_agent" ] && [ -n "$_rp_model" ] && [ -n "$_rp_effort" ] || return 1
    case $_rp_effort in *:*) return 1 ;; esac
    printf '%s\t%s\t%s\n' "$_rp_agent" "$_rp_model" "$_rp_effort"
}

# Resolve a role to its executor. Prints `agent<TAB>model<TAB>effort`.
# Returns 1 only when a value exists but is malformed — an absent role is not a failure,
# it is the default.
roles_resolve() {
    _rr_role=$1; _rr_root=${2:-}
    _rr_v=$(config_get "role_$_rr_role" "$_rr_root")
    if [ -z "$_rr_v" ]; then
        _rr_v=$(config_get role_default "$_rr_root")
        [ -n "$_rr_v" ] || _rr_v=$ROLES_BUILTIN
    fi
    roles_parse "$_rr_v" || {
        printf >&2 'роль %s: значение «%s» не в форме агент:модель:усилие\n' "$_rr_role" "$_rr_v"
        return 1
    }
}

# Where the effective value came from — for `fraim config` and for the dispatch report,
# so the conductor can see that a subtask is about to run on the machine default rather
# than on what the project asked for.
roles_source() {
    _rs_role=$1; _rs_root=${2:-}
    if [ -n "$(config_get "role_$_rs_role" "$_rs_root")" ]; then
        config_source "role_$_rs_role" "$_rs_root"; return
    fi
    if [ -n "$(config_get role_default "$_rs_root")" ]; then
        printf '%s (role_default)\n' "$(config_source role_default "$_rs_root")"; return
    fi
    printf 'встроенный дефолт\n'
}

# Every role named in the two config files, for `fraim roles`. Sorted, one per line,
# without the prefix. Reads both levels so the listing shows what the project adds.
# `[ -n "$x" ] && cat …` would have been the obvious spelling and it is a trap: under
# `set -e` that compound returns 1 when the root is empty, and inside the caller's
# `$(…)` that kills the subshell before the machine file is ever read. The listing then
# comes back empty on a machine that has roles — which is exactly how this was found.
roles_list() {
    _rl_root=${1:-}
    {
        if [ -n "$_rl_root" ]; then
            cat "$(config_project_file "$_rl_root")" 2>/dev/null || :
        fi
        cat "$(config_machine_file)" 2>/dev/null || :
    } | sed -n 's/^[[:space:]]*role_\([a-zA-Z0-9_-]*\)[[:space:]]*=.*/\1/p' |
        grep -vx default | sort -u || :
}
