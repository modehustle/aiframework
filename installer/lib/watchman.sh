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

# 3. Stale plan: the queue moved on while the plan sat in it.
#
#    The question is not «did HEAD move» — it is «did anything the plan STANDS ON move».
#    Counting commits answered the first one, and in this system the two diverge by
#    construction: every verb ends in a commit of its own, so sealing six plans moves HEAD
#    six times and each of those commits touches nothing but `ai/`. The queue then reported
#    every plan in it as stale — six alarms over zero lines of changed code — and the
#    executor's Step 4.6 turned each one into a blocker and a round of /revise-task. A
#    detector whose loudest signal is its own bookkeeping teaches the human to ignore it.
#
#    So the measurement is now over the plan's own surface, taken from the sections the
#    plan already has to fill: `## Codebase Context` (what the executor must read) and
#    `## Files to Change` (what it must write). Three outcomes, and the middle one is new:
#
#      · a file from the surface moved     → attention, and the message NAMES the files
#      · code moved, but past the surface  → info: worth a glance, not a defect
#      · only `ai/` moved                  → nothing at all. Bookkeeping is not divergence.
#
#    A plan whose surface cannot be read — no sections, or a hand-written stub — falls back
#    to the commit count minus `ai/`: with nothing to compare against, silence is the wrong
#    default. `stale_plan_commits` still gates the whole check, so a project can go on
#    tolerating N commits before any of this is reported.

# The plan's surface as repo-relative paths, one per line. Two things are dropped from it.
#
# `ai/…` — that is where the plan itself lives, and a plan is never stale because of itself.
#
# ARCHITECTURE.md and CONVENTIONS.md on the READ side — `/run-task` opens both in full at
# Step 1.1–1.2, before it so much as looks at the plan, so they are the one kind of file that
# cannot reach the executor as a stale snapshot. They are also in every plan by template, so
# counting them would flag the whole queue at once on a single typo in the map: the same
# alarm-per-plan shape this check was just cured of. On the WRITE side they stay — a plan out
# to change the map, against a map somebody already changed, is a real collision.
wm_plan_surface() {
    _dir=$1
    {
        verb_plan_context_paths "$_dir/context.md" |
            grep -vx -e ARCHITECTURE.md -e CONVENTIONS.md || :
        verb_plan_change_paths  "$_dir/task.md"
    } 2>/dev/null |
        sed 's#^\./##; s#/*$##' |
        grep -v '^ai/' | grep -v '[[:space:]]' | grep '[^[:space:]]' | sort -u
}

# Which of the changed files the plan stands on. A surface entry naming a directory
# matches everything under it, which is how the plans write it: `src/api/` — the module
# being extended.
wm_surface_hits() {
    _surface=$1; _changed=$2
    printf '%s\n' "$_changed" | awk -v s="$_surface" '
        BEGIN { n = split(s, a, "\n") }
        NF {
            for (i = 1; i <= n; i++) {
                if (a[i] == "") continue
                if ($0 == a[i] || index($0, a[i] "/") == 1) { print; break }
            }
        }'
}

# «a, b, c и ещё 4» — the evidence, not the whole diff. A finding is one line in a verdict
# read daily; what it owes the reader is enough to judge without running git themselves.
wm_name_some() {
    _items=$1; _max=$2
    _n=$(printf '%s\n' "$_items" | awk 'NF{n++} END{print n+0}')
    _head=$(printf '%s\n' "$_items" | grep '[^[:space:]]' | head -"$_max" |
            tr '\n' ',' | sed 's/,$//; s/,/, /g')
    if [ "$_n" -gt "$_max" ]; then
        printf '%s и ещё %s\n' "$_head" "$((_n - _max))"
    else
        printf '%s\n' "$_head"
    fi
}

wm_check_stale_plans() {
    _root=$1
    [ -d "$_root/ai/tasks" ] || return 0
    wm_is_git "$_root" || return 0
    _min=$(config_get stale_plan_commits "$_root")
    for _c in "$_root"/ai/tasks/*/context.md; do
        [ -f "$_c" ] || continue
        _dir=$(dirname -- "$_c")
        _slug=$(basename -- "$_dir")
        # Pull the first 7+ hex chars off the `Based on:` line.
        _ref=$(sed -n 's/^-\{0,1\}[[:space:]]*Based on:.*/&/p' "$_c" | head -1 |
               grep -oE '[0-9a-f]{7,40}' | head -1)
        [ -n "$_ref" ] || continue
        git -C "$_root" cat-file -e "$_ref^{commit}" 2>/dev/null || continue

        # Everything under ai/ is the system writing its own queue — plans, blockers,
        # results, the archive. It moves HEAD and changes nothing the executor works on.
        _behind=$(git -C "$_root" rev-list --count "$_ref"..HEAD -- ':!ai' 2>/dev/null) || continue
        [ -n "$_behind" ] || continue
        [ "$_behind" -ge "$_min" ] && [ "$_behind" -gt 0 ] || continue
        _w=$(wm_plural "$_behind" коммит коммита коммитов)

        _surface=$(wm_plan_surface "$_dir")
        if [ -z "$_surface" ]; then
            wm_add stale-plan attention \
                "план «$_slug» отстал от HEAD на $_behind $_w кода, а свои файлы не перечислил" \
                "/revise-task"
            continue
        fi
        # --no-renames on purpose: a rename shows as delete + add, so a plan standing on the
        # old path still sees its ground move. Rename detection would hide exactly that.
        _changed=$(git -C "$_root" diff --no-renames --name-only "$_ref"..HEAD -- ':!ai' 2>/dev/null)
        _hits=$(wm_surface_hits "$_surface" "$_changed")
        _nh=$(printf '%s\n' "$_hits" | awk 'NF{n++} END{print n+0}')
        if [ "$_nh" -gt 0 ]; then
            _v=$(wm_plural "$_nh" изменился изменились изменились)
            wm_add stale-plan attention \
                "план «$_slug» отстал: $_v $(wm_name_some "$_hits" 3)" "/revise-task"
        else
            wm_add stale-plan info \
                "план «$_slug»: $_behind $_w кода мимо его файлов — план в силе" ""
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
# The queue as DATA, not as a sentence. Three places used to walk ai/tasks/ and label
# each folder — /run-task 1.3-1.10 and /make-task 1.2-1.6 by prose, the watchman in code.
# Three implementations of one arithmetic drift; this is the one, and the procedures ask
# it instead of re-deriving it (A3).
#
# It also fixes a verdict that was simply wrong: the count used to be "folders holding a
# task.md", so a queue of one runnable task, one blocked and one awaiting archival read
# "3 задачи в очереди → /run-task". Two of those three cannot be run at all.
WM_TASKS=
wm_scan_tasks() {
    _root=$1
    WM_TASKS=
    [ -d "$_root/ai/tasks" ] || return 0
    for _t in "$_root"/ai/tasks/*/; do
        [ -d "$_t" ] || continue
        _slug=$(basename -- "$_t")
        [ -f "$_t/task.md" ] || continue
        if   [ -f "$_t/blockers.md" ]; then _state=blocked
        elif [ -f "$_t/result.md" ];   then _state=done
        else _state=runnable
        fi
        WM_TASKS="$WM_TASKS$_slug	$_state
"
    done
    return 0
}

# awk counts and prints, deliberately: `grep -c` exits 1 on zero matches, and under
# `set -e` that ends the whole run — a watchman that dies quietly on an empty queue.
wm_tasks_in_state() {
    printf '%s' "$WM_TASKS" | awk -F'	' -v s="$1" '$2 == s { n++ } END { print n + 0 }'
}

wm_check_queue() {
    _root=$1
    _n=$(wm_tasks_in_state runnable)
    if [ "$_n" -gt 0 ]; then
        wm_add queue info "$_n $(wm_plural "$_n" задача задачи задач) готова к исполнению" "/run-task"
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
    for _d in ai/tasks ai/archive ai/investigations; do
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
    config_is_on check_blockers     "$_root" && wm_check_blockers "$_root"
    config_is_on check_stale_plans  "$_root" && wm_check_stale_plans "$_root"
    config_is_on check_plan_version "$_root" && wm_check_plan_version "$_root"
    config_is_on check_unsealed       "$_root" && wm_check_unsealed "$_root"
    config_is_on check_investigations "$_root" && wm_check_investigations "$_root"
    config_is_on check_git            "$_root" && wm_check_git "$_root"
    config_is_on check_remote         "$_root" && wm_check_remote "$_root"
    config_is_on check_dirty          "$_root" && wm_check_dirty "$_root"
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
        _first=1
        printf '%s' "$WM_TASKS" | while IFS='	' read -r _slug _state; do
            [ -n "$_slug" ] || continue
            [ "$_first" = 1 ] || printf ',\n'
            _first=0
            printf '    { "slug": "%s", "state": "%s" }' "$(wm_json_escape "$_slug")" "$_state"
        done
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
