#!/bin/sh
# clean.sh — «чистка»: сделать за один заход всё, что чинится детерминированно.
#
# Сторож показывает, что в проекте не так, и на живом проекте этого набирается тридцать
# строк. Большая их часть — не работа, а хвосты: фундамент от старой версии, расследования,
# доведённые до исхода и не заархивированные, исполненные и не запечатанные задачи,
# несохранённые файлы фундамента. Каждый хвост закрывается известной командой, и человеку
# незачем набирать её тридцать раз.
#
# Граница проведена жёстко: чистка делает только то, у чего ответ один и он вычислим.
# Протухшие планы, очередь, дрейф фундамента и отправку копии она не трогает — там нужно
# суждение, а действие без суждения в этих местах и есть тот самый дрейф.
#
# Ратификация остаётся: план показывается, вопрос задаётся один раз (B5). Под пайпом без
# --yes чистка ничего не делает — печатает план и выходит.

CLEAN_PLAN=
CLEAN_N=0

clean_add() {
    CLEAN_N=$((CLEAN_N + 1))
    CLEAN_PLAN="$CLEAN_PLAN$1	$2	$3
"
}

# Что можно сделать прямо сейчас. Читает то же состояние, что и сторож: одна арифметика.
clean_scan() {
    _root=$1
    CLEAN_PLAN=; CLEAN_N=0

    wm_scan_tasks "$_root"
    WM_FINDINGS=
    config_is_on check_shape "$_root" && wm_check_shape "$_root"
    if printf '%s' "$WM_FINDINGS" | grep -q '^shape	'; then
        clean_add upgrade "" "довести фундамент до стандарта (fraim upgrade)"
    fi

    # Расследования. Доведённое до исхода — запечатать штатным гейтом. Брошенное —
    # закрыть честно: в архив с записью о том, что исхода нет и уборка не проверялась.
    _days_max=$(config_get abandon_after_days "$_root")
    for _f in "$_root"/ai/investigations/*/findings.md; do
        [ -f "$_f" ] || continue
        _slug=$(basename -- "$(dirname -- "$_f")")
        if verb_section_filled "$_f" '### DIAGNOSIS' || verb_section_filled "$_f" '### DEAD-END'; then
            clean_add investigate-seal "$_slug" "запечатать расследование «$_slug» (исход записан)"
            continue
        fi
        _age=$(wm_days_since "$(wm_mtime "$_f")")
        if [ "$_age" -ge "$_days_max" ]; then
            clean_add investigate-abandon "$_slug" \
                "закрыть брошенное расследование «$_slug» ($_age дн. без исхода) — в архив с пометкой"
        fi
    done

    # Исполненные и не запечатанные задачи. Гейт остаётся гейтом: он проверит отчёт о
    # фундаменте и откажет, если его нет. Отказ — это ответ, а не сбой чистки.
    # Обход без пайпа: `while read` за конвейером живёт в подоболочке, и всё, что он
    # добавил бы в план, исчезло бы вместе с ней. Ни одного временного файла в чужом
    # проекте чистка при этом не создаёт.
    _clean_ifs=$IFS; IFS='
'
    for _line in $WM_TASKS; do
        _slug=${_line%%	*}; _state=${_line##*	}
        [ "$_state" = done ] || continue
        clean_add task-seal "$_slug" "запечатать исполненную задачу «$_slug»"
    done
    IFS=$_clean_ifs

    # Несохранённый фундамент. Сохраняются ровно те пути, которые считает сторож, — у
    # чистки, как и у глагола, нет режима «сохрани всё» (B6).
    if verb_is_git "$_root" && config_is_on check_dirty "$_root"; then
        _dirty=$(clean_dirty_paths "$_root")
        [ -n "$_dirty" ] && clean_add commit "$_dirty" \
            "сохранить точкой изменённые файлы фундамента и ai/"
    fi
    return 0
}

clean_dirty_paths() {
    _root=$1
    {
        git -C "$_root" status --porcelain --untracked-files=normal -- \
            ARCHITECTURE.md CONVENTIONS.md DECISIONS.md README.md \
            AGENTS.md CLAUDE.md ai/archive 2>/dev/null
        git -C "$_root" status --porcelain --untracked-files=no -- \
            ai/tasks STACK.md 2>/dev/null
    } | sed 's/^...//' | sed 's/^.* -> //' | sort -u | tr '\n' ' '
}

clean_show() {
    if [ "$CLEAN_N" -eq 0 ]; then
        ok "чистить нечего"
        return 1
    fi
    say "${C_BLD}Чистка сделает $CLEAN_N $(wm_plural "$CLEAN_N" действие действия действий):${C_OFF}"
    _clean_ifs=$IFS; IFS='
'
    for _line in $CLEAN_PLAN; do
        [ -n "$_line" ] || continue
        printf '  · %s\n' "${_line##*	}"
    done
    IFS=$_clean_ifs
    say ""
    dim "  не трогает: протухшие планы, очередь, дрейф фундамента, отправку копии —"
    dim "  там нужно суждение, и это работа для /revise-task, /run-task и /prune."
    return 0
}

# Закрыть расследование, которое бросили. Запись честная: не «сделано», а «закрыто чисткой,
# исхода нет, уборка не проверялась». Архив обязан говорить правду — на этом стоит вся
# ценность архива, и молчаливое удаление папки её уничтожает.
clean_investigate_abandon() {
    _root=$1; _slug=$2
    _dir="$_root/ai/investigations/$_slug"
    _f="$_dir/findings.md"
    [ -f "$_f" ] || return 1
    _age=$(wm_days_since "$(wm_mtime "$_f")")
    {
        printf '\n## Abandoned\n'
        printf -- '- Закрыто чисткой %s: исход не записан, расследование не двигалось %s %s.\n' \
            "$(date +%Y-%m-%d)" "$_age" "$(wm_plural "$_age" день дня дней)"
        printf -- '- Уборка не проверялась: раздел «## Restored to baseline» остался незаполненным.\n'
        printf -- '- Это не диагноз и не тупик. Если вопрос ещё жив — заводи расследование заново.\n'
    } >> "$_f" || return 1
    verb_archive "$_root" "$_dir" "investigate_$_slug" abandon "investigate $_slug — брошено"
}

clean_apply() {
    _root=$1
    _done=0; _refused=0
    _clean_ifs=$IFS; IFS='
'
    for _line in $CLEAN_PLAN; do
        [ -n "$_line" ] || continue
        IFS=$_clean_ifs
        _op=${_line%%	*}
        _rest=${_line#*	}
        _arg=${_rest%%	*}
        _text=${_rest#*	}
        say ""
        say "${C_BLD}→ $_text${C_OFF}"
        case $_op in
            upgrade)
                if ( scaffold_run "$_root" >/dev/null 2>&1 && scaffold_sections "$_root" >/dev/null 2>&1 ); then
                    verb_commit "$_root" upgrade "фундамент доведён до стандарта" \
                        README.md ARCHITECTURE.md CONVENTIONS.md DECISIONS.md \
                        AGENTS.md CLAUDE.md .gitignore ai >/dev/null 2>&1
                    _done=$((_done + 1)); ok "готово"
                else
                    _refused=$((_refused + 1)); warn "не удалось"
                fi ;;
            investigate-seal)
                if ( verb_investigate_seal "$_root" "$_arg" ); then _done=$((_done + 1))
                else _refused=$((_refused + 1)); dim "  гейт отказал — это ответ, а не сбой: доведи расследование до исхода"; fi ;;
            investigate-abandon)
                if ( clean_investigate_abandon "$_root" "$_arg" ); then _done=$((_done + 1))
                else _refused=$((_refused + 1)); warn "не удалось закрыть «$_arg»"; fi ;;
            task-seal)
                if ( verb_task_seal "$_root" "$_arg" ); then _done=$((_done + 1))
                else _refused=$((_refused + 1)); dim "  гейт отказал — это ответ: допиши отчёт и запусти чистку снова"; fi ;;
            commit)
                # shellcheck disable=SC2086
                if ( verb_commit "$_root" fix "чистка: сохранены изменения фундамента и ai/" $_arg ); then
                    _done=$((_done + 1))
                else _refused=$((_refused + 1)); warn "не удалось сохранить"; fi ;;
        esac
        IFS='
'
    done
    IFS=$_clean_ifs
    say ""
    ok "сделано: $_done"
    [ "$_refused" -gt 0 ] && dim "  осталось требующего тебя: $_refused"
    return 0
}
