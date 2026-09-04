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
    # The trailer is what lets `fraim undo` tell our save points from everyone else's,
    # mechanically, in a repository we may not own. It stays out of the subject line,
    # so `git log --oneline` reads exactly as before.
    git -C "$_root" commit -q -m "$_kind: $_text" -m "fraim: $(fraim_version)" || return 1
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
# The prune anchor is the commit, not a line in a log file. It always was for
# `wm_check_foundation`, which finds the last `prune: ` commit; the marker written into
# ai/hotfix_log.md existed only for the hotfix counter, and went with it.
verb_prune_mark() {
    _root=$1
    _date=$(date +%Y-%m-%d)
    verb_is_git "$_root" || die "нет репозитория — прунинг нечем отметить"

    _before=$(git -C "$_root" rev-parse HEAD 2>/dev/null)
    verb_commit "$_root" prune "reconcile foundation $_date" \
        ARCHITECTURE.md CONVENTIONS.md DECISIONS.md ai/archive ||
        warn "коммит не удался"
    _after=$(git -C "$_root" rev-parse HEAD 2>/dev/null)

    # A prune that honestly found nothing to change still has to leave the anchor, or the
    # verdict keeps asking for the gardening that just happened. Nothing was committed
    # exactly when HEAD did not move.
    if [ "$_before" = "$_after" ]; then
        git -C "$_root" commit -q --allow-empty \
            -m "prune: reconcile foundation $_date" -m "fraim: $(fraim_version)" ||
            { warn "не удалось отметить прунинг"; return 0; }
        ok "прунинг отмечен: изменений в фундаменте не потребовалось"
    fi
}

# --- undo -------------------------------------------------------------------
# The system tells people to work boldly because there is a save point behind them.
# That promise is empty if getting back to one requires `git reset --hard HEAD~1` — the
# person who most needs the way back is the least likely to know it exists.
#
# Undo is a REVERT, never a reset: it adds a commit that takes the change back out. History
# is not rewritten, so this is safe in a repository shared with other people and with a
# remote — and it is the same rule the system already applies to DECISIONS.md: supersede,
# never delete. Two steps on purpose (list, then name one): showing is not doing.
verb_undo_list() {
    _root=$1
    git -C "$_root" log -n 8 --grep='^fraim: ' --format='%h%x09%ad%x09%s' --date=short 2>/dev/null
}

verb_undo_show() {
    _root=$1
    _rows=$(verb_undo_list "$_root")
    [ -n "$_rows" ] && [ -n "$(printf '%s' "$_rows" | tr -d '[:space:]')" ] ||
        die "нет ни одной точки сохранения, поставленной системой — отменять нечего"
    say "${C_BLD}Последние точки сохранения${C_OFF}"
    printf '%s\n' "$_rows" | while IFS='	' read -r _h _d _s; do
        [ -n "$_h" ] || continue
        printf '  %s  %s  %s\n' "$_h" "$_d" "$_s"
    done
    say ""
    dim "  отменить одну: fraim undo <хеш>"
    dim "  отмена — это встречный коммит, а не переписанная история: её саму можно отменить"
}

verb_undo() {
    _root=$1; _ref=$2
    verb_is_git "$_root" || die "здесь нет git — отменять нечего"
    git -C "$_root" cat-file -e "$_ref^{commit}" 2>/dev/null || die "нет такого коммита: $_ref"

    # Ours or not. We do not undo what we did not do — in someone else's repository that
    # is the difference between a tool and an accident.
    git -C "$_root" log -1 --format=%B "$_ref" 2>/dev/null | grep -q '^fraim: ' ||
        die "этот коммит поставила не система — отменять его не буду. Свои: fraim undo"

    # Only the files this commit touched have to be settled. The rest of the tree is the
    # human's work in progress, and it is none of our business — the same rule as everywhere:
    # we look at what we changed, and nothing else.
    _files=$(git -C "$_root" show --pretty= --name-only "$_ref" 2>/dev/null)
    if [ -n "$_files" ]; then
        _busy=$(printf '%s\n' "$_files" | while IFS= read -r _f; do
                    [ -n "$_f" ] || continue
                    git -C "$_root" status --porcelain --untracked-files=no -- "$_f" 2>/dev/null
                done)
        [ -z "$_busy" ] ||
            die "файлы этой точки сохранения сейчас изменены и не сохранены — сохрани или откати их, иначе отмену не с чем свести"
    fi

    _subj=$(git -C "$_root" log -1 --format=%s "$_ref")
    if git -C "$_root" revert --no-edit "$_ref" >/dev/null 2>&1; then
        ok "отменено: $_subj"
        dim "  встречный коммит добавлен; сама отмена тоже отменяема"
    else
        git -C "$_root" revert --abort >/dev/null 2>&1 || true
        die "отменить не удалось: изменения пересеклись с более поздними. Ничего не тронуто."
    fi
}

# --- restore ----------------------------------------------------------------
# The working-tree half of the same need, and the one /investigate lives on: put back
# exactly the paths named, and nothing else. `git restore .` would take the user's own
# unfinished work with it — which is why the workflow used to demand a clean tree before
# it would start, handing a git chore to the person least able to do it.
verb_restore() {
    _root=$1
    shift
    [ $# -gt 0 ] || die "нужен список путей: fraim restore ПУТЬ... («всё» не бывает)"
    verb_is_git "$_root" || die "здесь нет git — восстанавливать не из чего"
    for _p in "$@"; do
        case $_p in
            /*|.|..|*..*|"") die "путь должен быть внутри проекта и не «.»: $_p" ;;
        esac
    done
    for _p in "$@"; do
        if git -C "$_root" ls-files --error-unmatch -- "$_p" >/dev/null 2>&1; then
            if git -C "$_root" restore --source=HEAD -- "$_p" >/dev/null 2>&1 ||
               git -C "$_root" checkout HEAD -- "$_p" >/dev/null 2>&1; then
                ok "восстановлен: $_p"
            else
                warn "не удалось восстановить: $_p"
            fi
        elif [ -e "$_root/$_p" ]; then
            rm -rf -- "$_root/$_p" && ok "удалён (его не было в базе): $_p" ||
                warn "не удалось удалить: $_p"
        else
            dim "  $_p — уже нет, пропускаю"
        fi
    done
}

# --- decide / pitfall: writing INTO the foundation ---------------------------
# Appending to the foundation was the largest block of mechanics still left to the
# model. `DECISIONS.md` alone is written by three procedures (run-task 7.2,
# reconcile-task 2, prune) and its shape is described a fourth time in the template:
# four descriptions of one format, executed by prose (A3 + B1). What is mechanical
# here is placement, heading and date — never the wording, which is why the body
# arrives on stdin instead of through argv. A multi-line entry squeezed through a
# command-line argument is how a verb starts damaging content (AUDIT-VERBS 4.4).
#
# Neither verb commits. The save point stays in `fraim commit`, called by the
# procedure with the rest of the paths it touched — one implementation of a commit,
# and no surprise second commit inside a step that only meant to append a line.

verb_read_body() {
    # Refuse rather than block: on a terminal there is no piped body, and a verb
    # that silently waits for EOF looks identical to a hung agent session.
    [ -t 0 ] && return 1
    cat
}

verb_decide() {
    _root=$1; _title=$2; _supersedes=${3:-}
    _file="$_root/DECISIONS.md"
    [ -f "$_file" ] || die "нет DECISIONS.md — сначала fraim scaffold, потом /bootstrap или /onboard"
    [ -n "$_title" ] || die "нужен заголовок решения"

    _body=$(verb_read_body) ||
        die "тело решения приходит потоком:  fraim decide \"ЗАГОЛОВОК\" <<'EOF' … EOF"
    [ -n "$(printf '%s' "$_body" | tr -d '[:space:]')" ] || die "тело решения пустое"

    _date=$(date +%Y-%m-%d)
    _entry="## $_date — $_title"
    _tmp="$_file.fraim.tmp"

    # Newest on top: the entry goes above the first existing one, and when there is
    # none yet, after the header block. The stub marker goes away with the first real
    # entry — a file with a decision in it is no longer an unfilled scaffold (D1).
    awk -v entry="$_entry" -v body="$_body" -v sup="$_supersedes" -v stub="$SCAFFOLD_STUB" '
        index($0, stub) { next }
        !done && /^## / {
            print entry
            if (sup != "") print "> Supersedes: " sup
            print ""
            print body
            print ""
            done = 1
        }
        { print }
        END {
            if (!done) {
                print ""
                print entry
                if (sup != "") print "> Supersedes: " sup
                print ""
                print body
            }
        }
    ' "$_file" > "$_tmp" || { rm -f "$_tmp"; die "не удалось записать DECISIONS.md"; }
    mv "$_tmp" "$_file" || die "не удалось записать DECISIONS.md"

    ok "DECISIONS.md ← $_entry"
    dim "  запись не сохранена: добавь DECISIONS.md в свой fraim commit"
}

verb_pitfall() {
    _root=$1; shift
    _file="$_root/CONVENTIONS.md"
    _head='## Known Pitfalls / Lessons'
    [ -f "$_file" ] || die "нет CONVENTIONS.md — сначала fraim scaffold, потом /bootstrap или /onboard"
    grep -q "^$_head\$" "$_file" || die "в CONVENTIONS.md нет раздела '$_head'"

    if [ $# -gt 0 ]; then
        _lines=$(for _l in "$@"; do printf '%s\n' "$_l"; done)
    else
        _lines=$(verb_read_body) ||
            die "строки приходят аргументами или потоком: fraim pitfall \"СТРОКА\" [\"СТРОКА\"…]"
    fi
    [ -n "$(printf '%s' "$_lines" | tr -d '[:space:]')" ] || die "нечего добавлять"

    _tmp="$_file.fraim.tmp"
    # Appended at the END of that one section, not at the end of the file: the
    # section is what /make-task reads before planning, and a line that lands under
    # the wrong heading is a lesson nobody will ever be shown again.
    awk -v head="$_head" -v lines="$_lines" '
        $0 == head { inside = 1; print; next }
        inside && /^## / {
            n = split(lines, a, "\n")
            for (i = 1; i <= n; i++) if (a[i] != "") print "- " a[i]
            inside = 0; done = 1
            print ""
            print
            next
        }
        inside && $0 == "- None yet." { next }
        { print }
        END {
            if (inside && !done) {
                n = split(lines, a, "\n")
                for (i = 1; i <= n; i++) if (a[i] != "") print "- " a[i]
            }
        }
    ' "$_file" > "$_tmp" || { rm -f "$_tmp"; die "не удалось записать CONVENTIONS.md"; }
    mv "$_tmp" "$_file" || die "не удалось записать CONVENTIONS.md"

    _n=$(printf '%s\n' "$_lines" | grep -c '[^[:space:]]')
    ok "CONVENTIONS.md ← $_n $(wm_plural "$_n" строка строки строк) в '$_head'"
    dim "  запись не сохранена: добавь CONVENTIONS.md в свой fraim commit"
}

# --- plan-seal (the fourth door) --------------------------------------------
# Three gates guarded the exits from EXECUTION; the exit from PLANNING was a plain
# commit, preceded by a twelve-point self-check the author ran on their own work.
# That is the same construction B3 already rejected for invariant 0.4 — and the stakes
# are higher here, because the plan is the one artefact the executor trusts blindly:
# it arrives in a clean chat with no planner and no conversation to check it against.
#
# Seven of the twelve points are grep and test -e. Those move here. The other five —
# is the criterion objectively verifiable, is the dependency list complete — are
# judgment, and judgment is never a verb (AUDIT-VERBS 4.4).

# A template placeholder is <...> with a space inside: that is how every placeholder
# in our templates is written, and it is what keeps `List<T>`, `<html>` and `Vec<u8>`
# in a real plan from reading as an unfilled blank.
verb_has_placeholder() { grep -q '<[^>]* [^>]*>' "$1"; }

verb_plan_required() {
    _file=$1; _label=$2; shift 2
    for _s in "$@"; do
        grep -q "^## $_s" "$_file" || die "$_label: нет раздела '## $_s'"
        _sec=$(awk -v h="$_s" 'index($0, "## " h) == 1 {f=1;next} /^## /{f=0} f' "$_file")
        [ -n "$(printf '%s' "$_sec" | tr -d '[:space:]')" ] ||
            die "$_label: раздел '## $_s' пуст"
    done
}

verb_plan_seal() {
    _root=$1; _slug=$2
    _dir="$_root/ai/tasks/$_slug"
    _ctx="$_dir/context.md"; _task="$_dir/task.md"
    [ -d "$_dir" ] || die "нет такой задачи: ai/tasks/$_slug"
    [ -s "$_ctx" ]  || die "нет ai/tasks/$_slug/context.md — план не написан"
    [ -s "$_task" ] || die "нет ai/tasks/$_slug/task.md — план не написан"
    [ -f "$_dir/result.md" ] &&
        die "задача уже исполнена — план запечатывают до запуска, не после"

    # 1. Stub and placeholders — the plan is a scaffold nobody filled in.
    for _f in "$_ctx" "$_task"; do
        grep -q "$SCAFFOLD_STUB" "$_f" &&
            die "$(basename -- "$_f"): маркер $SCAFFOLD_STUB на месте — заготовка не заполнена"
        verb_has_placeholder "$_f" &&
            die "$(basename -- "$_f"): остались плейсхолдеры <…> — допиши их"
    done

    # 2. The provenance stamp, written by task-new and never by hand. Without it the
    #    watchman cannot tell a plan that went stale in the queue from a fresh one.
    grep -q '^## Plan provenance' "$_ctx" || die "context.md: нет '## Plan provenance' — папку задачи заводит fraim task-new"
    grep -q '^- Planned: '        "$_ctx" || die "context.md: в provenance нет даты"
    grep -q '^- Based on: '       "$_ctx" || die "context.md: в provenance нет базиса"
    grep -q '^- System: fraim '   "$_ctx" || die "context.md: в provenance нет версии системы"

    # 3. Self-containment (G1). The executor never sees the planning conversation, so a
    #    phrase pointing back at it is a hole it will fall through.
    # Both spellings of each Russian phrase are listed on purpose: in the C locale
    # `grep -i` folds ASCII only, so «Как» would slip past a lower-case pattern.
    _bad=$(grep -nE 'as (we )?[Dd]iscussed|[Aa]s discussed|[Tt]he plan above|approach we chose|per the conversation|as agreed above|[Кк]ак мы обсуждали|[Кк]ак договорились|[Вв]ыше по чату|[Мм]ы решили выше|[Кк]ак решили выше|[Вв] прошлом сообщении' \
           "$_ctx" "$_task" | head -3)
    [ -n "$_bad" ] && die "план ссылается на разговор, которого исполнитель не видел (G1):
$_bad"

    # 4. Every section the executor is told to read must exist and say something.
    verb_plan_required "$_ctx" context.md Goal Why "Codebase Context" Constraints \
        "Decisions and Rationale" "Known Pitfalls" "Out of Scope"
    verb_plan_required "$_task" task.md Summary "Files to Change" \
        "Step-by-step Implementation" "Acceptance Criteria" "Verification Commands" \
        "Foundation updates" "Executor Rules"

    # 5. Verification can never be empty (N8) — either a command or an explicit
    #    Operator confirmed: line that hands the check to the human on purpose.
    _ver=$(awk '/^## Verification Commands/{f=1;next} /^## /{f=0} f' "$_task" |
           grep -v '^```' | grep '[^[:space:]]')
    [ -n "$_ver" ] || die "task.md: '## Verification Commands' пуст (см. N8)"
    printf '%s' "$_ver" | grep -q '^[[:space:]]*<' &&
        die "task.md: в '## Verification Commands' остался плейсхолдер"

    # 6. Addresses must resolve. A path that does not exist is the classic plan defect:
    #    the executor pays a full run to discover a typo the planner could not see.
    _missing=
    _paths=$(awk '/^## Codebase Context/{f=1;next} /^## /{f=0} f' "$_ctx" |
             grep -oE '`[^`]+`' | tr -d '`' | grep -E '/|\.[a-z]+$' | sort -u)
    for _p in $_paths; do
        case $_p in */) _p=${_p%/} ;; esac
        [ -e "$_root/$_p" ] || _missing="$_missing $_p"
    done
    [ -n "$_missing" ] &&
        die "context.md: путь из Codebase Context не существует:$_missing"

    # The same for files being changed — except the ones the plan says to create.
    _missing=$(awk '
        /^### `/ { p = $0; sub(/^### `/, "", p); sub(/`.*$/, "", p); next }
        /^- \*\*Action:\*\*/ {
            if (p != "" && $0 !~ /create/) print p
            p = ""
        }
    ' "$_task" | sort -u | while read -r _p; do
        [ -n "$_p" ] || continue
        [ -e "$_root/$_p" ] || printf ' %s' "$_p"
    done)
    [ -n "$_missing" ] &&
        die "task.md: файл для изменения не существует (или Action должен быть create):$_missing"

    ok "план $_slug проверен: провенанс, самодостаточность, разделы, проверка, пути"
    verb_commit "$_root" plan "$_slug — план готов к исполнению" "ai/tasks/$_slug"
    dim "  дальше: открой новый чат и запусти /run-task"
}
