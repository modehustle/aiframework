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
# The task verbs live in tasks.sh: a task is a card on a board now, not a plan with gates.

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
# Used by investigations; tasks archive as cards (tasks.sh). The timestamp
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
    lang_check "findings.md" "$(cat "$_f")"

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
    # A merge commit has to say which side to keep. Ours are made by the fleet's trunk
    # write (`dispatch accept`), and there the first parent is the trunk as it stood — so
    # -m 1 undoes exactly the build that was merged in. Without this, undoing a trunk write
    # died with "the changes overlapped", which is the wrong sentence for "this is a merge".
    _mflag=
    [ "$(git -C "$_root" rev-list --parents -n 1 "$_ref" 2>/dev/null | wc -w)" -gt 2 ] && _mflag='-m 1'
    if git -C "$_root" revert --no-edit $_mflag "$_ref" >/dev/null 2>&1; then
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

# A verb's text arrives on stdin. Two ways that can go wrong, and both must end in a
# refusal that shows the right form, never in a hang:
#   · stdin is a terminal — nobody is going to type a body;
#   · stdin is open but nothing is coming — an agent harness or a script that runs every
#     command with an inherited pipe. `cat` then waits for an EOF that never arrives, and
#     the verb looks exactly like a hung session.
# So the read runs in the background and the verb waits for the FIRST byte only, a few
# seconds at most. A body that has started arriving is read to the end, however long.
# The descriptor is passed explicitly: an asynchronous command in a non-interactive shell
# otherwise gets /dev/null for stdin, and would always read nothing.
FRAIM_BODY_WAIT=${FRAIM_BODY_WAIT:-30}   # tenths of a second

verb_read_body() {
    [ -t 0 ] && { warn "текст не пришёл: вход — терминал"; return 1; }
    _rb_tmp=$(mktemp) || return 1
    exec 3<&0
    cat <&3 > "$_rb_tmp" &
    _rb_pid=$!
    exec 3<&-
    _rb_t=0
    while kill -0 "$_rb_pid" 2>/dev/null; do
        if [ -s "$_rb_tmp" ]; then wait "$_rb_pid" || :; break; fi
        if [ "$_rb_t" -ge "$FRAIM_BODY_WAIT" ]; then
            kill "$_rb_pid" 2>/dev/null || :
            rm -f "$_rb_tmp"
            warn "текст не пришёл на вход за $((FRAIM_BODY_WAIT / 10)) с — вход открыт, но пуст"
            return 1
        fi
        if sleep 0.1 2>/dev/null; then _rb_t=$((_rb_t + 1)); else sleep 1; _rb_t=$((_rb_t + 10)); fi
    done
    cat "$_rb_tmp"
    rm -f "$_rb_tmp"
}

verb_decide() {
    _root=$1; _title=$2; _supersedes=${3:-}
    _file="$_root/DECISIONS.md"
    [ -f "$_file" ] || die "нет DECISIONS.md — сначала fraim scaffold, потом /bootstrap или /onboard"
    [ -n "$_title" ] || die "нужен заголовок решения"

    _body=$(verb_read_body) ||
        die "тело решения приходит потоком:  fraim decide \"ЗАГОЛОВОК\" <<'EOF' … EOF"
    [ -n "$(printf '%s' "$_body" | tr -d '[:space:]')" ] || die "тело решения пустое"
    lang_check "the decision title" "$_title"
    lang_check "the decision body" "$_body"
    _body=$(printf '%s\n' "$_body" | fnd_wrap)

    # Superseding by name moves the old entry to the archive (foundation.sh). Resolved
    # BEFORE anything is written: an ambiguous name is a refusal, not a guess, and the
    # new entry must not be the one it matches.
    _match=
    if [ -n "$_supersedes" ]; then
        _m=$(fnd_decision_matches "$_file" "$_supersedes")
        _mn=$(printf '%s' "$_m" | grep -c . || true)
        if [ "$_mn" -gt 1 ]; then
            die "«$_supersedes» подходит к $_mn записям — уточни:
$(printf '%s\n' "$_m" | sed 's/^## /  · /')"
        fi
        if [ "$_mn" -eq 1 ]; then
            _match=$_m
            _supersedes=${_m#\#\# }
        fi
    fi

    _date=$(date +%Y-%m-%d)
    _entry="## $_date — $_title"
    _tmp="$_file.fraim.tmp"

    if [ -n "$_match" ]; then
        fnd_move_decision "$_root" "$_match" || die "не удалось перенести заменённую запись в архив"
    fi

    # Newest on top: the entry goes above the first existing one, and when there is
    # none yet, after the header block. The stub marker goes away with the first real
    # entry — a file with a decision in it is no longer an unfilled scaffold (D1).
    # Text travels through ENVIRON, not -v: awk -v expands backslash escapes, and a body
    # that quotes a regex or a Windows path would be silently rewritten.
    FND_ENTRY=$_entry FND_BODY=$_body FND_SUP=$_supersedes FND_STUB=$SCAFFOLD_STUB awk '
        BEGIN { entry = ENVIRON["FND_ENTRY"]; body = ENVIRON["FND_BODY"]
                sup = ENVIRON["FND_SUP"]; stub = ENVIRON["FND_STUB"] }
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
    if [ -n "$_match" ]; then
        ok "заменённая запись перенесена в ai/archive/decisions_log.md: ${_match#\#\# }"
        dim "  запись не сохранена: добавь DECISIONS.md и ai/archive/decisions_log.md в свой fraim commit"
    else
        [ -n "$_supersedes" ] && dim "  «$_supersedes» не найдена среди заголовков — оставлена ссылкой, ничего не перенесено"
        dim "  запись не сохранена: добавь DECISIONS.md в свой fraim commit"
    fi
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
    lang_check "the pitfall" "$_lines"

    _tmp="$_file.fraim.tmp"
    _items=$(printf '%s\n' "$_lines" | grep '[^[:space:]]' | sed 's/^/- /' | fnd_wrap)
    # Appended at the END of that one section, not at the end of the file: the
    # section is what every session reads first, and a line that lands under the
    # wrong heading is a lesson nobody will ever be shown again.
    FND_HEAD=$_head FND_ITEMS=$_items awk '
        BEGIN { head = ENVIRON["FND_HEAD"]; items = ENVIRON["FND_ITEMS"] }
        $0 == head { inside = 1; print; next }
        inside && /^## / {
            print items
            inside = 0; done = 1
            print ""
            print
            next
        }
        inside && $0 == "- None yet." { next }
        { print }
        END { if (inside && !done) print items }
    ' "$_file" > "$_tmp" || { rm -f "$_tmp"; die "не удалось записать CONVENTIONS.md"; }
    mv "$_tmp" "$_file" || die "не удалось записать CONVENTIONS.md"

    _n=$(printf '%s\n' "$_lines" | grep -c '[^[:space:]]')
    ok "CONVENTIONS.md ← $_n $(wm_plural "$_n" строка строки строк) в '$_head'"
    dim "  запись не сохранена: добавь CONVENTIONS.md в свой fraim commit"
}
