#!/bin/sh
# dispatch.sh — the conductor's machinery: plan, build, waves, collect, acceptance (MODES.md §2, §5).
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
# "we do not start an ontology of roles of our own"). roles.sh resolves it to agent, model and
# effort; it is the plan's only statement about the executor, on purpose.
# ---------------------------------------------------------------------------

# One record per subtask: id|role|summary|comma-separated paths|comma-separated After ids
# Fields are emitted even when empty so the validator can name what is missing
# rather than silently skipping the block.
#
# A per-subtask tier field was built here and removed on the owner's decision: judging
# which subtask deserves an expensive model is not the conductor's call to make. Executors
# run on what their procedure declares, and the human decides cost — see "What is not here
# yet" in the conductor procedure for the session-profile idea that replaces it.
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
    [ -f "$_dc_plan" ] || { printf >&2 '%s\n' "$(t disp_err_no_plan plan="$_dc_plan")"; return 1; }

    _dc_recs=$(dispatch_parse_plan "$_dc_plan")
    [ -n "$_dc_recs" ] || { printf >&2 '%s\n' "$(t disp_err_no_subtasks)"; return 1; }

    _dc_bad=0

    # 1. Structure: every subtask says who, what and where.
    _dc_struct=$(printf '%s\n' "$_dc_recs" | while IFS='|' read -r _id _role _sum _paths; do
        [ -n "$_id" ] || continue
        [ -n "$_role" ]  || printf '%s\n' "$(t disp_err_no_role id="$_id")"
        [ -n "$_sum" ]   || printf '%s\n' "$(t disp_err_no_summary id="$_id")"
        [ -n "$_paths" ] || printf '%s\n' "$(t disp_err_no_paths id="$_id")"
    done)
    if [ -n "$_dc_struct" ]; then
        printf >&2 '%s\n%s\n' "$(t disp_err_incomplete)" "$_dc_struct"
        _dc_bad=1
    fi

    # 2. Order: waves are derived here, and a plan whose order does not resolve is refused
    #    before anything else looks at paths — a ghost `After` or a cycle makes every
    #    per-wave answer below meaningless. dispatch_waves names the defect itself.
    if _dc_waves=$(dispatch_waves "$_dc_plan"); then :; else
        printf >&2 '%s\n' "$(t disp_err_order)"
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
        printf >&2 '%s\n' "$(t disp_err_collision)"
        printf '%s\n' "$_dc_dups" | while IFS='	' read -r _p _w; do
            [ -n "$_p" ] || continue
            _who=$(printf '%s\n' "$_dc_pairs" |
                   awk -F'\t' -v p="$_p" -v w="$_w" '$1 == p && $2 == w { printf "%s%s", sep, $3; sep=", " }')
            printf >&2 '  %s\n' "$(t disp_err_collision_line path="$_p" wave="$_w" who="$_who")"
        done
        printf >&2 '%s\n' "$(t disp_err_collision_ways)"
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
            printf >&2 '%s\n' "$(t disp_err_not_parallel role="$_dc_r")"
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
            printf >&2 '%s\n' "$(t disp_note_no_orca_model id="$_id" agent="$_ag" model="$_mo")"
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
#
# The two refusals are the operator's messages: their templates reach awk through ENVIRON,
# never `-v`, which would eat backslashes.
# ---------------------------------------------------------------------------
dispatch_waves() {
    dispatch_parse_plan "$1" |
    _dw_ghost=$(t disp_err_after_ghost) _dw_cycle=$(t disp_err_cycle) awk -F'|' '
        # {name} in s replaced by v, once per occurrence, left to right.
        function fill(s, name, v,    out, i) {
            out = ""
            while ((i = index(s, name)) > 0) {
                out = out substr(s, 1, i - 1) v
                s = substr(s, i + length(name))
            }
            return out s
        }
        { n = NR; id[n] = $1; after[n] = $5; known[$1] = 1 }
        END {
            for (i = 1; i <= n; i++) {
                if (after[i] == "") continue
                m = split(after[i], a, ",")
                for (j = 1; j <= m; j++) {
                    gsub(/^[ \t]+|[ \t]+$/, "", a[j])
                    if (a[j] == "") continue
                    if (!(a[j] in known)) {
                        print fill(fill(ENVIRON["_dw_ghost"], "{id}", id[i]), "{after}", a[j]) \
                            > "/dev/stderr"
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
                print ENVIRON["_dw_cycle"] > "/dev/stderr"
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
# ("the watchman notices, the human decides").
#
# The time threshold that used to live here ("a piece longer than half an hour") is deliberately
# absent: nobody can measure it — not the conductor before dispatch, not the human, not
# the machine after — and it read as a rule while working as the cheapest excuse to refuse.
# What replaces it is a comparison the conductor states out loud in the plan: dispatching
# is worth it when executing the piece costs more than dispatching it.
#
# Only ceilings, no floors. The lower bounds ("below three subtasks dispatch rarely pays",
# "one path is probably smaller than the cost of dispatch") assumed the fleet exists for
# calendar time. It also exists for tokens: a conductor on a strong model handing ONE piece
# to ONE worker on a cheap model is a whole, legitimate build (DECISIONS 2026-09-15). The
# human asked for it; a floor would only argue with them.
# ---------------------------------------------------------------------------
DISPATCH_MAX_SUBTASKS=6
DISPATCH_WAVE_MAX=5
DISPATCH_MAX_WAVES=3
DISPATCH_PATHS_MAX=10

# Warnings about size. Prints to stderr and always returns 0 — a caller must never be able
# to turn these into a refusal by accident.
dispatch_size_notes() {
    _sn_plan=$1
    _sn_recs=$(dispatch_parse_plan "$_sn_plan")
    [ -n "$_sn_recs" ] || return 0

    _sn_n=$(printf '%s\n' "$_sn_recs" | grep -c '[^[:space:]]')
    [ "$_sn_n" -le "$DISPATCH_MAX_SUBTASKS" ] ||
        printf >&2 '%s\n' "$(t disp_warn_subtasks n="$_sn_n" max="$DISPATCH_MAX_SUBTASKS")"

    # Width and depth. Until a plan declares order, the whole build is one wave, and the
    # width IS the count — so this reads correctly both before and after waves exist.
    _sn_waves=$(dispatch_waves "$_sn_plan" 2>/dev/null) || _sn_waves=
    if [ -n "$_sn_waves" ]; then
        _sn_depth=$(printf '%s\n' "$_sn_waves" | cut -f2 | sort -n | tail -1)
        [ "${_sn_depth:-1}" -le "$DISPATCH_MAX_WAVES" ] ||
            printf >&2 '%s\n' "$(t disp_warn_waves n="$_sn_depth" max="$DISPATCH_MAX_WAVES")"
        _sn_w=1
        while [ "$_sn_w" -le "${_sn_depth:-1}" ]; do
            _sn_wn=$(printf '%s\n' "$_sn_waves" | awk -F'\t' -v w="$_sn_w" '$2 == w' | grep -c '[^[:space:]]')
            [ "$_sn_wn" -le "$DISPATCH_WAVE_MAX" ] ||
                printf >&2 '%s\n' \
                    "$(t disp_warn_wave_wide wave="$_sn_w" n="$_sn_wn" max="$DISPATCH_WAVE_MAX")"
            _sn_w=$(( _sn_w + 1 ))
        done
    fi

    printf '%s\n' "$_sn_recs" | while IFS='|' read -r _sn_id _sn_role _sn_sum _sn_paths _sn_after; do
        [ -n "$_sn_id" ] || continue
        _sn_pn=$(printf '%s\n' "$_sn_paths" | tr ',' '\n' | grep -c '[^[:space:]]')
        [ "$_sn_pn" -le "$DISPATCH_PATHS_MAX" ] ||
            printf >&2 '%s\n' "$(t disp_warn_paths id="$_sn_id" n="$_sn_pn")"
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
    printf '%s\n' "$(t disp_cost_line \
        subtasks="$(tp "$_cl_n" disp_n_subtasks)" \
        waves="$(tp "${_cl_depth:-1}" disp_n_waves)" \
        workers="$(tp "$_cl_wide" disp_n_workers)")"
}

# What dispatch is about to do, before it does it: who runs what, on which model,
# and where that answer came from. Printed for the conductor to read — a run on the
# built-in default when the project meant to name a role is the kind of thing that
# is obvious here and invisible three hours later.
dispatch_report() {
    _dr_plan=$1; _dr_root=${2:-}
    _dr_waves=$(dispatch_waves "$_dr_plan" 2>/dev/null) || _dr_waves=
    # Padded inside the catalog, not by printf: POSIX printf pads bytes, and Cyrillic
    # headings would land short.
    printf '%s\n' "$(t disp_report_head)"
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
        printf '# Subtask %s\n\n' "$_wt_id"
        printf '## Summary\n%s\n\n' "$_wt_sum"
        printf '## Files to Change\n'
        printf '%s\n' "$_wt_paths" | tr ',' '\n' | while read -r _p; do
            [ -n "$_p" ] && printf -- '- `%s`\n' "$_p"
        done
        printf '\n## Executor Rules\n'
        printf -- '- This subtask runs as: %s (the «Fleet worker» rules of /run-task).\n' "$_wt_role"
        printf -- '- Change only the files in Files to Change. The rest of the tree belongs to the\n'
        printf -- '  other workers of this build: an edit outside the list merges silently, with no conflict.\n'
        printf -- '- Need a file outside the list? Do not touch it — stop and say so. The conductor\n'
        printf -- '  replans the build; that is cheaper than a silent overlap.\n'
        printf -- '\n'
        printf -- '- **The project foundation is not yours in this subtask.** Do not touch `DECISIONS.md`,\n'
        printf -- '  `ARCHITECTURE.md` or `CONVENTIONS.md`, even if the project AGENTS.md says to update\n'
        printf -- '  them after a change. That rule is suspended here: under parallelism the build writes\n'
        printf -- '  the foundation once, after acceptance (invariant 0.4). Two workers each appending to\n'
        printf -- '  DECISIONS.md produce a merge conflict out of nothing.\n'
        printf -- '- Whatever belongs in the foundation — write it in words in your report. The conductor\n'
        printf -- '  gathers it from the whole build and records it once.\n'
        printf -- '\n'
        printf -- '- **Commit your work.** Do not leave it uncommitted: the build is assembled by merging\n'
        printf -- '  branches, and what is not committed never reaches it — collect will refuse your\n'
        printf -- '  subtask and name the uncommitted files.\n'
        printf -- '- Build %s. There is one acceptance for the whole build, none per subtask.\n' "$_wt_build"
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
        }) || { printf >&2 '%s\n' "$(t disp_err_tree_unreadable ref="$_vt_ref")"; return 1; }
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
# "what was handed to whom and what came back" is our truth (A3), unlike fleet.tsv which is a cache
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
    [ -f "$_dl_plan" ] || { printf >&2 '%s\n' "$(t disp_err_no_build_plan build="$_dl_build")"; return 1; }

    # The journal is what makes this a BUILD rather than a directory that happens to hold
    # a plan. In the first live build the conductor ran `dispatch run v2-core` — the folder
    # where the plan was written by hand — while `dispatch` had sealed the build under
    # build-20260907-140427. The fleet started against a build that had no journal, and the
    # mismatch only surfaced at acceptance, after all four workers had finished.
    if [ ! -f "$_dl_dir/journal.md" ]; then
        printf >&2 '%s\n' "$(t disp_err_not_sealed build="$_dl_build")"
        printf >&2 '  %s\n' "$(t disp_hint_seal)"
        _dl_have=$(build_list "$_dl_root" 2>/dev/null | head -3)
        [ -n "$_dl_have" ] && { printf >&2 '  %s\n' "$(t disp_hint_have)"; printf '%s\n' "$_dl_have" | sed 's/^/    /' >&2; }
        return 1
    fi

    fleet_present || { printf >&2 '%s\n' "$(t disp_err_no_env)"; return 1; }
    fleet_ready   || { printf >&2 '%s\n' "$(t disp_err_env_down)"; return 1; }

    if [ -z "$_dl_wave" ]; then
        _dl_wave=$(build_next_wave "$_dl_root" "$_dl_build") || {
            printf >&2 '%s\n' "$(t disp_err_all_launched build="$_dl_build")"
            return 1
        }
    fi
    _dl_ids=$(dispatch_wave_ids "$_dl_plan" "$_dl_wave") || return 1
    [ -n "$_dl_ids" ] || {
        printf >&2 '%s\n' "$(t disp_err_no_wave build="$_dl_build" wave="$_dl_wave")"; return 1
    }
    printf '%s\n' "$(t disp_wave wave="$_dl_wave")"

    # Workers branch from the BUILD branch, not from whatever the conductor has checked
    # out: that is what lets a later wave start on top of what an earlier one left, and it
    # keeps the trunk out of the fleet's way entirely. Builds created before the build
    # branch existed fall back to the current branch, so an old build still launches.
    _dl_base=$(build_branch "$_dl_build")
    git -C "$_dl_root" rev-parse --verify --quiet "refs/heads/$_dl_base" >/dev/null 2>&1 ||
        _dl_base=$(cd "$_dl_root" && git rev-parse --abbrev-ref HEAD 2>/dev/null) || _dl_base=main

    # The run's objective lives in the environment, where workers may read it: English.
    _dl_run=$(fleet_run_create "fraim: build $_dl_build") || return 1
    printf 'Run: %s\n' "$_dl_run"

    # The launch-truth channel: fleet_worker_start appends one line per worker
    # (globals die in its command substitution; a file survives it).
    _dl_finfo=$(mktemp) || return 1
    _FLEET_INFO=$_dl_finfo

    # Appended, not truncated: a second wave must not erase the first wave's ids, which are
    # the only record of who ran what if the environment forgets.
    _dl_file=$(build_fleet_file "$_dl_root" "$_dl_build")
    printf '# build %s · wave %s · run %s · taken %s\n' \
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
            printf '  %s\n' "$(t disp_launch_cmd_model id="$_dl_id" disp="$_dl_disp" \
                agent="$_dl_ag" model="$_dl_mo" cmd="$_dl_lmodel")"
        elif [ "$_dl_lpath" = custom ]; then
            printf '  %s\n' "$(t disp_launch_no_model id="$_dl_id" disp="$_dl_disp" agent="$_dl_ag")"
            printf '     %s\n' "$(t disp_launch_teach agent="$_dl_ag")"
            printf '     fraim config set --machine modelcmd_%s "/model %%s"\n' "$_dl_ag"
        elif fleet_caps_has "$_dl_ag" no-launch-model 2>/dev/null; then
            if _dl_sent=$(fleet_worker_set_model "$_dl_disp" "$_dl_ag" "$_dl_mo" "$_dl_root"); then
                printf '  %s\n' "$(t disp_launch_set_model id="$_dl_id" disp="$_dl_disp" \
                    agent="$_dl_ag" model="$_dl_mo" cmd="$_dl_sent")"
            else
                printf '  %s\n' "$(t disp_launch_no_model id="$_dl_id" disp="$_dl_disp" agent="$_dl_ag")"
                printf '     %s\n' "$(t disp_launch_teach agent="$_dl_ag")"
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
    # branch FROM it and their results are merged back INTO it, so the trunk stays untouched
    # for the whole life of the build: `collect` writes only here, and the single merge into
    # the trunk happens once, in `accept`, after everything has been checked (MODES.md §4,
    # option B). No other verb touches the trunk.
    _bs_br=$(build_branch "$_bs_id")
    if ! git -C "$_bs_root" rev-parse --verify --quiet "refs/heads/$_bs_br" >/dev/null 2>&1; then
        git -C "$_bs_root" branch "$_bs_br" >/dev/null 2>&1 ||
            printf >&2 '%s\n' "$(t disp_err_branch_create branch="$_bs_br")"
    fi

    {
        printf '# Build journal %s\n\n' "$_bs_id"
        printf '## Contents\n\n'
        printf -- '- Created: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf -- '- Base: %s\n' "$(cd "$_bs_root" && git rev-parse --short HEAD 2>/dev/null || echo '—')"
        printf -- '- Plan: ai/builds/%s/plan.md\n\n' "$_bs_id"
        printf '| subtask | role | outcome | outside its paths |\n'
        printf '|---|---|---|---|\n'
        dispatch_parse_plan "$_bs_plan" | while IFS='|' read -r _id _role _sum _paths; do
            [ -n "$_id" ] && printf '| %s | %s | — | — |\n' "$_id" "$_role"
        done
        printf '\n## Conductor lessons\n\n'
        printf '<!-- Filled in after acceptance. MODES.md §11.4: a class of lessons no worker\n'
        printf '     has — the traps of dispatching, not the traps of the code. -->\n'
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
        printf >&2 '%s\n' "$(t disp_err_merge_checkout branch="$_mo_branch")"
        return 1
    fi

    _mo_rc=0
    if ! git -C "$_mo_tmp" merge --no-ff -m "$_mo_msg" "$_mo_sha" >/dev/null 2>&1; then
        printf >&2 '%s\n' "$(t disp_err_merge_conflict)"
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
    [ -f "$_co_plan" ] || { printf >&2 '%s\n' "$(t disp_err_no_build_plan build="$_co_build")"; return 1; }
    [ -f "$_co_dir/journal.md" ] ||
        { printf >&2 '%s\n' "$(t disp_err_not_sealed_short build="$_co_build")"; return 1; }

    _co_branch=$(build_branch "$_co_build")
    git -C "$_co_root" rev-parse --verify --quiet "refs/heads/$_co_branch" >/dev/null 2>&1 || {
        printf >&2 '%s\n' "$(t disp_err_no_branch branch="$_co_branch")"
        return 1
    }

    if [ -z "$_co_wave" ]; then
        _co_wave=$(build_next_wave "$_co_root" "$_co_build") || {
            printf >&2 '%s\n' "$(t disp_err_all_collected build="$_co_build")"; return 1
        }
    fi

    _co_ids=$(dispatch_wave_ids "$_co_plan" "$_co_wave") || return 1
    [ -n "$_co_ids" ] || {
        printf >&2 '%s\n' "$(t disp_err_no_wave build="$_co_build" wave="$_co_wave")"; return 1
    }

    # Where the build branch stood before this wave: the base for the combined diff the
    # conductor reads at the end, and the point every worker of this wave branched from.
    _co_before=$(git -C "$_co_root" rev-parse "$_co_branch" 2>/dev/null)
    _co_file=$(build_collected_file "$_co_root" "$_co_build")
    _co_bad=0

    printf '%s\n' "$(t disp_co_head wave="$_co_wave" build="$_co_build")"
    for _co_id in $_co_ids; do
        if build_is_collected "$_co_root" "$_co_build" "$_co_id"; then
            printf '  %-12s %s\n' "$_co_id" "$(t disp_co_already)"
            continue
        fi

        _co_tree=$(dispatch_worker_tree "$_co_root" "$_co_build-$_co_id")
        if [ -z "$_co_tree" ]; then
            printf '  %-12s %s\n' "$_co_id" "$(t disp_co_no_checkout)"
            _co_bad=1; continue
        fi

        _co_dirty=$(cd "$_co_tree" 2>/dev/null && {
                git status --porcelain 2>/dev/null | head -20
            })
        if [ -n "$_co_dirty" ]; then
            printf '  %-12s %s\n' "$_co_id" "$(t disp_co_dirty)"
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
            printf '  %-12s %s\n' "$_co_id" "$(t disp_co_outside)"
            printf '%s\n' "$_co_out" | sed 's/^/      /'
            _co_bad=1; continue
        fi

        _co_sha=$(git -C "$_co_tree" rev-parse HEAD 2>/dev/null)
        if [ "$_co_sha" = "$_co_base" ]; then
            printf '  %-12s %s\n' "$_co_id" "$(t disp_co_nothing)"
            printf '%s\t%s\t—\t%s\n' "$_co_wave" "$_co_id" \
                "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$_co_file"
            continue
        fi

        if _co_merged=$(dispatch_merge_one "$_co_root" "$_co_branch" "$_co_sha" \
                            "build $_co_build: subtask $_co_id"); then
            printf '  %-12s %s\n' "$_co_id" "$(t disp_co_merged sha="$_co_merged")"
            printf '%s\t%s\t%s\t%s\n' "$_co_wave" "$_co_id" "$_co_merged" \
                "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$_co_file"
        else
            printf '  %-12s %s\n' "$_co_id" "$(t disp_co_merge_failed)"
            _co_bad=1
        fi
    done

    _co_after=$(git -C "$_co_root" rev-parse "$_co_branch" 2>/dev/null)

    # The combined diff of the whole wave, not one subtask at a time. This is the only place
    # where a divergence the path check cannot see — two workers naming the same thing
    # differently, two different error formats — becomes visible at all. It is a look, not
    # a verdict: nothing here decides anything, the conductor reads it.
    if [ -n "$_co_before" ] && [ "$_co_before" != "$_co_after" ]; then
        printf '\n%s\n' "$(t disp_co_wave_diff)"
        git -C "$_co_root" diff --stat "$_co_before" "$_co_after" 2>/dev/null | sed 's/^/  /'
    fi

    {
        printf '\n## Wave %s collected — %s\n\n' "$_co_wave" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        if [ -f "$_co_file" ]; then
            awk -F'\t' -v w="$_co_wave" '$1 == w { printf "- %s → %s\n", $2, $3 }' "$_co_file"
        fi
        [ "$_co_bad" -eq 0 ] || printf -- '- collected partially: some subtasks were refused\n'
    } >> "$_co_dir/journal.md"

    [ "$_co_bad" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Acceptance: the whole of it is the conductor's, trunk write included
#
# The word "acceptance" used to carry two things and the CLI stamped only the second:
# `build_accept` wrote a time and a HEAD, while everything that should have come before it
# — verify each subtask against the tree, look at the build as a whole, run the project's
# own check, tidy up after the fleet — was a list of commands somebody had to remember, one
# at a time, in a chat. What reached the human was N diffs and the word "accepted".
#
# So the checking became the conductor's. Then the same logic finished the sentence: the
# human does not type commands at all here, and the trunk write is not a decision, it is
# the last step of checking — a build nobody merged has not been checked against the tree
# it has to live in. `accept` therefore does everything and prints a report to the terminal;
# the human reads that report and says whether it is right.
#
# This is MODES.md §4 option B, and it is affordable now for a reason that did not exist
# when §4 was written: `collect` assembles the whole build into ONE branch, so the trunk
# write is ONE `--no-ff` merge commit and undoing it is `fraim undo <sha>` — not the unwind
# of N interleaved results §4 refused. The commit carries the `fraim:` trailer precisely so
# that verb can recognise it as ours.
#
# What still refuses to happen silently: the trunk write is skipped, loudly, whenever the
# machine knows something is wrong — a red project check, a dirty working tree, a conflict,
# an empty build. Judgement did not move to the machine; only the labour did, and a red
# check is not judgement.
# ---------------------------------------------------------------------------

build_accepted_file() { printf '%s/accepted\n' "$(build_dir "$1" "$2")"; }

# Where the build branch started. The journal wrote it down when the build was sealed —
# that is our record (A3), and it stays true after the trunk moves on. Only when the line
# is missing or no longer resolves do we ask git for the fork point.
build_base_sha() {
    _bb_root=$1; _bb_build=$2
    # "Base" in Russian is how journals written before the English format name the line.
    _bb_s=$(sed -n 's/^- Base: //p; s/^- База: //p' "$(build_dir "$_bb_root" "$_bb_build")/journal.md" 2>/dev/null |
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
# Writes the command's output to $3. Prints its verdict, a token rather than a message:
# `none` (nothing configured), `cannot` (the checkout could not be opened) or the
# command's exit code. The token also goes into the journal, so it is English.
build_master_check() {
    _mc_root=$1; _mc_build=$2; _mc_out=$3
    : > "$_mc_out" 2>/dev/null || :

    _mc_cmd=$(config_get build_check "$_mc_root")
    [ -n "$_mc_cmd" ] || { printf 'none\n'; return 0; }

    _mc_tmp=$(mktemp -d) || { printf 'cannot\n'; return 0; }
    rmdir "$_mc_tmp" 2>/dev/null || :
    if ! git -C "$_mc_root" worktree add --quiet "$_mc_tmp" \
             "$(build_branch "$_mc_build")" >/dev/null 2>&1; then
        printf 'cannot\n'; return 0
    fi

    ( cd "$_mc_tmp" 2>/dev/null && sh -c "$_mc_cmd" ) > "$_mc_out" 2>&1
    _mc_rc=$?
    git -C "$_mc_root" worktree remove --force "$_mc_tmp" >/dev/null 2>&1 || rm -rf "$_mc_tmp"
    printf '%s\n' "$_mc_rc"
}

# Cleanup: only what this build itself created, and only once it is provably redundant.
#
# This is B6 scaled to the fleet (MODES.md §3): there is no "tidy up the extra worktrees" here.
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
# One TSV line per resource: kind, name, verdict — tokens, not words; build_accept says
# them to the human:
#   checkout  <subtask>  removed | kept-dirty | kept-unmerged | kept-git
#   worker    <dispatch> released | no-answer
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
            printf 'checkout\t%s\tkept-dirty\n' "$_cl_id"
            continue
        fi
        _cl_sha=$(git -C "$_cl_tree" rev-parse HEAD 2>/dev/null)
        if [ -z "$_cl_sha" ] ||
           ! git -C "$_cl_root" merge-base --is-ancestor "$_cl_sha" "$_cl_branch" >/dev/null 2>&1; then
            printf 'checkout\t%s\tkept-unmerged\n' "$_cl_id"
            continue
        fi
        if git -C "$_cl_root" worktree remove --force "$_cl_tree" >/dev/null 2>&1; then
            printf 'checkout\t%s\tremoved\n' "$_cl_id"
        else
            printf 'checkout\t%s\tkept-git\n' "$_cl_id"
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
                printf 'worker\t%s\treleased\n' "$_cl_d"
            else
                printf 'worker\t%s\tno-answer\n' "$_cl_d"
            fi
        done
    fi
}

# The trunk write: one --no-ff merge of the build branch into whatever branch the project
# root has checked out. Refuses instead of guessing in the four cases where merging would
# be destructive or meaningless, and every refusal names the thing to fix.
#
# Prints the merge sha on success; a reason on stderr and returns 1 otherwise.
build_land() {
    _bl_root=$1; _bl_build=$2
    _bl_branch=$(build_branch "$_bl_build")

    _bl_trunk=$(git -C "$_bl_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
    [ -n "$_bl_trunk" ] && [ "$_bl_trunk" != HEAD ] ||
        { printf >&2 '%s\n' "$(t disp_err_detached)"; return 1; }
    [ "$_bl_trunk" != "$_bl_branch" ] ||
        { printf >&2 '%s\n' "$(t disp_err_on_build_branch)"; return 1; }

    # A merge takes the working tree with it. Someone else's unsaved work is not ours to
    # carry into a merge commit (B6), so this is a refusal and not a stash.
    _bl_dirty=$(git -C "$_bl_root" status --porcelain --untracked-files=no 2>/dev/null | head -5)
    [ -z "$_bl_dirty" ] || {
        printf >&2 '%s\n' "$(t disp_err_dirty_tree)"
        printf '%s\n' "$_bl_dirty" | sed 's/^/    /' >&2
        return 1
    }

    # The `fraim:` trailer is what lets `fraim undo <sha>` recognise this commit as ours.
    # Without it the undo of a trunk write would have to be hand-rolled git, which is the
    # one thing the human must never be handed.
    if ! git -C "$_bl_root" merge --no-ff \
             -m "build: $_bl_build" -m "fraim: $(fraim_version)" \
             "$_bl_branch" >/dev/null 2>&1; then
        git -C "$_bl_root" merge --abort >/dev/null 2>&1 || :
        printf >&2 '%s\n' "$(t disp_err_land_failed)"
        return 1
    fi
    git -C "$_bl_root" rev-parse --short HEAD 2>/dev/null
}

# The conductor's acceptance, whole: check behind the workers, run the project's check on
# the assembled branch, tidy up, write the trunk, and print the report to the terminal.
# There is no report file: the human reads this output and answers in words.
#
#   0 — checked, cleaned, in the trunk
#   1 — checked, NOT in the trunk (the report says why)
#   2 — refused, nothing done
build_accept() {
    _ba_root=$1; _ba_id=$2

    _ba_dir=$(build_dir "$_ba_root" "$_ba_id")
    [ -d "$_ba_dir" ] || { printf >&2 '%s\n' "$(t disp_err_no_build build="$_ba_id")"; return 2; }
    [ -f "$_ba_dir/journal.md" ] ||
        { printf >&2 '%s\n' "$(t disp_err_acc_no_journal build="$_ba_id")"; return 2; }
    [ -f "$_ba_dir/plan.md" ] ||
        { printf >&2 '%s\n' "$(t disp_err_acc_no_plan build="$_ba_id")"; return 2; }
    [ -f "$(build_accepted_file "$_ba_root" "$_ba_id")" ] &&
        { printf >&2 '%s\n' "$(t disp_err_acc_already build="$_ba_id")"; return 2; }

    _ba_branch=$(build_branch "$_ba_id")
    git -C "$_ba_root" rev-parse --verify --quiet "refs/heads/$_ba_branch" >/dev/null 2>&1 || {
        printf >&2 '%s\n' "$(t disp_err_no_branch branch="$_ba_branch")"
        return 2
    }

    _ba_ids=$(dispatch_subtask_ids "$_ba_dir/plan.md")
    [ -n "$_ba_ids" ] || { printf >&2 '%s\n' "$(t disp_err_acc_no_subtasks build="$_ba_id")"; return 2; }

    # Nothing is accepted while a subtask is still out: a report over a half-collected build
    # describes work that is not there and calls it the build.
    _ba_open=$(build_open_subtasks "$_ba_root" "$_ba_id")
    if [ -n "$_ba_open" ]; then
        printf >&2 '%s\n' "$(t disp_err_acc_open build="$_ba_id")"
        printf '%s\n' "$_ba_open" | sed 's/^/    /' >&2
        printf >&2 '  %s\n' "$(t disp_hint_collect build="$_ba_id")"
        return 2
    fi

    _ba_base=$(git -C "$_ba_root" rev-parse --short "$(build_base_sha "$_ba_root" "$_ba_id")" 2>/dev/null)
    _ba_coll=$(build_collected_file "$_ba_root" "$_ba_id")
    _ba_tmp=$(mktemp -d) || { printf >&2 '%s\n' "$(t disp_err_no_tmp)"; return 2; }
    _ba_stop=      # what keeps this out of the trunk
    _ba_say=       # what the human should know anyway, in the operator's language
    _ba_jsay=      # the same notes for the journal, which lives in the project: English

    printf '%s\n\n' "$(t disp_acc_head build="$_ba_id")"

    # --- what came back: the tree, not the workers' reports (MODES.md §3) ----
    printf '  %s\n' "$(t disp_acc_came_back)"
    for _ba_s in $_ba_ids; do
        _ba_w=$(awk -F'\t' -v s="$_ba_s" '$2 == s { print $1; exit }' "$_ba_coll" 2>/dev/null)
        _ba_sha=$(awk -F'\t' -v s="$_ba_s" '$2 == s { print $3; exit }' "$_ba_coll" 2>/dev/null)
        _ba_wp=$(printf '%-3s' "${_ba_w:-—}")
        if [ -z "$_ba_sha" ] || [ "$_ba_sha" = "—" ]; then
            printf '    %-14s %s\n' "$_ba_s" "$(t disp_acc_sub_nothing wave="$_ba_wp")"
            _ba_say="$_ba_say    $(t disp_acc_say_sub_nothing id="$_ba_s")
"
            _ba_jsay="$_ba_jsay- subtask $_ba_s changed nothing — that is an outcome too, and usually a bad one
"
            continue
        fi
        _ba_f=$(git -C "$_ba_root" diff --name-only "$_ba_sha^1" "$_ba_sha" 2>/dev/null |
                grep -c '[^[:space:]]')
        printf '    %-14s %s\n' "$_ba_s" \
            "$(t disp_acc_sub_line wave="$_ba_wp" sha="$_ba_sha" files="$_ba_f")"
    done

    _ba_changed=$(git -C "$_ba_root" diff --name-only "$_ba_base" "$_ba_branch" 2>/dev/null |
                  grep '[^[:space:]]' | sort -u)
    _ba_nfiles=$(printf '%s' "$_ba_changed" | grep -c '[^[:space:]]')
    _ba_stat=$(git -C "$_ba_root" diff --shortstat "$_ba_base" "$_ba_branch" 2>/dev/null |
               sed 's/^[[:space:]]*//')
    [ -n "$_ba_stat" ] || _ba_stat=$(t disp_acc_nothing)
    printf '\n  %s\n' "$(t disp_acc_changed stat="$_ba_stat")"
    [ "$_ba_nfiles" -eq 0 ] &&
        _ba_stop="$_ba_stop    $(t disp_acc_stop_empty)
"

    build_declared_paths "$_ba_dir/plan.md" > "$_ba_tmp/declared"
    _ba_undecl=$(printf '%s\n' "$_ba_changed" | grep '[^[:space:]]' |
                 grep -vxF -f "$_ba_tmp/declared" 2>/dev/null || :)
    if [ -n "$_ba_undecl" ]; then
        printf '  %s\n' "$(t disp_acc_undeclared paths="$(printf '%s' "$_ba_undecl" | tr '\n' ' ')")"
        printf '    %s\n' "$(t disp_acc_undeclared_why)"
    fi

    # Under the fleet the foundation is written by the build, once (invariant 0.4).
    _ba_found=$(printf '%s\n' "$_ba_changed" |
                grep -xE 'ARCHITECTURE\.md|CONVENTIONS\.md|DECISIONS\.md' |
                tr '\n' ' ' | sed 's/[[:space:]]*$//')
    if [ "$_ba_nfiles" -gt 0 ] && [ -z "$_ba_found" ]; then
        _ba_say="$_ba_say    $(t disp_acc_say_foundation)
"
        _ba_jsay="$_ba_jsay- the foundation is untouched — under the fleet the build writes it, once (invariant 0.4)
"
    fi

    # --- master check --------------------------------------------------------
    _ba_cmd=$(config_get build_check "$_ba_root")
    _ba_mc=$(build_master_check "$_ba_root" "$_ba_id" "$_ba_tmp/check.out")
    case $_ba_mc in
        none)
            printf '  %s\n' "$(t disp_acc_mc_none)"
            _ba_say="$_ba_say    $(t disp_acc_say_no_check)
"
            _ba_jsay="$_ba_jsay- no project check — nobody ran what was assembled
" ;;
        cannot)
            printf '  %s\n' "$(t disp_acc_mc_cannot)"
            _ba_stop="$_ba_stop    $(t disp_acc_stop_no_checkout)
" ;;
        0)
            printf '  %s\n' "$(t disp_acc_mc_green cmd="$_ba_cmd")" ;;
        *)
            printf '  %s\n' "$(t disp_acc_mc_code cmd="$_ba_cmd" code="$_ba_mc")"
            [ -s "$_ba_tmp/check.out" ] && tail -8 "$_ba_tmp/check.out" | sed 's/^/      /'
            _ba_stop="$_ba_stop    $(t disp_acc_stop_red code="$_ba_mc")
" ;;
    esac

    # --- cleanup -------------------------------------------------------------
    _ba_clean=$(build_cleanup "$_ba_root" "$_ba_id")
    printf '  %s\n' "$(t disp_acc_cleanup \
        removed="$(printf '%s\n' "$_ba_clean" | grep -c '	removed$')" \
        kept="$(printf '%s\n' "$_ba_clean" | grep -c '	kept-')" \
        released="$(printf '%s\n' "$_ba_clean" | grep -c '	released$')")"
    printf '%s\n' "$_ba_clean" | while IFS='	' read -r _ba_ck _ba_cn _ba_cv; do
        case $_ba_cv in
            kept-dirty)    printf '      %s\n' "$(t disp_acc_kept_dirty id="$_ba_cn")" ;;
            kept-unmerged) printf '      %s\n' "$(t disp_acc_kept_unmerged id="$_ba_cn")" ;;
            kept-git)      printf '      %s\n' "$(t disp_acc_kept_git id="$_ba_cn")" ;;
        esac
    done
    if printf '%s\n' "$_ba_clean" | grep -q '	kept-dirty$'; then
        _ba_say="$_ba_say    $(t disp_acc_say_worker_on)
"
        _ba_jsay="$_ba_jsay- a worker kept working after collect — its checkout has uncommitted work
"
    fi

    # --- trunk ---------------------------------------------------------------
    _ba_merge=
    if [ -n "$_ba_stop" ]; then
        printf '\n  %s\n%s' "$(t disp_acc_not_landed)" "$_ba_stop"
        [ -n "$_ba_say" ] && printf '  %s\n%s' "$(t disp_acc_also)" "$_ba_say"
        printf '  %s\n' "$(t disp_acc_branch_intact branch="$_ba_branch")"
        rm -rf "$_ba_tmp"
        return 1
    fi

    if ! _ba_merge=$(build_land "$_ba_root" "$_ba_id"); then
        printf '  %s\n' "$(t disp_acc_land_failed)"
        [ -n "$_ba_say" ] && printf '  %s\n%s' "$(t disp_acc_also)" "$_ba_say"
        rm -rf "$_ba_tmp"
        return 1
    fi
    _ba_trunk=$(git -C "$_ba_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
    printf '  %s\n' "$(t disp_acc_landed trunk="$_ba_trunk" branch="$_ba_branch" merge="$_ba_merge")"

    {
        printf 'Accepted by: conductor\n'
        printf 'When: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'Build branch: %s\n' "$_ba_branch"
        printf 'Into the trunk: %s, merge %s\n' "$_ba_trunk" "$_ba_merge"
        printf 'Undo: fraim undo %s\n' "$_ba_merge"
    } > "$(build_accepted_file "$_ba_root" "$_ba_id")" || :

    {
        printf '\n## Acceptance — %s\n\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf -- '- Checked and merged into the trunk by the conductor: %s ← %s, merge %s\n' \
            "$_ba_trunk" "$_ba_branch" "$_ba_merge"
        printf -- '- Project check: %s\n' "$_ba_mc"
        [ -n "$_ba_jsay" ] && printf '%s' "$_ba_jsay"
        printf -- '- Undo with one command: fraim undo %s\n' "$_ba_merge"
    } >> "$_ba_dir/journal.md"

    [ -n "$_ba_say" ] && printf '\n  %s\n%s' "$(t disp_acc_look)" "$_ba_say"
    printf '  %s\n' "$(t disp_acc_undo merge="$_ba_merge")"

    rm -rf "$_ba_tmp"
    return 0
}


# Pending builds, newest first: id and where each one stands.
# A directory under ai/builds is a BUILD only if it has a journal. Anything else is a
# folder someone put a plan in — that is what ai/builds/v2-core was in the first live
# build, and listing it as a build is what let `dispatch run` be aimed at it.
#
build_list() {
    _bl_root=$1
    [ -d "$_bl_root/ai/builds" ] || return 0
    for _b in "$_bl_root/ai/builds"/*; do
        [ -d "$_b" ] || continue
        if [ ! -f "$_b/journal.md" ]; then
            printf '%s\t%s\n' "$(basename -- "$_b")" "$(t disp_list_not_build)"
        elif [ -f "$_b/accepted" ]; then
            printf '%s\t%s\n' "$(basename -- "$_b")" "$(t disp_list_accepted)"
        else
            printf '%s\t%s\n' "$(basename -- "$_b")" "$(t disp_list_pending)"
        fi
    done | sort -r
}
