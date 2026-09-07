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
    _dc_roles=$(printf '%s\n' "$_dc_recs" | cut -d'|' -f2 | grep '[^[:space:]]' | sort -u)
    for _r in $_dc_roles; do
        roles_resolve "$_r" "$_dc_root" >/dev/null || _dc_bad=1
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
dispatch_verify_tree() {
    _vt_root=$1; _vt_ref=$2; _vt_paths=$3

    _vt_changed=$(cd "$_vt_root" 2>/dev/null && git diff --name-only "$_vt_ref" 2>/dev/null) ||
        { printf >&2 'не могу прочитать дерево от %s\n' "$_vt_ref"; return 1; }
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
build_list() {
    _bl_root=$1
    [ -d "$_bl_root/ai/builds" ] || return 0
    for _b in "$_bl_root/ai/builds"/*; do
        [ -d "$_b" ] || continue
        if [ -f "$_b/accepted" ]; then
            printf '%s\tпринята\n' "$(basename -- "$_b")"
        else
            printf '%s\tне принята\n' "$(basename -- "$_b")"
        fi
    done | sort -r
}
