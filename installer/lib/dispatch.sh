#!/bin/sh
# dispatch.sh — parallel mode: split large task into independent subtasks for fleet execution
#
# This module implements MODES.md §5 and §11.2 (variant B):
# - A "build" is everything that passed dispatch-check as non-overlapping
# - Each subtask is assigned to one worker in ADE
# - One acceptance per build (§5, arithmetic of attention)
# - Semantic consistency checked by path intersection analysis
#
# Six operations from MODES.md §9:
# 1. dispatch_plan — analyze task, generate subtasks
# 2. dispatch_check — verify non-overlapping file paths
# 3. dispatch_to_workers — assign to fleet
# 4. collect_results — gather from completed workers
# 5. build_seal — create immutable build record
# 6. build_accept — one acceptance for the whole package

set -e

# Warn on semantic collision: same file modified by different subtasks,
# even if not strictly a merge conflict.
dispatch_check() {
    _plan=$1
    [ -f "$_plan" ] || return 0

    # Extract all paths that will be changed, with their subtask owner.
    # Format: path\tsubtask_id
    _all_paths=$(awk '
        /^## Subtask: / {
            subtask = $3
            next
        }
        /^### `/ {
            p = $0; sub(/^### `/, "", p); sub(/`.*$/, "", p)
            if (p != "") print p "\t" subtask
        }
    ' "$_plan")

    # Check for duplicates (same path in different subtasks).
    _dups=$(printf '%s\n' "$_all_paths" | cut -f1 | sort | uniq -d)
    if [ -n "$_dups" ]; then
        printf >&2 '%s\n' "dispatch-check: semantic collision — same file in different subtasks:"
        printf '%s\n' "$_dups" | while read -r _p; do
            printf >&2 '  %s\n' "$_p (in: $(printf '%s\n' "$_all_paths" | grep "^$_p" | cut -f2 | tr '\n' ', '))"
        done
        return 1
    fi

    return 0
}

# Parse a dispatch plan and emit one subtask record per line.
# Format: subtask_id|summary|paths_csv
dispatch_parse_plan() {
    _plan=$1
    awk '
        /^## Subtask: / {
            if (subtask != "") flush()
            subtask = $3
            summary = ""
            paths = ""
            next
        }
        /^### `/ && subtask != "" {
            p = $0; sub(/^### `/, "", p); sub(/`.*$/, "", p)
            if (paths != "") paths = paths ","
            paths = paths p
        }
        /^[^#]/ && subtask != "" && !/^$/ && summary == "" {
            summary = $0
            sub(/^- /, "", summary)
            gsub(/`/, "", summary)
        }
        END {
            if (subtask != "") flush()
        }
        function flush() {
            print subtask "|" summary "|" paths
        }
    ' "$_plan"
}

# Create one worker task folder from a subtask record.
# Takes: project_root, subtask_id, summary, paths_csv, original_task_dir
dispatch_create_worker_task() {
    _root=$1
    _id=$2
    _summary=$3
    _paths=$4
    _orig=$5

    _worker_dir="$_root/ai/parallel/$_id"
    mkdir -p "$_worker_dir"

    # Stub task.md for the worker.
    cat > "$_worker_dir/task.md" <<EOF
# Worker Task: $_id

## Summary
$_summary

## Files to Change
$_paths

## Step-by-step Implementation
<Implement as per the build plan>

## Acceptance Criteria
All changes in Files to Change match the build specification.

## Verification Commands
<Command to verify the subtask>

## Foundation updates
<Which foundation files need updates, if any>

## Executor Rules
- Read the original build plan at $_orig
- File modifications must stay within the listed paths
- On semantic conflict with other workers, escalate immediately
- Write one result.md entry per step

EOF

    # Inherit context from original task.
    if [ -f "$_orig/context.md" ]; then
        cat "$_orig/context.md" > "$_worker_dir/context.md"
    fi

    printf '%s\n' "$_worker_dir"
}

# Assign subtasks to a fleet. Returns worker session IDs and their task dirs.
# For now, serial enumeration; later: round-robin to actual ADE instances.
dispatch_to_workers() {
    _root=$1
    _plan=$2
    _subtask_count=$3

    dispatch_parse_plan "$_plan" | while IFS='|' read -r _id _summary _paths; do
        [ -n "$_id" ] || continue
        _task_dir=$(dispatch_create_worker_task "$_root" "$_id" "$_summary" "$_paths" "$_plan")
        printf '%s\t%s\n' "$_id" "$_task_dir"
    done
}

# Collect results from all worker task directories and merge them.
# Returns the merged build artifact path.
collect_results() {
    _root=$1
    _build_id=$2

    _build_dir="$_root/ai/builds/$_build_id"
    mkdir -p "$_build_dir"

    # Merge all result.md entries from worker tasks.
    _merged="$_build_dir/result.md"
    cat > "$_merged" <<'EOF'
# Build Result

## Subtask Results

EOF

    for _worker_dir in "$_root/ai/parallel"/*; do
        [ -d "$_worker_dir" ] || continue
        if [ -f "$_worker_dir/result.md" ]; then
            _id=$(basename "$_worker_dir")
            printf '\n### Worker %s\n\n' "$_id" >> "$_merged"
            cat "$_worker_dir/result.md" >> "$_merged"
        fi
    done

    printf '%s\n' "$_merged"
}

# Create an immutable build record: what was planned, what was built, who built it.
# This becomes the "journal" artifact mentioned in MODES.md §11.4.
build_seal() {
    _root=$1
    _build_id=$2
    _plan=$3
    _result=$4

    _build_dir="$_root/ai/builds/$_build_id"
    _seal="$_build_dir/build.sealed.md"

    cat > "$_seal" <<EOF
# Build Seal: $build_id

## Build Metadata
- Sealed at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
- Plan: $(_plan)
- Result: $(_result)

## Plan Summary
$(head -20 "$_plan")

---

## Lessons
(To be filled by conductor/dirizhyor after acceptance)

## Blocking Issues
(Any semantic collisions or worker escalations)

EOF

    printf '%s\n' "$_seal"
}

# Export for conductor's acceptance review: one build summary per line.
# Format: build_id|timestamp|plan_file|result_file|status
list_pending_builds() {
    _root=$1
    for _build in "$_root/ai/builds"/*; do
        [ -d "$_build" ] || continue
        _id=$(basename "$_build")
        if [ ! -f "$_build/build.accepted" ]; then
            printf '%s|%s|%s|%s|pending\n' \
                "$_id" \
                "$(stat -f %Sm -t '%Y-%m-%d %H:%M:%S' "$_build" 2>/dev/null || echo 'N/A')" \
                "$_build/plan.md" \
                "$_build/result.md"
        fi
    done
}
