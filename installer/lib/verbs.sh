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

# Where the file templates live. The SHAPE of every artefact the procedures write is a
# fixed structure, so it is code (A2); only what goes inside the sections is text.
verb_template() {
    _r=$(fraim_root) || return 1
    _t="$_r/installer/templates/$1"
    [ -f "$_t" ] || return 1
    printf '%s\n' "$_t"
}

# The provenance stamp: date, the snapshot the work is based on, and the system version.
# One implementation, used by task-new, task-revise and investigate-new alike — the three
# places where a forgotten or mistyped stamp silently disables a staleness check.
verb_provenance() {
    _root=$1
    _date=$(date +%Y-%m-%d)
    _ver=$(fraim_version)
    if verb_is_git "$_root"; then
        _ref=$(git -C "$_root" rev-parse --short HEAD 2>/dev/null)
        _based="HEAD $_ref"
    else
        _based="<no git — list the files this plan assumes the current state of>"
    fi
    printf -- '- Planned: %s\n- Based on: %s\n- System: fraim %s\n' "$_date" "$_based" "$_ver"
}

# A section of a markdown file must be present, non-empty and free of placeholders.
# Used by every gate: this is what turns "the executor promised" into a precondition.
verb_section_filled() {
    _file=$1; _head=$2
    grep -q "^$_head\$" "$_file" || return 1
    _sec=$(awk -v h="$_head" '$0 == h {f=1;next} /^#/{f=0} f' "$_file")
    [ -n "$(printf '%s' "$_sec" | tr -d '[:space:]')" ] || return 2
    printf '%s' "$_sec" | grep -q '<[^>]*>' && return 3
    return 0
}

# Move a finished folder into the archive under a timestamp, then commit it.
# One implementation for tasks, drifted sessions and investigations: the timestamp
# format is what /orient reads back as "recent history".
verb_archive() {
    _root=$1; _src=$2; _name=$3; _kind=$4; _text=$5
    _stamp=$(date +%Y-%m-%d_%H%M)
    _dest="$_root/ai/archive/${_stamp}_${_name}"
    [ -e "$_dest" ] && die "в архиве уже есть $_dest"
    mkdir -p "$_root/ai/archive" || die "не удалось создать ai/archive/"
    mv "$_src" "$_dest" || die "не удалось перенести в архив"
    ok "архивировано: ai/archive/${_stamp}_${_name}"
    verb_commit "$_root" "$_kind" "$_text" "ai/tasks" "ai/investigations" "ai/archive" ||
        warn "коммит не удался"
}

# What is still waiting in the queue after something left it.
verb_queue_left() {
    _root=$1
    _left=$(find "$_root/ai/tasks" -mindepth 1 -maxdepth 1 -type d 2>/dev/null |
            while read -r _d; do basename -- "$_d"; done | sort | tr '\n' ' ')
    if [ -n "$_left" ]; then say "  осталось в очереди: $_left"; else dim "  очередь пуста"; fi
}

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

    {
        printf '# Task Context\n\n'
        printf '## Plan provenance\n'
        verb_provenance "$_root"
        printf '\n'
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

    ok "ai/tasks/$_slug/ — provenance: $(verb_provenance "$_root" | tr '\n' ' ')"
    dim "  заполни разделы по /make-task, потом задачу исполняет /run-task"
}

# --- task-seal (the gate) ---------------------------------------------------
# The three preconditions below are shared with reconcile-seal: a task leaves the
# queue through one of two doors, and both doors are ours.
verb_task_gate() {
    _dir=$1
    # Gate 1 — the task must actually have been executed.
    [ -f "$_dir/result.md" ] ||
        die "нет result.md — задача не исполнена. Архивировать нечего."

    # Gate 2 — a blocked task goes back to the planner, not into the archive.
    [ -f "$_dir/blockers.md" ] &&
        die "есть blockers.md — задача заблокирована. Сначала /revise-task, потом /run-task."

    grep -q "$SCAFFOLD_STUB" "$_dir/result.md" 2>/dev/null &&
        die "result.md — незаполненная заготовка (маркер $SCAFFOLD_STUB на месте)"

    # Gate 3 — the foundation must be accounted for. This is invariant 0.4 turning from
    # a request into a precondition: the executor may legitimately have changed nothing,
    # but it has to SAY so, and the statement lands in the archive as a record.
    _rc=0; verb_section_filled "$_dir/result.md" '## Foundation updated' || _rc=$?
    case $_rc in
        1) die "в result.md нет раздела '## Foundation updated' — инвариант 0.4 не отчитан" ;;
        2) die "раздел '## Foundation updated' пуст — напиши, что стало с ARCHITECTURE.md и DECISIONS.md" ;;
        3) die "в '## Foundation updated' остались незаполненные плейсхолдеры — допиши их" ;;
    esac
}

verb_task_seal() {
    _root=$1; _slug=$2
    _dir="$_root/ai/tasks/$_slug"
    [ -d "$_dir" ] || die "нет такой задачи: ai/tasks/$_slug"
    verb_task_gate "$_dir"
    verb_archive "$_root" "$_dir" "$_slug" archive "$_slug"
    verb_queue_left "$_root"
}

# --- reconcile-seal (the second door) ---------------------------------------
# /reconcile-task used to archive a drifted session in PROSE — four mechanical steps
# and its own commit format, past this gate entirely. That made the claim "the only
# door out of a task is ours" false exactly where it mattered most: a session that
# turned into live debugging, where the record is the only thing keeping the archive
# honest. Same preconditions as task-seal, plus the one this workflow exists for.
verb_reconcile_seal() {
    _root=$1; _slug=$2
    _dir="$_root/ai/tasks/$_slug"
    [ -d "$_dir" ] || die "нет такой задачи: ai/tasks/$_slug"
    verb_task_gate "$_dir"

    _rc=0; verb_section_filled "$_dir/result.md" '## Divergence from plan' || _rc=$?
    case $_rc in
        1) die "в result.md нет раздела '## Divergence from plan' — заведи его: fraim task-result $_slug --reconcile" ;;
        2) die "раздел '## Divergence from plan' пуст — расхождения с планом и есть предмет этой процедуры" ;;
        3) die "в '## Divergence from plan' остались незаполненные плейсхолдеры — допиши их" ;;
    esac

    verb_archive "$_root" "$_dir" "$_slug" reconcile "$_slug — sealed drifted session"
    verb_queue_left "$_root"
}

# --- task-result / task-block -----------------------------------------------
# Both files have a fixed shape and are read back machine-side: the seal gate parses
# result.md, the watchman looks for blockers.md. A model retyping the headings from
# prose is how a gate starts refusing honest work — or passing dishonest work.
# Never overwrites: on a second pass the executor edits the report it already wrote.
verb_task_file() {
    _root=$1; _slug=$2; _tpl=$3; _name=$4
    _dir="$_root/ai/tasks/$_slug"
    [ -d "$_dir" ] || die "нет такой задачи: ai/tasks/$_slug"
    _src=$(verb_template "$_tpl") || die "не найден шаблон $_tpl — установка повреждена"
    if [ -f "$_dir/$_name" ]; then
        dim "  ai/tasks/$_slug/$_name уже есть — правь его, не перезаписываю"
        return 0
    fi
    cp "$_src" "$_dir/$_name" || die "не удалось записать $_name"
    ok "ai/tasks/$_slug/$_name — заполни разделы и удали строку $SCAFFOLD_STUB"
}

verb_task_result() {
    _root=$1; _slug=$2; _mode=${3:-}
    _dir="$_root/ai/tasks/$_slug"
    [ -d "$_dir" ] || die "нет такой задачи: ai/tasks/$_slug"
    case $_mode in
        --reset)
            [ -f "$_dir/result.md" ] || die "нет result.md — сбрасывать нечего"
            rm -f "$_dir/result.md" || die "не удалось удалить result.md"
            ok "result.md удалён — план оказался дефектным, дальше blockers.md и /revise-task"
            return 0
            ;;
        --reconcile|"") ;;
        *) die "неизвестный режим: $_mode (--reconcile | --reset)" ;;
    esac

    verb_task_file "$_root" "$_slug" task/result.md result.md
    [ "$_mode" = --reconcile ] || return 0

    if grep -q '^## Divergence from plan$' "$_dir/result.md"; then
        dim "  раздел '## Divergence from plan' уже есть"
        return 0
    fi
    _add=$(verb_template task/divergence.md) || die "не найден шаблон task/divergence.md"
    cat "$_add" >> "$_dir/result.md" || die "не удалось дописать раздел"
    ok "в result.md заведён раздел '## Divergence from plan'"
}

verb_task_block() {
    verb_task_file "$1" "$2" task/blockers.md blockers.md
}

# --- task-revise (the planner's gate) ---------------------------------------
# The repaired plan needs a FRESH provenance stamp, or the watchman keeps reporting it
# stale against the very commit that repaired it. That stamp is the same thing task-new
# took away from the model because it is the thing that gets forgotten — and after a
# repair it was handed straight back. Order matters here: the blocker is consumed last,
# so an interrupted revision leaves the task blocked rather than silently runnable.
verb_task_revise() {
    _root=$1; _slug=$2; _defect=$3; _fix=$4
    _dir="$_root/ai/tasks/$_slug"
    [ -d "$_dir" ] || die "нет такой задачи: ai/tasks/$_slug"
    [ -f "$_dir/blockers.md" ] ||
        die "нет blockers.md — чинить нечего. Новая задача — /make-task, исполнение — /run-task."
    [ -f "$_dir/task.md" ] || die "нет task.md — задача повреждена"
    [ -f "$_dir/context.md" ] || die "нет context.md — задача повреждена"

    _n=$(grep -c '^## Revision ' "$_dir/task.md" 2>/dev/null || true)
    [ -n "$_n" ] || _n=0
    _n=$((_n + 1))
    _date=$(date +%Y-%m-%d)

    _tmp="$_dir/.task.md.$$"
    {
        head -1 "$_dir/task.md"
        printf '\n## Revision %s — %s\n' "$_n" "$_date"
        printf -- '- Defect: %s\n' "$_defect"
        printf -- '- Fix: %s\n' "$_fix"
        tail -n +2 "$_dir/task.md"
    } > "$_tmp" || die "не удалось записать task.md"
    mv "$_tmp" "$_dir/task.md" || die "не удалось записать task.md"

    _tmp="$_dir/.context.md.$$"
    awk -v prov="$(verb_provenance "$_root")" '
        /^## Plan provenance/ { print; print prov; skip = 1; next }
        skip && /^[-[:space:]]*(Planned|Based on|System):/ { next }
        skip && /^##/ { skip = 0 }
        { print }
    ' "$_dir/context.md" > "$_tmp" || die "не удалось записать context.md"
    mv "$_tmp" "$_dir/context.md" || die "не удалось записать context.md"

    rm -f "$_dir/blockers.md" || die "не удалось удалить blockers.md"

    ok "ревизия $_n: провенанс обновлён, blockers.md снят"
    verb_commit "$_root" revise "$_slug — $_defect" "ai/tasks" || warn "коммит не удался"
    dim "  план починен — задачу снова исполняет /run-task"
}

# --- investigate-new / investigate-seal -------------------------------------
# An investigation has exactly the same mechanics as a task — a folder, a provenance
# stamp, an archive with a timestamp — and until now it had none of them: /investigate
# created the folder, typed the schema and archived with its own commit message by hand.
# Its exit also has a real precondition, and it is the one the system can least afford
# to leave to good intentions: the cleanup of everything the scout touched.
verb_investigate_new() {
    _root=$1; _slug=$2
    printf '%s' "$_slug" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' ||
        die "слаг должен быть kebab-case: буквы, цифры и дефисы"
    [ -d "$_root/ai/investigations" ] ||
        die "нет ai/investigations/ — проект не под системой; сначала fraim scaffold"
    _dir="$_root/ai/investigations/$_slug"
    [ -e "$_dir" ] && die "расследование уже существует: ai/investigations/$_slug"
    _tpl=$(verb_template investigation/findings.md) || die "не найден шаблон — установка повреждена"

    mkdir -p "$_dir" || die "не удалось создать $_dir"
    _prov=$(verb_provenance "$_root")
    awk -v slug="$_slug" -v prov="$_prov" '
        { gsub(/\{\{SLUG\}\}/, slug); if ($0 == "{{PROVENANCE}}") { print prov; next } print }
    ' "$_tpl" > "$_dir/findings.md" || die "не удалось записать findings.md"

    ok "ai/investigations/$_slug/findings.md"
    dim "  манифесты пиши живьём, а не в конце: они и есть список уборки"
}

verb_investigate_seal() {
    _root=$1; _slug=$2
    _dir="$_root/ai/investigations/$_slug"
    [ -d "$_dir" ] || die "нет такого расследования: ai/investigations/$_slug"
    _f="$_dir/findings.md"
    [ -f "$_f" ] || die "нет findings.md — архивировать нечего"
    grep -q "$SCAFFOLD_STUB" "$_f" &&
        die "findings.md — незаполненная заготовка (маркер $SCAFFOLD_STUB на месте)"

    # Exactly one outcome branch. None means the investigation was abandoned; both
    # means it was never landed — and a dead-end recorded honestly is a success here.
    _filled=0; _which=
    for _b in '### DIAGNOSIS' '### DEAD-END'; do
        if verb_section_filled "$_f" "$_b"; then
            _filled=$((_filled + 1)); _which=$_b
        fi
    done
    [ "$_filled" -eq 0 ] &&
        die "ни одна ветка исхода не заполнена — расследование без исхода не архивируется (DIAGNOSIS или DEAD-END)"
    [ "$_filled" -gt 1 ] &&
        die "заполнены обе ветки исхода — оставь ровно одну"

    _rc=0; verb_section_filled "$_f" '## Restored to baseline' || _rc=$?
    case $_rc in
        1) die "в findings.md нет раздела '## Restored to baseline' — уборка не отчитана" ;;
        2) die "раздел '## Restored to baseline' пуст — напиши, что стало с репозиторием и с миром" ;;
        3) die "в '## Restored to baseline' остались плейсхолдеры — допиши их" ;;
    esac

    ok "исход: $(printf '%s' "$_which" | sed 's/^### //')"
    verb_archive "$_root" "$_dir" "investigate_$_slug" archive "investigate $_slug"
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

# --- stack-passport ---------------------------------------------------------
# STACK.md has a fixed schema and a standing directive that must survive verbatim —
# an LLM retyping it from prose drops a section every few projects. The shape is
# the template's; only the facts are the workflow's.
verb_stack_passport() {
    _root=$1
    _dst="$_root/STACK.md"
    [ -e "$_dst" ] && die "STACK.md уже есть — заполняй его, шаблон не перезаписываю"
    _r=$(fraim_root) || die "не найдены шаблоны — установка повреждена"
    _tpl="$_r/installer/templates/stack/STACK.md"
    [ -f "$_tpl" ] || die "не найден шаблон: $_tpl"
    sed "s/{{PROJECT}}/$(basename -- "$_root")/g" "$_tpl" > "$_dst" || die "не удалось записать STACK.md"
    ok "STACK.md создан из шаблона"
    dim "  заполни разделы и удали строку fraim:stub — пока она на месте, паспорт считается незаполненным"
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
