#!/bin/sh
# update.sh — "has a new version arrived" and "bring it in".
#
# We always had updating, but it was spelled as two lines one had to remember:
# `sh ~/.fraim/src/installer/install.sh` (bring in the sources) and then
# `fraim init` (lay them out across the harnesses). Skipping the second left the human
# in the nastiest of states: `fraim version` shows the new one, while the agent reads
# the old procedures from disk.
#
# There are two actions here, and they are different on purpose:
#
#   DETECTION   update_probe   — go to the network, compare sha, write the verdict to the cache
#   ACTION      update_apply   — bring in and lay out
#
# They are not separated for looks. The whole system stands on D4: detection runs on a
# schedule, work is started by the human. So neither `fraim status` nor the watchman goes to
# the network — they read the CACHE, a file, offline and deterministically. The network is
# touched only by commands the human typed themselves: `fraim update`, `fraim doctor` and
# `fraim init`.
#
# There is no implementation of our own of "bring in the sources" here: install.sh does it,
# and it stays the only one (B2). update_apply is what runs it.

# The check cache: one line `<time> <local sha> <remote sha> <status>`.
# Status is behind | current | ahead | unknown. Two of the four exist for honesty:
# `unknown` is distinct from "never checked" (no file at all), because the silence of the
# network must not look like health (D1); `ahead` — because "our sha is not the host's" and
# "the host has something new" are different statements, and for someone editing the system
# locally the first is true all the time.
update_cache_file() { printf '%s/update-check\n' "$FRAIM_HOME"; }

update_cache_read() { cat "$(update_cache_file)" 2>/dev/null; }

update_cache_field() { update_cache_read | awk -v n="$1" '{ print $n }'; }

# The verdict of the last check: behind | current | ahead | unknown, or empty if never
# checked. Everything that decides how to display decides by it, not by the presence of
# text: the same line can be an alarm or just a note.
update_state() { update_cache_field 4; }

# The source directory being updated is the one we are running from right now.
# It counts as updatable only if it is a git clone with an origin: a dev copy laid
# out by hand is not subject to updating, and there is no need to lie about it.
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

# Network with a time ceiling. `timeout` is not everywhere (macOS without coreutils), so it
# is used if found, and is not replaced by a home-made watchdog over background processes:
# an unreachable network will hit git's own timeout anyway.
update_run_bounded() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "${FRAIM_NET_TIMEOUT:-10}" "$@"
    else
        "$@"
    fi
}

# Go to the network and write the result to the cache. Returns 0 if the check succeeded
# (no matter whether we are behind or not), and 1 if the network/repository did not answer.
update_probe() {
    _u_src=$(update_src)
    update_src_is_clone "$_u_src" || return 1
    _u_branch=$(update_branch "$_u_src")
    _u_local=$(git -C "$_u_src" rev-parse HEAD 2>/dev/null)
    mkdir -p "$FRAIM_HOME" 2>/dev/null || :

    # GIT_TERMINAL_PROMPT=0: a private repository without ready credentials must answer
    # with a refusal, not hang someone else's command on a login prompt.
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
        # We already have the host's commit, and it is behind our HEAD. This is not lagging,
        # it is work on the system itself: telling such a person to update would be a lie.
        _u_state=ahead
    else
        _u_state=behind
    fi
    printf '%s %s %s %s\n' "$(date +%s)" "$_u_local" "$_u_remote" "$_u_state" > "$(update_cache_file)"
    return 0
}

# Is the cache stale? An empty cache counts as stale — checking has not started yet.
update_cache_stale() {
    _u_when=$(update_cache_field 1)
    [ -n "$_u_when" ] || return 0
    _u_days=$(config_get update_check_days)
    _u_age=$(( $(date +%s) - _u_when ))
    [ "$_u_age" -ge $(( _u_days * 86400 )) ]
}

# Check, if it is time and if checking is enabled at all. Quietly: background, not a command.
update_probe_if_due() {
    config_is_on update_check || return 0
    update_cache_stale || return 0
    update_probe >/dev/null 2>&1 || :
    return 0
}

# One line about the state of the installation — or nothing, if there is nothing to say (D2).
# Reads only the cache: no network, no delay.
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

# Bring in and lay out. The sources are fetched by install.sh — it alone knows how, and it
# also knows about a branch change. Then exec into the new binary: continuing in this process
# is not allowed, we have already read the old lib/, and the new ones are on disk.
update_apply() {
    _u_src=$(update_src)
    # install.sh updates exactly `$FRAIM_HOME/src` — that is written in it, and it is the
    # source of truth about the installation. If we are not running from there (a dev copy
    # cloned for oneself), updating it with this command would mean updating SOMEONE ELSE'S
    # directory and reporting as if what the human launched us from had been updated.
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
    # The cache belonged to the previous installation.
    rm -f "$(update_cache_file)" 2>/dev/null || :
    return 0
}
