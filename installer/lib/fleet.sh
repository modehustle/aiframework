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
# Two things make this correct, and each was learned by getting it wrong.
#
# The colon: searching for `"run_…"` alone matches the FIELD NAME `"run_id"` and returns
# the string `run_id` as though it were an identifier. An id is always a VALUE, so it is
# always preceded by a colon; a field name never is.
#
# Hex only, and at least eight of them: in the first live build the response carried
# `"stage": "dispatch_input"`, a state name that sat after a colon and began with the
# prefix being searched for. It was written into fleet.tsv as every worker's identifier,
# and watch and verify were useless for the rest of the session. Orca's ids are hex
# (run_167eb45dfa55, task_cd10350c41cf, ctx_797e84aa5091), and a state name is words —
# `input` contains no hex digit at all, so requiring hex separates data from vocabulary.
fleet_id() {
    _fi_kind=$1
    case $_fi_kind in
        # term_all: EVERY terminal handle, for sweeps over a worktree's
        # terminals; the plain kinds take the first match.
        term_all) _fi_re="\"term_[0-9a-f][0-9a-f-]{7,}\"" ;;
        *)        _fi_re=":[[:space:]]*\"${_fi_kind}_[0-9a-f][0-9a-f-]{7,}\"" ;;
    esac
    tr -d '\n' 2>/dev/null |
        grep -oE "$_fi_re" 2>/dev/null |
        sed 's/^[[:space:]]*:[[:space:]]*//; s/"//g' |
        { [ "$_fi_kind" = term_all ] && cat || head -1; }
}

# The prefix Orca uses for the identifier of one dispatched worker.
#
# It is `ctx_`, not `dispatch_` — established from the first live build, where
# `worker-list --json` reported ctx_797e84aa5091 and friends for the four running workers.
# Named here rather than inlined so that the day it changes, it changes in one place.
FLEET_DISPATCH_KIND=ctx

# ---------------------------------------------------------------------------
# What an agent can be launched with
#
# The problem this solves, from the first live build: the role table said devin:glm-5.2,
# nothing could have known that Orca's devin agent rejects a launch-time model, and all
# four workers died on it. Retrying without the model fixes that one case; it does not
# help with whatever the next agent refuses for its own reason.
#
# The general answer is not a catalogue of agent capabilities — that is the treadmill P0
# warns about, and it would be stale the week it was written. It is to LEARN FROM THE
# REFUSAL: the environment already tells us what it will not accept, once, at the moment
# we ask. Writing that down turns a repeated failure into a single one.
#
# A cache, not a registry: the environment's capabilities are its truth, ours is a note of
# what it told us and when (§10). Stale entries cost one extra launch attempt to correct,
# which is why forgetting is safe and `fraim clean` may drop this file at any time.
#
# Format: one line per fact, `agent<TAB>fact<TAB>when`.
fleet_caps_file() { printf '%s/agent-caps\n' "$FRAIM_HOME"; }

fleet_caps_has() {
    _fch=$(fleet_caps_file)
    [ -f "$_fch" ] || return 1
    grep -q "^$1	$2	" "$_fch" 2>/dev/null
}

fleet_caps_note() {
    _fcn=$(fleet_caps_file)
    mkdir -p "$(dirname -- "$_fcn")" 2>/dev/null || return 0
    fleet_caps_has "$1" "$2" && return 0
    printf '%s\t%s\t%s\n' "$1" "$2" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$_fcn" 2>/dev/null || :
}

# Human-readable line for `fraim roles`, or nothing.
fleet_caps_describe() {
    fleet_caps_has "$1" no-launch-model && printf 'модель при запуске не принимает\n'
    return 0
}

# ---------------------------------------------------------------------------
# Setting the model from inside the session
#
# The owner's idea, and it is the right shape: an agent that refuses `--model` at launch
# may still be able to switch models once it is running, the way a person types `/model`.
# So instead of giving up on the model, hand the worker the instruction as its first input.
#
# What we do NOT do is guess the command. Sending `/model X` to an agent that has no such
# command does not fail — the agent reads it as the first line of its task, which is worse
# than not setting the model at all. So a command is sent only when it is KNOWN:
#
#   1. built in for agents whose command we have read (claude);
#   2. `modelcmd_<agent>` in the config, for everything else.
#
# The second is what makes this universal without a catalogue: the person who has the agent
# in front of them can teach us its command in one line, without waiting for a release.
#
#     fraim config set --machine modelcmd_devin '/model %s'
#
# `%s` is where the model id goes. No `%s` means the value is sent verbatim.
fleet_model_command() {
    _fmc_agent=$1; _fmc_model=$2
    _fmc_tpl=$(config_get "modelcmd_$_fmc_agent" "${3:-}" 2>/dev/null || :)
    if [ -z "$_fmc_tpl" ]; then
        case $_fmc_agent in
            claude) _fmc_tpl='/model %s' ;;
            *) return 1 ;;
        esac
    fi
    # Substituted with shell parameter expansion rather than printf: the template comes
    # from a config file, and feeding foreign text to printf as a FORMAT makes every %
    # in it an instruction. The first attempt here did exactly that and shipped the
    # literal "/model %s" to the worker.
    case $_fmc_tpl in
        *%s*)
            _fmc_pre=${_fmc_tpl%%'%s'*}
            _fmc_post=${_fmc_tpl#*'%s'}
            printf '%s%s%s\n' "$_fmc_pre" "$_fmc_model" "$_fmc_post"
            ;;
        *)  printf '%s\n' "$_fmc_tpl" ;;
    esac
}

# ---------------------------------------------------------------------------
# Launching an agent: command, readiness, cleanup
#
# The atomic `worker-start --agent` composes worktree, terminal, readiness and
# dispatch in one call — and on Orca 1.4.196 with the Devin CLI it injects the
# task preamble before the TUI is ready: the PTY records the bracketed-paste
# marker and the prompt text BEFORE the agent banner, Orca times out at
# `dispatch_input` with `agent_prompt_stalled`, and every worker of the build
# dies the same death. Orca's `--model` also supports only Claude, Codex and
# Cursor, so a role like devin:glm-5.2 silently runs on the agent's default.
#
# The general fix is Orca's own documented low-level recipe for custom agent
# argv: worktree create → terminal create --command "<argv>" → terminal wait
# --for tui-idle → worker-start --terminal. Readiness is the terminal's own
# state, never a sleep; the Dispatch (and with it task/dispatch provenance,
# worker_done authority, heartbeat, ask/reply) is created only after the TUI
# confirmed it is ready. `worker-start --terminal` is the supervised path —
# `dispatch --inject` would lose worker lifecycle state entirely.
#
# What an agent is launched WITH is split the same way the in-session model
# command already is: a launch command is used only when it is KNOWN —
#   1. `launchcmd_<agent>` in the config, template with `%s` for the model id;
#   2. built in here for agents we have read (devin).
# No guessing for unknown agents: a wrong argv is not a failed launch, it is a
# task that never starts while looking like it did.
fleet_launch_command() {
    _flc_agent=$1; _flc_model=$2; _flc_root=$3
    _flc_tpl=$(config_get "launchcmd_$_flc_agent" "$_flc_root" 2>/dev/null || :)
    if [ -z "$_flc_tpl" ]; then
        case $_flc_agent in
            # The one built-in: the role table names devin models, Orca refuses
            # to pass them, and the CLI takes --model itself. Verified against
            # `devin models list` (glm-5-2 present).
            devin) [ -n "$_flc_model" ] && _flc_tpl='devin --permission-mode bypass --model %s' ||
                   _flc_tpl='devin' ;;
            *) return 1 ;;
        esac
    fi
    # Same substitution discipline as fleet_model_command: parameter expansion,
    # never printf — the template comes from a config file and every % in it
    # would otherwise be an instruction.
    case $_flc_tpl in
        *%s*)
            # A template that names a model slot with no model to put there
            # degrades to the bare agent — the same launch Orca's native path
            # would make, and never a dangling "--model " argument.
            if [ -z "$_flc_model" ]; then
                printf '%s\n' "$_flc_agent"
            else
                _flc_pre=${_flc_tpl%%'%s'*}
                _flc_post=${_flc_tpl#*'%s'}
                printf '%s\n' "$_flc_pre$_flc_model$_flc_post"
            fi
            ;;
        *)  printf '%s\n' "$_flc_tpl" ;;
    esac
}

# How long a fresh agent TUI may take to reach tui-idle. Devin cold starts are
# the slow case; the default is generous because a timeout here fails the
# worker, and a too-small timeout would manufacture failures.
fleet_ready_timeout_ms() {
    _frt=$(config_get fleet_ready_timeout_ms "${1:-}" 2>/dev/null || :)
    [ -n "$_frt" ] || _frt=120000
    printf '%s\n' "$_frt"
}

# One Orca call, ok-gated, with the failure printed for the human. The shared
# body of every helper below: their envelope is the one field we trust.
fleet_call() {
    _fc_cmd=$(fleet_cli) || return 1
    _fc_out=$("$_fc_cmd" "$@" 2>&1) || {
        printf >&2 '%s\n' "$_fc_out"; return 1
    }
    printf '%s' "$_fc_out" | fleet_ok || {
        printf >&2 'orca отказал:\n%s\n' "$_fc_out"; return 1
    }
    printf '%s\n' "$_fc_out"
}

# An isolated checkout WITHOUT an agent — the first half of the low-level
# recipe. The selector is built from the returned path (selectors accept
# path:<path>), because worktree ids carry the repo id we do not know here.
# Orca silently REUSES an existing worktree of the same name (a previous
# failed attempt's), so _FLEET_WT_CREATED records whether THIS call created
# it — cleanup must never delete a checkout it did not create.
#
# Results travel in globals, not stdout: the caller must be able to read them
# after the call, and a `$()` would run the function in a subshell where its
# assignments die.
fleet_worktree_create() {
    _fwc_name=$1; _fwc_root=$2; _fwc_base=$3
    _FLEET_WT=; _FLEET_WT_CREATED=0
    _fwc_out=$(fleet_call worktree create --name "$_fwc_name" \
        --repo "path:$_fwc_root" --base-branch "$_fwc_base" --json) || return 1
    # The receipt names the checkout's path under worktreePath on current
    # runtimes and path on older ones; both are accepted selectors.
    _fwc_path=$(printf '%s' "$_fwc_out" | fleet_json_str worktreePath)
    [ -n "$_fwc_path" ] || _fwc_path=$(printf '%s' "$_fwc_out" | fleet_json_str path)
    [ -n "$_fwc_path" ] || {
        printf >&2 'worktree create: в ответе нет пути:\n%s\n' "$_fwc_out"; return 1
    }
    _fwc_created=$(printf '%s' "$_fwc_out" | fleet_json_num createdAt)
    case $_fwc_created in
        ''|*[!0-9]*) : ;;
        # A checkout created in the last minute is ours; anything older is a
        # reused leftover, and its fate is not ours to decide.
        *) [ "$_fwc_created" -gt $(( $(date +%s) * 1000 - 60000 )) ] && _FLEET_WT_CREATED=1 ;;
    esac
    _FLEET_WT="path:$_fwc_path"
    return 0
}

# One string value out of an Orca JSON response: the FIRST occurrence of
# "key": "value". Typed ids go through fleet_id (prefix + hex); this is for
# the rest — paths, handles' neighbours — where the prefix discipline does
# not apply.
fleet_json_str() {
    _fjs_key=$1
    tr -d '\n' 2>/dev/null |
        grep -oE "\"$_fjs_key\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" 2>/dev/null |
        head -1 | sed "s/^\"$_fjs_key\"[[:space:]]*:[[:space:]]*//; s/\"//g"
}

# One numeric value out of an Orca JSON response — timestamps arrive unquoted,
# where the string extractor must not look.
fleet_json_num() {
    _fjn_key=$1
    tr -d '\n' 2>/dev/null |
        grep -oE "\"$_fjn_key\"[[:space:]]*:[[:space:]]*[0-9]+" 2>/dev/null |
        head -1 | sed "s/^\"$_fjn_key\"[[:space:]]*:[[:space:]]*//"
}

# A terminal in the worktree running exactly our argv — the model travels
# inside the command, which is the only channel Orca leaves open for agents
# outside its --model allow-list. The handle travels in $_FLEET_TERM (globals,
# not stdout — see fleet_worktree_create).
fleet_terminal_create() {
    _ftc_wt=$1; _ftc_cmdline=$2
    _FLEET_TERM=
    _ftc_out=$(fleet_call terminal create --worktree "$_ftc_wt" \
        --command "$_ftc_cmdline" --json) || return 1
    _ftc_term=$(printf '%s' "$_ftc_out" | fleet_id term)
    [ -n "$_ftc_term" ] || {
        printf >&2 'terminal create: в ответе нет term_… идентификатора:\n%s\n' "$_ftc_out"
        return 1
    }
    _FLEET_TERM=$_ftc_term
    return 0
}

# The readiness gate. Exit code is the whole verdict: Orca's `terminal wait`
# exits 0 only when the state was reached, nonzero on timeout — there is
# nothing in the output to parse and no sleep to guess with.
fleet_terminal_wait_idle() {
    _ftw_term=$1; _ftw_root=$2
    _ftw_ms=$(fleet_ready_timeout_ms "$_ftw_root")
    _ftw_cmd=$(fleet_cli) || return 1
    "$_ftw_cmd" terminal wait --terminal "$_ftw_term" --for tui-idle \
        --timeout-ms "$_ftw_ms" --json >/dev/null 2>&1
}

# What the terminal actually shows. Orca's tui-idle proved too optimistic for a
# cold Devin start — it reported idle while the TUI was still initializing, and
# the prompt injected into that gap stalled exactly as before. The banner check
# closes that hole: readiness is not "Orca thinks it is idle" but "the agent's
# own banner is on screen".
fleet_terminal_tail() {
    _ftt_term=$1
    _ftw_cmd=$(fleet_cli) || return 1
    "$_ftw_cmd" terminal read --terminal "$_ftw_term" --limit 40 --json 2>/dev/null
}

# Close every terminal in the worktree except ours. Only handles Orca itself
# reported for this worktree are touched, and only after our agent terminal
# exists — so what is closed is by construction not the terminal we were given.
fleet_close_other_terminals() {
    _fco_wt=$1; _fco_keep=$2
    _fco_cmd=$(fleet_cli) || return 0
    _fco_out=$("$_fco_cmd" terminal list --worktree "$_fco_wt" --json 2>/dev/null) || return 0
    for _fco_h in $(printf '%s' "$_fco_out" | fleet_id term_all); do
        [ "$_fco_h" = "$_fco_keep" ] && continue
        "$_fco_cmd" terminal close --terminal "$_fco_h" --json >/dev/null 2>&1 || :
    done
    return 0
}

# The readiness pattern per agent: config `readypattern_<agent>` first, built-in
# for agents we have read. No pattern → tui-idle alone decides.
fleet_ready_pattern() {
    _frp_agent=$1; _frp_root=$2
    _frp=$(config_get "readypattern_$_frp_agent" "$_frp_root" 2>/dev/null || :)
    [ -n "$_frp" ] && { printf '%s\n' "$_frp"; return 0; }
    case $_frp_agent in
        devin) printf 'Devin CLI' ;;
        *)     return 1 ;;
    esac
}

# The full readiness gate: tui-idle first (cheap, Orca-side), then the banner
# pattern polled from the terminal itself until it appears or the readiness
# budget runs out. The poll interval is a cadence, not a readiness guess —
# every iteration reads the terminal's actual state.
fleet_terminal_wait_ready() {
    _fwr_term=$1; _fwr_root=$2; _fwr_agent=$3
    fleet_terminal_wait_idle "$_fwr_term" "$_fwr_root" || return 1
    _fwr_pat=$(fleet_ready_pattern "$_fwr_agent" "$_fwr_root") || return 0
    _fwr_deadline=$(( $(date +%s) + $(fleet_ready_timeout_ms "$_fwr_root") / 1000 ))
    while [ "$(date +%s)" -lt "$_fwr_deadline" ]; do
        if fleet_terminal_tail "$_fwr_term" | grep -qF -- "$_fwr_pat"; then
            return 0
        fi
        sleep 2
    done
    printf >&2 'агент %s запущен, но его баннер не появился в терминале за отведённое время\n' \
        "$_fwr_agent"
    return 1
}

# Clean up exactly what a failed launch created, best-effort and in the order
# ownership was taken: the Dispatch first (worker-release closes only the
# coordinator-owned agent terminal and is idempotent by their contract), then
# the terminal, then the worktree this call created. Any step may fail — a
# partial cleanup is reported by Orca, not hidden here — and no step may
# prevent the next.
fleet_launch_cleanup() {
    _flc_disp=$1; _flc_wt=$2; _flc_term=$3
    [ -n "$_flc_disp" ] && fleet_worker_release "$_flc_disp" >/dev/null 2>&1
    [ -n "$_flc_wt" ] && {
        _flc_cmd=$(fleet_cli) || return 0
        "$_flc_cmd" terminal stop --worktree "$_flc_wt" --json >/dev/null 2>&1 || :
        # Only a checkout THIS launch created may be removed — a reused one
        # belongs to a previous attempt and is not ours to delete.
        [ "${_FLEET_WT_CREATED:-0}" = "1" ] &&
            "$_flc_cmd" worktree rm --worktree "$_flc_wt" --json >/dev/null 2>&1 || :
    }
    return 0
}

# The terminal a worker runs in, so something can be typed into it.
fleet_worker_terminal() {
    fleet_worker_show "$1" | fleet_id term
}

# Type one line into a worker's terminal and press enter.
fleet_worker_send() {
    _fws2_term=$1; _fws2_text=$2
    _fws2_cmd=$(fleet_cli) || return 1
    "$_fws2_cmd" terminal send --terminal "$_fws2_term" \
        --text "$_fws2_text" --enter --json >/dev/null 2>&1
}

# Ask a running worker to switch to the model its role asked for. Returns 1 when we do not
# know how to say it to this agent — the caller then reports the model as not applied,
# which is the truth.
fleet_worker_set_model() {
    _fwsm_disp=$1; _fwsm_agent=$2; _fwsm_model=$3; _fwsm_root=${4:-}
    _fwsm_line=$(fleet_model_command "$_fwsm_agent" "$_fwsm_model" "$_fwsm_root") || return 1
    _fwsm_term=$(fleet_worker_terminal "$_fwsm_disp")
    [ -n "$_fwsm_term" ] || return 1
    fleet_worker_send "$_fwsm_term" "$_fwsm_line" || return 1
    printf '%s\n' "$_fwsm_line"
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

# The custom half of the lifecycle: create → launch → wait → dispatch. Every
# resource is cleaned up on the way out if a later step fails, and the task
# preamble is only ever sent to a terminal Orca itself has confirmed idle.
#
# What was actually used is reported back through _FLEET_LAST_LAUNCH (the argv)
# and _FLEET_LAST_LAUNCH_MODEL (the model that travelled inside it, empty when
# none did) — the caller's reporting reads these rather than re-deriving the
# path, because "which model actually ran" is the caller's contract. When the
# caller runs this inside a command substitution it could not read globals, so
# the same facts are appended, tab-separated, to $_FLEET_INFO when that file
# path is set.
fleet_worker_start_custom() {
    _fwsc_task=$1; _fwsc_agent=$2; _fwsc_model=$3
    _fwsc_name=$4; _fwsc_root=$5; _fwsc_base=$6

    _FLEET_LAST_LAUNCH=; _FLEET_LAST_LAUNCH_MODEL=
    _FLEET_WT=; _FLEET_WT_CREATED=0; _FLEET_TERM=

    if fleet_worktree_create "$_fwsc_name" "$_fwsc_root" "$_fwsc_base"; then :; else
        return 1
    fi
    _fwsc_wt=$_FLEET_WT

    if _fwsc_launch=$(fleet_launch_command "$_fwsc_agent" "$_fwsc_model" "$_fwsc_root"); then :; else
        # No launch command is known for this agent — the bare name is the same
        # launch Orca's native path would make, never an invented flag.
        _fwsc_launch=$_fwsc_agent
    fi
    _FLEET_LAST_LAUNCH=$_fwsc_launch
    [ -n "$_fwsc_model" ] && _FLEET_LAST_LAUNCH_MODEL=$_fwsc_model

    if fleet_terminal_create "$_fwsc_wt" "$_fwsc_launch"; then :; else
        fleet_launch_cleanup "" "$_fwsc_wt" ""
        return 1
    fi
    _fwsc_term=$_FLEET_TERM

    # A worktree carries terminals that are not ours: a fresh one gets Orca's
    # fallback shell, a reused one still holds the previous attempt's stale
    # agent processes. Both are closed before our agent is waited on — they
    # would compete for the task and make the terminal count lie.
    fleet_close_other_terminals "$_fwsc_wt" "$_fwsc_term"

    if fleet_terminal_wait_ready "$_fwsc_term" "$_fwsc_root" "$_fwsc_agent"; then :; else
        _fwsc_ms=$(fleet_ready_timeout_ms "$_fwsc_root")
        printf >&2 'агент %s не достиг готовности терминала (tui-idle) за %s мс — задание не отправлено\n' \
            "$_fwsc_agent" "$_fwsc_ms"
        fleet_launch_cleanup "" "$_fwsc_wt" "$_fwsc_term"
        return 1
    fi

    _fwsc_cmd=$(fleet_cli) || { fleet_launch_cleanup "" "$_fwsc_wt" "$_fwsc_term"; return 1; }
    # The bind timeout must cover a COLD agent start, not just prompt delivery:
    # Orca's own default (~33s) is what produced agent_prompt_stalled on a
    # healthy-but-slow Devin. The readiness budget is the same clock the TUI
    # already had, and a worker that needs longer fails honestly at the gate.
    _fwsc_ms=$(fleet_ready_timeout_ms "$_fwsc_root")
    if _fwsc_out=$("$_fwsc_cmd" orchestration worker-start \
        --task "$_fwsc_task" --terminal "$_fwsc_term" --worktree "$_fwsc_wt" \
        --timeout-ms "$_fwsc_ms" --json 2>&1)
    then _fwsc_rc=0; else _fwsc_rc=$?; fi

    if [ "$_fwsc_rc" -ne 0 ]; then
        printf >&2 'worker-start не привязал задание к терминалу %s:\n%s\n' \
            "$_fwsc_name" "$_fwsc_out"
        # The refusal may name the Dispatch it created (their receipts carry
        # effects/residualResources); when it does not, ask Orca directly — a
        # failed bind can still have left one behind, and release is idempotent.
        _fwsc_disp=$(printf '%s' "$_fwsc_out" | fleet_id "$FLEET_DISPATCH_KIND")
        [ -n "$_fwsc_disp" ] || _fwsc_disp=$(
            fleet_call orchestration dispatch-show --task "$_fwsc_task" --json 2>/dev/null |
                fleet_id "$FLEET_DISPATCH_KIND")
        fleet_launch_cleanup "$_fwsc_disp" "$_fwsc_wt" "$_fwsc_term"
        return 1
    fi

    _fwsc_id=$(printf '%s' "$_fwsc_out" | fleet_id "$FLEET_DISPATCH_KIND")
    [ -n "$_fwsc_id" ] || {
        printf >&2 'worker-start: в ответе нет %s_… идентификатора:\n%s\n' \
            "$FLEET_DISPATCH_KIND" "$_fwsc_out"
        fleet_launch_cleanup "" "$_fwsc_wt" "$_fwsc_term"
        return 1
    }
    fleet_launch_report custom "$_FLEET_LAST_LAUNCH" "$_FLEET_LAST_LAUNCH_MODEL"
    printf '%s\n' "$_fwsc_id"
}

# One line of launch truth for the caller, through the $_FLEET_INFO file when
# one is set (globals die in the caller's command substitution; a file does
# not). Silent when nobody is listening.
fleet_launch_report() {
    [ -n "${_FLEET_INFO:-}" ] || return 0
    printf '%s\t%s\t%s\n' "$1" "${2:-}" "${3:-}" >> "$_FLEET_INFO" 2>/dev/null || :
    return 0
}

# §9.1 + §9.2: an isolated checkout AND a named agent on a named model — but
# no longer one blind atomic call. Two paths, one contract (print the ctx_…
# dispatch id, exit 0 only for ready):
#
#   native  — `worker-start --agent --model --effort`, exactly as before. The
#             default, because Orca reports `launch.effective` for the agents
#             it launches itself, and bypassing that would cost us the truth
#             about which model ran.
#   custom  — the explicit lifecycle above, taken when a launch command is
#             known (config `launchcmd_<agent>` or the devin built-in), when
#             the agent is already known to refuse `--model`, or when a native
#             attempt has just refused it. The model travels inside the argv;
#             readiness is the terminal's own tui-idle; the Dispatch is bound
#             only after that.
#
# Their exit code is meaningful on both paths and we pass it through: "the call
# exits 0 only for ready. Failed or outcome_unknown exits 1."
fleet_worker_start() {
    _fws_task=$1; _fws_agent=$2; _fws_model=$3; _fws_effort=$4
    _fws_name=$5; _fws_root=$6; _fws_base=$7

    _fws_cmd=$(fleet_cli) || return 1

    # Known from a previous refusal: do not ask again. This is what turns "the fleet dies
    # every time" into "the fleet died once, and only until it was told why".
    if [ -n "$_fws_model" ] && fleet_caps_has "$_fws_agent" no-launch-model; then
        printf >&2 'агент %s модель при запуске не принимает (известно с прошлого раза) — %s пойдёт через команду запуска\n' \
            "$_fws_agent" "$_fws_name"
    fi

    # A launch command we can vouch for decides the path before anything is
    # called: the model rides in the argv and readiness is confirmed.
    if fleet_launch_command "$_fws_agent" "$_fws_model" "$_fws_root" >/dev/null 2>&1; then
        fleet_worker_start_custom "$_fws_task" "$_fws_agent" "$_fws_model" \
            "$_fws_name" "$_fws_root" "$_fws_base"
        return $?
    fi

    # `_fws_out=$(cmd)` followed by `_fws_rc=$?` looks right and is not: under `set -e`
    # the assignment itself carries the command's exit status, so a failing launch killed
    # the whole run before the retry below could ever be reached. Captured through `if`
    # instead, which is the one place a non-zero status is allowed to be read.
    if [ -n "$_fws_model" ]; then
        if _fws_out=$("$_fws_cmd" orchestration worker-start \
            --task "$_fws_task" --agent "$_fws_agent" \
            --model "$_fws_model" --effort "$_fws_effort" \
            --worktree new-top-level --name "$_fws_name" \
            --repo "path:$_fws_root" --base-branch "$_fws_base" --json 2>&1)
        then _fws_rc=0; else _fws_rc=$?; fi
    else
        if _fws_out=$("$_fws_cmd" orchestration worker-start \
            --task "$_fws_task" --agent "$_fws_agent" \
            --worktree new-top-level --name "$_fws_name" \
            --repo "path:$_fws_root" --base-branch "$_fws_base" --json 2>&1)
        then _fws_rc=0; else _fws_rc=$?; fi
    fi

    # Not every agent accepts a model at launch. The first live build died whole on this:
    # the role table said devin:glm-5.2, dispatch-check passed it (it validates shape, and
    # cannot know an agent's capabilities), and all four workers failed with "Agent devin
    # does not support launch-time model selection."
    #
    # Learned once, then routed into the explicit lifecycle — the same one every
    # launch-command agent takes — instead of a silent retry without the model. The
    # human is told: which model was dropped for whom is exactly the kind of thing
    # that is obvious now and invisible three hours later.
    if [ "$_fws_rc" -ne 0 ] && [ -n "$_fws_model" ] &&
       printf '%s' "$_fws_out" | grep -qi 'launch-time model\|does not support.*model'; then
        fleet_caps_note "$_fws_agent" no-launch-model
        printf >&2 'агент %s не принимает модель при запуске — поднимаю %s через команду запуска (модель %s не применена Orca)\n' \
            "$_fws_agent" "$_fws_name" "$_fws_model"
        printf >&2 '  запомнено: следующие сборки пойдут через команду запуска сразу\n'
        fleet_worker_start_custom "$_fws_task" "$_fws_agent" "" \
            "$_fws_name" "$_fws_root" "$_fws_base"
        return $?
    fi

    if [ "$_fws_rc" -ne 0 ]; then
        printf >&2 'worker-start не поднял воркера %s:\n%s\n' "$_fws_name" "$_fws_out"
        return 1
    fi
    _fws_id=$(printf '%s' "$_fws_out" | fleet_id "$FLEET_DISPATCH_KIND")
    [ -n "$_fws_id" ] || {
        printf >&2 'worker-start: в ответе нет %s_… идентификатора:\n%s\n' \
            "$FLEET_DISPATCH_KIND" "$_fws_out"
        return 1
    }
    fleet_launch_report native "" ""
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
