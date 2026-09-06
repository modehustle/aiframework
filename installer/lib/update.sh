#!/bin/sh
# update.sh — «приехала ли новая версия» и «привези её».
#
# Обновление у нас всегда было, но называлось двумя строчками, которые надо
# помнить: `sh ~/.fraim/src/installer/install.sh` (привезти исходники) и потом
# `fraim init` (разложить их по харнесам). Пропустив вторую, человек получал
# самое неприятное из состояний: `fraim version` показывает новое, а агент
# читает старые процедуры с диска.
#
# Здесь два действия, и они намеренно разные:
#
#   ОБНАРУЖЕНИЕ  update_probe   — сходить в сеть, сверить sha, записать вердикт в кэш
#   ДЕЙСТВИЕ     update_apply   — привезти и разложить
#
# Разделены они не для красоты. Вся система стоит на D4: по расписанию работает
# обнаружение, работу начинает человек. Поэтому в сеть не ходит ни `fraim status`,
# ни сторож — они читают КЭШ, файл, оффлайн и детерминированно. Сеть трогают только те
# команды, которые человек набрал сам: `fraim update`, `fraim doctor` и `fraim init`.
#
# Своей реализации «привезти исходники» здесь нет: это делает install.sh, и он
# остаётся единственной (B2). update_apply его и запускает.

# Кэш проверки: одна строка `<время> <локальный sha> <удалённый sha> <статус>`.
# Статус — behind | current | ahead | unknown. Два из четырёх заведены ради честности:
# `unknown` отличим от «не проверяли ни разу» (файла нет вовсе), потому что молчание сети
# не должно выглядеть как здоровье (D1); `ahead` — потому что «наш sha не равен хостовому»
# и «на хосте есть новое» это разные утверждения, и у того, кто правит систему у себя,
# первое верно постоянно.
update_cache_file() { printf '%s/update-check\n' "$FRAIM_HOME"; }

update_cache_read() { cat "$(update_cache_file)" 2>/dev/null; }

update_cache_field() { update_cache_read | awk -v n="$1" '{ print $n }'; }

# Вердикт последней проверки: behind | current | ahead | unknown, или пусто, если
# не проверяли ни разу. Всё, что решает, как показывать, решает по нему, а не по
# наличию текста: одна и та же строка бывает и тревогой, и просто справкой.
update_state() { update_cache_field 4; }

# Каталог исходников, который обновляется, — тот, откуда мы сейчас работаем.
# Обновляемым он считается, только если это git-клон с origin: dev-копия,
# разложенная руками, обновлению не подлежит, и врать об этом не надо.
update_src() { fraim_root 2>/dev/null; }

update_src_is_clone() {
    _u_src=${1:-$(update_src)}
    [ -n "$_u_src" ] || return 1
    git -C "$_u_src" rev-parse --git-dir >/dev/null 2>&1 || return 1
    git -C "$_u_src" remote get-url origin >/dev/null 2>&1
}

update_branch() {
    _u_src=${1:-$(update_src)}
    _u_b=$(git -C "$_u_src" rev-parse --abbrev-ref HEAD 2>/dev/null)
    [ -n "$_u_b" ] && [ "$_u_b" != HEAD ] || _u_b=${FRAIM_BRANCH:-main}
    printf '%s\n' "$_u_b"
}

# Сеть с потолком по времени. `timeout` есть не везде (macOS без coreutils), поэтому
# он используется, если найден, и не подменяется самодельным сторожем на фоновых
# процессах: недоступная сеть и так упрётся в собственный таймаут git.
update_run_bounded() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "${FRAIM_NET_TIMEOUT:-10}" "$@"
    else
        "$@"
    fi
}

# Сходить в сеть и записать результат в кэш. Возвращает 0, если проверка удалась
# (неважно, отстали мы или нет), и 1, если сеть/репозиторий не ответили.
update_probe() {
    _u_src=$(update_src)
    update_src_is_clone "$_u_src" || return 1
    _u_branch=$(update_branch "$_u_src")
    _u_local=$(git -C "$_u_src" rev-parse HEAD 2>/dev/null)
    mkdir -p "$FRAIM_HOME" 2>/dev/null || :

    # GIT_TERMINAL_PROMPT=0: приватный репозиторий без готовых доступов должен
    # ответить отказом, а не подвесить чужую команду на запросе логина.
    _u_remote=$(GIT_TERMINAL_PROMPT=0 update_run_bounded \
        git -C "$_u_src" ls-remote origin "refs/heads/$_u_branch" 2>/dev/null | cut -f1)

    if [ -z "$_u_remote" ]; then
        printf '%s %s %s %s\n' "$(date +%s)" "$_u_local" "-" "unknown" > "$(update_cache_file)"
        return 1
    fi
    if [ "$_u_remote" = "$_u_local" ]; then
        _u_state=current
    elif git -C "$_u_src" cat-file -e "$_u_remote^{commit}" 2>/dev/null &&
         git -C "$_u_src" merge-base --is-ancestor "$_u_remote" HEAD 2>/dev/null; then
        # Хостовый коммит у нас уже есть, и он позади нашего HEAD. Это не отставание,
        # это работа над самой системой: звать такого человека обновляться — враньё.
        _u_state=ahead
    else
        _u_state=behind
    fi
    printf '%s %s %s %s\n' "$(date +%s)" "$_u_local" "$_u_remote" "$_u_state" > "$(update_cache_file)"
    return 0
}

# Кэш протух? Пустой кэш считается протухшим — проверять ещё не начинали.
update_cache_stale() {
    _u_when=$(update_cache_field 1)
    [ -n "$_u_when" ] || return 0
    _u_days=$(config_get update_check_days)
    _u_age=$(( $(date +%s) - _u_when ))
    [ "$_u_age" -ge $(( _u_days * 86400 )) ]
}

# Проверить, если пора и если проверка вообще включена. Тихо: это фон, а не команда.
update_probe_if_due() {
    config_is_on update_check || return 0
    update_cache_stale || return 0
    update_probe >/dev/null 2>&1 || :
    return 0
}

# Одна строка о состоянии установки — или ничего, если сказать нечего (D2).
# Читает только кэш: ни сети, ни задержки.
update_line() {
    case $(update_cache_field 4) in
        behind)
            printf 'новая версия fraim на хосте (%s) — fraim update\n' \
                "$(update_cache_field 3 | cut -c1-7)" ;;
        ahead)
            printf 'локальная копия впереди хоста — обновлять нечего\n' ;;
        unknown)
            printf 'проверить обновления не удалось — хост не ответил\n' ;;
        *) return 1 ;;
    esac
}

# Привезти и разложить. Исходники тянет install.sh — он один это умеет, и он же
# знает про смену ветки. Дальше exec на новый бинарник: продолжать в этом процессе
# нельзя, мы уже прочитали старые lib/, а на диске лежат новые.
update_apply() {
    _u_src=$(update_src)
    # install.sh обновляет ровно `$FRAIM_HOME/src` — это записано в нём, и он источник
    # правды об установке. Если мы работаем не оттуда (dev-копия, склонированная себе),
    # то обновлять её этой командой значило бы обновить ЧУЖОЙ каталог и отчитаться так,
    # будто обновилось то, из чего человек нас запустил.
    if [ "$_u_src" != "$FRAIM_HOME/src" ]; then
        warn "запущено из $_u_src, а обновление живёт в $FRAIM_HOME/src"
        dim "    это копия для работы над самой системой — обнови её как обычно"
        dim "    (git pull), потом fraim init, чтобы разложить по харнесам"
        return 1
    fi
    update_src_is_clone "$_u_src" || {
        warn "источник $_u_src — не git-клон, обновлять нечего"
        dim "    так бывает у копии, разложенной руками: обнови её тем же способом,"
        dim "    которым ставил, и запусти fraim init"
        return 1
    }
    _u_installer="$_u_src/installer/install.sh"
    [ -f "$_u_installer" ] || { warn "не найден $_u_installer"; return 1; }

    FRAIM_BRANCH=${FRAIM_BRANCH:-$(update_branch "$_u_src")} sh "$_u_installer" || {
        warn "не удалось обновить исходники"
        return 1
    }
    # Кэш относился к прошлой установке.
    rm -f "$(update_cache_file)" 2>/dev/null || :
    return 0
}
