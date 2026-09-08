#!/bin/sh
# dispatch.sh — the conductor's half of parallel mode (MODES.md §2, §5).
#
# What this file is NOT: it does not launch anything. Launching is six operations
# against an execution environment (MODES.md §9) and lives in the adapter layer.
# This file decides WHAT to launch, WHO should run it, and — after the fact — WHAT
# actually changed. Keeping the two apart is what lets the conductor's logic be
# tested without an ADE installed, which is the only reason it can be tested at all
# on a machine that has none.
#
# The invariant that shapes everything here (MODES.md §3): the conductor checks the
# TREE, not the reports. A worker's result.md is prose written by the party being
# judged. It is worth reading and worthless as evidence, so nothing in this file
# decides anything from it — completion comes from the adapter's outcome signal
# (operation §9.5) and content comes from `git diff`.

# ---------------------------------------------------------------------------
# Plan parsing
#
# A subtask block:
#
#     ## Subtask: A
#     **Role**: run-task
#     **Summary**: one line, for the worker's task.md
#
#     ### `path/to/file`
#     - why
#
# Role is the name of a PROCEDURE, not a word invented per plan (MODES.md §10 —
# "свою онтологию ролей не заводим"). roles.sh resolves it to agent, model and
# effort; it is the plan's only statement about the executor, on purpose.
# ---------------------------------------------------------------------------

# One record per subtask: id|role|summary|comma-separated paths
# Fields are emitted even when empty so the validator can name what is missing
# rather than silently skipping the block.
#
# A per-subtask tier field was built here and removed on the owner's decision: judging
# which subtask deserves an expensive model is not the conductor's call to make. Executors
# run on what their procedure declares, and the human decides cost — see "Чего здесь пока
# нет" in the conductor procedure for the session-profile idea that replaces it.
dispatch_parse_plan() {
    [ -f "$1" ] || return 0
    awk '
        function flush() {
            if (id != "") print id "|" role "|" summary "|" paths
            id = ""; role = ""; summary = ""; paths = ""
        }
        /^## Subtask:/ { flush(); id = $3; next }
        id == "" { next }
        /^\*\*Role\*\*:/ {
            role = $0; sub(/^\*\*Role\*\*:[[:space:]]*/, "", role); next
        }
        /^\*\*Summary\*\*:/ {
            summary = $0; sub(/^\*\*Summary\*\*:[[:space:]]*/, "", summary); next
        }
        /^### `/ {
            p = $0; sub(/^### `/, "", p); sub(/`.*$/, "", p)
            if (p != "") paths = (paths == "" ? p : paths "," p)
            next
        }
        /^## / && !/^## Subtask:/ { flush() }
        END { flush() }
    ' "$1"
}

# Just the ids, in plan order.
dispatch_subtask_ids() { dispatch_parse_plan "$1" | cut -d'|' -f1; }

# One field of one subtask.
dispatch_field() {
    dispatch_parse_plan "$1" | awk -F'|' -v id="$2" -v n="$3" '$1 == id { print $n; exit }'
}

# ---------------------------------------------------------------------------
# dispatch-check — the gate that makes "one acceptance" honest (§11.2, answer B)
#
# The build's boundary is not what the human circled and not what one dispatch
# happened to carry: it is what this check passed. That is the only definition
# under which the promise "you review this once" cannot quietly become a lie.
#
# Two classes of defect, and they fail differently on purpose:
#   - a path in two subtasks is a COLLISION: two workers, one file, silent merge
#   - a missing role/summary/path is an INCOMPLETE plan
# Both are caught before a single worker starts, because the alternative is paying
# N launches to discover a typo.
# ---------------------------------------------------------------------------
dispatch_check() {
    _dc_plan=$1; _dc_root=${2:-}
    [ -f "$_dc_plan" ] || { printf >&2 'плана нет: %s\n' "$_dc_plan"; return 1; }

    _dc_recs=$(dispatch_parse_plan "$_dc_plan")
    [ -n "$_dc_recs" ] || { printf >&2 'в плане нет ни одной «## Subtask: ИМЯ»\n'; return 1; }

    _dc_bad=0

    # 1. Structure: every subtask says who, what and where.
    _dc_struct=$(printf '%s\n' "$_dc_recs" | while IFS='|' read -r _id _role _sum _paths; do
        [ -n "$_id" ] || continue
        [ -n "$_role" ]  || printf 'подзадача %s: нет «**Role**:»\n' "$_id"
        [ -n "$_sum" ]   || printf 'подзадача %s: нет «**Summary**:»\n' "$_id"
        [ -n "$_paths" ] || printf 'подзадача %s: нет ни одного «### `путь`»\n' "$_id"
    done)
    if [ -n "$_dc_struct" ]; then
        printf >&2 'dispatch-check: план неполон:\n%s\n' "$_dc_struct"
        _dc_bad=1
    fi

    # 2. Collision: the same path claimed by two subtasks.
    _dc_pairs=$(printf '%s\n' "$_dc_recs" | while IFS='|' read -r _id _role _sum _paths; do
        [ -n "$_paths" ] || continue
        printf '%s\n' "$_paths" | tr ',' '\n' | while read -r _p; do
            [ -n "$_p" ] && printf '%s\t%s\n' "$_p" "$_id"
        done
    done)
    _dc_dups=$(printf '%s\n' "$_dc_pairs" | cut -f1 | sort | uniq -d)
    if [ -n "$_dc_dups" ]; then
        printf >&2 'dispatch-check: один файл у двух подзадач — параллельно их запускать нельзя:\n'
        printf '%s\n' "$_dc_dups" | while read -r _p; do
            [ -n "$_p" ] || continue
            _who=$(printf '%s\n' "$_dc_pairs" | awk -F'\t' -v p="$_p" '$1 == p { printf "%s%s", sep, $2; sep=", " }')
            printf >&2 '  %s — в подзадачах: %s\n' "$_p" "$_who"
        done
        _dc_bad=1
    fi

    # 3. Every role resolves to an executor on THIS machine's table.
    # The loop variable carries a `_dc_` prefix because core.sh's fraim_procedure_file
    # assigns a bare `_r` internally, and sh has no locals: a plain `_r` here comes back
    # holding the install path after the first call into it.
    _dc_roles=$(printf '%s\n' "$_dc_recs" | cut -d'|' -f2 | grep '[^[:space:]]' | sort -u)
    for _dc_r in $_dc_roles; do
        roles_resolve "$_dc_r" "$_dc_root" >/dev/null || _dc_bad=1
    done

    # 4. A known procedure that may not run in parallel. `prune` and the rest write the
    #    foundation, and under this mode the foundation is written by the build once
    #    (invariant 0.4) — dispatching two of them is a collision no path check can see,
    #    because they collide inside the same file the plan never listed.
    #    An UNKNOWN role is not refused here: it already fell back to a default executor
    #    in step 3, and refusing a plan because this machine lacks a procedure would make
    #    plans non-portable, which is the thing roles exist to avoid.
    for _dc_r in $_dc_roles; do
        if fraim_procedure_file "$_dc_r" >/dev/null 2>&1 && ! roles_is_parallel "$_dc_r"; then
            printf >&2 'dispatch-check: роль %s нельзя раздавать воркеру\n' "$_dc_r"
            printf >&2 '  процедура %s не объявляет «parallel: yes» — она пишет фундамент\n' "$_dc_r"
            printf >&2 '  или действует на весь проект, а под параллелизмом фундамент пишет\n'
            printf >&2 '  сборка, один раз (MODES.md §2, инвариант 0.4)\n'
            _dc_bad=1
        fi
    done

    # 5. Known refusals. Not a failure — the launch will handle it — but the conductor
    #    should read it here rather than discover it in the launch output, because it
    #    changes what the build will actually cost.
    printf '%s\n' "$_dc_recs" | while IFS='|' read -r _id _role _sum _paths; do
        [ -n "$_role" ] || continue
        _ex=$(roles_resolve "$_role" "$_dc_root" 2>/dev/null) || continue
        _ag=$(printf '%s' "$_ex" | cut -f1)
        _mo=$(printf '%s' "$_ex" | cut -f2)
        if [ -n "$_mo" ] && fleet_caps_has "$_ag" no-launch-model 2>/dev/null; then
            printf >&2 'подзадача %s: агент %s не принимает модель через Orca — %s пойдёт в команде запуска\n' \
                "$_id" "$_ag" "$_mo"
        fi
    done

    [ "$_dc_bad" -eq 0 ] || return 1
    return 0
}

# What dispatch is about to do, before it does it: who runs what, on which model,
# and where that answer came from. Printed for the conductor to read — a run on the
# built-in default when the project meant to name a role is the kind of thing that
# is obvious here and invisible three hours later.
dispatch_report() {
    _dr_plan=$1; _dr_root=${2:-}
    # Literal: POSIX printf pads bytes, and Cyrillic headings would land short.
    printf 'подзадача  роль            агент   модель   усилие  источник\n'
    dispatch_parse_plan "$_dr_plan" | while IFS='|' read -r _id _role _sum _paths; do
        [ -n "$_id" ] || continue
        _ex=$(roles_resolve "$_role" "$_dr_root") || continue
        _ag=$(printf '%s' "$_ex" | cut -f1)
        _mo=$(printf '%s' "$_ex" | cut -f2)
        _ef=$(printf '%s' "$_ex" | cut -f3)
        printf '%-10s %-15s %-7s %-8s %-7s %s\n' \
            "$_id" "$_role" "$_ag" "$_mo" "$_ef" "$(roles_source "$_role" "$_dr_root")"
    done
}

# ---------------------------------------------------------------------------
# Worker task folders
# ---------------------------------------------------------------------------

# The executor never sees the conductor's conversation (G1), so the task file must
# carry everything: what to do, where it may write, and the one rule that makes
# parallel mode safe — staying inside the declared paths.
dispatch_write_task() {
    _wt_root=$1; _wt_build=$2; _wt_id=$3; _wt_role=$4; _wt_sum=$5; _wt_paths=$6

    _wt_dir="$_wt_root/ai/parallel/$_wt_build/$_wt_id"
    mkdir -p "$_wt_dir" || return 1

    {
        printf '# Подзадача %s\n\n' "$_wt_id"
        printf '## Summary\n%s\n\n' "$_wt_sum"
        printf '## Files to Change\n'
        printf '%s\n' "$_wt_paths" | tr ',' '\n' | while read -r _p; do
            [ -n "$_p" ] && printf -- '- `%s`\n' "$_p"
        done
        printf '\n## Executor Rules\n'
        printf -- '- Роль этой подзадачи: %s\n' "$_wt_role"
        printf -- '- Меняй только файлы из Files to Change. Всё остальное дерево принадлежит\n'
        printf -- '  другим воркерам этой сборки: правка вне списка сольётся молча и без конфликта.\n'
        printf -- '- Нужен файл вне списка — не трогай его, а останови работу и скажи об этом.\n'
        printf -- '  Дирижёр перепланирует сборку; это дешевле молчаливого пересечения.\n'
        printf -- '\n'
        printf -- '- **Фундамент проекта в этой подзадаче не твой.** `DECISIONS.md`,\n'
        printf -- '  `ARCHITECTURE.md`, `CONVENTIONS.md` не трогай, даже если `AGENTS.md` проекта\n'
        printf -- '  велит обновлять их после изменения. Здесь это правило отменено: под\n'
        printf -- '  параллелизмом фундамент пишет сборка, один раз, после приёмки\n'
        printf -- '  (MODES.md §2, инвариант 0.4). Два воркера, дописавшие DECISIONS.md\n'
        printf -- '  каждый от себя, дают конфликт слияния на ровном месте.\n'
        printf -- '- Что стоило бы записать в фундамент — напиши словами в свой отчёт. Дирижёр\n'
        printf -- '  соберёт это со всей сборки и внесёт одной записью.\n'
        printf -- '\n'
        printf -- '- **Закоммить свою работу.** Не оставляй сделанное незакоммиченным: сборку\n'
        printf -- '  собирают слиянием веток, и то, что не в коммите, до неё не доедет.\n'
        printf -- '- Сборка %s. Приёмка одна на всю сборку, отдельной приёмки этой подзадачи нет.\n' "$_wt_build"
    } > "$_wt_dir/task.md" || return 1

    printf '%s\n' "$_wt_dir"
}

# ---------------------------------------------------------------------------
# Verification against the tree (MODES.md §3)
#
# This is the function the whole design exists for. The conductor does not ask the
# worker whether it did the job; it asks git what changed, and compares that with
# what the plan allowed. Two questions, and the second is the one that catches the
# expensive failure:
#   - did anything in the declared paths change?          (did the work happen)
#   - did anything OUTSIDE the declared paths change?     (did it stay in its lane)
# ---------------------------------------------------------------------------
# Prints one line per changed file: `inside:PATH` for a file the subtask declared,
# `outside:PATH` for one it did not. No line at all means the worker changed nothing,
# which is its own kind of answer.
# Where a worker of this build actually works.
#
# Found from the FIRST live parallel build: the environment gives each worker its own
# checkout (`--worktree new-top-level`), so the workers' changes are not in the project
# root at all — they are in /…/workspaces/<repo>/<build>-<subtask>. Verifying the root
# therefore compared the conductor's own tree against itself and saw nothing, which made
# the one load-bearing check of the whole mode (§3) silently useless.
#
# Asked of git rather than of the environment: `git worktree list` is the same answer no
# matter who created the checkout, and ade.sh already states the principle — the registry
# of checkouts is kept by git, the environment is an optional enricher.
#
# The `if` is not style: `[ … ] && …` as the last command of a loop body returns 1 on the
# final non-matching iteration, and under `set -e` that kills the caller's `$( … )` with
# no output and no message. It cost this function a silent exit-1 the first time it ran.
dispatch_worker_tree() {
    _wt_root=$1; _wt_name=$2
    git -C "$_wt_root" worktree list --porcelain 2>/dev/null |
        sed -n 's/^worktree //p' |
        while read -r _wt_p; do
            if [ "$(basename -- "$_wt_p")" = "$_wt_name" ]; then
                printf '%s\n' "$_wt_p"
                break
            fi
        done
    return 0
}

# Prints one line per changed file: `inside:PATH` / `outside:PATH`.
#
# Uncommitted work counts. The first live build had a worker finish its job and leave it
# unstaged; `git diff <base>` in that checkout still shows it, and calling that "nothing
# changed" would have been a lie about work that was done.
dispatch_verify_tree() {
    _vt_root=$1; _vt_ref=$2; _vt_paths=$3

    # Two questions, because one of them alone leaves a blind spot the check exists to
    # cover: `git diff` reports what changed against the base but says nothing about files
    # that did not exist there. A worker that CREATES a file outside its lane — a new
    # module, a stray script, a foundation file — would pass a diff-only check silently.
    _vt_changed=$(cd "$_vt_root" 2>/dev/null && {
            git diff --name-only "$_vt_ref" 2>/dev/null
            git ls-files --others --exclude-standard 2>/dev/null
        }) || { printf >&2 'не могу прочитать дерево от %s\n' "$_vt_ref"; return 1; }
    _vt_decl=$(printf '%s\n' "$_vt_paths" | tr ',' '\n' | grep '[^[:space:]]' | sort -u)

    printf '%s\n' "$_vt_changed" | grep '[^[:space:]]' | sort -u | while read -r _p; do
        if printf '%s\n' "$_vt_decl" | grep -qxF -- "$_p"; then
            printf 'inside:%s\n' "$_p"
        else
            printf 'outside:%s\n' "$_p"
        fi
    done
}

# ---------------------------------------------------------------------------
# Build record
# ---------------------------------------------------------------------------

build_dir() { printf '%s/ai/builds/%s\n' "$1" "$2"; }

# ---------------------------------------------------------------------------
# Launching the fleet
#
# What we keep and what we do not: MODES.md §10 says the environment's ids — terminal
# handles, worktree ids, dispatch ids — are THEIR truth, and ours is "which subtask went
# to whom and what came back", which lives in git. So this file writes a cache with the
# time it was taken (the precedent §10 names is ~/.fraim/update-check), not a registry we
# pretend to own. If Orca and this file disagree, Orca is right about dispatch state and
# the tree is right about the work.
# ---------------------------------------------------------------------------

# subtask<TAB>task_id<TAB>dispatch_id<TAB>taken_at
build_fleet_file() { printf '%s/fleet.tsv\n' "$(build_dir "$1" "$2")"; }

# Start every subtask of a build. Returns 1 if any worker failed to start — but only
# after trying them all, because the subtasks are independent by construction and
# abandoning the rest would throw away work that is already running.
dispatch_launch() {
    _dl_root=$1; _dl_build=$2

    _dl_dir=$(build_dir "$_dl_root" "$_dl_build")
    _dl_plan="$_dl_dir/plan.md"
    [ -f "$_dl_plan" ] || { printf >&2 'нет плана сборки %s\n' "$_dl_build"; return 1; }

    # The journal is what makes this a BUILD rather than a directory that happens to hold
    # a plan. In the first live build the conductor ran `dispatch run v2-core` — the folder
    # where the plan was written by hand — while `dispatch` had sealed the build under
    # build-20260907-140427. The fleet started against a build that had no journal, and the
    # mismatch only surfaced at acceptance, after all four workers had finished.
    if [ ! -f "$_dl_dir/journal.md" ]; then
        printf >&2 'сборка %s не заводилась: нет журнала ai/builds/%s/journal.md\n' \
            "$_dl_build" "$_dl_build"
        printf >&2 '  сборку заводит «fraim dispatch ПЛАН» — он и назовёт её имя\n'
        _dl_have=$(build_list "$_dl_root" 2>/dev/null | head -3)
        [ -n "$_dl_have" ] && { printf >&2 '  заведённые сборки:\n'; printf '%s\n' "$_dl_have" | sed 's/^/    /' >&2; }
        return 1
    fi

    fleet_present || { printf >&2 'среда исполнения не найдена на этой машине\n'; return 1; }
    fleet_ready   || { printf >&2 'среда исполнения не отвечает — запусти её (orca open)\n'; return 1; }

    _dl_base=$(cd "$_dl_root" && git rev-parse --abbrev-ref HEAD 2>/dev/null) || _dl_base=main

    _dl_run=$(fleet_run_create "fraim: сборка $_dl_build") || return 1
    printf 'Run: %s\n' "$_dl_run"

    # The launch-truth channel: fleet_worker_start appends one line per worker
    # (globals die in its command substitution; a file survives it).
    _dl_finfo=$(mktemp) || return 1
    _FLEET_INFO=$_dl_finfo

    _dl_file=$(build_fleet_file "$_dl_root" "$_dl_build")
    printf '# сборка %s · run %s · снято %s\n' \
        "$_dl_build" "$_dl_run" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$_dl_file"

    _dl_bad=0
    # Not a pipe into `while`: the loop must write $_dl_bad and the cache file, and in a
    # subshell both would be lost the moment the pipeline ends.
    _dl_recs=$(dispatch_parse_plan "$_dl_plan")
    for _dl_id in $(printf '%s\n' "$_dl_recs" | cut -d'|' -f1); do
        [ -n "$_dl_id" ] || continue
        _dl_role=$(dispatch_field "$_dl_plan" "$_dl_id" 2)
        _dl_sum=$(dispatch_field "$_dl_plan" "$_dl_id" 3)

        _dl_ex=$(roles_resolve "$_dl_role" "$_dl_root") || { _dl_bad=1; continue; }
        _dl_ag=$(printf '%s' "$_dl_ex" | cut -f1)
        _dl_mo=$(printf '%s' "$_dl_ex" | cut -f2)
        _dl_ef=$(printf '%s' "$_dl_ex" | cut -f3)

        # The assignment is the file we already wrote for this subtask: it is
        # self-contained by construction (G1), which is exactly what a worker that never
        # saw this conversation needs.
        _dl_task_md="$_dl_root/ai/parallel/$_dl_build/$_dl_id/task.md"
        if [ -f "$_dl_task_md" ]; then
            _dl_spec=$(cat "$_dl_task_md")
        else
            _dl_spec=$_dl_sum
        fi

        _dl_task=$(fleet_task_create "$_dl_run" "$_dl_id" "$_dl_spec") || { _dl_bad=1; continue; }
        _dl_disp=$(fleet_worker_start "$_dl_task" "$_dl_ag" "$_dl_mo" "$_dl_ef" \
                       "$_dl_build-$_dl_id" "$_dl_root" "$_dl_base") || {
            printf '%s\t%s\t—\t%s\n' "$_dl_id" "$_dl_task" \
                "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$_dl_file"
            _dl_bad=1; continue
        }

        # Written per worker rather than at the end: a failure on the third subtask must
        # not lose the ids of the two already running.
        printf '%s\t%s\t%s\t%s\n' "$_dl_id" "$_dl_task" "$_dl_disp" \
            "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$_dl_file"
        # Which model actually ran is the one thing a build's cost depends on and the
        # launch is the only place that knows. fleet_worker_start reports the path it
        # took through $_FLEET_INFO (globals die in the command substitution above):
        #   native  — Orca applied the model itself;
        #   custom  — the model rode in the launch command (or nothing did);
        # The in-session `modelcmd_<agent>` stays only as the explicitly configured
        # in-session fallback AFTER a successful launch — it is never guessed.
        _dl_lp=$(tail -1 "$_dl_finfo" 2>/dev/null || :)
        _dl_lpath=$(printf '%s' "$_dl_lp" | cut -f1)
        _dl_lcmd=$(printf '%s' "$_dl_lp" | cut -f2)
        _dl_lmodel=$(printf '%s' "$_dl_lp" | cut -f3)
        : > "$_dl_finfo"
        if [ "$_dl_lpath" = custom ] && [ -n "$_dl_lmodel" ]; then
            printf '  %s → %s (%s %s, модель применена командой запуска «%s»)\n' \
                "$_dl_id" "$_dl_disp" "$_dl_ag" "$_dl_mo" "$_dl_lmodel"
        elif [ "$_dl_lpath" = custom ]; then
            printf '  %s → %s (%s, модель не применяется)\n' "$_dl_id" "$_dl_disp" "$_dl_ag"
            printf '     как %s меняет модель изнутри — неизвестно; научить:\n' "$_dl_ag"
            printf '     fraim config set --machine modelcmd_%s "/model %%s"\n' "$_dl_ag"
        elif fleet_caps_has "$_dl_ag" no-launch-model 2>/dev/null; then
            if _dl_sent=$(fleet_worker_set_model "$_dl_disp" "$_dl_ag" "$_dl_mo" "$_dl_root"); then
                printf '  %s → %s (%s %s, задана командой «%s»)\n' \
                    "$_dl_id" "$_dl_disp" "$_dl_ag" "$_dl_mo" "$_dl_sent"
            else
                printf '  %s → %s (%s, модель не применяется)\n' "$_dl_id" "$_dl_disp" "$_dl_ag"
                printf '     как %s меняет модель изнутри — неизвестно; научить:\n' "$_dl_ag"
                printf '     fraim config set --machine modelcmd_%s "/model %%s"\n' "$_dl_ag"
            fi
        else
            printf '  %s → %s (%s %s %s)\n' "$_dl_id" "$_dl_disp" "$_dl_ag" "$_dl_mo" "$_dl_ef"
        fi
    done

    rm -f "$_dl_finfo"
    [ "$_dl_bad" -eq 0 ]
}

# The dispatch ids of a build, as cached at launch.
build_fleet_rows() {
    _bf=$(build_fleet_file "$1" "$2")
    [ -f "$_bf" ] || return 1
    grep -v '^#' "$_bf" 2>/dev/null | grep '[^[:space:]]' || :
}

# The build journal — MODES.md §11.4, answer D. Deliberately created empty of
# lessons: what belongs in it is not knowable before the first real build, and a
# template invented now would teach the wrong thing.
build_seal() {
    _bs_root=$1; _bs_id=$2; _bs_plan=$3

    _bs_dir=$(build_dir "$_bs_root" "$_bs_id")
    mkdir -p "$_bs_dir" || return 1
    cp "$_bs_plan" "$_bs_dir/plan.md" 2>/dev/null || return 1

    {
        printf '# Журнал сборки %s\n\n' "$_bs_id"
        printf '## Состав\n\n'
        printf -- '- Заведена: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf -- '- База: %s\n' "$(cd "$_bs_root" && git rev-parse --short HEAD 2>/dev/null || echo '—')"
        printf -- '- План: ai/builds/%s/plan.md\n\n' "$_bs_id"
        printf '| подзадача | роль | исход | вне своих путей |\n'
        printf '|---|---|---|---|\n'
        dispatch_parse_plan "$_bs_plan" | while IFS='|' read -r _id _role _sum _paths; do
            [ -n "$_id" ] && printf '| %s | %s | — | — |\n' "$_id" "$_role"
        done
        printf '\n## Уроки дирижёра\n\n'
        printf '<!-- Заполняется после приёмки. MODES.md §11.4: класс уроков, которого нет\n'
        printf '     у воркера — грабли раздачи, а не грабли кода. -->\n'
    } > "$_bs_dir/journal.md" || return 1

    printf '%s\n' "$_bs_dir/journal.md"
}

# Acceptance: one per build, and it refuses rather than reports success on a build
# whose evidence is missing. The earlier version of this function printed "accepted"
# after failing to read the result — the single worst thing an acceptance can do.
build_accept() {
    _ba_root=$1; _ba_id=$2

    _ba_dir=$(build_dir "$_ba_root" "$_ba_id")
    [ -d "$_ba_dir" ] || { printf >&2 'нет такой сборки: %s\n' "$_ba_id"; return 1; }
    [ -f "$_ba_dir/journal.md" ] ||
        { printf >&2 'сборка %s: нет журнала — она не заводилась через dispatch\n' "$_ba_id"; return 1; }
    [ -f "$_ba_dir/accepted" ] &&
        { printf >&2 'сборка %s уже принята\n' "$_ba_id"; return 1; }

    {
        printf 'Принята: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'HEAD: %s\n' "$(cd "$_ba_root" && git rev-parse --short HEAD 2>/dev/null || echo '—')"
    } > "$_ba_dir/accepted" || return 1

    printf '%s\n' "$_ba_dir/accepted"
}

# Pending builds, newest first: id and whether it has been accepted.
# A directory under ai/builds is a BUILD only if it has a journal. Anything else is a
# folder someone put a plan in — that is what ai/builds/v2-core was in the first live
# build, and listing it as a build is what let `dispatch run` be aimed at it.
build_list() {
    _bl_root=$1
    [ -d "$_bl_root/ai/builds" ] || return 0
    for _b in "$_bl_root/ai/builds"/*; do
        [ -d "$_b" ] || continue
        if [ ! -f "$_b/journal.md" ]; then
            printf '%s\tне сборка (нет журнала)\n' "$(basename -- "$_b")"
        elif [ -f "$_b/accepted" ]; then
            printf '%s\tпринята\n' "$(basename -- "$_b")"
        else
            printf '%s\tне принята\n' "$(basename -- "$_b")"
        fi
    done | sort -r
}
