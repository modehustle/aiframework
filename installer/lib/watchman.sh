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

# Commits since a given one that changed anything OUTSIDE the task queue.
# `:(exclude)` needs git 1.9 (2014); on anything older the pathspec is rejected and
# we fall back to the plain count rather than silently reporting no drift at all.
wm_commits_outside_queue() {
    _root=$1; _from=$2
    git -C "$_root" rev-list --count "$_from..HEAD" -- . ':(exclude)ai/tasks' 2>/dev/null ||
        git -C "$_root" rev-list --count "$_from..HEAD" 2>/dev/null
}

# Commits touching anything but markdown, since a given commit (or all of them).
wm_code_commits_since() {
    _root=$1; _from=$2
    if [ -n "$_from" ]; then
        git -C "$_root" rev-list --count "$_from..HEAD" -- ':!*.md' 2>/dev/null
    else
        git -C "$_root" rev-list --count HEAD -- ':!*.md' 2>/dev/null
    fi
}

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

# 1. Drift used to be counted here, as hotfix entries since the last /prune marker. It is
#    gone with /hotfix itself: the metric only ever saw work that went through that one
#    procedure, while `wm_check_foundation` below counts code commits since ARCHITECTURE.md
#    last moved — the same signal, measured over every mode of work including the reactive
#    one. Two drift metrics where one is a strict subset of the other is not redundancy,
#    it is a second number to keep honest.

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

# 3. Stale plan: the CODE moved on while the plan sat in the queue. `Based on` is
#    the snapshot make-task wrote; if the codebase has since moved, the executor
#    would be working against something the plan never saw.
#
#    Two exclusions, and both are the difference between measuring drift and
#    measuring bookkeeping:
#
#    - commits that touch only `ai/tasks/` do not count. The plan's own save point
#      (`/make-task` step 4.0) lands there, and so does every revision and every
#      neighbouring plan. Counting them made a freshly written plan report itself
#      stale by exactly one commit — the one that saved it — which /run-task 4.6
#      turns into a blocker, and which /revise-task could never clear because its
#      own commit put the repaired plan one behind again.
#    - a task that already carries `result.md` or `blockers.md` is not waiting to be
#      executed. Staleness is a statement about what the executor will run into next,
#      so it is only ever about RUNNABLE plans.
wm_check_stale_plans() {
    _root=$1
    [ -d "$_root/ai/tasks" ] || return 0
    wm_is_git "$_root" || return 0
    for _c in "$_root"/ai/tasks/*/context.md; do
        [ -f "$_c" ] || continue
        _dir=$(dirname -- "$_c")
        _slug=$(basename -- "$_dir")
        [ -f "$_dir/result.md" ] && continue
        [ -f "$_dir/blockers.md" ] && continue
        # Pull the first 7+ hex chars off the `Based on:` line.
        _ref=$(sed -n 's/^-\{0,1\}[[:space:]]*Based on:.*/&/p' "$_c" | head -1 |
               grep -oE '[0-9a-f]{7,40}' | head -1)
        [ -n "$_ref" ] || continue
        git -C "$_root" cat-file -e "$_ref^{commit}" 2>/dev/null || continue
        _behind=$(wm_commits_outside_queue "$_root" "$_ref") || continue
        [ -n "$_behind" ] || continue
        _min=$(config_get stale_plan_commits "$_root")
        if [ "$_behind" -ge "$_min" ] && [ "$_behind" -gt 0 ]; then
            _w=$(wm_plural "$_behind" коммит коммита коммитов)
            wm_add stale-plan attention "план «$_slug» отстал от кода на $_behind $_w" "/revise-task"
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

# 4a. A plan that retells the code instead of pointing at it. `/make-task` G6 forbids line
#     numbers, copied signatures and paraphrased bodies, for a reason that is not economy:
#     the executor opens every listed file anyway (`/run-task` step 2) and believes the file
#     over the plan (G7), so a retelling can only ever agree redundantly or disagree falsely.
#     A rule that only the model it constrains reports on is not a rule, so this is the
#     deterministic half: grep for the shapes a retelling leaves behind. `info`, never
#     `attention` — the plan is wasteful, not broken, and it must not become a blocker.
wm_check_plan_retelling() {
    _root=$1
    [ -d "$_root/ai/tasks" ] || return 0
    for _d in "$_root"/ai/tasks/*/; do
        [ -d "$_d" ] || continue
        _slug=$(basename -- "$_d")
        [ -f "$_d/context.md" ] || continue
        [ -f "$_d/result.md" ] && continue
        [ -f "$_d/blockers.md" ] && continue
        # `grep -c` exits 1 on zero matches, and this whole file runs under `set -e`:
        # without the `|| true` a clean plan would abort the watchman mid-verdict.
        _hits=$(cat "$_d/context.md" "$_d/task.md" 2>/dev/null |
                grep -cE '[Ll]ines?[[:space:]]+[0-9]+|строк[^[:space:]]*[[:space:]]+[0-9]+|\.[a-z]{1,5}:[0-9]+' ||
                true)
        [ -n "$_hits" ] || continue
        if [ "$_hits" -gt 0 ]; then
            _w=$(wm_plural "$_hits" ссылка ссылки ссылок)
            wm_add plan-retelling info \
                "план «$_slug» пересказывает код: $_hits $_w на строки — исполнитель всё равно читает файл" ""
        fi
    done
}

# 4b. Unsealed work: the task was executed and never went through the gate. Until now
#     nothing noticed this, while DETERMINISM.md claimed the watchman would — which is
#     the one thing a system built on "the bypass is visible" cannot afford to be wrong about.
wm_check_unsealed() {
    _root=$1
    [ -d "$_root/ai/tasks" ] || return 0
    for _r in "$_root"/ai/tasks/*/result.md; do
        [ -f "$_r" ] || continue
        _dir=$(dirname -- "$_r")
        [ -f "$_dir/blockers.md" ] && continue
        _slug=$(basename -- "$_dir")
        _days=$(wm_days_since "$(wm_mtime "$_r")")
        if [ "$_days" -eq 0 ]; then _age="сегодня"
        else _age="$_days $(wm_plural "$_days" день дня дней) назад"; fi
        wm_add unsealed attention "задача «$_slug» исполнена $_age и не запечатана" "fraim task-seal $_slug"
    done
}

# 4c. Investigations: a folder that never landed on an outcome, or landed and stayed.
#     This is the terminal state /investigate never had — its folders grew forever.
wm_check_investigations() {
    _root=$1
    [ -d "$_root/ai/investigations" ] || return 0
    for _f in "$_root"/ai/investigations/*/findings.md; do
        [ -f "$_f" ] || continue
        _slug=$(basename -- "$(dirname -- "$_f")")
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
#     Detection only, per D4. Choosing a host, private or public, and authorising it is a
#     fork with real content in it, so it stays a conversation with the agent — the watchman
#     says the copy is missing and never reaches for the network to fix it.
wm_check_remote() {
    _root=$1
    wm_is_git "$_root" || return 0

    if [ -z "$(git -C "$_root" remote 2>/dev/null)" ]; then
        wm_add remote info "нет удалённой копии — проект живёт только на этой машине" ""
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
        wm_add remote attention "$_n $_w $_v в удалённую копию" "git push"
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
    # The exceptions stay modified-only: `ai/tasks` and `STACK.md` are both laid down as a
    # stub by a verb and committed by the procedure that fills them, so between the two they
    # are legitimately untracked — and a watchman that comments on work in progress stops
    # being read.
    _n=$(git -C "$_root" status --porcelain --untracked-files=normal -- \
            ARCHITECTURE.md CONVENTIONS.md DECISIONS.md README.md \
            AGENTS.md CLAUDE.md ai/archive 2>/dev/null | wc -l | tr -d ' ')
    _nt=$(git -C "$_root" status --porcelain --untracked-files=no -- \
            ai/tasks STACK.md 2>/dev/null | wc -l | tr -d ' ')
    _n=$((_n + _nt))
    [ "$_n" -gt 0 ] || return 0
    wm_add dirty attention \
        "$_n $(wm_plural "$_n" файл файла файлов) фундамента и ai/ изменены после последней точки сохранения" \
        "fraim commit"
    return 0
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
    config_is_on check_blockers     "$_root" && wm_check_blockers "$_root"
    config_is_on check_stale_plans  "$_root" && wm_check_stale_plans "$_root"
    config_is_on check_plan_version "$_root" && wm_check_plan_version "$_root"
    config_is_on check_plan_retelling "$_root" && wm_check_plan_retelling "$_root"
    config_is_on check_unsealed       "$_root" && wm_check_unsealed "$_root"
    config_is_on check_investigations "$_root" && wm_check_investigations "$_root"
    config_is_on check_git            "$_root" && wm_check_git "$_root"
    config_is_on check_remote         "$_root" && wm_check_remote "$_root"
    config_is_on check_dirty          "$_root" && wm_check_dirty "$_root"
    wm_check_queue "$_root"
    config_is_on check_foundation   "$_root" && wm_check_foundation "$_root"
    config_is_on check_lessons      "$_root" && wm_check_lessons "$_root"
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
