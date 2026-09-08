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
#   2. tier_<procedure>   — the tier declared in that procedure's own frontmatter
#   3. role_default       — one answer for everything
#   4. ROLES_BUILTIN      — the middle tier
#
# Step 2 means three lines of config (tier_cheap, tier_capable, tier_strong) already
# answer for every procedure, because each procedure declares what class of model it
# needs. Naming a single procedure explicitly is then the exception, which is what
# C4 asks for: configuration where the fork is real, not everywhere.
#
# WHAT A TIER MEANS, because the names mislead: a tier is what an execution COSTS YOU,
# not how clever the model is. Someone whose subscription includes a frontier model at no
# marginal cost puts it in tier_cheap, and everything that "only needs the cheap one" then
# runs on a frontier model. That is the table working, not a misuse of it.
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

# Agent names for the picker: the harnesses fraim knows about and that are present on
# this machine. This is independent of any execution environment (Orca or otherwise) —
# fraim installs skills into these harnesses, and the role table binds to what fraim can
# actually serve. harness_detect (harness.sh) probes each harness by its binary on PATH
# or its home directory, so an agent that is installed but not yet on PATH still appears.
roles_agents_available() {
    harness_detect 2>/dev/null | cut -f1
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

# ---------------------------------------------------------------------------
# Where the MODELS come from
#
# The same rule as the providers above, one level deeper: we do not keep a catalogue
# of the world's models (the treadmill P0 warns about), and we do not query provider
# APIs either — each agent already maintains its own catalogue, self-refreshing and
# authenticated. So the picker asks the agent the user just chose, at the moment of
# choosing, through that agent's own channel:
#
#   agent         source                       form
#   devin         `devin models list`          text table, id + display name + price
#   pi            `pi --list-models`           text table, provider + model + context
#   cursor-agent  `cursor-agent models`        text table, id - display name
#   codex         ~/.codex/models_cache.json   JSON, self-refreshed (etag, fetched_at)
#   claude        catalogue embedded in the    minified JS entries
#                 claude binary                  {id:"claude-...",family:"..."}
#
# Nothing is a valid answer: an agent that is absent, broken, or updated past our
# parser yields an empty list, and the picker falls back to a typed value — the same
# graceful miss the providers above are built on. A miss must never be an error.
#
# One parser per source, never one global parser: the formats differ per agent and
# each agent changes its own format on its own schedule. Every parser takes text on
# stdin and prints bare model ids — exactly the strings the agent accepts in its
# --model — one per line, sorted, deduplicated. Parsers are split from the source
# invocation so they can be tested against saved fixtures without the agent present
# (the same split as the parsers above).
# ---------------------------------------------------------------------------

# agent  kind      locator                          parser
# kind: command = run the locator; file = read $HOME/locator; binary = read the
# resolved claude executable (a node install symlinks it into a versioned bin dir).
roles_models_table() {
    cat <<'TBL'
devin	command	devin models list	roles_parse_devin_models
pi	command	pi --list-models	roles_parse_pi_models
cursor-agent	command	cursor-agent models	roles_parse_cursor_models
codex	file	.codex/models_cache.json	roles_parse_codex_models
claude	binary	claude	roles_parse_claude_models
TBL
}

# devin: indented lines carry "id  Display Name  [context, $price]"; family headers
# sit at the left margin and the alias line is "  aliases: opus". The colon in
# "aliases:" is what the id pattern rejects.
roles_parse_devin_models() {
    sed -n 's/^[[:space:]]\{1,\}\([^[:space:]][^[:space:]]*\).*/\1/p' |
        grep -E '^[a-z0-9][a-z0-9._-]*$' | sort -u || :
}

# cursor-agent: rows are "id - Display Name"; the header has no dash.
roles_parse_cursor_models() {
    sed -n 's/^\([^[:space:]][^[:space:]]*\) - .*/\1/p' |
        grep -E '^[a-z0-9][a-z0-9._-]*$' | sort -u || :
}

# pi: a column table, model in field 2, header on line 1. A leading "~" marks a
# pinned alias; pi accepts the id with or without it, so it is stripped.
roles_parse_pi_models() {
    awk 'NR > 1 && NF >= 2 { print $2 }' |
        sed 's/^~//' |
        grep -E '^[a-zA-Z0-9][a-zA-Z0-9/._-]*$' | sort -u || :
}

# codex: the JSON cache may arrive pretty-printed or on one line — not something we
# control (the same lesson the provider parser above paid for) — so the text is
# joined first and split on the "slug" key itself.
roles_parse_codex_models() {
    awk '
        { blob = blob " " $0 }
        END {
            n = split(blob, part, /"slug"/)
            for (i = 2; i <= n; i++)
                if (match(part[i], /"[^"]+"/) > 0)
                    print substr(part[i], RSTART + 1, RLENGTH - 2)
        }
    ' | sort -u || :
}

# claude: the model catalogue is baked into the minified bundle as objects of the
# shape {id:"claude-opus-5",family:"opus",...}. The pattern is deliberately loose
# about what follows — the bundle is re-minified between releases and anything more
# specific would rot. A miss is empty output, which the picker treats as "type one".
roles_parse_claude_models() {
    grep -aoE '\{[ ]*id: *"claude-[a-z0-9-]+" *,[ ]*family:' |
        sed -n 's/.*id: *"\([^"]*\)".*/\1/p' | sort -u || :
}

# The models one agent can serve, live. Prints bare ids, one per line; prints
# nothing and exits 0 when the agent is unknown, absent, or its source failed —
# callers treat "nothing" as "offer a typed value", never as an error.
roles_models_of() {
    _rmo_agent=$1
    _rmo_row=$(roles_models_table | awk -F'\t' -v a="$_rmo_agent" '$1 == a { print; exit }')
    [ -n "$_rmo_row" ] || return 0
    _rmo_kind=$(printf '%s' "$_rmo_row" | cut -f2)
    _rmo_src=$(printf '%s' "$_rmo_row" | cut -f3)
    _rmo_parser=$(printf '%s' "$_rmo_row" | cut -f4)

    case $_rmo_kind in
        command)
            # The timeout discipline is ade_query's: a runtime that stopped
            # answering must never hang the picker. Streams are joined because
            # agents disagree about which one carries the listing — pi prints
            # its table to stderr — and the parsers filter by pattern anyway.
            _rmo_to=$(ade_timeout_bin 2>/dev/null || :)
            if [ -n "$_rmo_to" ]; then
                "$_rmo_to" "${ADE_TIMEOUT_S:-5}" sh -c "$_rmo_src" 2>&1 | "$_rmo_parser"
            else
                sh -c "$_rmo_src" 2>&1 | "$_rmo_parser"
            fi
            ;;
        file)
            [ -f "${HOME:-}/$_rmo_src" ] || return 0
            "$_rmo_parser" < "${HOME:-}/$_rmo_src"
            ;;
        binary)
            _rmo_bin=$(command -v "$_rmo_src" 2>/dev/null) || return 0
            _rmo_real=$(readlink -f "$_rmo_bin" 2>/dev/null) || return 0
            [ -f "$_rmo_real" ] || return 0
            "$_rmo_parser" < "$_rmo_real"
            ;;
    esac
    return 0
}

# Effort levels for one agent's model, from the same source that named the model —
# an agent that knows its models usually knows what each accepts. Where the source
# does not answer (unknown agent, model not in the cache), fall back to the common
# rungs: an incomplete list is safe exactly because a typed value is always allowed.
roles_efforts_of() {
    _reo_agent=$1; _reo_model=$2
    _reo_out=
    case $_reo_agent in
        codex)
            [ -f "${HOME:-}/.codex/models_cache.json" ] || { roles_efforts; return 0; }
            _reo_out=$(awk -v m="$_reo_model" '
                { blob = blob " " $0 }
                END {
                    n = split(blob, part, /"slug"/)
                    for (i = 2; i <= n; i++) {
                        if (match(part[i], /"[^"]+"/) == 0) continue
                        if (substr(part[i], RSTART + 1, RLENGTH - 2) != m) continue
                        seg = part[i]
                        while (match(seg, /"effort"[ \t]*:[ \t]*"[^"]*"/)) {
                            e = substr(seg, RSTART, RLENGTH)
                            sub(/^"effort"[ \t]*:[ \t]*"/, "", e); sub(/"$/, "", e)
                            print e
                            seg = substr(seg, RSTART + RLENGTH)
                        }
                        exit
                    }
                }' "${HOME:-}/.codex/models_cache.json" 2>/dev/null)
            ;;
    esac
    if [ -n "$_reo_out" ]; then
        printf '%s\n' "$_reo_out" | sort -u
        return 0
    fi
    roles_efforts
}

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
