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
#     **After**: B          (optional — order, see waves below)
#     **Summary**: one line, for the worker's task.md
#
#     ### `path/to/file`
#     - why
#
# Role is the name of a PROCEDURE, not a word invented per plan (MODES.md §10 —
# "свою онтологию ролей не заводим"). roles.sh resolves it to agent, model and
# effort; it is the plan's only statement about the executor, on purpose.
# ---------------------------------------------------------------------------

# One record per subtask: id|role|summary|comma-separated paths|comma-separated After ids
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
            if (id != "") print id "|" role "|" summary "|" paths "|" after
            id = ""; role = ""; summary = ""; paths = ""; after = ""
        }
        /^## Subtask:/ { flush(); id = $3; next }
        id == "" { next }
        /^\*\*Role\*\*:/ {
            role = $0; sub(/^\*\*Role\*\*:[[:space:]]*/, "", role); next
        }
        /^\*\*Summary\*\*:/ {
            summary = $0; sub(/^\*\*Summary\*\*:[[:space:]]*/, "", summary); next
        }
        /^\*\*After\*\*:/ {
            after = $0; sub(/^\*\*After\*\*:[[:space:]]*/, "", after); next
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

    # 2. Order: waves are derived here, and a plan whose order does not resolve is refused
    #    before anything else looks at paths — a ghost `After` or a cycle makes every
    #    per-wave answer below meaningless. dispatch_waves names the defect itself.
    if _dc_waves=$(dispatch_waves "$_dc_plan"); then :; else
        printf >&2 'dispatch-check: порядок подзадач не разбирается\n'
        _dc_bad=1
        _dc_waves=
    fi

    # 3. Collision: the same path claimed by two subtasks OF THE SAME WAVE.
    #
    # Across waves a shared path is legal and is the whole point of order: wave N+1 starts
    # from what wave N left in the build branch, so the second worker sees the file as the
    # first one left it. Inside a wave nothing changed — two workers on one file still means
    # git merges both edits silently and "one acceptance" becomes a lie.
    _dc_pairs=$(printf '%s\n' "$_dc_recs" | while IFS='|' read -r _id _role _sum _paths _after; do
        [ -n "$_paths" ] || continue
        _dcp_w=$(printf '%s\n' "$_dc_waves" | awk -F'\t' -v i="$_id" '$1 == i { print $2; exit }')
        printf '%s\n' "$_paths" | tr ',' '\n' | while read -r _p; do
            [ -n "$_p" ] && printf '%s\t%s\t%s\n' "$_p" "${_dcp_w:-1}" "$_id"
        done
    done)
    _dc_dups=$(printf '%s\n' "$_dc_pairs" | cut -f1,2 | sort | uniq -d)
    if [ -n "$_dc_dups" ]; then
        printf >&2 'dispatch-check: один файл у двух подзадач одной волны — так их запускать нельзя:\n'
        printf '%s\n' "$_dc_dups" | while IFS='	' read -r _p _w; do
            [ -n "$_p" ] || continue
            _who=$(printf '%s\n' "$_dc_pairs" |
                   awk -F'\t' -v p="$_p" -v w="$_w" '$1 == p && $2 == w { printf "%s%s", sep, $3; sep=", " }')
            printf >&2 '  %s — волна %s, в подзадачах: %s\n' "$_p" "$_w" "$_who"
        done
        printf >&2 '  выходы по порядку: свести в одну подзадачу · перекроить границы ·\n'
        printf >&2 '  поставить «**After**: ИМЯ» и развести по волнам\n'
        _dc_bad=1
    fi

    # 4. Every role resolves to an executor on THIS machine's table.
    # The loop variable carries a `_dc_` prefix because core.sh's fraim_procedure_file
    # assigns a bare `_r` internally, and sh has no locals: a plain `_r` here comes back
    # holding the install path after the first call into it.
    _dc_roles=$(printf '%s\n' "$_dc_recs" | cut -d'|' -f2 | grep '[^[:space:]]' | sort -u)
    for _dc_r in $_dc_roles; do
        roles_resolve "$_dc_r" "$_dc_root" >/dev/null || _dc_bad=1
    done

    # 5. A known procedure that may not run in parallel. `prune` and the rest write the
    #    foundation, and under this mode the foundation is written by the build once
    #    (invariant 0.4) — dispatching two of them is a collision no path check can see,
    #    because they collide inside the same file the plan never listed.
    #    An UNKNOWN role is not refused here: it already fell back to a default executor
    #    in step 4, and refusing a plan because this machine lacks a procedure would make
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

    # 6. Known refusals. Not a failure — the launch will handle it — but the conductor
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

# ---------------------------------------------------------------------------
# Waves: the order inside a plan
#
# A subtask may declare `**After**: id[, id]` — it runs after the named ones. Waves are
# DERIVED from that, never written by hand: wave(x) = 1 + max(wave(its After)), a subtask
# with no After is wave 1. The reason is that a dependency is a LOCAL fact the author of
# the block knows, while a wave number is a global fact about the whole plan that has to be
# recomputed by hand on every edit — and a stale renumbering is exactly the error no check
# could see.
#
# This is the Bulk Synchronous Parallel model (Pregel, MapReduce): a wave is a superstep,
# and the barrier between waves is what makes every merge conflict-free by construction —
# inside a wave paths cannot collide, and nothing else writes to the build branch while the
# wave runs. The cost is the idle worker: a wave waits for its slowest piece. That cost is
# paid on purpose; the alternative (start each subtask the moment ITS dependencies land) is
# a scheduler of our own, which MODES.md §10 forbids, and it would also make merges depend
# on the completion signal — the one thing this design refuses to trust.
#
# Prints `id<TAB>wave`, in plan order. Refuses (exit 1) on an After that names nothing and
# on a dependency cycle, because both cost N launches to discover otherwise.
# ---------------------------------------------------------------------------
dispatch_waves() {
    dispatch_parse_plan "$1" | awk -F'|' '
        { n = NR; id[n] = $1; after[n] = $5; known[$1] = 1 }
        END {
            for (i = 1; i <= n; i++) {
                if (after[i] == "") continue
                m = split(after[i], a, ",")
                for (j = 1; j <= m; j++) {
                    gsub(/^[ \t]+|[ \t]+$/, "", a[j])
                    if (a[j] == "") continue
                    if (!(a[j] in known)) {
                        printf "подзадача %s: «After: %s» — такой подзадачи в плане нет\n", \
                            id[i], a[j] > "/dev/stderr"
                        bad = 1
                    }
                }
            }
            if (bad) exit 1

            for (i = 1; i <= n; i++) w[i] = 1
            # One relaxation pass can only raise a level by one, so n passes suffice for an
            # acyclic plan. Still changing after that means a cycle — and a cycle must be
            # named rather than silently levelled, or the plan runs in an order nobody meant.
            for (pass = 0; pass <= n; pass++) {
                changed = 0
                for (i = 1; i <= n; i++) {
                    if (after[i] == "") continue
                    m = split(after[i], a, ",")
                    for (j = 1; j <= m; j++) {
                        gsub(/^[ \t]+|[ \t]+$/, "", a[j])
                        if (a[j] == "") continue
                        for (k = 1; k <= n; k++)
                            if (id[k] == a[j] && w[k] + 1 > w[i]) { w[i] = w[k] + 1; changed = 1 }
                    }
                }
                if (!changed) break
            }
            if (changed) {
                print "цикл зависимостей: волны не выводятся, план надо переписать" > "/dev/stderr"
                exit 1
            }
            for (i = 1; i <= n; i++) printf "%s\t%s\n", id[i], w[i]
        }'
}

# The subtasks of one wave, in plan order.
#
# Taken first, filtered second — for the same reason as dispatch_wave_count: a pipeline
# reports its LAST command's status, so piping straight into awk would answer "no such
# wave" for a plan that was in fact refused for a cycle.
dispatch_wave_ids() {
    _wi_all=$(dispatch_waves "$1") || return 1
    printf '%s\n' "$_wi_all" | awk -F'\t' -v w="$2" '$2 == w { print $1 }'
}

# How many waves the plan has. 1 for a plan that declares no order at all.
#
# The wave list is taken first and cut afterwards: a pipeline's status is its LAST command's,
# so `dispatch_waves … | cut` would report the exit code of `cut` and turn a refused plan
# (ghost After, cycle) into a confident "1 wave".
dispatch_wave_count() {
    _wc_all=$(dispatch_waves "$1") || return 1
    _wc=$(printf '%s\n' "$_wc_all" | cut -f2 | sort -n | tail -1)
    printf '%s\n' "${_wc:-1}"
}

# ---------------------------------------------------------------------------
# The arithmetic of a build: what it costs, and whether one acceptance stays honest
#
# Every number here comes from ONE scarce resource, and it is not the machine and not the
# subscription: it is the single acceptance (MODES.md §5). A build of twelve subtasks is
# not accepted by one decision but by twelve, and then the mode's whole promise is a lie.
#
# They are WARNINGS, never refusals, and the line between the two is the point:
#   - refuse only on what the machine knows exactly — a path in two subtasks of one wave,
#     a cycle, an unresolvable role. Those are facts.
#   - warn on all arithmetic of size. A file count does not measure work, and refusing on
#     such a metric would be lying with precision.
# The conductor reads the warning and decides; that is the same division as the watchman's
# («сторож замечает, человек решает»).
#
# The time threshold that used to live here («кусок дольше получаса») is deliberately
# absent: nobody can measure it — not the conductor before dispatch, not the human, not
# the machine after — and it read as a rule while working as the cheapest excuse to refuse.
# What replaces it is a comparison the conductor states out loud in the plan: dispatching
# is worth it when executing the piece costs more than dispatching it.
# ---------------------------------------------------------------------------
DISPATCH_MAX_SUBTASKS=6
DISPATCH_WAVE_MIN=3
DISPATCH_WAVE_MAX=5
DISPATCH_MAX_WAVES=3
DISPATCH_PATHS_MIN=2
DISPATCH_PATHS_MAX=10

# Warnings about size. Prints to stderr and always returns 0 — a caller must never be able
# to turn these into a refusal by accident.
dispatch_size_notes() {
    _sn_plan=$1
    _sn_recs=$(dispatch_parse_plan "$_sn_plan")
    [ -n "$_sn_recs" ] || return 0

    _sn_n=$(printf '%s\n' "$_sn_recs" | grep -c '[^[:space:]]')
    [ "$_sn_n" -le "$DISPATCH_MAX_SUBTASKS" ] ||
        printf >&2 'подзадач %s: приёмка одним решением на такой сборке сомнительна (потолок %s)\n' \
            "$_sn_n" "$DISPATCH_MAX_SUBTASKS"

    # Width and depth. Until a plan declares order, the whole build is one wave, and the
    # width IS the count — so this reads correctly both before and after waves exist.
    _sn_waves=$(dispatch_waves "$_sn_plan" 2>/dev/null) || _sn_waves=
    if [ -n "$_sn_waves" ]; then
        _sn_depth=$(printf '%s\n' "$_sn_waves" | cut -f2 | sort -n | tail -1)
        [ "${_sn_depth:-1}" -le "$DISPATCH_MAX_WAVES" ] ||
            printf >&2 'волн %s: это уже последовательный проект, а не сборка (потолок %s)\n' \
                "$_sn_depth" "$DISPATCH_MAX_WAVES"
        _sn_w=1
        while [ "$_sn_w" -le "${_sn_depth:-1}" ]; do
            _sn_wn=$(printf '%s\n' "$_sn_waves" | awk -F'\t' -v w="$_sn_w" '$2 == w' | grep -c '[^[:space:]]')
            if [ "$_sn_wn" -gt "$DISPATCH_WAVE_MAX" ]; then
                printf >&2 'волна %s: %s подзадач одновременно — координация и приёмка растут быстрее выигрыша (потолок %s)\n' \
                    "$_sn_w" "$_sn_wn" "$DISPATCH_WAVE_MAX"
            elif [ "$_sn_wn" -lt "$DISPATCH_WAVE_MIN" ] && [ "${_sn_depth:-1}" -eq 1 ]; then
                # Only for a single-wave build: a narrow wave inside a chain is the point
                # of waves, not a mistake.
                printf >&2 'подзадач %s: раздача редко окупается ниже %s — но считаешь ты, а не эта строка\n' \
                    "$_sn_wn" "$DISPATCH_WAVE_MIN"
            fi
            _sn_w=$(( _sn_w + 1 ))
        done
    fi

    printf '%s\n' "$_sn_recs" | while IFS='|' read -r _sn_id _sn_role _sn_sum _sn_paths _sn_after; do
        [ -n "$_sn_id" ] || continue
        _sn_pn=$(printf '%s\n' "$_sn_paths" | tr ',' '\n' | grep -c '[^[:space:]]')
        if [ "$_sn_pn" -lt "$DISPATCH_PATHS_MIN" ]; then
            printf >&2 'подзадача %s: %s путь — вероятно, мельче цены раздачи\n' "$_sn_id" "$_sn_pn"
        elif [ "$_sn_pn" -gt "$DISPATCH_PATHS_MAX" ]; then
            printf >&2 'подзадача %s: %s путей — вероятно, это два куска, а не один\n' "$_sn_id" "$_sn_pn"
        fi
    done
    return 0
}

# The one line that answers "what does this build cost and what does it buy", printed
# before a single worker starts. Google's Rosie grew a formal review process for exactly
# this reason: an expensive mechanism aimed at cheap work eats more than it gives, and the
# cheapest guard against that is making the arithmetic visible at the moment of the choice.
dispatch_cost_line() {
    _cl_plan=$1
    _cl_n=$(dispatch_subtask_ids "$_cl_plan" | grep -c '[^[:space:]]')
    _cl_waves=$(dispatch_waves "$_cl_plan" 2>/dev/null) || _cl_waves=
    _cl_depth=1
    [ -n "$_cl_waves" ] && _cl_depth=$(printf '%s\n' "$_cl_waves" | cut -f2 | sort -n | tail -1)
    _cl_wide=$_cl_n
    if [ -n "$_cl_waves" ]; then
        _cl_wide=$(printf '%s\n' "$_cl_waves" | cut -f2 | sort | uniq -c | awk '{ if ($1 > m) m = $1 } END { print m + 0 }')
    fi
    printf 'состав: %s %s, %s %s, %s %s одновременно\n' \
        "$_cl_n" "$(dispatch_plural "$_cl_n" подзадача подзадачи подзадач)" \
        "${_cl_depth:-1}" "$(dispatch_plural "${_cl_depth:-1}" волна волны волн)" \
        "$_cl_wide" "$(dispatch_plural "$_cl_wide" воркер воркера воркеров)"
}

# Russian plural for the counts above. Borrowed shape from wm_plural, kept local because
# dispatch.sh must stay usable without the watchman.
dispatch_plural() {
    _dp_n=$1
    case $(( _dp_n % 100 )) in
        1[1-9]) printf '%s\n' "$4" ;;
        *) case $(( _dp_n % 10 )) in
               1) printf '%s\n' "$2" ;;
               2|3|4) printf '%s\n' "$3" ;;
               *) printf '%s\n' "$4" ;;
           esac ;;
    esac
}

# What dispatch is about to do, before it does it: who runs what, on which model,
# and where that answer came from. Printed for the conductor to read — a run on the
# built-in default when the project meant to name a role is the kind of thing that
# is obvious here and invisible three hours later.
dispatch_report() {
    _dr_plan=$1; _dr_root=${2:-}
    _dr_waves=$(dispatch_waves "$_dr_plan" 2>/dev/null) || _dr_waves=
    # Literal: POSIX printf pads bytes, and Cyrillic headings would land short.
    printf 'волна  подзадача  роль            агент   модель   усилие  источник\n'
    dispatch_parse_plan "$_dr_plan" | while IFS='|' read -r _id _role _sum _paths _after; do
        [ -n "$_id" ] || continue
        _ex=$(roles_resolve "$_role" "$_dr_root") || continue
        _ag=$(printf '%s' "$_ex" | cut -f1)
        _mo=$(printf '%s' "$_ex" | cut -f2)
        _ef=$(printf '%s' "$_ex" | cut -f3)
        _w=$(printf '%s\n' "$_dr_waves" | awk -F'\t' -v i="$_id" '$1 == i { print $2; exit }')
        printf '%-6s %-10s %-15s %-7s %-8s %-7s %s\n' \
            "${_w:-1}" "$_id" "$_role" "$_ag" "$_mo" "$_ef" "$(roles_source "$_role" "$_dr_root")"
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
        printf -- '  собирают слиянием веток, и то, что не в коммите, до неё не доедет —\n'
        printf -- '  сбор откажется собирать твою подзадачу и назовёт незакоммиченные файлы.\n'
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

# The branch a build is assembled on. Named after the build, so a project may carry several
# and none of them is the trunk.
build_branch() { printf 'fraim/%s\n' "$1"; }

# wave<TAB>subtask<TAB>merged sha<TAB>time. The record of what actually came back, in git —
# «что кому роздано и что вернулось» is our truth (A3), unlike fleet.tsv which is a cache
# of the environment's ids.
build_collected_file() { printf '%s/collected.tsv\n' "$(build_dir "$1" "$2")"; }

build_is_collected() {
    _bic=$(build_collected_file "$1" "$2")
    [ -f "$_bic" ] || return 1
    awk -F'\t' -v s="$3" '$2 == s { found = 1 } END { exit !found }' "$_bic"
}

# The first wave that is not fully collected — what `dispatch run` launches when nobody
# names a wave. A wave counts as collected only when every one of its subtasks is in
# collected.tsv, so a wave where one worker was refused stays open and re-collecting it
# picks up exactly what is missing.
build_next_wave() {
    _bnw_root=$1; _bnw_build=$2
    _bnw_plan="$(build_dir "$_bnw_root" "$_bnw_build")/plan.md"
    [ -f "$_bnw_plan" ] || return 1
    _bnw_max=$(dispatch_wave_count "$_bnw_plan") || return 1
    _bnw_w=1
    while [ "$_bnw_w" -le "$_bnw_max" ]; do
        for _bnw_id in $(dispatch_wave_ids "$_bnw_plan" "$_bnw_w"); do
            build_is_collected "$_bnw_root" "$_bnw_build" "$_bnw_id" || {
                printf '%s\n' "$_bnw_w"; return 0
            }
        done
        _bnw_w=$(( _bnw_w + 1 ))
    done
    return 1
}

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

# Start one WAVE of a build. Returns 1 if any worker failed to start — but only after
# trying them all, because the subtasks of a wave are independent by construction and
# abandoning the rest would throw away work that is already running.
#
# Which wave: the one named, or the first that is not fully collected. The conductor never
# has to remember a number, and the barrier is enforced here — while a wave is uncollected,
# `run` keeps offering that same wave rather than racing ahead into work whose base does not
# exist yet.
dispatch_launch() {
    _dl_root=$1; _dl_build=$2; _dl_wave=${3:-}

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

    if [ -z "$_dl_wave" ]; then
        _dl_wave=$(build_next_wave "$_dl_root" "$_dl_build") || {
            printf >&2 'все волны сборки %s собраны — поднимать нечего\n' "$_dl_build"
            return 1
        }
    fi
    _dl_ids=$(dispatch_wave_ids "$_dl_plan" "$_dl_wave") || return 1
    [ -n "$_dl_ids" ] || {
        printf >&2 'в сборке %s нет волны %s\n' "$_dl_build" "$_dl_wave"; return 1
    }
    printf 'Волна %s\n' "$_dl_wave"

    # Workers branch from the BUILD branch, not from whatever the conductor has checked
    # out: that is what lets a later wave start on top of what an earlier one left, and it
    # keeps the trunk out of the fleet's way entirely. Builds created before the build
    # branch existed fall back to the current branch, so an old build still launches.
    _dl_base=$(build_branch "$_dl_build")
    git -C "$_dl_root" rev-parse --verify --quiet "refs/heads/$_dl_base" >/dev/null 2>&1 ||
        _dl_base=$(cd "$_dl_root" && git rev-parse --abbrev-ref HEAD 2>/dev/null) || _dl_base=main

    _dl_run=$(fleet_run_create "fraim: сборка $_dl_build") || return 1
    printf 'Run: %s\n' "$_dl_run"

    # The launch-truth channel: fleet_worker_start appends one line per worker
    # (globals die in its command substitution; a file survives it).
    _dl_finfo=$(mktemp) || return 1
    _FLEET_INFO=$_dl_finfo

    # Appended, not truncated: a second wave must not erase the first wave's ids, which are
    # the only record of who ran what if the environment forgets.
    _dl_file=$(build_fleet_file "$_dl_root" "$_dl_build")
    printf '# сборка %s · волна %s · run %s · снято %s\n' \
        "$_dl_build" "$_dl_wave" "$_dl_run" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$_dl_file"

    _dl_bad=0
    # Not a pipe into `while`: the loop must write $_dl_bad and the cache file, and in a
    # subshell both would be lost the moment the pipeline ends.
    for _dl_id in $_dl_ids; do
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

    # The build branch, created here and never checked out in the project root. Workers
    # branch FROM it and their results are merged back INTO it, so the trunk stays
    # untouched until a human moves it there after acceptance — the gate stands before
    # the write to the trunk (MODES.md §4, вариант A), and a merge verb must not quietly
    # step over it.
    _bs_br=$(build_branch "$_bs_id")
    if ! git -C "$_bs_root" rev-parse --verify --quiet "refs/heads/$_bs_br" >/dev/null 2>&1; then
        git -C "$_bs_root" branch "$_bs_br" >/dev/null 2>&1 ||
            printf >&2 'не удалось завести ветку сборки %s — сбор работать не будет\n' "$_bs_br"
    fi

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

# ---------------------------------------------------------------------------
# Collect: the stage that was missing entirely
#
# Until this existed, nothing brought the workers' results together: `build_accept` recorded
# a time and a HEAD, and the merging was done by hand. Both mature answers to the same
# problem outside our world make integration a first-class stage — Zuul's gate queue, which
# tests each change on a tree that already carries the ones ahead of it, and Google's Rosie,
# which submits each shard on its own — and neither leaves it to the end of the process.
# Waves need it twice over: wave N+1 branches from what wave N left behind.
#
# Four refusals, and each is a lesson rather than a preference:
#   1. no checkout for a subtask        — there is nothing to collect, and guessing is worse
#   2. uncommitted work in the checkout — a merge takes commits; the first live build had a
#                                         worker finish and leave it unstaged
#   3. a file outside the declared paths — this is the one line the tree verification exists
#                                         to produce (MODES.md §3); merging it with a warning
#                                         would make the check decorative
#   4. a merge conflict                 — inside a wave paths cannot collide and nothing else
#                                         writes to the build branch, so a conflict means an
#                                         assumption broke. Never auto-resolved.
#
# The merge happens in a throwaway checkout of the build branch: the conductor's own working
# tree is never switched, and a failed merge leaves no half-merged state anywhere.
# ---------------------------------------------------------------------------

# One subtask into the build branch. Prints the merged sha on success.
dispatch_merge_one() {
    _mo_root=$1; _mo_branch=$2; _mo_sha=$3; _mo_msg=$4

    _mo_tmp=$(mktemp -d) || return 1
    rmdir "$_mo_tmp" 2>/dev/null || :
    if ! git -C "$_mo_root" worktree add --quiet "$_mo_tmp" "$_mo_branch" >/dev/null 2>&1; then
        printf >&2 'не удалось открыть чекаут ветки сборки %s\n' "$_mo_branch"
        return 1
    fi

    _mo_rc=0
    if ! git -C "$_mo_tmp" merge --no-ff -m "$_mo_msg" "$_mo_sha" >/dev/null 2>&1; then
        printf >&2 'конфликт слияния:\n'
        git -C "$_mo_tmp" diff --name-only --diff-filter=U 2>/dev/null | sed 's/^/    /' >&2
        git -C "$_mo_tmp" merge --abort >/dev/null 2>&1 || :
        _mo_rc=1
    fi

    git -C "$_mo_root" worktree remove --force "$_mo_tmp" >/dev/null 2>&1 || rm -rf "$_mo_tmp"
    [ "$_mo_rc" -eq 0 ] || return 1
    git -C "$_mo_root" rev-parse --short "$_mo_branch" 2>/dev/null
}

# Collect one wave. Returns 1 if any subtask was refused — after trying them all, because
# the ones that pass are independent by construction and holding them back helps nobody.
dispatch_collect() {
    _co_root=$1; _co_build=$2; _co_wave=${3:-}

    _co_dir=$(build_dir "$_co_root" "$_co_build")
    _co_plan="$_co_dir/plan.md"
    [ -f "$_co_plan" ] || { printf >&2 'нет плана сборки %s\n' "$_co_build"; return 1; }
    [ -f "$_co_dir/journal.md" ] ||
        { printf >&2 'сборка %s не заводилась: нет журнала\n' "$_co_build"; return 1; }

    _co_branch=$(build_branch "$_co_build")
    git -C "$_co_root" rev-parse --verify --quiet "refs/heads/$_co_branch" >/dev/null 2>&1 || {
        printf >&2 'нет ветки сборки %s — эта сборка заведена до появления сбора\n' "$_co_branch"
        return 1
    }

    if [ -z "$_co_wave" ]; then
        _co_wave=$(build_next_wave "$_co_root" "$_co_build") || {
            printf >&2 'все волны сборки %s уже собраны\n' "$_co_build"; return 1
        }
    fi

    _co_ids=$(dispatch_wave_ids "$_co_plan" "$_co_wave") || return 1
    [ -n "$_co_ids" ] || { printf >&2 'в сборке %s нет волны %s\n' "$_co_build" "$_co_wave"; return 1; }

    # Where the build branch stood before this wave: the base for the combined diff the
    # conductor reads at the end, and the point every worker of this wave branched from.
    _co_before=$(git -C "$_co_root" rev-parse "$_co_branch" 2>/dev/null)
    _co_file=$(build_collected_file "$_co_root" "$_co_build")
    _co_bad=0

    printf 'Волна %s сборки %s\n' "$_co_wave" "$_co_build"
    for _co_id in $_co_ids; do
        if build_is_collected "$_co_root" "$_co_build" "$_co_id"; then
            printf '  %-12s уже собрана\n' "$_co_id"
            continue
        fi

        _co_tree=$(dispatch_worker_tree "$_co_root" "$_co_build-$_co_id")
        if [ -z "$_co_tree" ]; then
            printf '  %-12s чекаута нет — собирать нечего\n' "$_co_id"
            _co_bad=1; continue
        fi

        _co_dirty=$(cd "$_co_tree" 2>/dev/null && {
                git status --porcelain 2>/dev/null | head -20
            })
        if [ -n "$_co_dirty" ]; then
            printf '  %-12s есть незакоммиченное — слить можно только коммит:\n' "$_co_id"
            printf '%s\n' "$_co_dirty" | sed 's/^/      /'
            _co_bad=1; continue
        fi

        _co_base=$(git -C "$_co_tree" merge-base HEAD "$_co_branch" 2>/dev/null)
        [ -n "$_co_base" ] || _co_base=$_co_before
        _co_paths=$(dispatch_field "$_co_plan" "$_co_id" 4)

        # The tree, not the report (MODES.md §3). This runs BEFORE the merge on purpose:
        # after it, a stray file is already in the build branch and the check is archaeology.
        _co_out=$(dispatch_verify_tree "$_co_tree" "$_co_base" "$_co_paths" 2>/dev/null |
                  sed -n 's/^outside://p')
        if [ -n "$_co_out" ]; then
            printf '  %-12s вышла за свои пути — не сливаю:\n' "$_co_id"
            printf '%s\n' "$_co_out" | sed 's/^/      /'
            _co_bad=1; continue
        fi

        _co_sha=$(git -C "$_co_tree" rev-parse HEAD 2>/dev/null)
        if [ "$_co_sha" = "$_co_base" ]; then
            printf '  %-12s ничего не изменила\n' "$_co_id"
            printf '%s\t%s\t—\t%s\n' "$_co_wave" "$_co_id" \
                "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$_co_file"
            continue
        fi

        if _co_merged=$(dispatch_merge_one "$_co_root" "$_co_branch" "$_co_sha" \
                            "сборка $_co_build: подзадача $_co_id"); then
            printf '  %-12s слита → %s\n' "$_co_id" "$_co_merged"
            printf '%s\t%s\t%s\t%s\n' "$_co_wave" "$_co_id" "$_co_merged" \
                "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$_co_file"
        else
            printf '  %-12s слияние не прошло\n' "$_co_id"
            _co_bad=1
        fi
    done

    _co_after=$(git -C "$_co_root" rev-parse "$_co_branch" 2>/dev/null)

    # The combined diff of the whole wave, not one subtask at a time. This is the only place
    # where a divergence the path check cannot see — two workers naming the same thing
    # differently, two different error formats — becomes visible at all. It is a look, not
    # a verdict: nothing here decides anything, the conductor reads it.
    if [ -n "$_co_before" ] && [ "$_co_before" != "$_co_after" ]; then
        printf '\nЧто волна изменила целиком:\n'
        git -C "$_co_root" diff --stat "$_co_before" "$_co_after" 2>/dev/null | sed 's/^/  /'
    fi

    {
        printf '\n## Сбор волны %s — %s\n\n' "$_co_wave" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        if [ -f "$_co_file" ]; then
            awk -F'\t' -v w="$_co_wave" '$1 == w { printf "- %s → %s\n", $2, $3 }' "$_co_file"
        fi
        [ "$_co_bad" -eq 0 ] || printf -- '- собрана не полностью: часть подзадач отклонена\n'
    } >> "$_co_dir/journal.md"

    [ "$_co_bad" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Acceptance: the conductor's work, and the report a human ratifies over
#
# One word carried two different things, and the CLI stamped only the second. `build_accept`
# wrote a time and a HEAD; everything that should have come before it — verify each subtask
# against the tree, look at what the build changed as a whole, run the project's own check on
# the assembled branch, tidy up what the fleet created — was a list of commands somebody had
# to remember, one at a time, in a chat. What reached the human was N diffs and the word
# «принято», which is the opposite of what the mode promises (MODES.md §5).
#
# Split the word and each half gets an owner:
#
#   приёмка      — CHECKING. The conductor verifies, looks, runs the check, cleans up and
#                  writes a report. It is work, and work is what a conductor is for.
#   ратификация  — JUDGEMENT. «Годится?» — the human's, over that report, and nothing
#                  reaches the trunk without it.
#
# B5 is untouched by this, and the distinction is the reason: the stop for judgement still
# exists and still belongs to the human — it now stands in front of one report instead of in
# front of N diffs. What moved is the labour, not the authority.
#
# What this deliberately does NOT do is write the trunk. The gate stands before that write
# (MODES.md §4, вариант A) and no verb steps over it: the report ends with the command for
# the human to type, and typing it is the ratification.
# ---------------------------------------------------------------------------

build_report_file()   { printf '%s/report.md\n' "$(build_dir "$1" "$2")"; }
build_accepted_file() { printf '%s/accepted\n'  "$(build_dir "$1" "$2")"; }
build_returned_file() { printf '%s/returned\n'  "$(build_dir "$1" "$2")"; }

# Where the build branch started. The journal wrote it down when the build was sealed —
# that is our record (A3), and it stays true after the trunk moves on. Only when the line
# is missing or no longer resolves do we ask git for the fork point.
build_base_sha() {
    _bb_root=$1; _bb_build=$2
    _bb_s=$(sed -n 's/^- База: //p' "$(build_dir "$_bb_root" "$_bb_build")/journal.md" 2>/dev/null |
            head -1 | tr -d ' ')
    if [ -n "$_bb_s" ] && [ "$_bb_s" != "—" ] &&
       git -C "$_bb_root" rev-parse --verify --quiet "$_bb_s^{commit}" >/dev/null 2>&1; then
        printf '%s\n' "$_bb_s"; return 0
    fi
    git -C "$_bb_root" merge-base "$(build_branch "$_bb_build")" HEAD 2>/dev/null
}

# Every path any subtask declared, one per line. The union is what this build was allowed
# to touch; anything else in the assembled branch was declared by nobody.
build_declared_paths() {
    dispatch_parse_plan "$1" | cut -d'|' -f4 | tr ',' '\n' |
        sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep '[^[:space:]]' | sort -u
}

# Subtasks of the plan that are not in collected.tsv. Asked positively on purpose:
# `build_next_wave` answers "nothing left" both when everything is collected and when the
# plan cannot be read, and an acceptance must not read the second as the first.
build_open_subtasks() {
    _os_root=$1; _os_build=$2
    for _os_id in $(dispatch_subtask_ids "$(build_dir "$_os_root" "$_os_build")/plan.md" 2>/dev/null); do
        [ -n "$_os_id" ] || continue
        build_is_collected "$_os_root" "$_os_build" "$_os_id" || printf '%s\n' "$_os_id"
    done
}

# The project's own check, run on the ASSEMBLED branch rather than on any one worker's
# result: the failure it catches is the one no worker could see — two results each correct
# on its own and wrong together. The command is project configuration (C1), so it lives in
# `build_check` and not in this file; unset, the report says so instead of implying a pass.
#
# Writes the command's output to $3. Prints its verdict: `нет` (nothing configured),
# `нельзя` (the checkout could not be opened) or the command's exit code.
build_master_check() {
    _mc_root=$1; _mc_build=$2; _mc_out=$3
    : > "$_mc_out" 2>/dev/null || :

    _mc_cmd=$(config_get build_check "$_mc_root")
    [ -n "$_mc_cmd" ] || { printf 'нет\n'; return 0; }

    _mc_tmp=$(mktemp -d) || { printf 'нельзя\n'; return 0; }
    rmdir "$_mc_tmp" 2>/dev/null || :
    if ! git -C "$_mc_root" worktree add --quiet "$_mc_tmp" \
             "$(build_branch "$_mc_build")" >/dev/null 2>&1; then
        printf 'нельзя\n'; return 0
    fi

    ( cd "$_mc_tmp" 2>/dev/null && sh -c "$_mc_cmd" ) > "$_mc_out" 2>&1
    _mc_rc=$?
    git -C "$_mc_root" worktree remove --force "$_mc_tmp" >/dev/null 2>&1 || rm -rf "$_mc_tmp"
    printf '%s\n' "$_mc_rc"
}

# Чистка: only what this build itself created, and only once it is provably redundant.
#
# This is B6 scaled to the fleet (MODES.md §3): there is no «прибрать лишние воркtree» here.
# The list comes from the build's own record — the subtasks of its plan, the dispatch ids in
# its fleet.tsv — so nobody ever decides "what not to touch": another build's checkouts, and
# the ones a human opened by hand, are not on the list to begin with.
#
# A checkout goes only when its commit is already an ancestor of the build branch: then the
# tree holds nothing git does not already have. Uncommitted work is a refusal, never a
# --force — the first live build had a worker finish and leave its work unstaged, and
# deleting that would destroy exactly what the mode exists to collect. The --force below
# runs only after that check has passed and covers ignored artefacts (a node_modules is what
# stops a plain `worktree remove`, and it is not work).
#
# One TSV line per resource: kind, name, verdict.
build_cleanup() {
    _cl_root=$1; _cl_build=$2
    _cl_plan="$(build_dir "$_cl_root" "$_cl_build")/plan.md"
    _cl_branch=$(build_branch "$_cl_build")

    for _cl_id in $(dispatch_subtask_ids "$_cl_plan" 2>/dev/null); do
        [ -n "$_cl_id" ] || continue
        _cl_tree=$(dispatch_worker_tree "$_cl_root" "$_cl_build-$_cl_id")
        [ -n "$_cl_tree" ] || continue

        _cl_dirty=$(cd "$_cl_tree" 2>/dev/null && git status --porcelain 2>/dev/null | head -5)
        if [ -n "$_cl_dirty" ]; then
            printf 'чекаут\t%s\tоставлен: есть незакоммиченное\n' "$_cl_id"
            continue
        fi
        _cl_sha=$(git -C "$_cl_tree" rev-parse HEAD 2>/dev/null)
        if [ -z "$_cl_sha" ] ||
           ! git -C "$_cl_root" merge-base --is-ancestor "$_cl_sha" "$_cl_branch" >/dev/null 2>&1; then
            printf 'чекаут\t%s\tоставлен: работы нет в ветке сборки\n' "$_cl_id"
            continue
        fi
        if git -C "$_cl_root" worktree remove --force "$_cl_tree" >/dev/null 2>&1; then
            printf 'чекаут\t%s\tснят\n' "$_cl_id"
        else
            printf 'чекаут\t%s\tоставлен: git не снял\n' "$_cl_id"
        fi
    done

    # The environment's own resources. Their release verb closes exactly the worker's own
    # terminal and nothing else (§9.6) — that is B6 implemented on their side, which is why
    # we call it instead of killing anything ourselves. Best-effort: an environment that is
    # not running is not a failed acceptance.
    if fleet_present && fleet_ready >/dev/null 2>&1; then
        build_fleet_rows "$_cl_root" "$_cl_build" 2>/dev/null |
        while IFS='	' read -r _cl_s _cl_t _cl_d _cl_at; do
            [ -n "$_cl_d" ] && [ "$_cl_d" != "—" ] || continue
            if fleet_worker_release "$_cl_d" >/dev/null 2>&1; then
                printf 'воркер\t%s\tосвобождён\n' "$_cl_d"
            else
                printf 'воркер\t%s\tсреда не ответила\n' "$_cl_d"
            fi
        done
    fi
}

# The conductor's acceptance. Refuses rather than reports success on a build whose evidence
# is missing — an earlier version printed «принято» after failing to read the result, which
# is the single worst thing an acceptance can do.
#
# Returns 0 when the report has nothing for anyone to deal with, 1 when it has. The report
# is written either way: «проектная проверка красная» is a valid report, and withholding it
# would leave the human with nothing to ratify over at all.
build_accept() {
    _ba_root=$1; _ba_id=$2

    _ba_dir=$(build_dir "$_ba_root" "$_ba_id")
    [ -d "$_ba_dir" ] || { printf >&2 'нет такой сборки: %s\n' "$_ba_id"; return 2; }
    [ -f "$_ba_dir/journal.md" ] ||
        { printf >&2 'сборка %s: нет журнала — она не заводилась через dispatch\n' "$_ba_id"; return 2; }
    [ -f "$_ba_dir/plan.md" ] ||
        { printf >&2 'сборка %s: нет плана — принимать нечего\n' "$_ba_id"; return 2; }
    if [ -f "$(build_accepted_file "$_ba_root" "$_ba_id")" ]; then
        printf >&2 'сборка %s уже принята дирижёром — отчёт в ai/builds/%s/report.md\n' \
            "$_ba_id" "$_ba_id"
        printf >&2 '  если человек вернул её словами, запиши это: fraim dispatch return %s "что не так"\n' "$_ba_id"
        return 2
    fi

    _ba_branch=$(build_branch "$_ba_id")
    git -C "$_ba_root" rev-parse --verify --quiet "refs/heads/$_ba_branch" >/dev/null 2>&1 || {
        printf >&2 'нет ветки сборки %s — эта сборка заведена до появления сбора\n' "$_ba_branch"
        return 2
    }

    _ba_ids=$(dispatch_subtask_ids "$_ba_dir/plan.md")
    [ -n "$_ba_ids" ] || { printf >&2 'в плане сборки %s нет подзадач\n' "$_ba_id"; return 2; }

    # Nothing is accepted while a subtask is still out. A report over a half-collected build
    # would describe work that is not there and call it the build.
    _ba_open=$(build_open_subtasks "$_ba_root" "$_ba_id")
    if [ -n "$_ba_open" ]; then
        printf >&2 'сборка %s собрана не вся — не принимаю:\n' "$_ba_id"
        printf '%s\n' "$_ba_open" | sed 's/^/    /' >&2
        printf >&2 '  собрать:  fraim dispatch collect %s\n' "$_ba_id"
        return 2
    fi

    printf 'Приёмка сборки %s — проверяю за воркерами\n' "$_ba_id"

    _ba_head=$(git -C "$_ba_root" rev-parse --short "$_ba_branch" 2>/dev/null)
    _ba_base=$(git -C "$_ba_root" rev-parse --short "$(build_base_sha "$_ba_root" "$_ba_id")" 2>/dev/null)
    _ba_coll=$(build_collected_file "$_ba_root" "$_ba_id")
    _ba_n=$(printf '%s\n' "$_ba_ids" | grep -c '[^[:space:]]')
    _ba_waves=$(dispatch_wave_count "$_ba_dir/plan.md" 2>/dev/null || echo 1)

    _ba_tmp=$(mktemp -d) || { printf >&2 'нет временного каталога\n'; return 2; }
    _ba_find=          # what somebody has to deal with, one line each

    # --- что вернулось: the tree, not the reports (MODES.md §3) ---------------
    _ba_changed=$(git -C "$_ba_root" diff --name-only "$_ba_base" "$_ba_branch" 2>/dev/null |
                  grep '[^[:space:]]' | sort -u)
    _ba_nfiles=$(printf '%s' "$_ba_changed" | grep -c '[^[:space:]]')
    build_declared_paths "$_ba_dir/plan.md" > "$_ba_tmp/declared"
    _ba_undecl=$(printf '%s\n' "$_ba_changed" | grep '[^[:space:]]' |
                 grep -vxF -f "$_ba_tmp/declared" 2>/dev/null || :)

    _ba_empty=$(awk -F'\t' '$3 == "—" { print $2 }' "$_ba_coll" 2>/dev/null | sort -u)
    [ -n "$_ba_empty" ] &&
        _ba_find="$_ba_find- ничего не изменили: $(printf '%s' "$_ba_empty" | tr '\n' ' ')— пустой результат это тоже исход, и обычно плохой
"
    [ "$_ba_nfiles" -eq 0 ] &&
        _ba_find="$_ba_find- сборка не изменила ни одного файла: принимать нечего
"

    # Под флотом фундамент пишет сборка, один раз (инвариант 0.4) — и это единственная
    # часть сборки, которую не объявляла ни одна подзадача, потому что писать её должен был
    # дирижёр.
    _ba_found=$(printf '%s\n' "$_ba_changed" |
                grep -xE 'ARCHITECTURE\.md|CONVENTIONS\.md|DECISIONS\.md' |
                tr '\n' ' ' | sed 's/[[:space:]]*$//')
    [ "$_ba_nfiles" -gt 0 ] && [ -z "$_ba_found" ] &&
        _ba_find="$_ba_find- фундамент не тронут: под флотом его пишет сборка, один раз (инвариант 0.4)
"

    # --- мастер-проверка -----------------------------------------------------
    _ba_cmd=$(config_get build_check "$_ba_root")
    _ba_mc=$(build_master_check "$_ba_root" "$_ba_id" "$_ba_tmp/check.out")
    case $_ba_mc in
        нет)    printf '  проектной проверки нет (config build_check)\n' ;;
        нельзя) printf '  проектную проверку запустить не удалось\n'
                _ba_find="$_ba_find- проектная проверка не запустилась: чекаут ветки сборки не открылся
" ;;
        0)      printf '  проектная проверка: код 0\n' ;;
        *)      printf '  проектная проверка: код %s\n' "$_ba_mc"
                _ba_find="$_ba_find- проектная проверка «$_ba_cmd» вернула код $_ba_mc
" ;;
    esac

    # --- чистка --------------------------------------------------------------
    _ba_clean=$(build_cleanup "$_ba_root" "$_ba_id")
    _ba_gone=$(printf '%s\n' "$_ba_clean" | grep -c '	снят$')
    _ba_left=$(printf '%s\n' "$_ba_clean" | grep -c '	оставлен')
    printf '  чистка: чекаутов снято %s, оставлено %s\n' "$_ba_gone" "$_ba_left"
    printf '%s\n' "$_ba_clean" | grep -q '	оставлен: есть незакоммиченное' &&
        _ba_find="$_ba_find- воркер продолжил работу после сбора: в его чекауте есть незакоммиченное
"

    # --- отчёт ---------------------------------------------------------------
    _ba_report=$(build_report_file "$_ba_root" "$_ba_id")
    {
        printf '# Отчёт дирижёра — сборка %s\n\n' "$_ba_id"
        printf 'По этому отчёту сборку ратифицирует человек. Проверял дирижёр и отвечает\n'
        printf 'дирижёр; решает человек, и до его решения в ствол не уходит ничего.\n\n'
        printf -- '- Ветка сборки: `%s` (`%s`)\n' "$_ba_branch" "$_ba_head"
        printf -- '- База: `%s`\n' "$_ba_base"
        printf -- '- Подзадач: %s, волн: %s — собраны все\n' "$_ba_n" "$_ba_waves"
        printf -- '- Проверено: %s\n\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

        printf '## Чем заняться\n\n'
        if [ -n "$_ba_find" ]; then
            printf '%s' "$_ba_find"
        else
            printf -- '- нечем: всё, что машина умеет проверить, чистое\n'
        fi
        printf '\n'

        printf '## Что вернулось\n\n'
        printf '| подзадача | волна | слито | файлов |\n|---|---|---|---|\n'
        for _ba_s in $_ba_ids; do
            _ba_w=$(awk -F'\t' -v s="$_ba_s" '$2 == s { print $1; exit }' "$_ba_coll" 2>/dev/null)
            _ba_sha=$(awk -F'\t' -v s="$_ba_s" '$2 == s { print $3; exit }' "$_ba_coll" 2>/dev/null)
            if [ -z "$_ba_sha" ] || [ "$_ba_sha" = "—" ]; then
                printf '| %s | %s | — | 0 |\n' "$_ba_s" "${_ba_w:-—}"
            else
                _ba_f=$(git -C "$_ba_root" diff --name-only "$_ba_sha^1" "$_ba_sha" 2>/dev/null |
                        grep -c '[^[:space:]]')
                printf '| %s | %s | `%s` | %s |\n' "$_ba_s" "${_ba_w:-—}" "$_ba_sha" "$_ba_f"
            fi
        done
        printf '\nПути сверены с деревом на сборе: подзадача, вышедшая за свои файлы, не\n'
        printf 'сливается вовсе, поэтому в таблице выше её бы не было.\n\n'

        printf '## Что сборка изменила целиком\n\n'
        printf '```\n'
        git -C "$_ba_root" diff --stat "$_ba_base" "$_ba_branch" 2>/dev/null | sed 's/^/ /'
        printf '```\n\n'
        if [ -n "$_ba_undecl" ]; then
            printf 'Не объявляла ни одна подзадача — это либо фундамент, который под флотом\n'
            printf 'пишет сама сборка, либо утечка. Скажи словами, что именно:\n\n'
            printf '%s\n' "$_ba_undecl" | sed 's/^/- `/; s/$/`/'
            printf '\n'
        fi

        printf '## Мастер-проверка\n\n'
        case $_ba_mc in
            нет)    printf -- '- проектной проверки нет. Задать: `fraim config set build_check "…"`\n' ;;
            нельзя) printf -- '- проектная проверка не запустилась: чекаут ветки сборки не открылся\n' ;;
            *)      printf -- '- `%s` → код %s\n' "$_ba_cmd" "$_ba_mc" ;;
        esac
        if [ -n "$_ba_found" ]; then
            printf -- '- фундамент сборки: %s\n' "$_ba_found"
        else
            printf -- '- фундамент: не тронут\n'
        fi
        printf -- '- файлов в сборке: %s\n' "$_ba_nfiles"
        if [ -s "$_ba_tmp/check.out" ]; then
            printf '\nПоследнее, что сказала проверка:\n\n```\n'
            tail -20 "$_ba_tmp/check.out" | sed 's/^/ /'
            printf '```\n'
        fi
        printf '\n'

        printf '## Чистка\n\n'
        if [ -n "$_ba_clean" ]; then
            printf '%s\n' "$_ba_clean" | awk -F'\t' 'NF { printf "- %s %s — %s\n", $1, $2, $3 }'
        else
            printf -- '- убирать было нечего\n'
        fi
        printf '\nВетки воркеров не трогались: их коммиты уже в ветке сборки, а ветку, которую\n'
        printf 'мы не заводили, чистка не удаляет ([B6](../../../PRINCIPLES.md#b6-глагол-трогает-только-то-что-сам-изменил)).\n\n'

        printf '## Словами дирижёра\n\n'
        printf '<!-- Заполняется дирижёром ДО того, как это прочтёт человек. Три вопроса,\n'
        printf '     на которые машина выше не ответила:\n'
        printf '     1. что ты проверил такого, чего в цифрах не видно;\n'
        printf '     2. в чём ты не уверен;\n'
        printf '     3. что рекомендуешь — принять, переделать волну, переписать план. -->\n\n'

        printf '## Если годится\n\n'
        printf 'Запись в ствол делает человек — гейт стоит до неё\n'
        printf '([MODES.md §4](../../../MODES.md#4-гейт-относительно-ствола-развилка-ab)):\n\n'
        printf '    git merge --no-ff %s\n\n' "$_ba_branch"
        printf 'Если не годится — скажи дирижёру, и пусть он запишет это:\n\n'
        printf '    fraim dispatch return %s "что не так"\n' "$_ba_id"
    } > "$_ba_report" || { rm -rf "$_ba_tmp"; printf >&2 'не удалось записать отчёт\n'; return 2; }

    {
        printf 'Принял: дирижёр\n'
        printf 'Когда: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'Ветка сборки: %s\n' "$_ba_branch"
        printf 'Собрано на: %s\n' "$_ba_head"
        printf 'База: %s\n' "$_ba_base"
        printf 'Отчёт: ai/builds/%s/report.md\n' "$_ba_id"
        printf 'Ратификация: за человеком, по отчёту — в ствол ничего не ушло\n'
    } > "$(build_accepted_file "$_ba_root" "$_ba_id")" || {
        rm -rf "$_ba_tmp"; printf >&2 'не удалось записать приёмку\n'; return 2
    }
    rm -f "$(build_returned_file "$_ba_root" "$_ba_id")"

    {
        printf '\n## Приёмка дирижёра — %s\n\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf -- '- Ветка сборки %s на %s, база %s\n' "$_ba_branch" "$_ba_head" "$_ba_base"
        printf -- '- Отчёт: ai/builds/%s/report.md\n' "$_ba_id"
        if [ -n "$_ba_find" ]; then printf '%s' "$_ba_find"; else printf -- '- машинные проверки чистые\n'; fi
    } >> "$_ba_dir/journal.md"

    rm -rf "$_ba_tmp"
    printf '  отчёт: %s\n' "$_ba_report"
    [ -z "$_ba_find" ]
}

# The human's other answer. Acceptance has two outcomes and only one of them existed in the
# system: «не годится» lived in the chat, where the next session cannot read it. Returning
# also clears the acceptance, so the conductor has to check and report again rather than
# hand back the same report with a sentence added.
build_return() {
    _br_root=$1; _br_id=$2; _br_why=$3

    _br_dir=$(build_dir "$_br_root" "$_br_id")
    [ -d "$_br_dir" ] || { printf >&2 'нет такой сборки: %s\n' "$_br_id"; return 1; }
    [ -n "$_br_why" ] ||
        { printf >&2 'скажи, что не так: fraim dispatch return %s "причина"\n' "$_br_id"; return 1; }
    [ -f "$(build_accepted_file "$_br_root" "$_br_id")" ] ||
        { printf >&2 'сборка %s ещё не принята дирижёром — возвращать нечего\n' "$_br_id"; return 1; }

    {
        printf 'Вернул: человек\n'
        printf 'Когда: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'Почему: %s\n' "$_br_why"
    } > "$(build_returned_file "$_br_root" "$_br_id")" || return 1
    rm -f "$(build_accepted_file "$_br_root" "$_br_id")"

    {
        printf '\n## Возврат человеком — %s\n\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf -- '- %s\n' "$_br_why"
    } >> "$_br_dir/journal.md"

    printf '%s\n' "$(build_returned_file "$_br_root" "$_br_id")"
}

# Pending builds, newest first: id and where each one stands.
# A directory under ai/builds is a BUILD only if it has a journal. Anything else is a
# folder someone put a plan in — that is what ai/builds/v2-core was in the first live
# build, and listing it as a build is what let `dispatch run` be aimed at it.
#
# Three states, because acceptance has two owners: the conductor checks and reports, the
# human ratifies over that report or hands it back. «Принята дирижёром» is therefore not
# «готово» — it is «отчёт лежит и ждёт человека».
build_list() {
    _bl_root=$1
    [ -d "$_bl_root/ai/builds" ] || return 0
    for _b in "$_bl_root/ai/builds"/*; do
        [ -d "$_b" ] || continue
        if [ ! -f "$_b/journal.md" ]; then
            printf '%s\tне сборка (нет журнала)\n' "$(basename -- "$_b")"
        elif [ -f "$_b/accepted" ]; then
            printf '%s\tпринята дирижёром — отчёт ждёт человека\n' "$(basename -- "$_b")"
        elif [ -f "$_b/returned" ]; then
            printf '%s\tвозвращена человеком\n' "$(basename -- "$_b")"
        else
            printf '%s\tне принята\n' "$(basename -- "$_b")"
        fi
    done | sort -r
}
