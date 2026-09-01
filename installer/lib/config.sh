#!/bin/sh
# config.sh — settings on two levels, and the ability to say where a value came from.
#
#   default        baked in here
#   machine        ~/.fraim/config       — per machine, not in git
#   project        ai/fraim.conf         — travels with the repository
#
# Project beats machine beats default. The point of `fraim config` is not to show a file
# but to answer "what is in effect right now, and who set it" — that is what makes
# settings legible to someone who did not write them.
#
# Format is `key = value`, one per line, `#` comments. Deliberately not JSON or YAML:
# it must stay editable by hand and parsable without a dependency.

# key|default|description
config_table() {
    cat <<'TBL'
foundation_lag_commits|10|Сколько коммитов кода без обновления ARCHITECTURE.md считать дрейфом
stale_plan_commits|1|Сколько коммитов вперёд делают план протухшим
lessons_lag_commits|25|Сколько коммитов кода без единой записи в Known Pitfalls считать потерей уроков
unpushed_threshold|5|Сколько точек сохранения без удалённой копии считать проблемой
check_blockers|on|Проверять заблокированные задачи
check_stale_plans|on|Проверять протухшие планы
check_plan_version|on|Проверять планы, написанные другой версией fraim
check_plan_retelling|on|Проверять планы, пересказывающие код вместо ссылок на него
check_unsealed|on|Проверять исполненные, но не запечатанные задачи
check_investigations|on|Проверять расследования без исхода и незаархивированные
check_git|on|Проверять, что репозиторий есть — без него нет точек сохранения
check_remote|on|Проверять, что точки сохранения уезжают с этой машины
check_dirty|on|Проверять несохранённые изменения фундамента и ai/
check_foundation|on|Проверять отставание фундамента от кода
check_lessons|on|Проверять, возвращаются ли грабли в CONVENTIONS.md
commit_verbs|on|Детерминированные глаголы делают коммит сами
TBL
}

config_machine_file() { printf '%s/config\n' "$FRAIM_HOME"; }
config_project_file() { printf '%s/ai/fraim.conf\n' "$1"; }

config_default() { config_table | awk -F'|' -v k="$1" '$1 == k { print $2; exit }'; }
config_describe() { config_table | awk -F'|' -v k="$1" '$1 == k { print $3; exit }'; }
config_known()   { config_table | cut -d'|' -f1 | grep -qx "$1"; }

# Read one key from one file. Empty output means "not set here".
config_read_file() {
    _f=$1; _k=$2
    [ -f "$_f" ] || return 0
    sed -n "s/^[[:space:]]*$_k[[:space:]]*=[[:space:]]*//p" "$_f" 2>/dev/null |
        sed 's/[[:space:]]*$//; s/[[:space:]]*#.*$//' | head -1
}

# The effective value. Project wins, then machine, then the built-in default.
config_get() {
    _root=${2:-}; _k=$1
    if [ -n "$_root" ]; then
        _v=$(config_read_file "$(config_project_file "$_root")" "$_k")
        [ -n "$_v" ] && { printf '%s\n' "$_v"; return; }
    fi
    _v=$(config_read_file "$(config_machine_file)" "$_k")
    [ -n "$_v" ] && { printf '%s\n' "$_v"; return; }
    config_default "$_k"
}

# Where the effective value came from: project path, machine, or default.
config_source() {
    _root=${2:-}; _k=$1
    if [ -n "$_root" ] && [ -n "$(config_read_file "$(config_project_file "$_root")" "$_k")" ]; then
        printf 'ai/fraim.conf\n'; return
    fi
    if [ -n "$(config_read_file "$(config_machine_file)" "$_k")" ]; then
        printf '~/.fraim/config\n'; return
    fi
    printf 'по умолчанию\n'
}

config_is_on() { [ "$(config_get "$1" "${2:-}")" = on ]; }

# Write a key into one of the two files, replacing any existing line.
config_set_file() {
    _f=$1; _k=$2; _v=$3
    mkdir -p "$(dirname -- "$_f")" || return 1
    [ -f "$_f" ] || printf '# fraim settings — see `fraim config`\n' > "$_f"
    _tmp="$_f.fraim.$$"
    grep -v "^[[:space:]]*$_k[[:space:]]*=" "$_f" > "$_tmp" 2>/dev/null || : > "$_tmp"
    printf '%s = %s\n' "$_k" "$_v" >> "$_tmp"
    mv "$_tmp" "$_f"
}
