#!/bin/sh
# watchman.sh — the deterministic verdict on one project.
#
# Reads files, git log and mtimes. No model, no network, nothing written.
# That is the whole point: detection is cheap enough to run on a schedule,
# while every action it suggests still starts with a human.
#
# Contract (SCHEDULING.md):
#   exit 0 — healthy
#   exit 1 — something needs the human
#   exit 2 — not a project under the system

# Findings accumulate as tab-separated records: id \t severity \t message \t action
WM_FINDINGS=

wm_add() {
    _rec=$(printf '%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4")
    if [ -z "$WM_FINDINGS" ]; then WM_FINDINGS=$_rec
    else WM_FINDINGS=$(printf '%s\n%s' "$WM_FINDINGS" "$_rec"); fi
}

# --- portability helpers ----------------------------------------------------
wm_mtime() { stat -c %Y -- "$1" 2>/dev/null || stat -f %m -- "$1" 2>/dev/null; }
wm_now()   { date +%s; }
wm_days_since() { _t=$1; [ -n "$_t" ] || { printf '0\n'; return; }; printf '%s\n' "$(( ( $(wm_now) - _t ) / 86400 ))"; }

wm_is_git() { git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }

# Russian plurals: 1 хотфикс, 2 хотфикса, 5 хотфиксов. The verdict is read
# daily, so getting this wrong is a small papercut repeated forever.
wm_plural() {
    _n=$1; _one=$2; _few=$3; _many=$4
    _mod100=$(( _n % 100 ))
    if [ "$_mod100" -ge 11 ] && [ "$_mod100" -le 14 ]; then printf '%s\n' "$_many"; return; fi
    case $(( _n % 10 )) in
        1) printf '%s\n' "$_one" ;;
        2|3|4) printf '%s\n' "$_few" ;;
        *) printf '%s\n' "$_many" ;;
    esac
}

# Pad to a column width in CHARACTERS. printf's %-Ns counts bytes, and every
# Cyrillic character is two of them, so byte padding shears the columns apart.
wm_pad() {
    _s=$1; _w=$2
    _len=$(printf '%s' "$_s" | wc -m | tr -d ' ')
    printf '%s' "$_s"
    while [ "$_len" -lt "$_w" ]; do printf ' '; _len=$((_len + 1)); done
}

# --- the checks -------------------------------------------------------------

# 1. Drift: hotfix entries logged since the last /prune marker.
wm_check_drift() {
    _root=$1
    _log="$_root/ai/hotfix_log.md"
    [ -f "$_log" ] || return 0
    _threshold=$(config_get hotfix_threshold "$_root")

    # Entries after the LAST `--- pruned <date> ---` marker; an entry is a
    # list item, so blank lines and prose in the log do not inflate the count.
    _count=$(awk '
        /^--- pruned .* ---[[:space:]]*$/ { n = 0; next }
        /^-[[:space:]]/                   { n++ }
        END { print n + 0 }
    ' "$_log")

    if [ "$_count" -ge "$_threshold" ]; then
        _w=$(wm_plural "$_count" хотфикс хотфикса хотфиксов)
        wm_add drift attention "$_count $_w с последнего прунинга (порог $_threshold)" "/prune"
    elif [ "$_count" -gt 0 ]; then
        _w=$(wm_plural "$_count" хотфикс хотфикса хотфиксов)
        wm_add drift info "$_count $_w с последнего прунинга (порог $_threshold)" ""
    fi
}

# 2. Blockers: the executor refused a plan and stopped. Nothing moves until
#    the planner repairs it, so age matters more than count.
wm_check_blockers() {
    _root=$1
    [ -d "$_root/ai/tasks" ] || return 0
    for _b in "$_root"/ai/tasks/*/blockers.md; do
        [ -f "$_b" ] || continue
        _slug=$(basename -- "$(dirname -- "$_b")")
        _days=$(wm_days_since "$(wm_mtime "$_b")")
        if [ "$_days" -eq 0 ]; then
            _age="сегодня"
        else
            _age="$_days $(wm_plural "$_days" день дня дней) назад"
        fi
        wm_add blocker attention "задача «$_slug» заблокирована $_age" "/revise-task"
    done
}

# 3. Stale plan: the queue moved on while the plan sat in it. `Based on` is the
#    snapshot make-task wrote; if HEAD has since moved, the executor would be
#    working against a codebase the plan never saw.
wm_check_stale_plans() {
    _root=$1
    [ -d "$_root/ai/tasks" ] || return 0
    wm_is_git "$_root" || return 0
    for _c in "$_root"/ai/tasks/*/context.md; do
        [ -f "$_c" ] || continue
        _slug=$(basename -- "$(dirname -- "$_c")")
        # Pull the first 7+ hex chars off the `Based on:` line.
        _ref=$(sed -n 's/^-\{0,1\}[[:space:]]*Based on:.*/&/p' "$_c" | head -1 |
               grep -oE '[0-9a-f]{7,40}' | head -1)
        [ -n "$_ref" ] || continue
        git -C "$_root" cat-file -e "$_ref^{commit}" 2>/dev/null || continue
        _behind=$(git -C "$_root" rev-list --count "$_ref"..HEAD 2>/dev/null) || continue
        [ -n "$_behind" ] || continue
        _min=$(config_get stale_plan_commits "$_root")
        if [ "$_behind" -ge "$_min" ] && [ "$_behind" -gt 0 ]; then
            _w=$(wm_plural "$_behind" коммит коммита коммитов)
            wm_add stale-plan attention "план «$_slug» отстал от HEAD на $_behind $_w" "/revise-task"
        fi
    done
}

# 4. Version drift of the system itself: a plan written by an older make-task
#    would otherwise be executed silently by a newer run-task.
wm_check_plan_version() {
    _root=$1
    [ -d "$_root/ai/tasks" ] || return 0
    _installed=$(fraim_version)
    [ "$_installed" = unknown ] && return 0
    for _c in "$_root"/ai/tasks/*/context.md; do
        [ -f "$_c" ] || continue
        _slug=$(basename -- "$(dirname -- "$_c")")
        _pv=$(sed -n 's/^[-[:space:]]*System:[[:space:]]*fraim[[:space:]]*//p' "$_c" | head -1 | tr -d ' \r')
        [ -n "$_pv" ] || continue
        [ "$_pv" = "$_installed" ] && continue
        wm_add plan-version attention "план «$_slug» написан fraim $_pv, установлен $_installed" "/revise-task"
    done
}

# 5. Queue depth. Informational — a full queue is normal, an empty one is too.
wm_check_queue() {
    _root=$1
    [ -d "$_root/ai/tasks" ] || return 0
    _n=0
    for _t in "$_root"/ai/tasks/*/task.md; do
        [ -f "$_t" ] || continue
        _n=$((_n + 1))
    done
    if [ "$_n" -gt 0 ]; then
        wm_add queue info "$_n $(wm_plural "$_n" задача задачи задач) в очереди" "/run-task"
    fi
    return 0
}

# 6. Foundation freshness: has the code moved since ARCHITECTURE.md last did?
#    Commit time, not mtime, when git is available — a fresh clone rewrites
#    every mtime and would otherwise report the whole foundation as current.
wm_check_foundation() {
    _root=$1
    _arch="$_root/ARCHITECTURE.md"
    if [ ! -f "$_arch" ]; then
        wm_add foundation attention "нет ARCHITECTURE.md — фундамент не заложен" "/onboard"
        return 0
    fi
    # A scaffolded file is not a filled one. Without this distinction an empty skeleton
    # would report the project as healthy, which is worse than having no files at all:
    # the agent reads ARCHITECTURE.md, finds nothing, and goes back to guessing.
    _stubs=
    for _f in README.md ARCHITECTURE.md CONVENTIONS.md DECISIONS.md; do
        if scaffold_is_stub "$_root/$_f"; then _stubs="$_stubs $_f"; fi
    done
    if [ -n "$_stubs" ]; then
        _n=$(printf '%s' "$_stubs" | wc -w | tr -d ' ')
        wm_add foundation attention \
            "скелет развёрнут, но не заполнен: $_n $(wm_plural "$_n" файл файла файлов) —$_stubs" \
            "/bootstrap или /onboard"
        return 0
    fi
    wm_is_git "$_root" || return 0

    _arch_t=$(git -C "$_root" log -1 --format=%ct -- ARCHITECTURE.md 2>/dev/null)
    [ -n "$_arch_t" ] || _arch_t=$(wm_mtime "$_arch")
    _code_t=$(git -C "$_root" log -1 --format=%ct -- ':!*.md' 2>/dev/null)
    [ -n "$_code_t" ] || return 0
    [ -n "$_arch_t" ] || return 0

    if [ "$_code_t" -gt "$_arch_t" ]; then
        _gap=$(( (_code_t - _arch_t) / 86400 ))
        # A day or two of lag is just the normal order of a commit. Weeks is drift.
        _max=$(config_get foundation_lag_days "$_root")
        if [ "$_gap" -ge "$_max" ]; then
            _w=$(wm_plural "$_gap" день дня дней)
            wm_add foundation attention "ARCHITECTURE.md отстаёт от кода на $_gap $_w" "/prune"
        fi
    fi
    return 0
}

# --- entry point ------------------------------------------------------------

# Is this project under the system at all? Missing ai/ AND missing foundation
# means it was never bootstrapped or onboarded — that is exit 2, a broken
# contour, not a finding.
wm_managed() {
    _root=$1
    [ -d "$_root/ai" ] && return 0
    [ -f "$_root/ARCHITECTURE.md" ] && return 0
    return 1
}

wm_run() {
    _root=$1
    WM_FINDINGS=
    config_is_on check_drift        "$_root" && wm_check_drift "$_root"
    config_is_on check_blockers     "$_root" && wm_check_blockers "$_root"
    config_is_on check_stale_plans  "$_root" && wm_check_stale_plans "$_root"
    config_is_on check_plan_version "$_root" && wm_check_plan_version "$_root"
    wm_check_queue "$_root"
    config_is_on check_foundation   "$_root" && wm_check_foundation "$_root"
    return 0
}

wm_has_attention() {
    [ -n "$WM_FINDINGS" ] || return 1
    printf '%s\n' "$WM_FINDINGS" | cut -f2 | grep -qx attention
}

wm_report_human() {
    _root=$1
    _name=$(basename -- "$_root")
    if [ -z "$WM_FINDINGS" ]; then
        ok "$_name — всё чисто"
        return
    fi
    printf '%s%s%s\n' "$C_BLD" "$_name" "$C_OFF"
    printf '%s\n' "$WM_FINDINGS" | while IFS='	' read -r _id _sev _msg _act; do
        [ -n "$_id" ] || continue
        if [ "$_sev" = attention ]; then _mark="$C_YEL!$C_OFF"; else _mark="$C_DIM·$C_OFF"; fi
        if [ -n "$_act" ]; then
            printf '  %s %s %s→ %s%s\n' "$_mark" "$(wm_pad "$_msg" 56)" "$C_DIM" "$_act" "$C_OFF"
        else
            printf '  %s %s\n' "$_mark" "$_msg"
        fi
    done
}

wm_json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

wm_report_json() {
    _root=$1
    _status=healthy
    wm_has_attention && _status=attention
    printf '{\n'
    printf '  "project": "%s",\n' "$(wm_json_escape "$_root")"
    printf '  "status": "%s",\n' "$_status"
    printf '  "version": "%s",\n' "$(fraim_version)"
    printf '  "findings": ['
    if [ -z "$WM_FINDINGS" ]; then
        printf ']\n}\n'
        return
    fi
    printf '\n'
    _first=1
    printf '%s\n' "$WM_FINDINGS" | while IFS='	' read -r _id _sev _msg _act; do
        [ -n "$_id" ] || continue
        [ "$_first" = 1 ] || printf ',\n'
        _first=0
        printf '    { "id": "%s", "severity": "%s", "message": "%s", "action": "%s" }' \
            "$_id" "$_sev" "$(wm_json_escape "$_msg")" "$(wm_json_escape "$_act")"
    done
    printf '\n  ]\n}\n'
}
