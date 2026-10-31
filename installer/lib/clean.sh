#!/bin/sh
# clean.sh — "cleanup": do in one pass everything that can be fixed deterministically.
#
# The watchman shows what is wrong with the project, and on a live project that adds up to
# thirty lines. Most of them are not work but leftovers: a foundation from an old version,
# investigations brought to an outcome and not archived, tasks in the old format, unsaved
# foundation files. Each leftover is closed by a known command, and the human has no reason
# to type it thirty times.
#
# The line is drawn hard: cleanup does only what has one answer and that answer is
# computable. The task board, foundation drift and pushing the copy it leaves alone — those
# need judgement, and action without judgement in those places is exactly that drift.
#
# Ratification stays: the plan is shown, the question is asked once (B5). Under a pipe
# without --yes cleanup does nothing — it prints the plan and exits.

CLEAN_PLAN=
CLEAN_N=0

clean_add() {
    CLEAN_N=$((CLEAN_N + 1))
    CLEAN_PLAN="$CLEAN_PLAN$1	$2	$3
"
}

# What can be done right now. Reads the same state as the watchman: one arithmetic.
clean_scan() {
    _root=$1
    CLEAN_PLAN=; CLEAN_N=0

    wm_scan_tasks "$_root"
    WM_FINDINGS=
    config_is_on check_shape "$_root" && wm_check_shape "$_root"
    if printf '%s' "$WM_FINDINGS" | grep -q '^shape	'; then
        clean_add upgrade "" "$(t clean_act_upgrade)"
    fi

    # Investigations. One brought to an outcome — seal it through the regular gate. An
    # abandoned one — close it honestly: into the archive with a record that there is no
    # outcome and the cleanup was not checked.
    #
    # The walk is over FOLDERS, not over findings.md: a folder without a report was visible
    # to neither the watchman nor cleanup, and so survived any number of passes silently.
    # The age of such a folder is taken from the newest file inside — the mtime of the
    # directory itself moves only when entries are added or removed, and a folder where a
    # note is edited every day would look abandoned after a month.
    _days_max=$(config_get abandon_after_days "$_root")
    for _dir in "$_root"/ai/investigations/*/; do
        [ -d "$_dir" ] || continue
        _slug=$(basename -- "$_dir")
        _f="$_dir/findings.md"
        if [ ! -f "$_f" ]; then
            _age=$(wm_days_since "$(wm_newest_mtime "$_dir")")
            if [ "$_age" -ge "$_days_max" ]; then
                clean_add investigate-abandon "$_slug" \
                    "$(t clean_act_abandon_no_findings days="$_age" slug="$_slug")"
            fi
            continue
        fi
        if verb_section_filled "$_f" '### DIAGNOSIS' || verb_section_filled "$_f" '### DEAD-END'; then
            clean_add investigate-seal "$_slug" "$(t clean_act_seal slug="$_slug")"
            continue
        fi
        _age=$(wm_days_since "$(wm_mtime "$_f")")
        if [ "$_age" -ge "$_days_max" ]; then
            clean_add investigate-abandon "$_slug" \
                "$(t clean_act_abandon days="$_age" slug="$_slug")"
        fi
    done

    # Unsaved foundation. Exactly the paths the watchman counts are saved — cleanup, like
    # the verb, has no "save everything" mode (B6).
    if verb_is_git "$_root" && config_is_on check_dirty "$_root"; then
        _dirty=$(clean_dirty_paths "$_root")
        [ -n "$_dirty" ] && clean_add commit "$_dirty" \
            "$(t clean_act_commit)"
    fi
    return 0
}

clean_dirty_paths() {
    _root=$1
    {
        git -C "$_root" status --porcelain --untracked-files=normal -- \
            ARCHITECTURE.md CONVENTIONS.md DECISIONS.md README.md \
            AGENTS.md CLAUDE.md ai/archive ai/tasks 2>/dev/null
        git -C "$_root" status --porcelain --untracked-files=no -- \
            STACK.md 2>/dev/null
    } | sed 's/^...//' | sed 's/^.* -> //' | sort -u | tr '\n' ' '
}

clean_show() {
    if [ "$CLEAN_N" -eq 0 ]; then
        ok "$(t clean_nothing)"
        return 1
    fi
    say "${C_BLD}$(tp "$CLEAN_N" clean_plan)${C_OFF}"
    _clean_ifs=$IFS; IFS='
'
    for _line in $CLEAN_PLAN; do
        [ -n "$_line" ] || continue
        printf '  · %s\n' "${_line##*	}"
    done
    IFS=$_clean_ifs
    say ""
    dim "  $(t clean_not_touched)"
    dim "  $(t clean_not_touched_why)"
    return 0
}

# Close an investigation that was abandoned. The record is honest: not "done" but "closed by
# cleanup, no outcome, cleanup not checked". The archive must tell the truth — the whole
# value of the archive rests on that, and silently deleting the folder destroys it.
clean_investigate_abandon() {
    _root=$1; _slug=$2
    _dir="$_root/ai/investigations/$_slug"
    [ -d "$_dir" ] || return 1
    _f="$_dir/findings.md"
    # A folder without findings.md gets one here instead of being left lying around: an
    # archive without a report is the same silent garbage, only one floor down. The heading
    # is the same one the template prints, so /orient reads the archive uniformly.
    if [ ! -f "$_f" ]; then
        _age=$(wm_days_since "$(wm_newest_mtime "$_dir")")
        printf '# INVESTIGATION — %s\n\n## Outcome — fill exactly ONE branch\n\n' "$_slug" > "$_f" ||
            return 1
    else
        _age=$(wm_days_since "$(wm_mtime "$_f")")
    fi
    {
        printf '\n## Abandoned\n'
        printf -- '- Closed by fraim clean on %s: no outcome recorded; the investigation had not moved for %s days.\n' \
            "$(date +%Y-%m-%d)" "$_age"
        printf -- '- Cleanup was never checked: «## Restored to baseline» was left unfilled.\n'
        printf -- '- This is neither a diagnosis nor a dead end. If the question is still alive, open a new investigation.\n'
    } >> "$_f" || return 1
    verb_archive "$_root" "$_dir" "investigate_$_slug" abandon "investigate $_slug — abandoned"
}

# One action: run it, show its output and — if it refused — remember WHAT the refusal was.
# The refusal used to be printed mid-list and scroll off the top of the screen, and at the
# end a single number remained: "left needing you: 1". The human saw that the investigations
# were still there and saw not one word about why. The reason is the last non-empty line of
# the refusing gate: exactly the text the gate itself wrote.
CLEAN_LEFT=
clean_run() {
    _clean_text=$1; shift
    if _clean_out=$("$@" 2>&1); then
        [ -n "$_clean_out" ] && printf '%s\n' "$_clean_out"
        return 0
    fi
    [ -n "$_clean_out" ] && printf '%s\n' "$_clean_out"
    _clean_why=$(printf '%s\n' "$_clean_out" | grep -v '^[[:space:]]*$' | tail -1)
    [ -n "$_clean_why" ] || _clean_why=$(t clean_failed)
    CLEAN_LEFT="$CLEAN_LEFT  · $_clean_text
      $_clean_why
"
    return 1
}

clean_apply() {
    _root=$1
    _done=0; _refused=0
    CLEAN_LEFT=
    _clean_ifs=$IFS; IFS='
'
    for _line in $CLEAN_PLAN; do
        [ -n "$_line" ] || continue
        IFS=$_clean_ifs
        _op=${_line%%	*}
        _rest=${_line#*	}
        _arg=${_rest%%	*}
        _text=${_rest#*	}
        say ""
        say "${C_BLD}→ $_text${C_OFF}"
        case $_op in
            upgrade)
                if clean_run "$_text" clean_upgrade "$_root"; then _done=$((_done + 1))
                else _refused=$((_refused + 1)); fi ;;
            investigate-seal)
                if clean_run "$_text" verb_investigate_seal "$_root" "$_arg"; then _done=$((_done + 1))
                else _refused=$((_refused + 1)); dim "  $(t clean_gate_refused)"; fi ;;
            investigate-abandon)
                if clean_run "$_text" clean_investigate_abandon "$_root" "$_arg"; then _done=$((_done + 1))
                else _refused=$((_refused + 1)); fi ;;
            commit)
                # shellcheck disable=SC2086
                if clean_run "$_text" verb_commit "$_root" fix "clean: saved foundation and ai/ changes" $_arg; then
                    _done=$((_done + 1))
                else _refused=$((_refused + 1)); fi ;;
        esac
        IFS='
'
    done
    IFS=$_clean_ifs
    say ""
    ok "$(t clean_done count="$_done")"
    # What remains — as a list, not a number. The tail is printed last and therefore stays
    # visible: the human leaves cleanup knowing the names and the reasons, not guessing why
    # the folders are still there.
    if [ "$_refused" -gt 0 ]; then
        say ""
        say "${C_BLD}$(t clean_left count="$_refused")${C_OFF}"
        printf '%s' "$CLEAN_LEFT"
        dim "  $(t clean_left_hint)"
    fi
    return 0
}

# Foundation up to standard — in one step, so that cleanup has a single way to call actions
# and a single way to understand a refusal.
clean_upgrade() {
    _cu_root=$1
    scaffold_run "$_cu_root" >/dev/null 2>&1 || { printf '%s\n' "$(t clean_err_scaffold)" >&2; return 1; }
    scaffold_sections "$_cu_root" >/dev/null 2>&1 || { printf '%s\n' "$(t clean_err_sections)" >&2; return 1; }
    tasks_upgrade "$_cu_root" >/dev/null 2>&1 || { printf '%s\n' "$(t clean_err_tasks)" >&2; return 1; }
    verb_commit "$_cu_root" upgrade "foundation brought up to the standard" \
        README.md ARCHITECTURE.md CONVENTIONS.md DECISIONS.md \
        AGENTS.md CLAUDE.md .gitignore ai >/dev/null 2>&1 || true
    ok "$(t clean_upgrade_done)"
}
