#!/bin/sh
# tasks.sh — the task board: a card per task, and nothing a card could go stale with.
#
# A task used to be a plan: a snapshot of the code it was written against (paths,
# patterns, a reference scan, a provenance stamp) handed to an executor who trusted it
# blindly. A snapshot starts going stale the moment it is sealed, and half the system was
# machinery for noticing that — stale-plan, plan-version, blockers, revise, reconcile.
# The foundation and the code are the living context; a second, frozen copy of them in
# the queue always loses. So a task is now an INTENT: what and why, and how we will know
# it is done. Whoever takes it gathers the context from the tree as it is that day.
#
# A card is `ai/tasks/<slug>.md`. What the CLI reads and writes lives in the frontmatter;
# the body is for people and agents:
#
#   ---
#   kind: task | master
#   created: YYYY-MM-DD
#   parent: <slug of a master>      (optional, children only)
#   ---
#   # Title
#   ## Что и зачем
#   ## Готово, когда
#   ## Ссылки                       (optional)
#
# The state is WHERE the file is, never a field: `ai/tasks/` is open, `ai/archive/tasks/`
# is closed. A status field is a second answer to the same question, and the two would
# disagree the first time someone moved a file by hand.
#
# A master task is a project: children point at it with `parent`. Its «in progress» is
# computed (open, and at least one child closed), and only the human closes it — new
# branches can arrive after every current child is done. One level only: a master has
# no parent.

TASK_WHAT='## Что и зачем'
TASK_DONE='## Готово, когда'

tasks_dir()    { printf '%s/ai/tasks\n' "$1"; }
tasks_closed() { printf '%s/ai/archive/tasks\n' "$1"; }

# A card is a .md file in ai/tasks/ whose frontmatter carries `kind`. Anything else there
# (a .gitkeep, a README, an old-format folder) is not a card and is not counted as one.
tasks_is_card() { [ -f "$1" ] && [ -n "$(fm_get "$1" kind 2>/dev/null)" ]; }

# The title: the first `# ` line after the frontmatter.
tasks_title() {
    awk '
        NR == 1 && $0 == "---" { fm = 1; next }
        fm && $0 == "---" { fm = 0; next }
        fm { next }
        /^# / { sub(/^# +/, ""); print; exit }
    ' "$1"
}

# Days since an ISO date. GNU date first, BSD second; an unreadable date reads as 0
# rather than failing the listing over one hand-edited card.
tasks_days_since() {
    _s=$(date -d "$1" +%s 2>/dev/null) ||
        _s=$(date -j -f %Y-%m-%d "$1" +%s 2>/dev/null) || { printf '0\n'; return; }
    printf '%s\n' "$(( ( $(date +%s) - _s ) / 86400 ))"
}

# Every open card, one line each: slug kind parent created title, joined by TASK_SEP.
# Not a tab: tab is IFS whitespace, and `read` collapses a run of it — an empty `parent`
# would silently shift every field after it one place to the left.
TASK_SEP=$(printf '\037')
tasks_scan() {
    _ts_root=$1
    for _ts_f in "$(tasks_dir "$_ts_root")"/*.md; do
        tasks_is_card "$_ts_f" || continue
        _ts_slug=$(basename -- "$_ts_f" .md)
        printf "%s$TASK_SEP%s$TASK_SEP%s$TASK_SEP%s$TASK_SEP%s\n" "$_ts_slug" \
            "$(fm_get "$_ts_f" kind)" "$(fm_get "$_ts_f" parent)" \
            "$(fm_get "$_ts_f" created)" "$(tasks_title "$_ts_f")"
    done
}

# Children of a master: open ones from the board, closed ones from the archive.
tasks_open_children() {
    tasks_scan "$1" | awk -F"$TASK_SEP" -v p="$2" '$3 == p { print $1 }'
}
tasks_closed_children_n() {
    _tc_n=0
    for _tc_f in "$(tasks_closed "$1")"/*.md; do
        [ -f "$_tc_f" ] || continue
        [ "$(fm_get "$_tc_f" parent)" = "$2" ] && _tc_n=$((_tc_n + 1))
    done
    printf '%s\n' "$_tc_n"
}

# Old-format tasks: a FOLDER per task, holding a plan. `fraim upgrade` turns them into cards.
tasks_legacy() {
    for _tl_d in "$(tasks_dir "$1")"/*/; do
        [ -d "$_tl_d" ] || continue
        [ -f "$_tl_d/task.md" ] || [ -f "$_tl_d/context.md" ] || continue
        basename -- "$_tl_d"
    done
}

tasks_slug_ok() {
    printf '%s' "$1" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' ||
        die "слаг должен быть kebab-case: буквы, цифры и дефисы"
}

# --- task-new ---------------------------------------------------------------
# The card arrives whole, on stdin, and leaves committed: the agent writes the words,
# the verb owns the frontmatter, the place and the save point. A card that is laid down
# empty and filled later is a card that sits half-written in the board when a session dies.
verb_task_new() {
    _root=$1; shift
    _slug=; _kind=task; _parent=
    while [ $# -gt 0 ]; do
        case $1 in
            --master) _kind=master ;;
            --parent) [ $# -ge 2 ] || die "--parent требует слаг мастер-задачи"; _parent=$2; shift ;;
            -*) die "неизвестный флаг: $1" ;;
            *) [ -z "$_slug" ] || die "лишний аргумент: $1"; _slug=$1 ;;
        esac
        shift
    done
    [ -n "$_slug" ] || die "нужен слаг задачи"
    tasks_slug_ok "$_slug"
    _dir=$(tasks_dir "$_root")
    [ -d "$_dir" ] || die "нет ai/tasks/ — проект не под системой; сначала fraim scaffold"
    [ -e "$_dir/$_slug.md" ] && die "задача уже существует: ai/tasks/$_slug.md"
    [ -e "$_dir/$_slug" ] && die "ai/tasks/$_slug/ — задача старого формата с тем же слагом; сначала fraim upgrade"

    if [ -n "$_parent" ]; then
        [ "$_kind" = master ] && die "у мастер-задачи нет родителя: вложенность — один уровень"
        _pf="$_dir/$_parent.md"
        tasks_is_card "$_pf" || die "нет открытой задачи «$_parent» — родителем может быть только открытая мастер-задача"
        [ "$(fm_get "$_pf" kind)" = master ] ||
            die "«$_parent» — обычная задача, не мастер-задача. Сделать её проектом может только человек: fraim task-master $_parent"
    fi

    _body=$(verb_read_body) ||
        die "карточка приходит потоком:  fraim task-new $_slug <<'EOF'  # Заголовок … EOF"
    printf '%s\n' "$_body" | head -1 | grep -qx -- '---' &&
        die "frontmatter пишет глагол, не ты — пришли карточку начиная с «# Заголовок»"
    printf '%s\n' "$_body" | grep -q '^# [^[:space:]]' ||
        die "у карточки нет заголовка — первая строка «# Что сделать»"

    _tmp="$_dir/.$_slug.md.$$"
    printf '%s\n' "$_body" > "$_tmp" || die "не удалось записать карточку"
    for _sec in "$TASK_WHAT" "$TASK_DONE"; do
        _rc=0; verb_section_filled "$_tmp" "$_sec" || _rc=$?
        case $_rc in
            1) rm -f "$_tmp"; die "в карточке нет раздела «$_sec»" ;;
            2) rm -f "$_tmp"; die "раздел «$_sec» пуст" ;;
            3) rm -f "$_tmp"; die "в разделе «$_sec» остался плейсхолдер <…>" ;;
        esac
    done

    {
        printf -- '---\nkind: %s\ncreated: %s\n' "$_kind" "$(date +%Y-%m-%d)"
        if [ -n "$_parent" ]; then printf 'parent: %s\n' "$_parent"; fi
        printf -- '---\n'
        cat "$_tmp"
    } > "$_dir/$_slug.md" || { rm -f "$_tmp"; die "не удалось записать карточку"; }
    rm -f "$_tmp"

    _what=задача; [ "$_kind" = master ] && _what=мастер-задача
    ok "ai/tasks/$_slug.md — $_what поставлена${_parent:+ (в проекте «$_parent»)}"
    verb_commit "$_root" task "$_slug — поставлена" "ai/tasks/$_slug.md" || warn "коммит не удался"
}

# --- task-master ------------------------------------------------------------
# An ordinary task becomes a project only on the human's word. The verb exists so the
# agent has nothing to edit by hand, not so it can decide this on its own.
verb_task_master() {
    _root=$1; _slug=$2
    [ -n "$_slug" ] || die "нужен слаг задачи"
    _f="$(tasks_dir "$_root")/$_slug.md"
    tasks_is_card "$_f" || die "нет открытой задачи: ai/tasks/$_slug.md"
    [ "$(fm_get "$_f" kind)" = master ] && { dim "  «$_slug» уже мастер-задача"; return 0; }
    [ -n "$(fm_get "$_f" parent)" ] &&
        die "«$_slug» — подзадача проекта «$(fm_get "$_f" parent)»; вложенность — один уровень"
    _tmp="$_f.fraim.tmp"
    awk 'NR == 1 { print; fm = 1; next }
         fm && /^kind:/ { print "kind: master"; next }
         fm && $0 == "---" { fm = 0 }
         { print }' "$_f" > "$_tmp" && mv "$_tmp" "$_f" || die "не удалось записать карточку"
    ok "«$_slug» теперь мастер-задача — подзадачи: fraim task-new СЛАГ --parent $_slug"
    verb_commit "$_root" task "$_slug — стала мастер-задачей" "ai/tasks/$_slug.md" || warn "коммит не удался"
}

# --- task-seal --------------------------------------------------------------
# Closing a task is moving its card to the archive with one line of outcome. The verb
# appends `closed`, `outcome` and `result` to the frontmatter so the archive answers
# «when, how, and what came of it» without anyone reading the body.
verb_task_seal() {
    _root=$1; shift
    _slug=; _outcome=done; _result=
    while [ $# -gt 0 ]; do
        case $1 in
            --dropped) _outcome=dropped ;;
            -*) die "неизвестный флаг: $1" ;;
            *) if [ -z "$_slug" ]; then _slug=$1
               elif [ -z "$_result" ]; then _result=$1
               else die "лишний аргумент: $1"; fi ;;
        esac
        shift
    done
    [ -n "$_slug" ] || die "нужен слаг задачи"
    _f="$(tasks_dir "$_root")/$_slug.md"
    if ! tasks_is_card "$_f"; then
        [ -d "$(tasks_dir "$_root")/$_slug" ] &&
            die "ai/tasks/$_slug/ — задача старого формата; сначала fraim upgrade"
        die "нет открытой задачи: ai/tasks/$_slug.md"
    fi
    [ -n "$(printf '%s' "$_result" | tr -d '[:space:]')" ] ||
        die "нужна строка итога: fraim task-seal $_slug \"что сделано\"  (или --dropped \"почему отменена\")"

    _kind=$(fm_get "$_f" kind)
    if [ "$_kind" = master ]; then
        _open=$(tasks_open_children "$_root" "$_slug" | tr '\n' ' ')
        [ -z "$_open" ] ||
            die "у мастер-задачи «$_slug» открыты подзадачи: $_open— сначала закрой или отмени их"
    fi

    _dest_dir=$(tasks_closed "$_root")
    mkdir -p "$_dest_dir" || die "не удалось создать ai/archive/tasks/"
    _dest="$_dest_dir/$(date +%Y-%m-%d)_$_slug.md"
    [ -e "$_dest" ] && die "в архиве уже есть $_dest"

    _head=
    verb_is_git "$_root" && _head=$(git -C "$_root" rev-parse --short HEAD 2>/dev/null)
    _q=$(printf '%s' "$_result" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')
    awk -v closed="$(date +%Y-%m-%d)" -v outcome="$_outcome" -v result="$_q" -v head="$_head" '
        NR == 1 { print; fm = 1; next }
        fm && $0 == "---" {
            print "closed: " closed
            print "outcome: " outcome
            print "result: \"" result "\""
            if (head != "") print "commit: " head
            fm = 0
        }
        { print }
    ' "$_f" > "$_dest" || { rm -f "$_dest"; die "не удалось записать архив"; }
    rm -f "$_f" || die "не удалось убрать карточку с доски"

    _word=выполнена; [ "$_outcome" = dropped ] && _word=отменена
    ok "«$_slug» $_word → ai/archive/tasks/$(basename -- "$_dest")"
    verb_commit "$_root" archive "$_slug — $_word" "ai/tasks" "ai/archive/tasks" || warn "коммит не удался"

    _parent=$(fm_get "$_dest" parent)
    if [ -n "$_parent" ]; then
        _o=$(tasks_open_children "$_root" "$_parent" | grep -c . || true)
        _c=$(tasks_closed_children_n "$_root" "$_parent")
        say "  проект «$_parent»: закрыто $_c из $((_o + _c))"
        [ "$_o" -eq 0 ] && dim "  открытых подзадач нет — закрыть сам проект решает человек"
    fi
    return 0
}

# --- tasks (the board) ------------------------------------------------------
tasks_age_words() {
    _d=$(tasks_days_since "$1")
    if [ "$_d" -eq 0 ]; then printf 'сегодня\n'; else printf '%s дн.\n' "$_d"; fi
}

tasks_master_words() {
    _o=$(tasks_open_children "$1" "$2" | grep -c . || true)
    _c=$(tasks_closed_children_n "$1" "$2")
    _all=$((_o + _c))
    if [ "$_all" -eq 0 ]; then printf 'подзадач нет\n'
    elif [ "$_c" -eq 0 ]; then printf 'не начата, 0 из %s\n' "$_all"
    else printf 'в работе, %s из %s\n' "$_c" "$_all"; fi
}

verb_tasks() {
    _root=$1; _json=${2:-}
    _scan=$(tasks_scan "$_root")
    _legacy=$(tasks_legacy "$_root" | tr '\n' ' ')

    if [ "$_json" = --json ]; then
        printf '{\n  "tasks": ['
        [ -n "$_scan" ] && printf '%s\n' "$_scan" | {
            _first=1
            while IFS="$TASK_SEP" read -r _s _k _p _cr _t; do
                [ -n "$_s" ] || continue
                if [ "$_first" = 1 ]; then printf '\n'; else printf ',\n'; fi
                _first=0
                printf '    { "slug": "%s", "kind": "%s", "parent": "%s", "title": "%s", "created": "%s", "age_days": %s' \
                    "$_s" "$_k" "$_p" "$(wm_json_escape "$_t")" "$_cr" "$(tasks_days_since "$_cr")"
                if [ "$_k" = master ]; then
                    printf ', "open_children": %s, "closed_children": %s' \
                        "$(tasks_open_children "$_root" "$_s" | grep -c . || true)" \
                        "$(tasks_closed_children_n "$_root" "$_s")"
                fi
                printf ' }'
            done
            printf '\n  '
        }
        printf '],\n  "legacy": ['
        _first=1
        for _s in $_legacy; do
            [ "$_first" = 1 ] || printf ', '
            _first=0
            printf '"%s"' "$_s"
        done
        printf ']\n}\n'
        return 0
    fi

    _n=$(printf '%s' "$_scan" | grep -c . || true)
    if [ "$_n" -eq 0 ]; then
        ok "открытых задач нет"
    else
        say "${C_BLD}Задачи · открыто $_n${C_OFF}"
        # Masters first, each with its children under it; then ordinary tasks; then
        # children whose parent is not an open master — shown, never hidden.
        _masters=$(printf '%s\n' "$_scan" | awk -F"$TASK_SEP" '$2 == "master" { print $1 }' | tr '\n' ' ')
        printf '%s\n' "$_scan" | awk -F"$TASK_SEP" '$2 == "master"' |
            while IFS="$TASK_SEP" read -r _s _k _p _cr _t; do
                printf '  ◆ %s — %s %s· %s · %s%s\n' "$_s" "$_t" "$C_DIM" \
                    "$(tasks_master_words "$_root" "$_s")" "$(tasks_age_words "$_cr")" "$C_OFF"
                printf '%s\n' "$_scan" | awk -F"$TASK_SEP" -v p="$_s" '$3 == p' |
                    while IFS="$TASK_SEP" read -r _cs _ck _cp _ccr _ct; do
                        printf '      · %s — %s %s· %s%s\n' "$_cs" "$_ct" "$C_DIM" "$(tasks_age_words "$_ccr")" "$C_OFF"
                    done
            done
        printf '%s\n' "$_scan" | awk -F"$TASK_SEP" -v m=" $_masters" '$2 != "master" && index(m, " " $3 " ") == 0' |
            while IFS="$TASK_SEP" read -r _s _k _p _cr _t; do
                _note=
                [ -n "$_p" ] && _note=" (родитель «$_p» не открыт)"
                printf '  · %s — %s %s· %s%s%s\n' "$_s" "$_t" "$C_DIM" "$(tasks_age_words "$_cr")" "$_note" "$C_OFF"
            done
    fi
    [ -n "$_legacy" ] && warn "задачи старого формата (папки): $_legacy— перевести в карточки: fraim upgrade"
    return 0
}

# --- migration from the old format ------------------------------------------
# A folder task carried a plan, and its sections were guaranteed by plan-seal — so the
# intent can be lifted out of it mechanically: Summary → title, Goal + Why → «Что и
# зачем», Acceptance Criteria → «Готово, когда». The plan itself is kept, whole, in the
# archive, and the card links to it. A folder with a result.md was executed and never
# sealed: it is archived as it is. What cannot be read mechanically is still turned into
# a card — with the gap said in words — and named in TASKS_UNPARSED for the caller.
TASKS_MIGRATED=0
TASKS_UNPARSED=

tasks_section() {
    [ -f "$1" ] || return 0
    awk -v h="$2" '$0 == h { f = 1; next } /^#/ { f = 0 } f' "$1" |
        sed '/^[[:space:]]*$/{N;/^\n$/D;}' | sed -e '/./,$!d'
}

tasks_migrate_legacy() {
    _root=$1
    TASKS_MIGRATED=0; TASKS_UNPARSED=
    _legacy=$(tasks_legacy "$_root")
    [ -n "$_legacy" ] || return 0
    _lp="$_root/ai/archive/legacy-plans"
    mkdir -p "$_lp" || return 1
    for _s in $_legacy; do
        _d="$(tasks_dir "$_root")/$_s"
        if [ -f "$_d/result.md" ] && [ ! -f "$_d/blockers.md" ]; then
            _dest="$_root/ai/archive/$(date +%Y-%m-%d_%H%M)_$_s"
            [ -e "$_dest" ] && _dest="$_dest-legacy"
            mv "$_d" "$_dest" || return 1
            ok "ai/tasks/$_s/ исполнена и не запечатана → ai/archive/$(basename -- "$_dest")"
            TASKS_MIGRATED=$((TASKS_MIGRATED + 1))
            continue
        fi
        _title=$(tasks_section "$_d/task.md" '## Summary' | sed -n '/[^[:space:]]/{p;q;}')
        _goal=$(tasks_section "$_d/context.md" '## Goal')
        _why=$(tasks_section "$_d/context.md" '## Why')
        _acc=$(tasks_section "$_d/task.md" '## Acceptance Criteria')
        _gap=
        [ -n "$_title" ] || { _title=$_s; _gap=1; }
        [ -n "$(printf '%s%s' "$_goal" "$_why" | tr -d '[:space:]')" ] || _gap=1
        [ -n "$(printf '%s' "$_acc" | tr -d '[:space:]')" ] || _gap=1
        _card="$(tasks_dir "$_root")/$_s.md"
        _created=$(sed -n 's/^- Planned: *\([0-9-]*\).*/\1/p' "$_d/context.md" 2>/dev/null | head -1)
        [ -n "$_created" ] || _created=$(date +%Y-%m-%d)
        {
            printf -- '---\nkind: task\ncreated: %s\n---\n' "$_created"
            printf '# %s\n\n%s\n' "$_title" "$TASK_WHAT"
            if [ -n "$(printf '%s%s' "$_goal" "$_why" | tr -d '[:space:]')" ]; then
                if [ -n "$_goal" ]; then printf '%s\n' "$_goal"; fi
                if [ -n "$_why" ]; then printf '\n%s\n' "$_why"; fi
            else
                printf 'Не разобрано механически — см. старый план.\n'
            fi
            printf '\n%s\n' "$TASK_DONE"
            if [ -n "$(printf '%s' "$_acc" | tr -d '[:space:]')" ]; then printf '%s\n' "$_acc"
            else printf 'Не разобрано механически — см. старый план.\n'; fi
            printf '\n## Ссылки\n- Старый план: `ai/archive/legacy-plans/%s/`\n' "$_s"
            if [ -f "$_d/blockers.md" ]; then
                printf -- '- План был заблокирован исполнителем: `blockers.md` там же.\n'
            fi
        } > "$_card" || return 1
        mv "$_d" "$_lp/$_s" || return 1
        ok "ai/tasks/$_s/ → карточка ai/tasks/$_s.md (план в ai/archive/legacy-plans/$_s/)"
        TASKS_MIGRATED=$((TASKS_MIGRATED + 1))
        if [ -n "$_gap" ]; then TASKS_UNPARSED="$TASKS_UNPARSED $_s"; fi
    done
    return 0
}

# What the mechanics could not read goes on the board as a task, not into a warning that
# scrolls away: the next session sees it in `fraim tasks` and takes it like any other.
tasks_migration_card() {
    _root=$1; _list=$2
    _card="$_root/ai/tasks/fraim-migration.md"
    if [ -f "$_card" ]; then
        printf -- '- задачи без нужных разделов:%s\n' "$_list" >> "$_card"
    else
        {
            printf -- '---\nkind: task\ncreated: %s\n---\n' "$(date +%Y-%m-%d)"
            printf '# Довести перевод на формат fraim %s\n\n' "$(fraim_version)"
            printf '## Что и зачем\n'
            printf '`fraim upgrade` сделал механическую часть, но этого он прочитать не смог:\n'
            printf -- '- задачи без нужных разделов:%s\n' "$_list"
            printf '\nКак это доделать — раздел «Миграция формата» в /prune.\n\n'
            printf '## Готово, когда\nУ каждой названной карточки осмысленные «Что и зачем» и «Готово, когда».\n'
        } > "$_card"
    fi
    warn "не всё разобралось механически — на доске задача fraim-migration"
}

# The whole task half of `fraim upgrade` (and of the cleanup's upgrade step): migrate,
# put what did not parse on the board, save it as one point.
tasks_upgrade() {
    _root=$1
    tasks_migrate_legacy "$_root" || return 1
    [ "$TASKS_MIGRATED" -gt 0 ] || return 0
    if [ -n "$TASKS_UNPARSED" ]; then tasks_migration_card "$_root" "$TASKS_UNPARSED"; fi
    verb_commit "$_root" upgrade "задачи старого формата переведены в карточки" ai/tasks ai/archive ||
        warn "коммит не удался"
}
