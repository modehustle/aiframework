#!/bin/sh
# roles.sh — the role table: role → agent → model → effort.
#
# MODES.md §11.3, closed as C: both levels, project beats machine. There is no new
# mechanism here on purpose — config.sh already resolves a key through project file,
# machine file, then built-in default, and a role is just a key. Adding a third config
# file for roles would have been a second implementation of a thing that works (B2).
#
# WHAT A ROLE IS, and this is the part that is easy to get wrong: a role is the name of
# a PROCEDURE. MODES.md §10 forbids inventing an onion of our own — "роли у нас уже
# названы: make-task, run-task, investigate, prune" — so the table binds names that
# already exist rather than a fresh vocabulary of refactor/design/migration. A subtask
# saying `**Role**: run-task` says which procedure its worker executes, and the table
# says on what.
#
# Resolution walks four steps, and the second is what makes the table cheap to fill:
#
#   1. role_<procedure>   — this exact procedure, e.g. role_investigate
#   2. tier_<tier>        — the tier declared in that procedure's own frontmatter
#   3. role_default       — one answer for everything
#   4. ROLES_BUILTIN      — the middle tier
#
# Step 2 means three lines of config (tier_cheap, tier_capable, tier_strong) already
# answer for every procedure, because each procedure declares what class of model it
# needs. Naming a single procedure explicitly is then the exception, which is what
# C4 asks for: configuration where the fork is real, not everywhere.
#
# Why a plan names a role and not a model: a plan travels between machines, and a model
# name is a fact about one person's subscriptions.

# Used when nothing else answers. Deliberately the middle tier: an unknown role is an
# unknown cost, and the cheap tier failing a job it cannot do costs more than the middle
# tier doing it.
#
# The model is a full provider model id, not a nickname. `sonnet` was here and was wrong:
# the environment passes --model through as an opaque provider id, so a nickname reaches
# the provider unrecognised and the worker fails at launch.
ROLES_BUILTIN='claude:claude-sonnet-5:medium'

# One suggested model per tier, so the very first `fraim roles set` has something to pick
# rather than a blank prompt. This is NOT a catalogue of the world's models — that is the
# treadmill P0 warns about, and roles.sh does not keep one. It is three values attached to
# the three tiers we already have, and every picker that shows them also accepts a typed
# value, which is what keeps an aging list harmless.
roles_models_suggested() {
    case ${1:-} in
        cheap)   printf 'claude-haiku-4-5\n' ;;
        capable) printf 'claude-sonnet-5\n' ;;
        strong)  printf 'claude-opus-5\n' ;;
        *)       printf 'claude-opus-5\nclaude-sonnet-5\nclaude-haiku-4-5\n' ;;
    esac
}

# Whether a procedure may be handed to a fleet worker at all.
#
# Not every procedure can: `prune` rewrites the foundation, and under parallel mode the
# foundation is written by the BUILD, once (MODES.md §2, invariant 0.4) — two of them at
# a time collide by construction, not by accident. `make-task` plans, which happens
# before dispatch. `conductor` is the dispatcher itself. `bootstrap`/`onboard` act on the
# whole project.
#
# So the default is NO and a procedure opts in by declaring `parallel: yes`. Defaulting
# the other way would mean every procedure added later is silently dispatchable until
# someone notices — the failure being a foundation file quietly overwritten by whichever
# worker finished last.
roles_is_parallel() {
    _rp_f=$(fraim_procedure_file "$1" 2>/dev/null) || return 1
    [ "$(fm_get "$_rp_f" parallel 2>/dev/null || :)" = yes ]
}

# The tier a procedure declares for itself. Read from the frontmatter, which skills.sh
# calls the source of truth — manifest.json is generated from it, so reading the JSON
# here would be reading a copy.
roles_tier_of() {
    _rt_f=$(fraim_procedure_file "$1" 2>/dev/null) || return 1
    _rt_t=$(fm_get "$_rt_f" tier 2>/dev/null) || return 1
    [ -n "$_rt_t" ] || return 1
    printf '%s\n' "$_rt_t"
}

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
        _rr_t=$(roles_tier_of "$_rr_role" 2>/dev/null || :)
        [ -n "$_rr_t" ] && _rr_v=$(config_get "tier_$_rr_t" "$_rr_root")
    fi
    [ -n "$_rr_v" ] || _rr_v=$(config_get role_default "$_rr_root")
    [ -n "$_rr_v" ] || _rr_v=$ROLES_BUILTIN

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
    _rs_t=$(roles_tier_of "$_rs_role" 2>/dev/null || :)
    if [ -n "$_rs_t" ] && [ -n "$(config_get "tier_$_rs_t" "$_rs_root")" ]; then
        printf '%s (tier_%s)\n' "$(config_source "tier_$_rs_t" "$_rs_root")" "$_rs_t"; return
    fi
    if [ -n "$(config_get role_default "$_rs_root")" ]; then
        printf '%s (role_default)\n' "$(config_source role_default "$_rs_root")"; return
    fi
    printf 'встроенный дефолт\n'
}

# Every role named in the two config files, for `fraim roles`. Sorted, one per line,
# without the prefix. Reads both levels so the listing shows what the project adds.
# ---------------------------------------------------------------------------
# Where the choices come from
#
# The rule is: we do not keep a catalogue of the world's models. Models ship weekly, and
# a list baked into fraim is stale between releases — the treadmill P0 names outright.
# So each source below asks whoever actually knows, and returns nothing when nobody does.
# Nothing is a valid answer: the picker then takes a typed value instead of pretending
# the list is complete.
# ---------------------------------------------------------------------------

# Providers the execution environment knows about, and whether each is usable right now.
# Prints `name<TAB>ok` or `name<TAB>reason`; nothing at all when there is no environment
# or it declines to answer.
#
# Two decisions worth stating, both learned from the real output rather than guessed:
#
# 1. Availability is read from "error", not "status". Inside one provider's block the
#    word "status" also appears on unrelated objects — a codex account carries three
#    rate-limit credits each with "status": "available" — so a scan for it lands on the
#    wrong one depending on key order, which JSON does not promise. "error" appears once
#    per provider and is null exactly when the provider works.
#
# 2. The parse survives reformatting. ade.sh warns that whether the JSON arrives
#    pretty-printed or on one line is not something we control, so the text is joined
#    first and split on the "provider" key itself rather than read line by line.
#
# This is still a field name, and ade.sh is right that a field name can be renamed out
# from under us. The mitigation is that a miss is silent and harmless: no names means the
# picker asks for a typed value, which is what it did before this function existed.
roles_providers() {
    _rap_cmd=$(ade_cli orca 2>/dev/null) || return 0
    _rap_out=$(ade_query "$_rap_cmd" account list --json)
    [ -n "$_rap_out" ] || return 0
    printf '%s' "$_rap_out" | roles_parse_providers
}

# Split out so it can be tested against a saved response without an environment present.
roles_parse_providers() {
    awk '
        { blob = blob " " $0 }
        END {
            gsub(/"provider"/, "\n@", blob)
            n = split(blob, part, "\n")
            for (i = 2; i <= n; i++) {
                if (match(part[i], /"[^"]+"/) == 0) continue
                name = substr(part[i], RSTART + 1, RLENGTH - 2)
                if (match(part[i], /"error"[ \t]*:[ \t]*null/) > 0) {
                    print name "\tok"
                } else if (match(part[i], /"error"[ \t]*:[ \t]*"[^"]*"/) > 0) {
                    why = substr(part[i], RSTART, RLENGTH)
                    sub(/^"error"[ \t]*:[ \t]*"/, "", why); sub(/"$/, "", why)
                    print name "\t" why
                } else {
                    print name "\tнеизвестно"
                }
            }
        }
    '
}

# Agent names for the picker: the ones that can actually run, most useful first, with the
# blocked ones after them so a stale login is visible at the moment of choosing rather
# than at the moment a fleet fails to start.
roles_agents_available() {
    _raa=$(roles_providers) || return 0
    [ -n "$_raa" ] || return 0
    printf '%s\n' "$_raa" | awk -F'\t' '$2 == "ok" { print $1 }'
    printf '%s\n' "$_raa" | awk -F'\t' '$2 != "ok" { printf "%s (недоступен: %s)\n", $1, $2 }'
}

# Models already in use on this machine — the honest list that costs no network and no
# catalogue: whatever the two config files already name. On a first run it is empty and
# the picker asks for a typed value; from the second role onward it answers well, because
# people reuse the same few models.
roles_models_seen() {
    _rm_root=${1:-}
    {
        if [ -n "$_rm_root" ]; then cat "$(config_project_file "$_rm_root")" 2>/dev/null || :; fi
        cat "$(config_machine_file)" 2>/dev/null || :
    } | sed -n 's/^[[:space:]]*\(role_\|tier_\)[a-zA-Z0-9_-]*[[:space:]]*=[[:space:]]*//p' |
        cut -d: -f2 | grep '[^[:space:]]' | sort -u || :
}

# Effort levels. Orca calls --effort "reasoning effort for the selected model" and does
# not enumerate the values, so these are the common rungs offered as a convenience —
# the picker always allows a typed value, which is what makes an incomplete list safe.
roles_efforts() { printf 'low\nmedium\nhigh\nxhigh\nmax\n'; }

# Pick one value: a numbered list on stderr, the answer on stdout. The list arrives on
# stdin and may be empty, in which case the only option is to type one.
#
# stderr for the prompt and stdout for the answer, so the caller can capture the choice
# with $( ) while the person still sees the menu. Reading from /dev/tty rather than stdin
# for the same reason: stdin is carrying the list.
roles_pick() {
    _rk_title=$1; _rk_dflt=${2:-}
    _rk_items=$(grep '[^[:space:]]' || :)
    _rk_n=$(printf '%s' "$_rk_items" | grep -c '[^[:space:]]' || :)
    [ -n "$_rk_items" ] || _rk_n=0

    printf >&2 '\n%s\n' "$_rk_title"
    [ "$_rk_n" -gt 0 ] && printf '%s\n' "$_rk_items" |
        awk '{ printf "  %d) %s\n", NR, $0 }' >&2
    printf >&2 '  %d) ввести своё\n' $((_rk_n + 1))
    if [ -n "$_rk_dflt" ]; then
        printf >&2 'Выбор [%s]: ' "$_rk_dflt"
    else
        printf >&2 'Выбор: '
    fi

    read -r _rk_c </dev/tty 2>/dev/null || return 1
    [ -n "$_rk_c" ] || _rk_c=$_rk_dflt
    [ -n "$_rk_c" ] || return 1

    # A number picks from the list; anything else is taken as the value itself, so
    # someone who already knows what they want does not have to walk the menu.
    case $_rk_c in
        ''|*[!0-9]*) printf '%s\n' "$_rk_c"; return 0 ;;
    esac
    if [ "$_rk_c" -ge 1 ] 2>/dev/null && [ "$_rk_c" -le "$_rk_n" ]; then
        printf '%s\n' "$_rk_items" | sed -n "${_rk_c}p"
        return 0
    fi
    if [ "$_rk_c" -eq $((_rk_n + 1)) ] 2>/dev/null; then
        printf >&2 'Значение: '
        read -r _rk_v </dev/tty 2>/dev/null || return 1
        [ -n "$_rk_v" ] || return 1
        printf '%s\n' "$_rk_v"
        return 0
    fi
    return 1
}

# `[ -n "$x" ] && cat …` would have been the obvious spelling and it is a trap: under
# `set -e` that compound returns 1 when the root is empty, and inside the caller's
# `$(…)` that kills the subshell before the machine file is ever read. The listing then
# comes back empty on a machine that has roles — which is exactly how this was found.
roles_list() {
    _rl_root=${1:-}
    {
        # Every procedure is a role whether or not anyone configured it — that is what
        # "the vocabulary already exists" means. Listing only configured keys would hide
        # the ones running on a tier or built-in default, which are exactly the ones
        # worth seeing before a dispatch.
        fraim_procedures 2>/dev/null || :
        if [ -n "$_rl_root" ]; then
            cat "$(config_project_file "$_rl_root")" 2>/dev/null || :
        fi
        cat "$(config_machine_file)" 2>/dev/null || :
    } | sed -n 's/^[[:space:]]*role_\([a-zA-Z0-9_-]*\)[[:space:]]*=.*/\1/p; /^[a-z][a-z0-9-]*$/p' |
        grep -vx default | sort -u || :
}
