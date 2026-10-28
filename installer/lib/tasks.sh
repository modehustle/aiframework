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
#   after: <sibling>, <sibling>     (optional, children only)
#   ---
#   # Title
#   ## What and why
#   ## Done when
#   ## Links                        (optional)
#
# The state is WHERE the file is, never a field: `ai/tasks/` is open, `ai/archive/tasks/`
# is closed. A status field is a second answer to the same question, and the two would
# disagree the first time someone moved a file by hand.
#
# A master task is a project: children point at it with `parent`. Its «in progress» is
# computed (open, and at least one child closed), and only the human closes it — new
# branches can arrive after every current child is done. One level only: a master has
# no parent.
#
# A project's breakdown lives in its children and nowhere else: a master is laid down
# together with them in one call (a `## Subtasks` section the verb turns into cards), so
# the breakdown the human approved has a place on the board the moment it exists. The
# queue inside a project is `after`: a child waits while any card it names is still open.
# There is no position number — of the children nobody waits on, any may be taken next,
# and the human picks.

TASK_WHAT='## What and why'
TASK_DONE='## Done when'
TASK_LINKS='## Links'

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

# `after:` as a space-separated list. Written `after: a, b`; read tolerantly.
tasks_after() {
    fm_get "$1" after 2>/dev/null | tr ',' ' ' | tr -s ' ' | sed 's/^ //; s/ $//'
}

# Every open card, one line each: slug kind parent created title after, joined by TASK_SEP.
# Not a tab: tab is IFS whitespace, and `read` collapses a run of it — an empty `parent`
# would silently shift every field after it one place to the left.
TASK_SEP=$(printf '\037')
tasks_scan() {
    _ts_root=$1
    for _ts_f in "$(tasks_dir "$_ts_root")"/*.md; do
        tasks_is_card "$_ts_f" || continue
        _ts_slug=$(basename -- "$_ts_f" .md)
        printf "%s$TASK_SEP%s$TASK_SEP%s$TASK_SEP%s$TASK_SEP%s$TASK_SEP%s\n" "$_ts_slug" \
            "$(fm_get "$_ts_f" kind)" "$(fm_get "$_ts_f" parent)" \
            "$(fm_get "$_ts_f" created)" "$(tasks_title "$_ts_f")" "$(tasks_after "$_ts_f")"
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

# A child of a master, open or closed. `after` may name only these: a sibling that is
# already done costs nothing, a name that is nobody's would silently never block.
tasks_is_child() {
    _ic_f="$(tasks_dir "$1")/$3.md"
    if tasks_is_card "$_ic_f"; then [ "$(fm_get "$_ic_f" parent)" = "$2" ]; return; fi
    for _ic_f in "$(tasks_closed "$1")"/*_"$3".md; do
        [ -f "$_ic_f" ] && [ "$(fm_get "$_ic_f" parent)" = "$2" ] && return 0
    done
    return 1
}

# The queue of a project: its open children, one line each — slug state waits created
# title — where state is `ready` or `waiting` and waits names the `after` cards still open
# on the board. Ordered by the longest chain of open dependencies in front of a child,
# then by slug. The passes are bounded: a cycle written by hand ends the loop, not the
# board.
tasks_queue() {
    tasks_scan "$1" | awk -F"$TASK_SEP" -v p="$2" -v OFS="$TASK_SEP" '
        { open[$1] = 1 }
        $3 == p { n++; s[n] = $1; dep[$1] = $6; cr[$1] = $4; ti[$1] = $5 }
        END {
            for (i = 1; i <= n; i++) {
                c = s[i]; w = ""; lv[c] = 0
                m = split(dep[c], d, / +/)
                for (j = 1; j <= m; j++)
                    if (d[j] != "" && (d[j] in open)) w = w (w == "" ? "" : ", ") d[j]
                wait[c] = w
            }
            for (pass = 0; pass < n; pass++) {
                changed = 0
                for (i = 1; i <= n; i++) {
                    c = s[i]; m = split(dep[c], d, / +/)
                    for (j = 1; j <= m; j++)
                        if ((d[j] in lv) && lv[d[j]] + 1 > lv[c]) { lv[c] = lv[d[j]] + 1; changed = 1 }
                }
                if (!changed) break
            }
            for (i = 1; i <= n; i++) {
                c = s[i]
                print lv[c], c, (wait[c] == "" ? "ready" : "waiting"), wait[c], cr[c], ti[c]
            }
        }' | sort -t"$TASK_SEP" -k1,1n -k2,2 | cut -d"$TASK_SEP" -f2-
}

# The children of a project nobody waits on, comma-separated: what can be taken next.
tasks_ready() {
    tasks_queue "$1" "$2" | awk -F"$TASK_SEP" '$2 == "ready" { o = o (o == "" ? "" : ", ") $1 } END { print o }'
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
#
# The kind is never a default. A silent `task` was the cheap way out for a model that was
# asked for a project and did not connect the word with `--master`: it got one ordinary
# card and put the breakdown in a file of its own. So the verb asks: --task, --master, or
# --parent (a child is always a task).
#
# A master may bring its children in the same call — a `## Subtasks` section, one
# `### <slug> — <title>` per child with `What and why:`, `Done when:` and an optional
# `After:` naming children above it. Every card is checked before any is written, the
# section itself is not kept on the master (the cards are the breakdown, and a second copy
# would go stale with the first child closed), and the project is saved as one point.
TASK_SUBTASKS='## Subtasks'

verb_task_new() {
    _root=$1; shift
    _slug=; _kind=; _parent=; _from=; _after=
    while [ $# -gt 0 ]; do
        case $1 in
            --task) [ "$_kind" != master ] || die "либо --task, либо --master"; _kind=task ;;
            --master) [ "$_kind" != task ] || die "либо --task, либо --master"; _kind=master ;;
            --parent) [ $# -ge 2 ] || die "--parent требует слаг мастер-задачи"; _parent=$2; shift ;;
            --after) [ $# -ge 2 ] || die "--after требует слаги подзадач того же проекта"; _after=$2; shift ;;
            --from) [ $# -ge 2 ] || die "--from требует слаг вопроса из бэклога"; _from=$2; shift ;;
            -*) die "неизвестный флаг: $1" ;;
            *) [ -z "$_slug" ] || die "лишний аргумент: $1"; _slug=$1 ;;
        esac
        shift
    done
    [ -n "$_slug" ] || die "нужен слаг задачи"
    tasks_slug_ok "$_slug"
    if [ -z "$_kind" ]; then
        [ -n "$_parent" ] ||
            die "укажи тип: --task — одна задача; --master — проект из нескольких задач (подзадачи — разделом «$TASK_SUBTASKS» в той же карточке). Человек говорил о проекте или о нескольких задачах — это --master; не ясно — спроси его одним вопросом"
        _kind=task
    fi
    _dir=$(tasks_dir "$_root")
    [ -d "$_dir" ] || die "нет ai/tasks/ — проект не под системой; сначала fraim scaffold"
    [ -e "$_dir/$_slug.md" ] && die "задача уже существует: ai/tasks/$_slug.md"
    [ -e "$_dir/$_slug" ] && die "ai/tasks/$_slug/ — задача старого формата с тем же слагом; сначала fraim upgrade"

    if [ -n "$_from" ] && [ ! -f "$(backlog_dir "$_root")/$_from.md" ]; then
        die "в бэклоге нет вопроса «$_from»"
    fi
    if [ -n "$_parent" ]; then
        [ "$_kind" = master ] && die "у мастер-задачи нет родителя: вложенность — один уровень"
        _pf="$_dir/$_parent.md"
        tasks_is_card "$_pf" || die "нет открытой задачи «$_parent» — родителем может быть только открытая мастер-задача"
        [ "$(fm_get "$_pf" kind)" = master ] ||
            die "«$_parent» — обычная задача, не мастер-задача. Сделать её проектом может только человек: fraim task-master $_parent"
    fi
    if [ -n "$_after" ]; then
        [ -n "$_parent" ] || die "--after — порядок внутри проекта: только вместе с --parent"
        _after=$(printf '%s' "$_after" | tr ',' ' ' | tr -s ' ' | sed 's/^ //; s/ $//')
        for _a in $_after; do
            tasks_is_child "$_root" "$_parent" "$_a" ||
                die "--after: «$_a» — не подзадача проекта «$_parent»"
        done
    fi

    _body=$(verb_read_body) ||
        die "карточка приходит потоком:  fraim task-new $_slug --task <<'EOF'  # Заголовок … EOF"
    printf '%s\n' "$_body" | head -1 | grep -qx -- '---' &&
        die "frontmatter пишет глагол, не ты — пришли карточку начиная с «# Заголовок»"
    printf '%s\n' "$_body" | grep -q '^# [^[:space:]]' ||
        die "у карточки нет заголовка — первая строка «# Что сделать»"
    lang_check "the task card" "$_body"

    # Split the card from its subtasks: the master's own text, and per child a head line
    # and its fields, each in a file of the scratch folder.
    _sd="$_dir/.$_slug.$$"
    mkdir "$_sd" || die "не удалось записать карточку"
    printf '%s\n' "$_body" | tasks_split_subtasks "$_sd"
    _n=$(cat "$_sd/count")
    if [ -f "$_sd/found" ] && [ "$_kind" != master ]; then
        rm -rf "$_sd"
        die "раздел «$TASK_SUBTASKS» бывает только у проекта (--master); подзадачу в открытый проект ставят по одной: --parent"
    fi
    if [ -f "$_sd/found" ] && [ "$_n" -eq 0 ]; then
        rm -rf "$_sd"; die "раздел «$TASK_SUBTASKS» пуст — каждая подзадача: «### слаг — Заголовок», затем «What and why:» и «Done when:»"
    fi
    if [ -f "$_sd/stray" ]; then
        rm -rf "$_sd"
        die "в разделе «$TASK_SUBTASKS» текст вне подзадачи — каждая: «### слаг — Заголовок», затем «What and why:», «Done when:», необязательно «After:»"
    fi

    fnd_wrap < "$_sd/master" > "$_sd/card" || { rm -rf "$_sd"; die "не удалось записать карточку"; }
    for _sec in "$TASK_WHAT" "$TASK_DONE"; do
        _rc=0; verb_section_filled "$_sd/card" "$_sec" || _rc=$?
        case $_rc in
            1) rm -rf "$_sd"; die "в карточке нет раздела «$_sec»" ;;
            2) rm -rf "$_sd"; die "раздел «$_sec» пуст" ;;
            3) rm -rf "$_sd"; die "в разделе «$_sec» остался плейсхолдер <…>" ;;
        esac
    done

    # Every child is checked before anything is written: a project half on the board is
    # worse than a refusal.
    _i=0; _kids=
    while [ "$_i" -lt "$_n" ]; do
        _i=$((_i + 1))
        _tn_err=$(tasks_check_subtask "$_root" "$_sd" "$_i" "$_slug" "$_kids") ||
            { rm -rf "$_sd"; die "$_tn_err"; }
        _kids="$_kids $(cat "$_sd/$_i.slug")"
    done

    _date=$(date +%Y-%m-%d)
    {
        printf -- '---\nkind: %s\ncreated: %s\n' "$_kind" "$_date"
        if [ -n "$_parent" ]; then printf 'parent: %s\n' "$_parent"; fi
        if [ -n "$_after" ]; then printf 'after: %s\n' "$(printf '%s' "$_after" | sed 's/ /, /g')"; fi
        printf -- '---\n'
        cat "$_sd/card"
    } > "$_dir/$_slug.md" || { rm -rf "$_sd"; die "не удалось записать карточку"; }
    _paths="ai/tasks/$_slug.md"
    _i=0
    while [ "$_i" -lt "$_n" ]; do
        _i=$((_i + 1))
        _cs=$(cat "$_sd/$_i.slug")
        {
            printf -- '---\nkind: task\ncreated: %s\nparent: %s\n' "$_date" "$_slug"
            if [ -s "$_sd/$_i.deps" ]; then printf 'after: %s\n' "$(sed 's/ /, /g' "$_sd/$_i.deps")"; fi
            printf -- '---\n'
            cat "$_sd/$_i.card"
        } > "$_dir/$_cs.md" || { rm -rf "$_sd"; die "не удалось записать подзадачу $_cs"; }
        _paths="$_paths ai/tasks/$_cs.md"
    done
    rm -rf "$_sd"

    _what=задача; [ "$_kind" = master ] && _what=мастер-задача
    ok "ai/tasks/$_slug.md — $_what поставлена${_parent:+ (в проекте «$_parent»)}"
    _msg="$_slug — added"
    if [ "$_n" -gt 0 ]; then
        ok "  подзадач: $_n — можно брать: $(tasks_ready "$_root" "$_slug")"
        _msg="$_slug — added with $_n subtasks"
    fi
    if [ -n "$_from" ]; then
        backlog_to_task "$_root" "$_from" "$_slug"
        ok "вопрос «$_from» стал задачей — ушёл из бэклога в архив"
    fi
    # shellcheck disable=SC2086 # the paths are slugs: no spaces by construction
    verb_commit "$_root" task "$_msg" $_paths ai/backlog ai/archive/backlog || warn "коммит не удался"
}

# Read a card on stdin; write into DIR: `master` (the card without its subtasks section),
# `count`, and per child N: `N.head`, `N.what`, `N.done`, `N.after`. `found` marks that
# the section exists, `stray` that it holds text outside a child's fields.
tasks_split_subtasks() {
    awk -v dir="$1" '
        function shut() { if (n) { close(dir "/" n ".head"); close(dir "/" n ".what"); close(dir "/" n ".done"); close(dir "/" n ".after") } }
        /^## / {
            t = tolower($0); sub(/[ \t]+$/, "", t)
            insec = (t == "## subtasks")
            if (insec) { found = 1; next }
        }
        !insec { print > (dir "/master"); next }
        /^### / { shut(); n++; h = $0; sub(/^### +/, "", h); print h > (dir "/" n ".head"); field = ""; next }
        {
            line = $0
            if (line !~ /[^ \t]/) next
            sub(/^[ \t]+/, "", line)
            if (match(tolower(line), /^(what and why|done when|after)[ \t]*:/)) {
                lab = tolower(substr(line, 1, RLENGTH)); line = substr(line, RLENGTH + 1)
                sub(/^[ \t]+/, "", line)
                if (lab ~ /what/) field = "what"; else if (lab ~ /done/) field = "done"; else field = "after"
                if (n == 0) stray = 1
                if (line == "") next
            }
            if (n == 0 || field == "") { stray = 1; next }
            print line > (dir "/" n "." field)
        }
        END {
            shut()
            print n + 0 > (dir "/count")
            if (found) print 1 > (dir "/found")
            if (stray) print 1 > (dir "/stray")
        }'
    [ -f "$1/master" ] || : > "$1/master"
}

# Check child N of a project and lay out its card body (`N.card`), slug (`N.slug`) and
# dependencies (`N.deps`) in DIR. KIDS are the slugs listed above it: `After` may name only
# those, so the order the human approved can never hold a cycle. Prints the refusal.
tasks_check_subtask() {
    _cs_root=$1; _cs_d=$2; _cs_i=$3; _cs_master=$4; _cs_kids=$5
    _cs_head=$(cat "$_cs_d/$_cs_i.head")
    _cs_slug=$(printf '%s' "$_cs_head" | sed -E 's/^`?([^` :]+)`?.*/\1/')
    _cs_title=$(printf '%s' "$_cs_head" | sed -E 's/^`?[^` :]+`?([[:space:]]*:|[[:space:]]+(—|–|-))[[:space:]]+//')
    if [ "$_cs_title" = "$_cs_head" ] || [ -z "$(printf '%s' "$_cs_title" | tr -d '[:space:]')" ]; then
        printf 'подзадача «%s»: заголовок пишется «### слаг — Заголовок»\n' "$_cs_head"; return 1
    fi
    printf '%s' "$_cs_slug" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' ||
        { printf 'подзадача «%s»: слаг — kebab-case, буквы, цифры и дефисы\n' "$_cs_slug"; return 1; }
    [ "$_cs_slug" != "$_cs_master" ] ||
        { printf 'подзадача «%s»: слаг совпадает с проектом\n' "$_cs_slug"; return 1; }
    case " $_cs_kids " in *" $_cs_slug "*)
        printf 'подзадача «%s» указана дважды\n' "$_cs_slug"; return 1 ;;
    esac
    if [ -e "$(tasks_dir "$_cs_root")/$_cs_slug.md" ] || [ -e "$(tasks_dir "$_cs_root")/$_cs_slug" ]; then
        printf 'подзадача «%s»: такая задача уже есть на доске\n' "$_cs_slug"; return 1
    fi
    for _cs_f in what done; do
        _cs_v=$(cat "$_cs_d/$_cs_i.$_cs_f" 2>/dev/null) || _cs_v=
        _cs_name="What and why:"; [ "$_cs_f" = done ] && _cs_name="Done when:"
        [ -n "$(printf '%s' "$_cs_v" | tr -d '[:space:]')" ] ||
            { printf 'подзадача «%s»: нет «%s»\n' "$_cs_slug" "$_cs_name"; return 1; }
        printf '%s' "$_cs_v" | grep -q '<[^>]*>' &&
            { printf 'подзадача «%s»: в «%s» остался плейсхолдер <…>\n' "$_cs_slug" "$_cs_name"; return 1; }
    done
    _cs_deps=$(cat "$_cs_d/$_cs_i.after" 2>/dev/null | tr ',\n' '  ' | tr -s ' ' | sed 's/^ //; s/ $//')
    for _cs_a in $_cs_deps; do
        case " $_cs_kids " in *" $_cs_a "*) ;; *)
            printf 'подзадача «%s»: After «%s» — можно ссылаться только на подзадачи выше по списку\n' "$_cs_slug" "$_cs_a"
            return 1 ;;
        esac
    done
    printf '%s' "$_cs_slug" > "$_cs_d/$_cs_i.slug"
    printf '%s' "$_cs_deps" > "$_cs_d/$_cs_i.deps"
    {
        printf '# %s\n\n%s\n' "$_cs_title" "$TASK_WHAT"
        cat "$_cs_d/$_cs_i.what"
        printf '\n%s\n' "$TASK_DONE"
        cat "$_cs_d/$_cs_i.done"
    } | fnd_wrap > "$_cs_d/$_cs_i.card"
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
    verb_commit "$_root" task "$_slug — became a master task" "ai/tasks/$_slug.md" || warn "коммит не удался"
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
    lang_check "the result line" "$_result"

    _kind=$(fm_get "$_f" kind)
    if [ "$_kind" = master ]; then
        _open=$(tasks_open_children "$_root" "$_slug" | tr '\n' ' ')
        [ -z "$_open" ] ||
            die "у мастер-задачи «$_slug» открыты подзадачи: $_open— сначала закрой или отмени их"
    fi

    _dest=$(tasks_archive_card "$_root" "$_f" "$(tasks_closed "$_root")" "$_slug" "$_outcome" "$_result") || exit 2

    _word=выполнена; [ "$_outcome" = dropped ] && _word=отменена
    _cword=done; [ "$_outcome" = dropped ] && _cword=dropped
    ok "«$_slug» $_word → ai/archive/tasks/$(basename -- "$_dest")"
    verb_commit "$_root" archive "$_slug — $_cword" "ai/tasks" "ai/archive/tasks" || warn "коммит не удался"

    _parent=$(fm_get "$_dest" parent)
    if [ -n "$_parent" ]; then
        _o=$(tasks_open_children "$_root" "$_parent" | grep -c . || true)
        _c=$(tasks_closed_children_n "$_root" "$_parent")
        say "  проект «$_parent»: закрыто $_c из $((_o + _c))"
        if [ "$_o" -eq 0 ]; then
            dim "  открытых подзадач нет — закрыть сам проект решает человек"
        else
            _r=$(tasks_ready "$_root" "$_parent")
            [ -z "$_r" ] || say "  можно брать: $_r"
        fi
    fi
    # A dropped card frees whoever waited on it — the queue cannot tell «no longer needed»
    # from «done», so the waiting ones are named for the human to look at.
    if [ "$_outcome" = dropped ]; then
        _waited=$(tasks_scan "$_root" | awk -F"$TASK_SEP" -v s="$_slug" \
            '{ n = split($6, d, / +/); for (i = 1; i <= n; i++) if (d[i] == s) { print $1; break } }' | tr '\n' ' ')
        [ -z "$_waited" ] || warn "эту задачу ждали: $_waited— нужны ли они без неё, решает человек"
    fi
    return 0
}

# Move a card into an archive folder with its outcome appended to the frontmatter:
# closed, outcome, result, and the commit the work ended on. One implementation for
# tasks and backlog questions. Prints the destination path.
tasks_archive_card() {
    _ac_root=$1; _ac_src=$2; _ac_dir=$3; _ac_slug=$4; _ac_outcome=$5; _ac_result=$6
    mkdir -p "$_ac_dir" || die "не удалось создать ${_ac_dir#"$_ac_root"/}/"
    _ac_dest="$_ac_dir/$(date +%Y-%m-%d)_$_ac_slug.md"
    [ -e "$_ac_dest" ] && die "в архиве уже есть ${_ac_dest#"$_ac_root"/}"
    _ac_head=
    verb_is_git "$_ac_root" && _ac_head=$(git -C "$_ac_root" rev-parse --short HEAD 2>/dev/null)
    _ac_q=$(printf '%s' "$_ac_result" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')
    FND_CLOSED=$(date +%Y-%m-%d) FND_OUTCOME=$_ac_outcome FND_RESULT=$_ac_q FND_HEAD=$_ac_head awk '
        NR == 1 { print; fm = 1; next }
        fm && $0 == "---" {
            print "closed: " ENVIRON["FND_CLOSED"]
            print "outcome: " ENVIRON["FND_OUTCOME"]
            print "result: \"" ENVIRON["FND_RESULT"] "\""
            if (ENVIRON["FND_HEAD"] != "") print "commit: " ENVIRON["FND_HEAD"]
            fm = 0
        }
        { print }
    ' "$_ac_src" > "$_ac_dest" || { rm -f "$_ac_dest"; die "не удалось записать архив"; }
    rm -f "$_ac_src" || die "не удалось убрать карточку"
    printf '%s\n' "$_ac_dest"
}

# --- tasks (the board) ------------------------------------------------------
tasks_age_words() {
    _d=$(tasks_days_since "$1")
    if [ "$_d" -eq 0 ]; then printf 'сегодня\n'; else printf '%s дн.\n' "$_d"; fi
}

# A list (spaces or commas) as a JSON array of strings. Slugs only: nothing to escape.
tasks_json_list() {
    printf '%s' "$1" | tr ',' ' ' | awk '{ for (i = 1; i <= NF; i++) o = o (o == "" ? "" : ", ") "\"" $i "\"" }
        END { printf "[%s]", o }'
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
            while IFS="$TASK_SEP" read -r _s _k _p _cr _t _a; do
                [ -n "$_s" ] || continue
                if [ "$_first" = 1 ]; then printf '\n'; else printf ',\n'; fi
                _first=0
                printf '    { "slug": "%s", "kind": "%s", "parent": "%s", "title": "%s", "created": "%s", "age_days": %s' \
                    "$_s" "$_k" "$_p" "$(wm_json_escape "$_t")" "$_cr" "$(tasks_days_since "$_cr")"
                if [ "$_k" = master ]; then
                    printf ', "open_children": %s, "closed_children": %s, "ready": %s' \
                        "$(tasks_open_children "$_root" "$_s" | grep -c . || true)" \
                        "$(tasks_closed_children_n "$_root" "$_s")" \
                        "$(tasks_json_list "$(tasks_ready "$_root" "$_s")")"
                fi
                if [ -n "$_p" ]; then
                    _w=; for _x in $_a; do tasks_is_card "$(tasks_dir "$_root")/$_x.md" && _w="$_w $_x"; done
                    printf ', "after": %s, "waiting_on": %s' "$(tasks_json_list "$_a")" "$(tasks_json_list "$_w")"
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
            while IFS="$TASK_SEP" read -r _s _k _p _cr _t _a; do
                _r=$(tasks_ready "$_root" "$_s")
                printf '  ◆ %s — %s %s· %s · %s%s%s\n' "$_s" "$_t" "$C_DIM" \
                    "$(tasks_master_words "$_root" "$_s")" "$(tasks_age_words "$_cr")" \
                    "${_r:+ · можно брать: $_r}" "$C_OFF"
                # The queue: nobody-waits-on first, each waiting child naming what it waits for.
                tasks_queue "$_root" "$_s" |
                    while IFS="$TASK_SEP" read -r _cs _cst _cw _ccr _ct; do
                        printf '      · %s — %s %s· %s%s%s\n' "$_cs" "$_ct" "$C_DIM" "$(tasks_age_words "$_ccr")" \
                            "${_cw:+ · ждёт: $_cw}" "$C_OFF"
                    done
            done
        printf '%s\n' "$_scan" | awk -F"$TASK_SEP" -v m=" $_masters" '$2 != "master" && index(m, " " $3 " ") == 0' |
            while IFS="$TASK_SEP" read -r _s _k _p _cr _t _a; do
                _note=
                [ -n "$_p" ] && _note=" (родитель «$_p» не открыт)"
                printf '  · %s — %s %s· %s%s%s\n' "$_s" "$_t" "$C_DIM" "$(tasks_age_words "$_cr")" "$_note" "$C_OFF"
            done
    fi
    _bn=$(backlog_scan "$_root" | grep -c . || true)
    if [ "$_bn" -gt 0 ]; then dim "  в бэклоге $_bn $(wm_plural "$_bn" вопрос вопроса вопросов) — fraim backlog"; fi
    [ -n "$_legacy" ] && warn "задачи старого формата (папки): $_legacy— перевести в карточки: fraim upgrade"
    return 0
}

# --- backlog: open questions ------------------------------------------------
# Not tasks. A task is something we know we will do; a backlog entry is a question that
# matters and that nobody wants to answer now — the «open questions» an agent lists at the
# end of a session, which are gone the moment the chat closes unless they land somewhere.
# Same shape as a card, own folder: `ai/backlog/<slug>.md`, frontmatter `created` and the
# optional `from` (where it came up). Only the human decides what goes in.
BACKLOG_WHAT='## Question'
BACKLOG_WHY='## Why it matters'

backlog_dir()    { printf '%s/ai/backlog\n' "$1"; }
backlog_closed() { printf '%s/ai/archive/backlog\n' "$1"; }

# slug created from title, joined by TASK_SEP
backlog_scan() {
    for _bs_f in "$(backlog_dir "$1")"/*.md; do
        [ -f "$_bs_f" ] || continue
        [ -n "$(fm_get "$_bs_f" created 2>/dev/null)" ] || continue
        printf "%s$TASK_SEP%s$TASK_SEP%s$TASK_SEP%s\n" "$(basename -- "$_bs_f" .md)" \
            "$(fm_get "$_bs_f" created)" "$(fm_get "$_bs_f" from)" "$(tasks_title "$_bs_f")"
    done
}

verb_backlog() {
    _root=$1
    _scan=$(backlog_scan "$_root")
    _n=$(printf '%s' "$_scan" | grep -c . || true)
    if [ "$_n" -eq 0 ]; then ok "бэклог пуст"; return 0; fi
    say "${C_BLD}Бэклог · открытых вопросов $_n${C_OFF}"
    printf '%s\n' "$_scan" | while IFS="$TASK_SEP" read -r _s _cr _from _t; do
        printf '  ? %s — %s %s· %s%s%s\n' "$_s" "$_t" "$C_DIM" "$(tasks_age_words "$_cr")" \
            "${_from:+ · из $_from}" "$C_OFF"
    done
    dim "  стал задачей — fraim task-new СЛАГ --from ВОПРОС; снят — fraim backlog-drop ВОПРОС \"почему\""
}

verb_backlog_new() {
    _root=$1; shift
    _slug=; _from=
    while [ $# -gt 0 ]; do
        case $1 in
            --from) [ $# -ge 2 ] || die "--from требует, откуда вопрос (слаг задачи или «сессия»)"; _from=$2; shift ;;
            -*) die "неизвестный флаг: $1" ;;
            *) [ -z "$_slug" ] || die "лишний аргумент: $1"; _slug=$1 ;;
        esac
        shift
    done
    [ -n "$_slug" ] || die "нужен слаг вопроса"
    tasks_slug_ok "$_slug"
    _dir=$(backlog_dir "$_root")
    mkdir -p "$_dir" || die "не удалось создать ai/backlog/"
    [ -e "$_dir/$_slug.md" ] && die "вопрос уже в бэклоге: ai/backlog/$_slug.md"
    _body=$(verb_read_body) ||
        die "вопрос приходит потоком:  fraim backlog-new $_slug <<'EOF'  # Вопрос … EOF"
    printf '%s\n' "$_body" | head -1 | grep -qx -- '---' &&
        die "frontmatter пишет глагол — пришли вопрос начиная с «# Заголовок»"
    printf '%s\n' "$_body" | grep -q '^# [^[:space:]]' || die "у вопроса нет заголовка — первая строка «# …»"
    lang_check "the backlog question" "$_body"
    _tmp="$_dir/.$_slug.md.$$"
    printf '%s\n' "$_body" | fnd_wrap > "$_tmp" || die "не удалось записать вопрос"
    for _sec in "$BACKLOG_WHAT" "$BACKLOG_WHY"; do
        _rc=0; verb_section_filled "$_tmp" "$_sec" || _rc=$?
        case $_rc in
            1) rm -f "$_tmp"; die "в вопросе нет раздела «$_sec»" ;;
            2) rm -f "$_tmp"; die "раздел «$_sec» пуст" ;;
            3) rm -f "$_tmp"; die "в разделе «$_sec» остался плейсхолдер <…>" ;;
        esac
    done
    {
        printf -- '---\ncreated: %s\n' "$(date +%Y-%m-%d)"
        if [ -n "$_from" ]; then printf 'from: %s\n' "$_from"; fi
        printf -- '---\n'
        cat "$_tmp"
    } > "$_dir/$_slug.md" || { rm -f "$_tmp"; die "не удалось записать вопрос"; }
    rm -f "$_tmp"
    ok "ai/backlog/$_slug.md — вопрос записан в бэклог"
    verb_commit "$_root" backlog "$_slug — added" "ai/backlog/$_slug.md" || warn "коммит не удался"
}

verb_backlog_drop() {
    _root=$1; _slug=${2:-}; _why=${3:-}
    [ -n "$_slug" ] || die "нужен слаг вопроса"
    _f="$(backlog_dir "$_root")/$_slug.md"
    [ -f "$_f" ] || die "нет такого вопроса: ai/backlog/$_slug.md"
    [ -n "$(printf '%s' "$_why" | tr -d '[:space:]')" ] ||
        die "нужна строка: fraim backlog-drop $_slug \"почему снят\""
    lang_check "the reason" "$_why"
    _dest=$(tasks_archive_card "$_root" "$_f" "$(backlog_closed "$_root")" "$_slug" dropped "$_why") || exit 2
    ok "«$_slug» снят → ai/archive/backlog/$(basename -- "$_dest")"
    verb_commit "$_root" backlog "$_slug — dropped" ai/backlog ai/archive/backlog || warn "коммит не удался"
}

# A question that became a task leaves the backlog the same way, with the task named.
backlog_to_task() {
    _root=$1; _q=$2; _task=$3
    _f="$(backlog_dir "$_root")/$_q.md"
    _dest=$(tasks_archive_card "$_root" "$_f" "$(backlog_closed "$_root")" "$_q" task "became task $_task") || exit 2
    _card="$(tasks_dir "$_root")/$_task.md"
    _link="- From the backlog: \`${_dest#"$_root"/}\`"
    if grep -qx "$TASK_LINKS" "$_card"; then
        FND_LINK=$_link FND_LINKS=$TASK_LINKS awk '
            $0 == ENVIRON["FND_LINKS"] { print; inside = 1; next }
            inside && /^## / { print ENVIRON["FND_LINK"]; print ""; inside = 0 }
            { print }
            END { if (inside) print ENVIRON["FND_LINK"] }
        ' "$_card" > "$_card.fraim.tmp" && mv "$_card.fraim.tmp" "$_card"
    else
        printf '\n%s\n%s\n' "$TASK_LINKS" "$_link" >> "$_card"
    fi
}

# --- migration from the old format ------------------------------------------
# A folder task carried a plan, and its sections were guaranteed by plan-seal — so the
# intent can be lifted out of it mechanically: Summary → title, Goal + Why → «What and
# why», Acceptance Criteria → «Done when». The plan itself is kept, whole, in the
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
                printf 'Not parsed mechanically — see the old plan.\n'
            fi
            printf '\n%s\n' "$TASK_DONE"
            if [ -n "$(printf '%s' "$_acc" | tr -d '[:space:]')" ]; then printf '%s\n' "$_acc"
            else printf 'Not parsed mechanically — see the old plan.\n'; fi
            printf '\n%s\n- Old plan: `ai/archive/legacy-plans/%s/`\n' "$TASK_LINKS" "$_s"
            if [ -f "$_d/blockers.md" ]; then
                printf -- '- The executor had blocked this plan: `blockers.md` in the same folder.\n'
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
    _mc_root=$1; _mc_item="- $2"
    _mc_card="$_mc_root/ai/tasks/fraim-migration.md"
    if [ -f "$_mc_card" ]; then
        grep -qxF -- "$_mc_item" "$_mc_card" && return 0
        FND_ITEM=$_mc_item awk '
            /^How to finish them/ && !done { print ENVIRON["FND_ITEM"]; print ""; done = 1 }
            { print }
        ' "$_mc_card" | awk 'NF || !blank { print } { blank = !NF }' > "$_mc_card.fraim.tmp" &&
            mv "$_mc_card.fraim.tmp" "$_mc_card"
    else
        {
            printf -- '---\nkind: task\ncreated: %s\n---\n' "$(date +%Y-%m-%d)"
            printf '# Finish the move to the fraim %s format\n\n' "$(fraim_version)"
            printf '%s\n' "$TASK_WHAT"
            printf '`fraim upgrade` did the mechanical part; these it could not do on its own:\n'
            printf '%s\n' "$_mc_item"
            printf '\nHow to finish them — the «Format migration» section of /prune.\n\n'
            printf '%s\nEvery item above is done: the cards and the map are in the new format.\n' "$TASK_DONE"
        } > "$_mc_card"
    fi
    TASKS_CARD=1
    warn "не всё разобралось механически — на доске задача fraim-migration: $2"
}

# The whole task half of `fraim upgrade` (and of the cleanup's upgrade step): migrate,
# put what did not parse on the board, save it as one point.
# Cards written before the format went English carry Russian section headings. The verbs
# check those headings by exact text, so they are renamed in place — the heading line only,
# never the body.
TASKS_RENAMED=0
tasks_rename_headings() {
    TASKS_RENAMED=0
    # The Russian headings below are the OLD format, kept only as the source of this rename.
    for _rh_f in "$1"/ai/tasks/*.md "$1"/ai/backlog/*.md "$1"/ai/archive/tasks/*.md "$1"/ai/archive/backlog/*.md; do
        [ -f "$_rh_f" ] || continue
        grep -qx '## Что и зачем\|## Готово, когда\|## Ссылки\|## В чём вопрос\|## Почему важно' "$_rh_f" || continue
        sed -e 's/^## Что и зачем$/## What and why/' -e 's/^## Готово, когда$/## Done when/' \
            -e 's/^## Ссылки$/## Links/' -e 's/^## В чём вопрос$/## Question/' \
            -e 's/^## Почему важно$/## Why it matters/' "$_rh_f" > "$_rh_f.fraim.tmp" &&
            mv "$_rh_f.fraim.tmp" "$_rh_f"
        TASKS_RENAMED=$((TASKS_RENAMED + 1))
    done
}

TASKS_CARD=0
tasks_upgrade() {
    _root=$1
    TASKS_CARD=0
    tasks_migrate_legacy "$_root" || return 1
    tasks_rename_headings "$_root"
    if [ -n "$TASKS_UNPARSED" ]; then
        tasks_migration_card "$_root" "tasks without the required sections:$TASKS_UNPARSED"
    fi
    # A map with no `## ` sections cannot be written by `fraim arch`, and splitting it is
    # judgement — which section a paragraph belongs to is not a fact the verb can compute.
    _tu_a="$_root/ARCHITECTURE.md"
    if [ -f "$_tu_a" ] && ! scaffold_is_stub "$_tu_a" && ! grep -q '^## ' "$_tu_a"; then
        tasks_migration_card "$_root" "ARCHITECTURE.md has no «## » sections — fraim arch cannot edit it; split the map into sections"
    fi
    [ "$TASKS_MIGRATED" -gt 0 ] || [ "$TASKS_CARD" = 1 ] || [ "$TASKS_RENAMED" -gt 0 ] || return 0
    verb_commit "$_root" upgrade "tasks and map moved to the new format" ai/tasks ai/archive ai/backlog ||
        warn "коммит не удался"
}
