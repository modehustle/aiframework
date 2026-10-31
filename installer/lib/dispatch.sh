#!/bin/sh
# dispatch.sh — the fleet's control layer: plan check, build, briefs, checkouts, collect,
# acceptance (MODES.md §2, §5; DECISIONS 2026-10-31 «the fleet is the harness's own subagents»).
#
# What this file is NOT: it does not launch anything. The harness launches the workers —
# its own subagents, in its own way, on its own model. Every harness worth the name does
# that well by now, and a launcher of ours was the slowest and most expensive part of
# both live builds. This file does what no harness does:
#
#   before — checks the split: the files of two subtasks never overlap, every subtask says
#            where it may write and what it is for;
#   during — writes each worker's brief from the board card, and prepares a checkout per
#            subtask where the harness has no isolation of its own;
#   after  — verifies each result against the tree, assembles the round on the build branch,
#            runs the project's check and takes the round into the trunk in one merge that
#            one command undoes, closing the round's cards in that same merge.
#
# The invariant that shapes everything here (MODES.md §3): the conductor checks the TREE,
# not the reports. A worker's report is prose written by the party being judged. It is
# worth reading and worthless as evidence, so nothing in this file decides anything from
# it — content comes from git.
#
# A build is ONE ROUND: the subtasks run at the same time and none waits for another.
# Order lives on the board (a card's `after:`), not in the plan: what depends on this round
# is the next round, taken from the board once this one is in the trunk. That is also what
# makes a harness's own worktrees usable — they branch from the current branch, and the
# next round's workers must see this round's work, which they do once it is accepted.

# ---------------------------------------------------------------------------
# Plan parsing
#
#     ## Contract                      (optional, once: goes verbatim into every brief)
#     POST /api/login {email, password} → 200 {token} | 401
#
#     ## Subtask: login-form           (a card slug on the board, or a plain name)
#     **Files**: web/login/, api/auth.ts
#     **Summary**: one line            (only without a card — a card says it itself)
#     **Done when**: one line          (only without a card, optional)
#
#     ### `api/auth.ts`                (also accepted: a heading adds a path)
#     - why
#
# A path ending with `/` is a directory: everything under it belongs to the subtask. Exact
# files were the only form before, and they made the conductor list every file up front
# and turned a worker's new helper file in its own module into a refusal.
#
# The card is the source of the intent: what and why, done when. The plan adds only what a
# card deliberately never holds — the files (DECISIONS 2026-10-27: a card carries no code
# context) — so nothing is written twice. `**Role**` (the retired role table) is ignored;
# `**After**` is read only to refuse it: order comes from the board now.
# ---------------------------------------------------------------------------

# Fields are separated by \037, not `|` or a tab: a summary may contain `|`, and a tab is
# IFS whitespace — `read` collapses empty fields around it (Known Pitfalls).
DISPATCH_SEP=$(printf '\037')

# One record per subtask: id, comma-separated paths, After, summary, done when.
dispatch_parse_plan() {
    [ -f "$1" ] || return 0
    _DP_SEP=$DISPATCH_SEP awk '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        function addpaths(list,    n, a, i, p) {
            n = split(list, a, ",")
            for (i = 1; i <= n; i++) {
                p = a[i]; gsub(/`/, "", p); p = trim(p); sub(/^\.\//, "", p)
                if (p != "") paths = (paths == "" ? p : paths "," p)
            }
        }
        function flush(    s) {
            s = ENVIRON["_DP_SEP"]
            if (id != "") print id s paths s after s summary s done
            id = ""; paths = ""; after = ""; summary = ""; done = ""
        }
        /^## Subtask:/ { flush(); id = $3; next }
        /^## / { flush(); next }
        id == "" { next }
        /^\*\*Files\*\*:/     { v = $0; sub(/^\*\*Files\*\*:[ \t]*/, "", v); addpaths(v); next }
        /^\*\*Summary\*\*:/   { v = $0; sub(/^\*\*Summary\*\*:[ \t]*/, "", v); summary = trim(v); next }
        /^\*\*Done when\*\*:/ { v = $0; sub(/^\*\*Done when\*\*:[ \t]*/, "", v); done = trim(v); next }
        /^\*\*After\*\*:/     { v = $0; sub(/^\*\*After\*\*:[ \t]*/, "", v); after = trim(v); next }
        /^### `/ { v = $0; sub(/^### `/, "", v); sub(/`.*$/, "", v); addpaths(v); next }
        END { flush() }
    ' "$1"
}

# Just the ids, in plan order.
dispatch_subtask_ids() { dispatch_parse_plan "$1" | cut -d"$DISPATCH_SEP" -f1; }

# One field of one subtask: 1 id, 2 paths, 3 After, 4 summary, 5 done when.
dispatch_field() {
    dispatch_parse_plan "$1" | awk -F"$DISPATCH_SEP" -v id="$2" -v n="$3" '$1 == id { print $n; exit }'
}

# The plan's `## Contract` section, verbatim, without the heading.
dispatch_contract() {
    [ -f "$1" ] || return 0
    awk '/^## Contract[[:space:]]*$/ { f = 1; next } /^## / { f = 0 } f' "$1" | sed -e '/./,$!d'
}

# The open board card a subtask stands for, or failure. Without a project there is no
# board, and every subtask has to say what it is for itself.
dispatch_card() {
    [ -n "$1" ] || return 1
    _dcd_f="$(tasks_dir "$1")/$2.md"
    tasks_is_card "$_dcd_f" || return 1
    printf '%s\n' "$_dcd_f"
}

# Every path of the plan, comma-separated: what the whole build may touch.
dispatch_all_paths() {
    dispatch_parse_plan "$1" | cut -d"$DISPATCH_SEP" -f2 | tr ',' '\n' | grep '[^[:space:]]' |
        sort -u | tr '\n' ',' | sed 's/,$//'
}

# Paths on stdin → `inside:PATH` or `outside:PATH`, against comma-separated entries where
# one ending with `/` covers everything under it. The entries travel through ENVIRON, not
# `awk -v`, which would eat backslashes (CONVENTIONS).
dispatch_classify() {
    _DC_ENTRIES=$1 awk '
        BEGIN { n = split(ENVIRON["_DC_ENTRIES"], e, ",") }
        $0 == "" { next }
        {
            p = $0; hit = 0
            for (i = 1; i <= n; i++) {
                if (e[i] == "") continue
                if (p == e[i] || (substr(e[i], length(e[i])) == "/" && index(p, e[i]) == 1)) { hit = 1; break }
            }
            print (hit ? "inside:" : "outside:") p
        }'
}

# Every pair of paths from two different subtasks that overlap — the same file, or a file
# inside the other's directory. One line each: path<TAB>subtask<TAB>path<TAB>subtask.
dispatch_overlaps() {
    dispatch_parse_plan "$1" | awk -F"$DISPATCH_SEP" '
        function covers(x, y) { return x == y || (substr(x, length(x)) == "/" && index(y, x) == 1) }
        { m = split($2, a, ","); for (j = 1; j <= m; j++) if (a[j] != "") { n++; ent[n] = a[j]; own[n] = $1 } }
        END {
            for (i = 1; i <= n; i++) for (k = i + 1; k <= n; k++)
                if (own[i] != own[k] && (covers(ent[i], ent[k]) || covers(ent[k], ent[i])))
                    printf "%s\t%s\t%s\t%s\n", ent[i], own[i], ent[k], own[k]
        }'
}

# ---------------------------------------------------------------------------
# dispatch-check — the gate that makes "one acceptance" honest (MODES.md §11.2, answer B)
#
# The build's boundary is what this check passed. It refuses only on what the machine knows
# exactly, before a single worker starts — the alternative is paying N workers to find a
# typo:
#   - a subtask with no paths, or with neither a card nor a summary (INCOMPLETE);
#   - a project card as a subtask — a project is done through its tasks;
#   - the same subtask name twice;
#   - `**After**` — order lives on the board now: the dependent piece is the next round;
#   - two subtasks over one path (COLLISION) — two workers, one file, a silent merge.
# ---------------------------------------------------------------------------
dispatch_check() {
    _dc_plan=$1; _dc_root=${2:-}
    [ -f "$_dc_plan" ] || { printf >&2 '%s\n' "$(t disp_err_no_plan plan="$_dc_plan")"; return 1; }

    _dc_recs=$(dispatch_parse_plan "$_dc_plan")
    [ -n "$_dc_recs" ] || { printf >&2 '%s\n' "$(t disp_err_no_subtasks)"; return 1; }

    _dc_bad=0

    _dc_struct=$(printf '%s\n' "$_dc_recs" | while IFS="$DISPATCH_SEP" read -r _dcs_id _dcs_p _dcs_a _dcs_s _dcs_d; do
        [ -n "$_dcs_id" ] || continue
        [ -n "$_dcs_p" ] || printf '%s\n' "$(t disp_err_no_files id="$_dcs_id")"
        if _dcs_f=$(dispatch_card "$_dc_root" "$_dcs_id"); then
            [ "$(fm_get "$_dcs_f" kind)" = master ] && printf '%s\n' "$(t disp_err_master id="$_dcs_id")"
        else
            [ -n "$_dcs_s" ] || printf '%s\n' "$(t disp_err_no_intent id="$_dcs_id")"
        fi
    done)
    _dc_dupid=$(printf '%s\n' "$_dc_recs" | cut -d"$DISPATCH_SEP" -f1 | grep '[^[:space:]]' | sort | uniq -d)
    for _dc_id in $_dc_dupid; do
        _dc_struct="$_dc_struct
$(t disp_err_dup_id id="$_dc_id")"
    done
    _dc_struct=$(printf '%s\n' "$_dc_struct" | grep '[^[:space:]]' || :)
    if [ -n "$_dc_struct" ]; then
        printf >&2 '%s\n%s\n' "$(t disp_err_incomplete)" "$(printf '%s\n' "$_dc_struct" | sed 's/^/  /')"
        _dc_bad=1
    fi

    _dc_after=$(printf '%s\n' "$_dc_recs" | awk -F"$DISPATCH_SEP" '$3 != "" { printf "%s%s", s, $1; s = ", " }')
    if [ -n "$_dc_after" ]; then
        printf >&2 '%s\n' "$(t disp_err_after_retired who="$_dc_after")"
        _dc_bad=1
    fi

    _dc_ov=$(dispatch_overlaps "$_dc_plan")
    if [ -n "$_dc_ov" ]; then
        printf >&2 '%s\n' "$(t disp_err_collision)"
        printf '%s\n' "$_dc_ov" | while IFS='	' read -r _dco_p1 _dco_a _dco_p2 _dco_b; do
            [ -n "$_dco_p1" ] || continue
            printf >&2 '  %s\n' "$(t disp_err_overlap_line a="$_dco_a" pa="$_dco_p1" b="$_dco_b" pb="$_dco_p2")"
        done
        printf >&2 '%s\n' "$(t disp_err_collision_ways)"
        _dc_bad=1
    fi

    [ "$_dc_bad" -eq 0 ]
}

# ---------------------------------------------------------------------------
# The arithmetic of a build: whether one acceptance stays honest
#
# Every number comes from ONE scarce resource, the single acceptance (MODES.md §5): a build
# of twelve subtasks is not accepted by one decision but by twelve. They are WARNINGS,
# never refusals — a file count does not measure work, and refusing on such a metric would
# be lying with precision. The conductor reads them and decides.
# ---------------------------------------------------------------------------
DISPATCH_MAX_SUBTASKS=6
DISPATCH_PATHS_MAX=10

# Warnings, to stderr; always returns 0 — a caller must never turn these into a refusal.
dispatch_size_notes() {
    _sn_recs=$(dispatch_parse_plan "$1")
    [ -n "$_sn_recs" ] || return 0
    _sn_n=$(printf '%s\n' "$_sn_recs" | grep -c '[^[:space:]]')
    [ "$_sn_n" -le "$DISPATCH_MAX_SUBTASKS" ] ||
        printf >&2 '%s\n' "$(t disp_warn_subtasks n="$_sn_n" max="$DISPATCH_MAX_SUBTASKS")"
    printf '%s\n' "$_sn_recs" | while IFS="$DISPATCH_SEP" read -r _sn_id _sn_p _sn_rest; do
        [ -n "$_sn_id" ] || continue
        _sn_pn=$(printf '%s\n' "$_sn_p" | tr ',' '\n' | grep -c '[^[:space:]]')
        [ "$_sn_pn" -le "$DISPATCH_PATHS_MAX" ] ||
            printf >&2 '%s\n' "$(t disp_warn_paths id="$_sn_id" n="$_sn_pn")"
    done
    # The failure of the second live build: three pieces each right on its own, all three
    # rejected for a different API. A contract written down is what they share.
    if [ "$_sn_n" -gt 1 ] && [ -z "$(dispatch_contract "$1")" ]; then
        printf >&2 '%s\n' "$(t disp_note_no_contract)"
    fi
    return 0
}

# What the build is about to hand out: one line per subtask — where its intent comes from
# (the board card or the plan), how many paths, and the title.
dispatch_report() {
    _dr_plan=$1; _dr_root=${2:-}
    dispatch_parse_plan "$_dr_plan" | while IFS="$DISPATCH_SEP" read -r _dr_id _dr_p _dr_a _dr_s _dr_d; do
        [ -n "$_dr_id" ] || continue
        _dr_n=$(printf '%s\n' "$_dr_p" | tr ',' '\n' | grep -c '[^[:space:]]')
        if _dr_f=$(dispatch_card "$_dr_root" "$_dr_id"); then
            printf '  %s\n' "$(t disp_report_card id="$_dr_id" n="$_dr_n" title="$(tasks_title "$_dr_f")")"
        else
            printf '  %s\n' "$(t disp_report_plan id="$_dr_id" n="$_dr_n" title="$_dr_s")"
        fi
    done
}

# ---------------------------------------------------------------------------
# Build record and briefs
# ---------------------------------------------------------------------------

build_dir() { printf '%s/ai/builds/%s\n' "$1" "$2"; }

# The branch a round is assembled on. Named after the build, so a project may carry several
# and none of them is the trunk.
build_branch() { printf 'fraim/%s\n' "$1"; }

# A worker's brief, next to the plan and the journal: one folder per build.
dispatch_brief_file() { printf '%s/%s.md\n' "$(build_dir "$1" "$2")" "$3"; }

# subtask<TAB>merged sha or «—»<TAB>time<TAB>where it came from. Our record of what actually
# came back (A3) — what was handed to whom and what came back is our truth, and it is in git.
build_collected_file() { printf '%s/collected.tsv\n' "$(build_dir "$1" "$2")"; }

build_is_collected() {
    _bic=$(build_collected_file "$1" "$2")
    [ -f "$_bic" ] || return 1
    awk -F'\t' -v s="$3" '$1 == s { found = 1 } END { exit !found }' "$_bic"
}

# The sha a subtask was merged as, from its LAST record: «—» means "looked, nothing came back
# yet", and a later collect looks again — a worker collected before it finished, or from the
# wrong checkout, must not be locked out of the round by that first look.
build_collected_sha() {
    _bcs=$(build_collected_file "$1" "$2")
    [ -f "$_bcs" ] || return 0
    awk -F'\t' -v s="$3" '$1 == s { v = $2 } END { if (v != "") print v }' "$_bcs"
}

# The build journal — MODES.md §11.4, answer D — and the build branch.
build_seal() {
    _bs_root=$1; _bs_id=$2; _bs_plan=$3

    _bs_dir=$(build_dir "$_bs_root" "$_bs_id")
    mkdir -p "$_bs_dir" || return 1
    cp "$_bs_plan" "$_bs_dir/plan.md" 2>/dev/null || return 1

    # The build branch, created here and never checked out in the project root. Workers'
    # results are merged INTO it, so the trunk stays untouched for the whole round: the
    # single merge into the trunk happens once, in `accept`, after everything has been
    # checked (MODES.md §4, option B).
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
        printf '| subtask | board card |\n'
        printf '|---|---|\n'
        dispatch_subtask_ids "$_bs_plan" | while read -r _bs_s; do
            [ -n "$_bs_s" ] || continue
            if dispatch_card "$_bs_root" "$_bs_s" >/dev/null; then
                printf '| %s | ai/tasks/%s.md |\n' "$_bs_s" "$_bs_s"
            else
                printf '| %s | — |\n' "$_bs_s"
            fi
        done
        printf '\n## Conductor lessons\n\n'
        printf '<!-- Filled in after acceptance. MODES.md §11.4: a class of lessons no worker\n'
        printf '     has — the traps of dispatching, not the traps of the code. -->\n'
    } > "$_bs_dir/journal.md" || return 1

    printf '%s\n' "$_bs_dir/journal.md"
}

# The worker never sees the conductor's conversation (G1), so the brief carries everything:
# the intent and the done-when from the card, the paths, the contract, and the rules that
# make a round safe. English: it is written into the project.
dispatch_write_brief() {
    _wb_root=$1; _wb_build=$2; _wb_id=$3
    _wb_plan="$(build_dir "$_wb_root" "$_wb_build")/plan.md"
    _wb_paths=$(dispatch_field "$_wb_plan" "$_wb_id" 2)
    _wb_sum=$(dispatch_field "$_wb_plan" "$_wb_id" 4)
    _wb_done=$(dispatch_field "$_wb_plan" "$_wb_id" 5)
    _wb_cardtxt=
    if _wb_card=$(dispatch_card "$_wb_root" "$_wb_id"); then
        _wb_title=$(tasks_title "$_wb_card")
        _wb_what=$(tasks_section "$_wb_card" "$TASK_WHAT")
        _wb_dw=$(tasks_section "$_wb_card" "$TASK_DONE")
        [ -n "$_wb_dw" ] || _wb_dw=$_wb_done
        _wb_cardtxt=" — board card \`ai/tasks/$_wb_id.md\`"
    else
        _wb_title=$_wb_sum; _wb_what=$_wb_sum; _wb_dw=$_wb_done
    fi
    [ -n "$_wb_what" ] || _wb_what=$_wb_sum
    _wb_contract=$(dispatch_contract "$_wb_plan")
    _wb_out=$(dispatch_brief_file "$_wb_root" "$_wb_build" "$_wb_id")

    {
        printf '# %s\n\n' "${_wb_title:-$_wb_id}"
        printf 'Subtask `%s` of build `%s`%s.\n' "$_wb_id" "$_wb_build" "$_wb_cardtxt"
        printf 'You did not see the conversation that planned this build: this brief is everything you get.\n\n'
        printf '## What and why\n\n%s\n\n' "$_wb_what"
        [ -n "$_wb_dw" ] && printf '## Done when\n\n%s\n\n' "$_wb_dw"
        printf '## Files you may change\n\n'
        printf '%s\n' "$_wb_paths" | tr ',' '\n' | while read -r _wb_p; do
            [ -n "$_wb_p" ] || continue
            case $_wb_p in
                */) printf -- '- `%s` — and everything under it\n' "$_wb_p" ;;
                *)  printf -- '- `%s`\n' "$_wb_p" ;;
            esac
        done
        printf '\n'
        if [ -n "$_wb_contract" ]; then
            printf '## Contract\n\n'
            printf 'Every worker of this build gets the same text. Code against it exactly; if it does\n'
            printf 'not fit, stop and say so — do not change it on your own.\n\n'
            printf '%s\n\n' "$_wb_contract"
        fi
        cat <<'RULES'
## Rules (the «Fleet worker» section of /run-task)

- **Your own checkout only.** Work where your harness put you (its own worktree), or in the
  checkout the conductor named. Never in the project's main checkout: other workers run
  next to you.
- **Only the files above.** Need another one → do not touch it; stop and say which and why.
  An edit outside the list merges silently over someone else's.
- **Nothing beyond the brief.** No neighbouring refactoring, no fixes along the way, no new
  dependencies or configs unless the brief names them. What you notice goes into the report.
- **The brief and the code disagree → stop** and describe the disagreement. Bend neither.
- **The foundation is not yours here.** Do not touch `ARCHITECTURE.md`, `CONVENTIONS.md` or
  `DECISIONS.md`, even if `AGENTS.md` says to update them after a change: the build writes
  them once, after acceptance. Say in the report what belongs there.
- **Commit your work** in your checkout before you finish: the round is assembled from
  commits, and uncommitted work is not collected.
- **Report in a few lines**: what you did, what you could not, what belongs in the
  foundation. End with the line `Branch: <name>` — the output of `git branch --show-current`.
RULES
    } > "$_wb_out" || return 1

    printf '%s\n' "$_wb_out"
}

# ---------------------------------------------------------------------------
# Checkouts
#
# The registry of checkouts is git's (`git worktree list`), whoever created them — the
# harness, fraim or a human. A checkout fraim prepares is named <build>-<subtask>, so it is
# found again by name, and it lives inside the project under `.fraim/` — inside, because a
# harness whose sandbox is the project directory can reach it there; under a directory that
# ignores itself, so the project's own `git status` never shows it.
# ---------------------------------------------------------------------------
DISPATCH_WT_DIR=.fraim/worktrees

# Where a checkout with this directory name is, or nothing.
#
# The `if` is not style: `[ … ] && …` as the last command of a loop body returns 1 on the
# final non-matching iteration, and under `set -e` that kills the caller's `$( … )`.
dispatch_worker_tree() {
    git -C "$1" worktree list --porcelain 2>/dev/null |
        sed -n 's/^worktree //p' |
        while read -r _wtr_p; do
            if [ "$(basename -- "$_wtr_p")" = "$2" ]; then
                printf '%s\n' "$_wtr_p"
                break
            fi
        done
    return 0
}

# The checkout a branch is checked out in, or nothing.
dispatch_branch_tree() {
    git -C "$1" worktree list --porcelain 2>/dev/null |
        awk -v b="refs/heads/$2" '/^worktree / { p = substr($0, 10) } $0 == "branch " b { print p; exit }'
}

# A checkout per subtask of the build, from the build branch — for a harness without
# isolation of its own. Run again, it reuses what exists.
dispatch_prepare() {
    _dp_root=$1; _dp_build=$2
    _dp_dir=$(build_dir "$_dp_root" "$_dp_build")
    _dp_plan="$_dp_dir/plan.md"
    [ -f "$_dp_plan" ] || { printf >&2 '%s\n' "$(t disp_err_no_build_plan build="$_dp_build")"; return 1; }
    [ -f "$_dp_dir/journal.md" ] ||
        { printf >&2 '%s\n' "$(t disp_err_not_sealed build="$_dp_build")"; return 1; }
    _dp_branch=$(build_branch "$_dp_build")
    git -C "$_dp_root" rev-parse --verify --quiet "refs/heads/$_dp_branch" >/dev/null 2>&1 ||
        { printf >&2 '%s\n' "$(t disp_err_no_branch branch="$_dp_branch")"; return 1; }

    _dp_home="$_dp_root/.fraim"
    mkdir -p "$_dp_root/$DISPATCH_WT_DIR" || return 1
    [ -f "$_dp_home/.gitignore" ] || printf '*\n' > "$_dp_home/.gitignore"

    _dp_bad=0
    for _dp_id in $(dispatch_subtask_ids "$_dp_plan"); do
        _dp_prev=$(build_collected_sha "$_dp_root" "$_dp_build" "$_dp_id")
        [ -n "$_dp_prev" ] && [ "$_dp_prev" != "—" ] && continue
        _dp_name="$_dp_build-$_dp_id"
        _dp_tree=$(dispatch_worker_tree "$_dp_root" "$_dp_name")
        if [ -z "$_dp_tree" ]; then
            _dp_tree="$_dp_root/$DISPATCH_WT_DIR/$_dp_name"
            if git -C "$_dp_root" rev-parse --verify --quiet "refs/heads/fraim/$_dp_name" >/dev/null 2>&1; then
                git -C "$_dp_root" worktree add -q "$_dp_tree" "fraim/$_dp_name" >/dev/null 2>&1
            else
                git -C "$_dp_root" worktree add -q -b "fraim/$_dp_name" "$_dp_tree" "$_dp_branch" >/dev/null 2>&1
            fi || {
                printf '  %s\n' "$(t disp_prep_failed id="$_dp_id")"
                _dp_bad=1; continue
            }
        fi
        printf '  %s\n' "$(t disp_prep_line id="$_dp_id" checkout="$_dp_tree" \
            brief="$(dispatch_brief_file "$_dp_root" "$_dp_build" "$_dp_id")")"
    done
    [ "$_dp_bad" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Where a worker's result is, and what it changed
# ---------------------------------------------------------------------------

# tip<TAB>checkout (may be empty)<TAB>label. From a branch the conductor names (the harness
# made the worktree and the worker reported its branch), or from the checkout fraim
# prepared. Status 2: the named branch does not exist; 1: no result found at all.
dispatch_source() {
    _ds_root=$1; _ds_build=$2; _ds_id=$3; _ds_br=${4:-}
    if [ -n "$_ds_br" ]; then
        _ds_tip=$(git -C "$_ds_root" rev-parse --verify --quiet "refs/heads/$_ds_br^{commit}" 2>/dev/null) ||
            return 2
        printf '%s\t%s\t%s\n' "$_ds_tip" "$(dispatch_branch_tree "$_ds_root" "$_ds_br")" "$_ds_br"
        return 0
    fi
    _ds_tree=$(dispatch_worker_tree "$_ds_root" "$_ds_build-$_ds_id")
    [ -n "$_ds_tree" ] || return 1
    _ds_tip=$(git -C "$_ds_tree" rev-parse HEAD 2>/dev/null) || return 1
    _ds_lab=$(git -C "$_ds_tree" branch --show-current 2>/dev/null)
    printf '%s\t%s\t%s\n' "$_ds_tip" "$_ds_tree" "${_ds_lab:-$_ds_build-$_ds_id}"
}

# The files a worker's own commits touched: everything reachable from its tip and from
# neither the trunk nor the build branch. Not a diff against the base: a harness's worktree
# branches from wherever the trunk stood, and only the worker's commits are its work.
# Renames are split into their two paths, so moving a file out of the lane is seen.
dispatch_worker_files() {
    git -C "$1" log --no-merges --no-renames --format= --name-only "$3" \
        --not HEAD "$(build_branch "$2")" 2>/dev/null | grep '[^[:space:]]' | sort -u
}

# What a worker left uncommitted in its checkout: status lines, for the refusal.
dispatch_dirty() {
    [ -n "$1" ] || return 0
    (cd "$1" 2>/dev/null && git status --porcelain 2>/dev/null | head -20)
}

# `inside:` / `outside:` lines for one subtask's result: its commits and, when the checkout
# is known, its uncommitted files too — the first live build had a worker finish and leave
# its work unstaged, and calling that "nothing changed" would be a lie (MODES.md §3).
dispatch_verify() {
    _dv_root=$1; _dv_build=$2; _dv_id=$3; _dv_br=${4:-}
    _dv_plan="$(build_dir "$_dv_root" "$_dv_build")/plan.md"
    _dv_paths=$(dispatch_field "$_dv_plan" "$_dv_id" 2)
    _dv_src=$(dispatch_source "$_dv_root" "$_dv_build" "$_dv_id" "$_dv_br") || return 1
    _dv_tip=$(printf '%s' "$_dv_src" | cut -f1)
    _dv_tree=$(printf '%s' "$_dv_src" | cut -f2)
    {
        dispatch_worker_files "$_dv_root" "$_dv_build" "$_dv_tip"
        dispatch_dirty "$_dv_tree" | cut -c4- | sed 's/.* -> //'
    } | grep '[^[:space:]]' | sort -u | dispatch_classify "$_dv_paths"
}

# ---------------------------------------------------------------------------
# Collect: the round into the build branch
#
# Four refusals, and each is a lesson rather than a preference:
#   1. no result for a subtask          — nothing to collect, and guessing is worse
#   2. uncommitted work in its checkout — a merge takes commits
#   3. a file outside the declared paths — the one line the tree verification exists to
#                                         produce (MODES.md §3); merging it with a warning
#                                         would make the check decorative
#   4. a merge conflict                 — paths cannot overlap inside a build and nothing
#                                         else writes to the build branch, so a conflict
#                                         means an assumption broke. Never auto-resolved.
#
# The merge happens in a throwaway checkout of the build branch: the conductor's own working
# tree is never switched, and a failed merge leaves no half-merged state anywhere.
# ---------------------------------------------------------------------------

# One result into the build branch. Prints the merged sha on success.
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

# Files changed in the project's own checkout that fall inside this build's paths: a worker
# that wrote by a relative path into the main checkout instead of its own. The build's own
# record (ai/builds/) and fraim's checkouts are not such files.
dispatch_main_leaks() {
    git -C "$1" status --porcelain --untracked-files=all 2>/dev/null | cut -c4- |
        sed 's/^"//; s/"$//; s/.* -> //' | grep -v '^ai/builds/' | grep -v '^\.fraim/' |
        dispatch_classify "$2" | sed -n 's/^inside://p'
}

dispatch_collect() {
    _co_root=$1; _co_build=$2; shift 2

    _co_dir=$(build_dir "$_co_root" "$_co_build")
    _co_plan="$_co_dir/plan.md"
    [ -f "$_co_plan" ] || { printf >&2 '%s\n' "$(t disp_err_no_build_plan build="$_co_build")"; return 1; }
    [ -f "$_co_dir/journal.md" ] ||
        { printf >&2 '%s\n' "$(t disp_err_not_sealed build="$_co_build")"; return 1; }
    _co_branch=$(build_branch "$_co_build")
    git -C "$_co_root" rev-parse --verify --quiet "refs/heads/$_co_branch" >/dev/null 2>&1 || {
        printf >&2 '%s\n' "$(t disp_err_no_branch branch="$_co_branch")"
        return 1
    }

    # SUB=BRANCH pairs: the branches the harness's worktrees produced, as the workers reported.
    _co_ids=$(dispatch_subtask_ids "$_co_plan")
    _co_map=
    for _co_a in "$@"; do
        case $_co_a in
            ?*=?*) ;;
            *) printf >&2 '%s\n' "$(t disp_err_pair arg="$_co_a")"; return 1 ;;
        esac
        printf '%s\n' "$_co_ids" | grep -qxF -- "${_co_a%%=*}" ||
            { printf >&2 '%s\n' "$(t disp_err_no_subtask build="$_co_build" sub="${_co_a%%=*}")"; return 1; }
        _co_map="$_co_map$_co_a
"
    done

    _co_paths=$(dispatch_all_paths "$_co_plan")
    _co_before=$(git -C "$_co_root" rev-parse "$_co_branch" 2>/dev/null)
    _co_file=$(build_collected_file "$_co_root" "$_co_build")
    _co_bad=0
    printf '%s\n' "$(t disp_co_head build="$_co_build")"

    for _co_id in $_co_ids; do
        _co_prev=$(build_collected_sha "$_co_root" "$_co_build" "$_co_id")
        if [ -n "$_co_prev" ] && [ "$_co_prev" != "—" ]; then
            printf '  %-12s %s\n' "$_co_id" "$(t disp_co_already)"
            continue
        fi
        _co_br=$(printf '%s' "$_co_map" | awk -v s="$_co_id" 'index($0, s "=") == 1 { print substr($0, length(s) + 2); exit }')
        _co_src=$(dispatch_source "$_co_root" "$_co_build" "$_co_id" "$_co_br")
        case $? in
            0) ;;
            2) printf '  %-12s %s\n' "$_co_id" "$(t disp_co_no_branch branch="$_co_br")"; _co_bad=1; continue ;;
            *) printf '  %-12s %s\n' "$_co_id" "$(t disp_co_no_result id="$_co_id")"; _co_bad=1; continue ;;
        esac
        _co_tip=$(printf '%s' "$_co_src" | cut -f1)
        _co_tree=$(printf '%s' "$_co_src" | cut -f2)
        _co_from=$(printf '%s' "$_co_src" | cut -f3)

        _co_dirty=$(dispatch_dirty "$_co_tree")
        if [ -n "$_co_dirty" ]; then
            printf '  %-12s %s\n' "$_co_id" "$(t disp_co_dirty)"
            printf '%s\n' "$_co_dirty" | sed 's/^/      /'
            _co_bad=1; continue
        fi

        _co_files=$(dispatch_worker_files "$_co_root" "$_co_build" "$_co_tip")
        if [ -z "$_co_files" ] ||
           git -C "$_co_root" merge-base --is-ancestor "$_co_tip" "$_co_branch" >/dev/null 2>&1; then
            printf '  %-12s %s\n' "$_co_id" "$(t disp_co_nothing)"
            [ -n "$_co_prev" ] ||
                printf '%s\t—\t%s\t%s\n' "$_co_id" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$_co_from" >> "$_co_file"
            continue
        fi

        # The tree, not the report (MODES.md §3) — before the merge, on purpose: after it a
        # stray file is already in the build branch and the check is archaeology.
        _co_mine=$(dispatch_field "$_co_plan" "$_co_id" 2)
        _co_out=$(printf '%s\n' "$_co_files" | dispatch_classify "$_co_mine" | sed -n 's/^outside://p')
        if [ -n "$_co_out" ]; then
            printf '  %-12s %s\n' "$_co_id" "$(t disp_co_outside)"
            printf '%s\n' "$_co_out" | sed 's/^/      /'
            _co_bad=1; continue
        fi

        if _co_merged=$(dispatch_merge_one "$_co_root" "$_co_branch" "$_co_tip" \
                            "build $_co_build: subtask $_co_id"); then
            printf '  %-12s %s\n' "$_co_id" "$(t disp_co_merged sha="$_co_merged" from="$_co_from")"
            printf '%s\t%s\t%s\t%s\n' "$_co_id" "$_co_merged" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
                "$_co_from" >> "$_co_file"
        else
            printf '  %-12s %s\n' "$_co_id" "$(t disp_co_merge_failed)"
            _co_bad=1
        fi
    done

    _co_leaks=$(dispatch_main_leaks "$_co_root" "$_co_paths")
    if [ -n "$_co_leaks" ]; then
        printf '\n%s\n' "$(t disp_co_main_leak)"
        printf '%s\n' "$_co_leaks" | sed 's/^/  /'
    fi

    # The combined diff of the whole round: the only place where a divergence the path check
    # cannot see — two workers naming one thing differently — becomes visible at all. A look,
    # not a verdict: the conductor reads it.
    _co_after=$(git -C "$_co_root" rev-parse "$_co_branch" 2>/dev/null)
    if [ -n "$_co_before" ] && [ "$_co_before" != "$_co_after" ]; then
        printf '\n%s\n' "$(t disp_co_round_diff)"
        git -C "$_co_root" diff --stat "$_co_before" "$_co_after" 2>/dev/null | sed 's/^/  /'
    fi

    {
        printf '\n## Collected — %s\n\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        [ -f "$_co_file" ] && awk -F'\t' '{ v[$1] = $2; f[$1] = $4; if (!($1 in o)) { o[$1] = ++n; id[n] = $1 } }
            END { for (i = 1; i <= n; i++) printf "- %s → %s (%s)\n", id[i], v[id[i]], f[id[i]] }' "$_co_file"
        [ "$_co_bad" -eq 0 ] || printf -- '- collected partially: some subtasks were refused\n'
    } >> "$_co_dir/journal.md"

    [ "$_co_bad" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Acceptance: the whole of it is the conductor's, trunk write included
#
# The checking is the conductor's, and the trunk write is not a decision but the last step
# of checking — a round nobody merged has not been checked against the tree it has to live
# in. `accept` therefore does everything and prints a report to the terminal; the human reads
# it and says whether it is right (MODES.md §4, option B).
#
# It is affordable because `collect` assembles the round into ONE branch: the trunk write is
# ONE `--no-ff` merge and undoing it is `fraim undo <sha>`. The round's board cards are
# closed by a commit ON the build branch, so that merge carries them too, and the one undo
# reopens them with the code.
#
# What still refuses to happen silently: the trunk write is skipped, loudly, whenever the
# machine knows something is wrong — a red project check, a dirty working tree, a conflict,
# an empty build. Judgement did not move to the machine; only the labour did.
# ---------------------------------------------------------------------------

build_accepted_file() { printf '%s/accepted\n' "$(build_dir "$1" "$2")"; }

# Where the build branch started: the journal's record (A3); git's fork point only when the
# line is missing or no longer resolves.
build_base_sha() {
    _bb_root=$1; _bb_build=$2
    # The second pattern is how journals written before the English format name the line.
    _bb_s=$(sed -n 's/^- Base: //p; s/^- База: //p' "$(build_dir "$_bb_root" "$_bb_build")/journal.md" 2>/dev/null |
            head -1 | tr -d ' ')
    if [ -n "$_bb_s" ] && [ "$_bb_s" != "—" ] &&
       git -C "$_bb_root" rev-parse --verify --quiet "$_bb_s^{commit}" >/dev/null 2>&1; then
        printf '%s\n' "$_bb_s"; return 0
    fi
    git -C "$_bb_root" merge-base "$(build_branch "$_bb_build")" HEAD 2>/dev/null
}

# Subtasks of the plan that are not in collected.tsv. Asked positively on purpose: the
# absence of an answer must never read as "everything is in" (Known Pitfalls).
build_open_subtasks() {
    _os_root=$1; _os_build=$2
    for _os_id in $(dispatch_subtask_ids "$(build_dir "$_os_root" "$_os_build")/plan.md" 2>/dev/null); do
        [ -n "$_os_id" ] || continue
        build_is_collected "$_os_root" "$_os_build" "$_os_id" || printf '%s\n' "$_os_id"
    done
}

# The project's own check, run on the ASSEMBLED branch: the failure it catches is the one no
# worker could see — two results each correct alone and wrong together. The command is
# project configuration (C1), `build_check`; unset, the report says so instead of implying
# a pass. Writes the output to $3; prints `none`, `cannot` or the exit code — a token, it
# also goes into the journal.
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

# Cleanup: only what this build itself created — the checkouts `prepare` made — and only once
# provably redundant: its commit is already in the build branch. Uncommitted work is a
# refusal, never a --force (the --force below covers ignored artefacts such as a
# node_modules, which is not work). The checkout's branch goes with it, since fraim made it
# too. A harness's own worktrees are the harness's to clean (B6).
#   <subtask><TAB>removed | kept-dirty | kept-unmerged | kept-git
build_cleanup() {
    _cl_root=$1; _cl_build=$2
    _cl_plan="$(build_dir "$_cl_root" "$_cl_build")/plan.md"
    _cl_branch=$(build_branch "$_cl_build")

    for _cl_id in $(dispatch_subtask_ids "$_cl_plan" 2>/dev/null); do
        [ -n "$_cl_id" ] || continue
        _cl_tree=$(dispatch_worker_tree "$_cl_root" "$_cl_build-$_cl_id")
        [ -n "$_cl_tree" ] || continue
        if [ -n "$(dispatch_dirty "$_cl_tree")" ]; then
            printf '%s\tkept-dirty\n' "$_cl_id"; continue
        fi
        _cl_sha=$(git -C "$_cl_tree" rev-parse HEAD 2>/dev/null)
        if [ -z "$_cl_sha" ] ||
           ! git -C "$_cl_root" merge-base --is-ancestor "$_cl_sha" "$_cl_branch" >/dev/null 2>&1; then
            printf '%s\tkept-unmerged\n' "$_cl_id"; continue
        fi
        if git -C "$_cl_root" worktree remove --force "$_cl_tree" >/dev/null 2>&1; then
            # -D, not -d: -d compares with the current branch, and the round reaches the trunk
            # only after this cleanup. The commit is in the build branch — checked just above.
            git -C "$_cl_root" branch -D "fraim/$_cl_build-$_cl_id" >/dev/null 2>&1 || :
            printf '%s\tremoved\n' "$_cl_id"
        else
            printf '%s\tkept-git\n' "$_cl_id"
        fi
    done
}

# The round's board cards, closed ON the build branch: one commit in a throwaway checkout,
# so the trunk merge carries the closures with the code and `fraim undo <merge>` reopens
# them with it. Only cards whose subtask brought something back; a project card is never
# closed here — that is the human's. Prints the closed slugs, one per line.
build_close_cards() {
    _cc_root=$1; _cc_build=$2; shift 2
    [ $# -gt 0 ] || return 0
    _cc_tmp=$(mktemp -d) || return 1
    rmdir "$_cc_tmp" 2>/dev/null || :
    git -C "$_cc_root" worktree add --quiet "$_cc_tmp" "$(build_branch "$_cc_build")" >/dev/null 2>&1 || return 1
    _cc_done=
    for _cc_id in "$@"; do
        _cc_f="$(tasks_dir "$_cc_tmp")/$_cc_id.md"
        tasks_is_card "$_cc_f" || continue
        [ "$(fm_get "$_cc_f" kind)" = master ] && continue
        # tasks_archive_card dies on a failure; the subshell keeps that from ending the acceptance.
        if ( tasks_archive_card "$_cc_tmp" "$_cc_f" "$(tasks_closed "$_cc_tmp")" "$_cc_id" done \
                 "done in build $_cc_build" ) >/dev/null 2>&1; then
            _cc_done="$_cc_done $_cc_id"
        fi
    done
    if [ -n "$_cc_done" ]; then
        git -C "$_cc_tmp" add -A -- ai/tasks ai/archive/tasks >/dev/null 2>&1
        git -C "$_cc_tmp" commit -q -m "archive:$_cc_done — done in build $_cc_build" \
            -m "fraim: $(fraim_version)" >/dev/null 2>&1 || _cc_done=
    fi
    git -C "$_cc_root" worktree remove --force "$_cc_tmp" >/dev/null 2>&1 || rm -rf "$_cc_tmp"
    for _cc_id in $_cc_done; do printf '%s\n' "$_cc_id"; done
}

# The trunk write: one --no-ff merge of the build branch into whatever branch the project
# root has checked out. Refuses instead of guessing where merging would be destructive or
# meaningless, and every refusal names the thing to fix. Prints the merge sha.
build_land() {
    _bl_root=$1; _bl_build=$2
    _bl_branch=$(build_branch "$_bl_build")

    _bl_trunk=$(git -C "$_bl_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
    [ -n "$_bl_trunk" ] && [ "$_bl_trunk" != HEAD ] ||
        { printf >&2 '%s\n' "$(t disp_err_detached)"; return 1; }
    [ "$_bl_trunk" != "$_bl_branch" ] ||
        { printf >&2 '%s\n' "$(t disp_err_on_build_branch)"; return 1; }

    # Someone else's unsaved work is not ours to carry into a merge commit (B6).
    _bl_dirty=$(git -C "$_bl_root" status --porcelain --untracked-files=no 2>/dev/null | head -5)
    [ -z "$_bl_dirty" ] || {
        printf >&2 '%s\n' "$(t disp_err_dirty_tree)"
        printf '%s\n' "$_bl_dirty" | sed 's/^/    /' >&2
        return 1
    }

    # The `fraim:` trailer is what lets `fraim undo <sha>` recognise this commit as ours.
    if ! git -C "$_bl_root" merge --no-ff \
             -m "build: $_bl_build" -m "fraim: $(fraim_version)" \
             "$_bl_branch" >/dev/null 2>&1; then
        git -C "$_bl_root" merge --abort >/dev/null 2>&1 || :
        printf >&2 '%s\n' "$(t disp_err_land_failed)"
        return 1
    fi
    git -C "$_bl_root" rev-parse --short HEAD 2>/dev/null
}

# The conductor's acceptance, whole. There is no report file: the human reads this output
# and answers in words.
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

    # Nothing is accepted while a subtask is still out: a report over a half-collected round
    # describes work that is not there and calls it the build.
    _ba_open=$(build_open_subtasks "$_ba_root" "$_ba_id")
    if [ -n "$_ba_open" ]; then
        printf >&2 '%s\n' "$(t disp_err_acc_open build="$_ba_id")"
        printf '%s\n' "$_ba_open" | sed 's/^/    /' >&2
        printf >&2 '  %s\n' "$(t disp_hint_collect build="$_ba_id")"
        return 2
    fi

    _ba_base=$(git -C "$_ba_root" rev-parse --short "$(build_base_sha "$_ba_root" "$_ba_id")" 2>/dev/null)
    _ba_tmp=$(mktemp -d) || { printf >&2 '%s\n' "$(t disp_err_no_tmp)"; return 2; }
    _ba_stop=      # what keeps this out of the trunk
    _ba_say=       # what the human should know anyway, in the operator's language
    _ba_jsay=      # the same notes for the journal, which lives in the project: English
    _ba_cards=     # cards whose subtask brought something back

    printf '%s\n\n' "$(t disp_acc_head build="$_ba_id")"

    # --- what came back: the tree, not the workers' reports (MODES.md §3) ----
    printf '  %s\n' "$(t disp_acc_came_back)"
    for _ba_s in $_ba_ids; do
        _ba_sha=$(build_collected_sha "$_ba_root" "$_ba_id" "$_ba_s")
        if [ -z "$_ba_sha" ] || [ "$_ba_sha" = "—" ]; then
            printf '    %-14s %s\n' "$_ba_s" "$(t disp_acc_sub_empty)"
            _ba_say="$_ba_say    $(t disp_acc_say_sub_nothing id="$_ba_s")
"
            _ba_jsay="$_ba_jsay- subtask $_ba_s changed nothing — that is an outcome too, and usually a bad one
"
            continue
        fi
        dispatch_card "$_ba_root" "$_ba_s" >/dev/null && _ba_cards="$_ba_cards $_ba_s"
        _ba_f=$(git -C "$_ba_root" diff --name-only "$_ba_sha^1" "$_ba_sha" 2>/dev/null |
                grep -c '[^[:space:]]')
        printf '    %-14s %s\n' "$_ba_s" "$(t disp_acc_sub_merged sha="$_ba_sha" files="$_ba_f")"
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

    # Declared by nobody: the build's own bookkeeping (closed cards) is not such a file.
    _ba_undecl=$(printf '%s\n' "$_ba_changed" | grep '[^[:space:]]' |
                 grep -v '^ai/tasks/' | grep -v '^ai/archive/tasks/' |
                 dispatch_classify "$(dispatch_all_paths "$_ba_dir/plan.md")" | sed -n 's/^outside://p')
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
    printf '  %s\n' "$(t disp_acc_cleanup_n \
        removed="$(printf '%s\n' "$_ba_clean" | grep -c '	removed$')" \
        kept="$(printf '%s\n' "$_ba_clean" | grep -c '	kept-')")"
    printf '%s\n' "$_ba_clean" | while IFS='	' read -r _ba_cn _ba_cv; do
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
    if [ -n "$_ba_stop" ]; then
        printf '\n  %s\n%s' "$(t disp_acc_not_landed)" "$_ba_stop"
        [ -n "$_ba_say" ] && printf '  %s\n%s' "$(t disp_acc_also)" "$_ba_say"
        printf '  %s\n' "$(t disp_acc_branch_intact branch="$_ba_branch")"
        rm -rf "$_ba_tmp"
        return 1
    fi

    # The cards go into the build branch right before the merge, after every check passed:
    # a round that does not land leaves them open on the board.
    # shellcheck disable=SC2086 — the slugs are words on purpose
    _ba_closed=$(build_close_cards "$_ba_root" "$_ba_id" $_ba_cards | tr '\n' ' ' | sed 's/ $//')

    if ! _ba_merge=$(build_land "$_ba_root" "$_ba_id"); then
        printf '  %s\n' "$(t disp_acc_land_failed)"
        [ -n "$_ba_say" ] && printf '  %s\n%s' "$(t disp_acc_also)" "$_ba_say"
        rm -rf "$_ba_tmp"
        return 1
    fi
    _ba_trunk=$(git -C "$_ba_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
    printf '  %s\n' "$(t disp_acc_landed trunk="$_ba_trunk" branch="$_ba_branch" merge="$_ba_merge")"
    [ -n "$_ba_closed" ] && printf '  %s\n' "$(t disp_acc_cards_closed cards="$_ba_closed")"

    {
        printf 'Accepted by: conductor\n'
        printf 'When: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'Build branch: %s\n' "$_ba_branch"
        printf 'Into the trunk: %s, merge %s\n' "$_ba_trunk" "$_ba_merge"
        [ -n "$_ba_closed" ] && printf 'Cards closed: %s\n' "$_ba_closed"
        printf 'Undo: fraim undo %s\n' "$_ba_merge"
    } > "$(build_accepted_file "$_ba_root" "$_ba_id")" || :

    {
        printf '\n## Acceptance — %s\n\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf -- '- Checked and merged into the trunk by the conductor: %s ← %s, merge %s\n' \
            "$_ba_trunk" "$_ba_branch" "$_ba_merge"
        printf -- '- Project check: %s\n' "$_ba_mc"
        [ -n "$_ba_closed" ] && printf -- '- Board cards closed in the same merge: %s\n' "$_ba_closed"
        [ -n "$_ba_jsay" ] && printf '%s' "$_ba_jsay"
        printf -- '- Undo with one command: fraim undo %s\n' "$_ba_merge"
    } >> "$_ba_dir/journal.md"

    [ -n "$_ba_say" ] && printf '\n  %s\n%s' "$(t disp_acc_look)" "$_ba_say"
    printf '  %s\n' "$(t disp_acc_undo merge="$_ba_merge")"

    rm -rf "$_ba_tmp"
    return 0
}

# Builds, newest first: id and where each one stands. A directory under ai/builds is a BUILD
# only if it has a journal; anything else is a folder someone put a plan in.
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
