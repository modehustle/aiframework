#!/bin/sh
# verbs.sh — the deterministic half of every procedure.
#
# The system's weakest joint has always been this: mechanical, repeating actions —
# commit, append a log line in a fixed format, create a folder, move it to the archive,
# write the prune marker — were described in PROSE and left to the model's discretion.
# A model that is 95% reliable on each of six such steps completes all six correctly
# about 74% of the time. Over months that is where drift comes from.
#
# So each of them becomes a verb. The model still decides WHEN to call it, but the
# format, the paths and the commit stop being its business. That is what makes this a
# universal hook layer: a shell command works in every harness, in CI and in a container,
# whereas a harness hook works in exactly one harness.
#
# And one verb is a GATE. `task-seal` refuses to archive a task whose result.md does not
# state what happened to the foundation. Invariant 0.4 stops being self-reported and
# becomes a precondition: the only door out of a task is one we own.

verb_is_git() { git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }

# One commit format for the whole system. Kinds mirror the procedures that produce them.
verb_commit() {
    _root=$1; _kind=$2; _text=$3
    shift 3
    verb_is_git "$_root" || return 0
    config_is_on commit_verbs "$_root" || { dim "  коммит отключён (commit_verbs = off)"; return 0; }
    [ $# -gt 0 ] || return 0
    for _p in "$@"; do
        [ -e "$_root/$_p" ] || continue
        git -C "$_root" add -- "$_p" >/dev/null 2>&1 || true
    done
    git -C "$_root" diff --cached --quiet 2>/dev/null && return 0
    git -C "$_root" commit -q -m "$_kind: $_text" || return 1
    ok "коммит: $_kind: $_text"
}

# --- task-new ---------------------------------------------------------------
# Creates the task folder and stamps provenance. The planner fills the sections;
# what it can no longer do is forget the stamp, mistype the date, or omit the system
# version — the three things /run-task later relies on to detect a stale plan.
verb_task_new() {
    _root=$1; _slug=$2
    printf '%s' "$_slug" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' ||
        die "слаг должен быть kebab-case: буквы, цифры и дефисы"
    _dir="$_root/ai/tasks/$_slug"
    [ -e "$_dir" ] && die "задача уже существует: ai/tasks/$_slug"
    [ -d "$_root/ai/tasks" ] || die "нет ai/tasks/ — проект не под системой; сначала fraim scaffold"

    mkdir -p "$_dir" || die "не удалось создать $_dir"
    _date=$(date +%Y-%m-%d)
    _ver=$(fraim_version)
    if verb_is_git "$_root"; then
        _ref=$(git -C "$_root" rev-parse --short HEAD 2>/dev/null)
        _based="HEAD $_ref"
    else
        _based="<no git — list the files this plan assumes the current state of>"
    fi

    {
        printf '# Task Context\n\n'
        printf '## Plan provenance\n'
        printf -- '- Planned: %s\n' "$_date"
        printf -- '- Based on: %s\n' "$_based"
        printf -- '- System: fraim %s\n\n' "$_ver"
        printf '<!-- fraim:stub — /make-task fills the sections below and deletes this line. -->\n\n'
        for _s in Goal Why "Codebase Context" Constraints "Decisions and Rationale" \
                  "Known Pitfalls" "Out of Scope"; do
            printf '## %s\n\n' "$_s"
        done
    } > "$_dir/context.md"

    {
        printf '# Task\n\n'
        printf '<!-- fraim:stub — /make-task fills the sections below and deletes this line. -->\n\n'
        for _s in Summary "Files to Change" "Step-by-step Implementation" \
                  "Acceptance Criteria" "Verification Commands" \
                  "Foundation updates (executor's final step — invariant 0.4)" \
                  "Executor Rules — read before starting"; do
            printf '## %s\n\n' "$_s"
        done
    } > "$_dir/task.md"

    ok "ai/tasks/$_slug/ — provenance: $_based, fraim $_ver"
    dim "  заполни разделы по /make-task, потом задачу исполняет /run-task"
}

# --- task-seal (the gate) ---------------------------------------------------
verb_task_seal() {
    _root=$1; _slug=$2
    _dir="$_root/ai/tasks/$_slug"
    [ -d "$_dir" ] || die "нет такой задачи: ai/tasks/$_slug"

    # Gate 1 — the task must actually have been executed.
    [ -f "$_dir/result.md" ] ||
        die "нет result.md — задача не исполнена. Архивировать нечего."

    # Gate 2 — a blocked task goes back to the planner, not into the archive.
    [ -f "$_dir/blockers.md" ] &&
        die "есть blockers.md — задача заблокирована. Сначала /revise-task, потом /run-task."

    # Gate 3 — the foundation must be accounted for. This is invariant 0.4 turning from
    # a request into a precondition: the executor may legitimately have changed nothing,
    # but it has to SAY so, and the statement lands in the archive as a record.
    if ! grep -q '^## Foundation updated' "$_dir/result.md"; then
        die "в result.md нет раздела '## Foundation updated' — инвариант 0.4 не отчитан"
    fi
    _fsec=$(awk '/^## Foundation updated/{f=1;next} /^## /{f=0} f' "$_dir/result.md")
    if [ -z "$(printf '%s' "$_fsec" | tr -d '[:space:]')" ]; then
        die "раздел '## Foundation updated' пуст — напиши, что стало с ARCHITECTURE.md и DECISIONS.md"
    fi
    if printf '%s' "$_fsec" | grep -q '<[^>]*>'; then
        die "в '## Foundation updated' остались незаполненные плейсхолдеры — допиши их"
    fi

    _stamp=$(date +%Y-%m-%d_%H%M)
    _dest="$_root/ai/archive/${_stamp}_${_slug}"
    [ -e "$_dest" ] && die "в архиве уже есть $_dest"
    mkdir -p "$_root/ai/archive" || die "не удалось создать ai/archive/"
    mv "$_dir" "$_dest" || die "не удалось перенести задачу в архив"
    ok "архивировано: ai/archive/${_stamp}_${_slug}"

    verb_commit "$_root" archive "$_slug" "ai/tasks" "ai/archive" || warn "коммит не удался"

    _left=$(find "$_root/ai/tasks" -mindepth 1 -maxdepth 1 -type d 2>/dev/null |
            while read -r _d; do basename -- "$_d"; done | sort | tr '\n' ' ')
    if [ -n "$_left" ]; then say "  осталось в очереди: $_left"; else dim "  очередь пуста"; fi
}

# --- hotfix-log -------------------------------------------------------------
# The exact line format matters: the watchman counts these, and /prune resets the count.
# A model improvising the format quietly breaks the drift counter, and nobody notices
# until the foundation has rotted.
verb_hotfix_log() {
    _root=$1; _file=$2; _desc=$3; _behavior=${4:-no}
    case $_behavior in yes|no) ;; *) die "behavior должен быть yes или no" ;; esac
    _log="$_root/ai/hotfix_log.md"
    [ -d "$_root/ai" ] || die "нет ai/ — проект не под системой"
    [ -f "$_log" ] || printf '# Hotfix log\n\n' > "$_log"
    printf -- '- %s — `%s` — %s — behavior: %s\n' \
        "$(date '+%Y-%m-%d %H:%M')" "$_file" "$_desc" "$_behavior" >> "$_log"
    ok "записано в ai/hotfix_log.md"

    _count=$(awk '/^--- pruned .* ---[[:space:]]*$/ { n = 0; next } /^-[[:space:]]/ { n++ } END { print n+0 }' "$_log")
    _threshold=$(config_get hotfix_threshold "$_root")
    if [ "$_count" -ge "$_threshold" ]; then
        warn "хотфиксов с последнего прунинга: $_count (порог $_threshold) — пора /prune"
    else
        dim "  хотфиксов с последнего прунинга: $_count из $_threshold"
    fi

    verb_commit "$_root" hotfix "$_desc" "$_file" ai/hotfix_log.md DECISIONS.md ||
        warn "коммит не удался"
}

# --- prune-mark -------------------------------------------------------------
verb_prune_mark() {
    _root=$1
    _log="$_root/ai/hotfix_log.md"
    [ -f "$_log" ] || die "нет ai/hotfix_log.md — нечего сбрасывать"
    _date=$(date +%Y-%m-%d)
    printf -- '--- pruned %s ---\n' "$_date" >> "$_log"
    ok "счётчик дрейфа сброшен маркером --- pruned $_date ---"
    verb_commit "$_root" prune "reconcile foundation $_date" \
        ai/hotfix_log.md ARCHITECTURE.md CONVENTIONS.md DECISIONS.md ai/archive ||
        warn "коммит не удался"
}
