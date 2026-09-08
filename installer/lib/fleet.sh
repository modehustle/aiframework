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
    tr -d '\n' 2>/dev/null |
        grep -oE ":[[:space:]]*\"${_fi_kind}_[0-9a-f][0-9a-f-]{7,}\"" 2>/dev/null |
        head -1 | sed 's/^:[[:space:]]*//; s/"//g'
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

# ---------------------------------------------------------------------------
# Reading the pane, for a human or a conductor to judge — not for THIS code to judge
#
# `terminal read`/`terminal show` exist in Orca's own CLI (skill-guides/orca-cli.md:
# "ORCA terminal read --terminal <handle> --cursor <cursor> --limit <n> --json") and were
# missing from MODES.md §9's six operations entirely — the first survey never asked for
# them, so nothing here used them. That is the gap the owner pointed at: we recorded THAT
# an agent refused a launch-time model (fleet_caps_note above), never WHAT it is actually
# running instead, because nothing ever looked.
#
# What this function does NOT do: decide whether the text it returns means the switch
# worked. Parsing "did this confirm the model" per agent is exactly the treadmill P0 warns
# against — thirteen agents, thirteen banners, thirteen ways to get the grep wrong and
# report false confidence. G7 (verify against the tree, not a report) does not forbid
# READING evidence, it forbids TRUSTING A VERDICT written by the party being judged. A
# transcript is not a verdict — nobody composed it to convince us of anything. So the raw
# text is handed back whole, the same way fleet_worker_show hands back JSON whole, and the
# party equipped to read it — the conductor, who is the one that just ran `fraim dispatch
# run` and receives this text in its own tool output — makes the call, not this shell
# function pretending to.
fleet_worker_read_terminal() {
    _fwrt_disp=$1; _fwrt_limit=${2:-40}
    _fwrt_cmd=$(fleet_cli) || return 1
    _fwrt_term=$(fleet_worker_terminal "$_fwrt_disp")
    [ -n "$_fwrt_term" ] || return 1
    "$_fwrt_cmd" terminal read --terminal "$_fwrt_term" --limit "$_fwrt_limit" --json 2>&1
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

    # Known from a previous refusal: do not ask again. This is what turns "the fleet dies
    # every time" into "the fleet died once, and only until it was told why".
    if [ -n "$_fws_model" ] && fleet_caps_has "$_fws_agent" no-launch-model; then
        printf >&2 'агент %s модель при запуске не принимает (известно с прошлого раза) — %s пойдёт без неё\n' \
            "$_fws_agent" "$_fws_name"
        _fws_model=
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
    # Retried without the model rather than refused, because the alternative is a fleet
    # that will not start over a flag the agent simply ignores. The human is told: which
    # model was dropped for whom is exactly the kind of thing that is obvious now and
    # invisible three hours later.
    if [ "$_fws_rc" -ne 0 ] && [ -n "$_fws_model" ] &&
       printf '%s' "$_fws_out" | grep -qi 'launch-time model\|does not support.*model'; then
        fleet_caps_note "$_fws_agent" no-launch-model
        printf >&2 'агент %s не принимает модель при запуске — поднимаю %s без неё (модель %s не применена)\n' \
            "$_fws_agent" "$_fws_name" "$_fws_model"
        printf >&2 '  запомнено: следующие сборки не будут пытаться\n'
        if _fws_out=$("$_fws_cmd" orchestration worker-start \
            --task "$_fws_task" --agent "$_fws_agent" \
            --worktree new-top-level --name "$_fws_name" \
            --repo "path:$_fws_root" --base-branch "$_fws_base" --json 2>&1)
        then _fws_rc=0; else _fws_rc=$?; fi
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
