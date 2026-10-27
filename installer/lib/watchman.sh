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

# Commits touching anything but markdown, since a given commit (or all of them).
wm_code_commits_since() {
    _root=$1; _from=$2
    if [ -n "$_from" ]; then
        git -C "$_root" rev-list --count "$_from..HEAD" -- ':!*.md' 2>/dev/null
    else
        git -C "$_root" rev-list --count HEAD -- ':!*.md' 2>/dev/null
    fi
}

# Russian plurals: "hotfix" takes three forms — after 1, after 2 and after 5. The verdict is read
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
    _len=$(str_len "$_s")
    printf '%s' "$_s"
    while [ "$_len" -lt "$_w" ]; do printf ' '; _len=$((_len + 1)); done
}

# --- the checks -------------------------------------------------------------

# 1. Drift used to be counted here, as hotfix entries since the last /prune marker. It is
#    gone with /hotfix itself: the metric only ever saw work that went through that one
#    procedure, while `wm_check_foundation` below counts code commits since ARCHITECTURE.md
#    last moved — the same signal, measured over every mode of work including the reactive
#    one. Two drift metrics where one is a strict subset of the other is not redundancy,
#    it is a second number to keep honest.

# 2–4b. Blockers, stale plans, plans written by another release, plans retelling the code,
#       executed-but-unsealed tasks: all gone with the plan itself. A task is a card that
#       carries an intent and no snapshot of the code, so there is nothing in it to go
#       stale, to block on, or to seal behind a gate (tasks.sh).

# The freshest mtime in a folder: the folder itself, and everything one level inside it.
# A directory's own mtime moves only when entries are added or removed, so a folder whose
# one file is edited every day reads as untouched for a month — and «untouched for a month»
# is exactly what decides whether the cleanup may archive it.
wm_newest_mtime() {
    _wnm_dir=$1
    _wnm_best=$(wm_mtime "$_wnm_dir")
    for _wnm_e in "$_wnm_dir"/* "$_wnm_dir"/.[!.]*; do
        [ -e "$_wnm_e" ] || continue
        _wnm_m=$(wm_mtime "$_wnm_e")
        case $_wnm_m in ''|*[!0-9]*) continue ;; esac
        [ "$_wnm_m" -gt "${_wnm_best:-0}" ] && _wnm_best=$_wnm_m
    done
    printf '%s\n' "${_wnm_best:-}"
}

# 4c. Investigations: a folder that never landed on an outcome, or landed and stayed.
#     This is the terminal state /investigate never had — its folders grew forever.
#
#     The walk is over FOLDERS, not over findings.md. It used to be over the file, and a
#     folder without one was therefore invisible to the verdict and to the cleanup alike:
#     it survived every `fraim clean` and nothing ever said why. A folder with no report
#     is not a healthy state — it is the one investigation state with nothing at all to
#     show for itself.
wm_check_investigations() {
    _root=$1
    [ -d "$_root/ai/investigations" ] || return 0
    for _dir in "$_root"/ai/investigations/*/; do
        [ -d "$_dir" ] || continue
        _slug=$(basename -- "$_dir")
        _f="$_dir/findings.md"
        if [ ! -f "$_f" ]; then
            _days=$(wm_days_since "$(wm_newest_mtime "$_dir")")
            wm_add investigation attention \
                "расследование «$_slug» без findings.md — ни исхода, ни отчёта об уборке ($_days $(wm_plural "$_days" день дня дней))" \
                "/investigate или fraim clean"
            continue
        fi
        _days=$(wm_days_since "$(wm_mtime "$_f")")
        if verb_section_filled "$_f" '### DIAGNOSIS' || verb_section_filled "$_f" '### DEAD-END'; then
            wm_add investigation attention "расследование «$_slug» закончено и не заархивировано" \
                "fraim investigate-seal $_slug"
        elif [ "$_days" -ge 7 ]; then
            wm_add investigation attention \
                "расследование «$_slug» открыто $_days $(wm_plural "$_days" день дня дней) без исхода" "/investigate"
        else
            wm_add investigation info "расследование «$_slug» в работе" ""
        fi
    done
    return 0
}

# 4d. No save points at all. Every save point in this system is a commit, so a project
#     without a repository is a project where nothing can be undone — and nobody said so.
wm_check_git() {
    _root=$1
    if ! command -v git >/dev/null 2>&1; then
        wm_add git attention "git не установлен — точек сохранения нет" "установи git"
        return 0
    fi
    wm_is_git "$_root" ||
        wm_add git attention "нет репозитория — точек сохранения нет" "fraim scaffold"
    return 0
}

# 4d-bis. Save points that never left this machine.
#
#     Not a backup check — the system deliberately makes no promise about backups, and the
#     history carries code and decisions, never data or secrets. This is about REACH: the
#     product's promise is that you can re-enter a project with full context, and re-entering
#     increasingly means from somewhere else — a web session, a cloud agent, CI, a second
#     machine. All of them start by cloning. A foundation that never left this disk does not
#     exist for any of them.
#
#     Detection only, per D4 — and that has not changed now that `fraim publish` exists. The
#     watchman names the command; it never runs it. Choosing a host, private or public, and
#     authorising it is a fork with real content in it, and the answer belongs to the human
#     standing in front of the plan `fraim publish` prints.
wm_check_remote() {
    _root=$1
    wm_is_git "$_root" || return 0

    if [ -z "$(git -C "$_root" remote 2>/dev/null)" ]; then
        wm_add remote info "нет удалённой копии — проект живёт только на этой машине" "fraim publish"
        return 0
    fi

    # The setup was started and not finished: an address is set, but there is not a single
    # remote-tracking branch — so nothing was ever pushed there. The repository on the host
    # is usually created and empty at this point, and that is the worst of states: from the
    # outside the copy looks like it exists, but inside there is nothing. Visible without
    # network — the watchman reads its own refs instead of asking the host.
    #
    # A separate finding, not "N points did not leave", because the quantity is different:
    # not the copy lagging, but unfinished work (D5). The threshold does not apply here —
    # an unfinished setup does not become normal because the project has only two save points.
    if [ -n "$(git -C "$_root" rev-parse -q --verify HEAD 2>/dev/null)" ] &&
       [ -z "$(git -C "$_root" for-each-ref --count=1 refs/remotes 2>/dev/null)" ]; then
        wm_add remote attention "адрес копии прописан, но туда ни разу ничего не уезжало" "fraim publish"
        return 0
    fi

    # Commits on HEAD that no remote ref carries. This works without an upstream being
    # configured, which matters: a branch created locally usually has none.
    _n=$(git -C "$_root" rev-list --count HEAD --not --remotes 2>/dev/null)
    [ -n "$_n" ] || return 0
    [ "$_n" -gt 0 ] || return 0

    _max=$(config_get unpushed_threshold "$_root")
    _w=$(wm_plural "$_n" "точка сохранения" "точки сохранения" "точек сохранения")
    _v=$(wm_plural "$_n" "не уехала" "не уехали" "не уехали")
    if [ "$_n" -ge "$_max" ]; then
        wm_add remote attention "$_n $_w $_v в удалённую копию" "fraim publish"
    else
        wm_add remote info "$_n $_w $_v в удалённую копию" ""
    fi
    return 0
}

# 4e. Changed and not saved. Only the artefacts the verbs always commit themselves: if one
#     of them is modified and uncommitted, a verb was interrupted or bypassed. Code and
#     settings are the human's business and are deliberately not counted — a watchman that
#     comments on work in progress stops being read.
wm_check_dirty() {
    _root=$1
    wm_is_git "$_root" || return 0
    # Two sets, because "unsaved" means different things for them.
    #
    # The foundation and the archive belong in history from the moment they exist: a verb
    # writes them and commits them in the same breath, so an untracked one is an interrupted
    # or bypassed verb. Excluding untracked files made this blind exactly where it matters
    # most now — reactive work usually leaves behind a file that never entered history at
    # all, which `--untracked-files=no` cannot see.
    #
    # `ai/tasks` is in the first set: a card is written and committed by one verb, so an
    # untracked card is a bypassed verb too. The exception that stays modified-only is
    # `STACK.md` — laid down as a stub by a verb and committed by the procedure that fills
    # it, so between the two it is legitimately untracked, and a watchman that comments on
    # work in progress stops being read.
    _n=$(git -C "$_root" status --porcelain --untracked-files=normal -- \
            ARCHITECTURE.md CONVENTIONS.md DECISIONS.md README.md \
            AGENTS.md CLAUDE.md ai/archive ai/tasks 2>/dev/null | wc -l | tr -d ' ')
    _nt=$(git -C "$_root" status --porcelain --untracked-files=no -- \
            STACK.md 2>/dev/null | wc -l | tr -d ' ')
    _n=$((_n + _nt))
    [ "$_n" -gt 0 ] || return 0
    wm_add dirty attention \
        "$_n $(wm_plural "$_n" файл файла файлов) фундамента и ai/ изменены после последней точки сохранения" \
        "fraim commit"
    return 0
}

# 4f. Parallel checkouts. Until the fleet appeared, «the project» and «the directory» were
#     the same thing, and every other check in this file still assumes it: they read
#     $_root and nothing else. One `git worktree add` — by hand, or by an ADE creating a
#     checkout per task — and the verdict describes one directory while the work happens
#     in another. That is drift of exactly the kind this file exists to catch, on a layer
#     that did not exist when it was written.
#
#     The register of checkouts is git itself, not the ADE. That matters twice: the answer
#     stays true when the runtime is closed or was never installed, and it costs no
#     dependency — git already keeps this list, so there is nothing to keep in sync (A3).
wm_check_worktrees() {
    _root=$1
    wm_is_git "$_root" || return 0
    _wt_list=$(git -C "$_root" worktree list --porcelain 2>/dev/null) || return 0

    # Split on newlines only: a checkout path may contain spaces, and `set -f` keeps a
    # path with a glob character in it from expanding into something else entirely.
    _wt_old_ifs=$IFS
    set -f
    IFS='
'
    _wt_n=0
    _wt_names=
    for _wt_p in $(printf '%s\n' "$_wt_list" | sed -n 's/^worktree //p'); do
        [ -d "$_wt_p" ] || continue
        _wt_real=$(cd -- "$_wt_p" 2>/dev/null && pwd -P) || continue
        [ "$_wt_real" = "$_root" ] && continue
        _wt_n=$((_wt_n + 1))
        _wt_name=$(basename -- "$_wt_real")

        if [ -z "$_wt_names" ]; then _wt_names=$_wt_name; else _wt_names="$_wt_names, $_wt_name"; fi
    done
    IFS=$_wt_old_ifs
    set +f

    [ "$_wt_n" -gt 0 ] || return 0
    wm_add worktree info \
        "$_wt_n $(wm_plural "$_wt_n" "параллельный чекаут" "параллельных чекаута" "параллельных чекаутов"): $_wt_names" \
        "fraim fleet"
    return 0
}

# 4g. The fleet runtime, when there is one. Read-only, offline, no model: the same contract
#     as every other check here (SCHEDULING.md). An environment that is installed but not
#     running is silence, not a finding — whether it runs is the operator's business (C1).
#
#     The one thing worth saying out loud is a scheduled free-form prompt against this
#     project. It is not forbidden and we do not touch it, but it explains drift that
#     otherwise looks causeless: code appears in the morning and nothing in the git log
#     says who asked for it. A scheduled watchman is the opposite case and stays silent —
#     that is layer 2 of SCHEDULING.md working as designed.
wm_check_ade() {
    _root=$1
    _ade_det=$(ade_detect)
    [ -n "$_ade_det" ] || return 0
    _ade_old_ifs=$IFS
    IFS='
'
    for _ade_row in $_ade_det; do
        _ade_label=$(printf '%s' "$_ade_row" | cut -f2)
        _ade_cmd=$(printf '%s' "$_ade_row" | cut -f3)
        ade_alive "$_ade_cmd" || continue
        _ade_a=$(ade_automations "$_ade_cmd" "$_root")
        [ "$(printf '%s' "$_ade_a" | cut -f1)" = 1 ] || continue
        [ "$(printf '%s' "$_ade_a" | cut -f2)" = 0 ] || continue
        wm_add ade-automation info \
            "$_ade_label: по этому проекту работает агент по расписанию" "fraim fleet"
    done
    IFS=$_ade_old_ifs
    return 0
}

# 5. The board. Informational — open tasks are normal, none is too. The scan is tasks.sh's,
#    the one implementation of "what is on the board" (A3); `fraim tasks` shows the rest.
WM_TASKS=
wm_scan_tasks() {
    WM_TASKS=$(tasks_scan "$1")
    return 0
}

wm_check_queue() {
    _n=$(printf '%s' "$WM_TASKS" | grep -c . || true)
    if [ "$_n" -gt 0 ]; then
        wm_add queue info "$_n $(wm_plural "$_n" "открытая задача" "открытые задачи" "открытых задач") на доске" "fraim tasks"
    fi
    return 0
}

# The foundation as DATA: missing / stub / filled, per file. The marker was understood by
# the watchman alone, so a procedure that checks "file exists → read it" could honestly
# read an empty scaffold and start guessing — D1 held at the reporting end and leaked at
# the reading end. Now the reading end can ask.
WM_FOUNDATION=
wm_scan_foundation() {
    _root=$1
    WM_FOUNDATION=
    for _f in README.md ARCHITECTURE.md CONVENTIONS.md DECISIONS.md STACK.md; do
        if   [ ! -f "$_root/$_f" ];            then _s=missing
        elif scaffold_is_stub "$_root/$_f";    then _s=stub
        else _s=filled
        fi
        WM_FOUNDATION="$WM_FOUNDATION$_f	$_s
"
    done
    return 0
}

# Conformance to the CURRENT standard, checked by shape rather than by a version number.
# A project laid down by an older release is missing whatever that release did not have
# yet — AGENTS.md and CLAUDE.md, ai/fraim.conf, the Known Pitfalls section the pitfall
# verb writes into — and nothing ever said so: `fraim status` reported it healthy because
# every check it ran passed. Shape is checked instead of a stamped version because shape
# is the truth: a version number stays right while someone deletes a section by hand.
wm_check_shape() {
    _root=$1
    _missing=
    for _f in README.md ARCHITECTURE.md CONVENTIONS.md DECISIONS.md ai/fraim.conf; do
        [ -e "$_root/$_f" ] || _missing="$_missing $_f"
    done
    for _d in ai/tasks ai/backlog ai/archive ai/investigations; do
        [ -d "$_root/$_d" ] || _missing="$_missing $_d/"
    done
    # The repository has to describe itself to whoever clones it: AGENTS.md carries the
    # rules, CLAUDE.md points at them. A project from before that existed has neither, and
    # a cloud session or a second machine then opens the foundation with no reason to read it.
    for _f in AGENTS.md CLAUDE.md; do
        if [ ! -f "$_root/$_f" ]; then _missing="$_missing $_f"
        elif ! grep -qF "$CTX_BEGIN" "$_root/$_f" 2>/dev/null; then _missing="$_missing $_f(без блока)"
        fi
    done
    # Sections that CODE reads. Known Pitfalls is where `fraim pitfall` writes and what
    # /make-task 0.3 reads before planning; without it both are broken, silently.
    if [ -f "$_root/CONVENTIONS.md" ] &&
       ! grep -q '^## Known Pitfalls / Lessons$' "$_root/CONVENTIONS.md"; then
        _missing="$_missing CONVENTIONS.md:Known-Pitfalls"
    fi
    # Tasks in the old format — a folder holding a plan. They are still somebody's intent,
    # so they are carried over, not dropped: `fraim upgrade` turns each into a card.
    [ -n "$(tasks_legacy "$_root")" ] && _missing="$_missing ai/tasks:старый-формат"
    [ -n "$_missing" ] &&
        wm_add shape attention "фундамент отстал от стандарта:$_missing" "fraim upgrade"
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

    # How much has changed since the map last did — measured in CHANGE, not in time.
    #
    # This used to be the number of days between the last code commit and the last
    # ARCHITECTURE.md commit, and that was the wrong quantity. Time is a decent proxy
    # only in the task loop, where one task is one sitting and the gate updates the map
    # at the end of it. In reactive work — the most frequent mode, and the one with no
    # gate at all — it inverts: a hundred commits inside a fortnight stayed silent while
    # a single commit a fortnight later raised the alarm. The denser the work, the less
    # likely the watchman was to notice. Counting commits measures the thing itself.
    # Two anchors reset the count, and the nearer one wins: the map itself moving, and
    # /prune having run. A prune that honestly found nothing to change still commits
    # nothing to ARCHITECTURE.md — without the second anchor the verdict would keep
    # asking for a gardening that just happened.
    _n=$(wm_code_commits_since "$_root" "$(git -C "$_root" log -1 --format=%H -- ARCHITECTURE.md 2>/dev/null)")
    _np=$(wm_code_commits_since "$_root" "$(git -C "$_root" log -1 --format=%H --grep='^prune: ' 2>/dev/null)")
    [ -n "$_n" ] || _n=0
    [ -n "$_np" ] || _np=0
    [ "$_np" -lt "$_n" ] && _n=$_np

    _max=$(config_get foundation_lag_commits "$_root")
    if [ "$_n" -ge "$_max" ]; then
        _w=$(wm_plural "$_n" коммит коммита коммитов)
        wm_add foundation attention "$_n $_w кода с последнего обновления ARCHITECTURE.md" "/prune"
    fi
    return 0
}

# 8. Lessons that never came back. `CONVENTIONS.md`'s `## Known Pitfalls / Lessons` is the
#    one loop that carries what execution learned back to planning — and until now it had
#    exactly two producers, `/run-task` step 9 and `/prune`. Both live in the task loop.
#    Reactive work, the default and most frequent mode, produced nothing: the gotcha that
#    cost an afternoon of live debugging stayed in the chat and died with it.
#
#    This is not a subset of `wm_check_foundation`, which the file warns against: that one
#    anchors on `ARCHITECTURE.md` and measures whether the MAP still matches the code. A
#    project can have a perfectly fresh map and a `CONVENTIONS.md` frozen since the day it
#    was written — different file, different question, and neither count implies the other.
#
#    The threshold is deliberately far above `foundation_lag_commits`: a lesson is a rarer
#    event than a structural change, and a verdict that asks for one too often is a verdict
#    that gets skimmed (D2).
wm_check_lessons() {
    _root=$1
    _conv="$_root/CONVENTIONS.md"
    [ -f "$_conv" ] || return 0
    scaffold_is_stub "$_conv" && return 0
    wm_is_git "$_root" || return 0

    # Same arithmetic as the map check, one file over: work saved since the lessons last
    # moved. A prune resets it too — a gardening that honestly found nothing to add still
    # means somebody looked.
    _n=$(wm_code_commits_since "$_root" "$(git -C "$_root" log -1 --format=%H -- CONVENTIONS.md 2>/dev/null)")
    _np=$(wm_code_commits_since "$_root" "$(git -C "$_root" log -1 --format=%H --grep='^prune: ' 2>/dev/null)")
    [ -n "$_n" ] || _n=0
    [ -n "$_np" ] || _np=0
    [ "$_np" -lt "$_n" ] && _n=$_np

    _max=$(config_get lessons_lag_commits "$_root")
    if [ "$_n" -ge "$_max" ]; then
        _w=$(wm_plural "$_n" коммит коммита коммитов)
        wm_add lessons attention \
            "$_n $_w кода с последнего пополнения CONVENTIONS.md — грабли никуда не записывались" "/prune"
    fi
    return 0
}

# 11. A new version of the system itself. The only finding that is not about the project —
#     and therefore info, not attention: someone's project does not get worse because a
#     fresh fraim is sitting on the host.
#
#     This check does NOT go to the network. The watchman must work offline and within
#     milliseconds (SCHEDULING.md, layer 1), so it reads the cache file written by the
#     commands where the human expects the network: `fraim update --check` and `fraim doctor`.
#     It also follows that it does not show "we do not know": the watchman's not knowing is
#     its silence, and the state of the check is visible in doctor, which performs it.
wm_check_update() {
    [ "$(update_cache_field 4)" = behind ] || return 0
    wm_add system-update info \
        "новая версия fraim на хосте ($(update_cache_field 3 | cut -c1-7))" "fraim update"
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
    wm_scan_tasks "$_root"
    wm_scan_foundation "$_root"
    config_is_on check_shape        "$_root" && wm_check_shape "$_root"
    config_is_on check_investigations "$_root" && wm_check_investigations "$_root"
    config_is_on check_git            "$_root" && wm_check_git "$_root"
    config_is_on check_remote         "$_root" && wm_check_remote "$_root"
    config_is_on check_dirty          "$_root" && wm_check_dirty "$_root"
    config_is_on check_worktrees      "$_root" && wm_check_worktrees "$_root"
    config_is_on check_ade            "$_root" && wm_check_ade "$_root"
    wm_check_queue
    config_is_on check_foundation   "$_root" && wm_check_foundation "$_root"
    config_is_on check_lessons      "$_root" && wm_check_lessons "$_root"
    config_is_on check_update       "$_root" && wm_check_update
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
    printf '  "foundation": {'
    _first=1
    printf '%s' "$WM_FOUNDATION" | while IFS='	' read -r _f _s; do
        [ -n "$_f" ] || continue
        [ "$_first" = 1 ] || printf ','
        _first=0
        printf ' "%s": "%s"' "$_f" "$_s"
    done
    printf ' },\n'
    printf '  "tasks": ['
    if [ -n "$WM_TASKS" ]; then
        printf '\n'
        printf '%s\n' "$WM_TASKS" | {
            _first=1
            while IFS="$TASK_SEP" read -r _slug _kind _parent _created _title; do
                [ -n "$_slug" ] || continue
                [ "$_first" = 1 ] || printf ',\n'
                _first=0
                printf '    { "slug": "%s", "kind": "%s", "parent": "%s" }' \
                    "$(wm_json_escape "$_slug")" "$_kind" "$(wm_json_escape "$_parent")"
            done
        }
        printf '\n  '
    fi
    printf '],\n'
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
