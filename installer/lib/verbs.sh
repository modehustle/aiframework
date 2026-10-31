#!/bin/sh
# verbs.sh — the deterministic half of every procedure.
#
# The system's weakest joint has always been this: mechanical, repeating actions —
# commit, append a log line in a fixed format, create a folder, move it to the archive,
# write the prune marker — were described in PROSE and left to the model's discretion.
# A model that is 95% reliable on each of six such steps completes all six correctly
# about 74% of the time. Over months that is where drift comes from.
#
# So each of them becomes a verb. The model still decides WHEN to call it, but the
# format, the paths and the commit stop being its business. That is what makes this a
# universal hook layer: a shell command works in every harness, in CI and in a container,
# whereas a harness hook works in exactly one harness.
#
# The task verbs live in tasks.sh: a task is a card on a board now, not a plan with gates.

verb_is_git() { git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }

# Where the file templates live. The SHAPE of every artefact the procedures write is a
# fixed structure, so it is code (A2); only what goes inside the sections is text.
verb_template() {
    _r=$(fraim_root) || return 1
    _t="$_r/installer/templates/$1"
    [ -f "$_t" ] || return 1
    printf '%s\n' "$_t"
}

# The provenance stamp: date, the snapshot the work is based on, and the system version.
# One implementation, used by task-new, task-revise and investigate-new alike — the three
# places where a forgotten or mistyped stamp silently disables a staleness check.
verb_provenance() {
    _root=$1
    _date=$(date +%Y-%m-%d)
    _ver=$(fraim_version)
    if verb_is_git "$_root"; then
        _ref=$(git -C "$_root" rev-parse --short HEAD 2>/dev/null)
        _based="HEAD $_ref"
    else
        _based="<no git — list the files this plan assumes the current state of>"
    fi
    printf -- '- Planned: %s\n- Based on: %s\n- System: fraim %s\n' "$_date" "$_based" "$_ver"
}

# A section of a markdown file must be present, non-empty and free of placeholders.
# Used by every gate: this is what turns "the executor promised" into a precondition.
verb_section_filled() {
    _file=$1; _head=$2
    grep -q "^$_head\$" "$_file" || return 1
    _sec=$(awk -v h="$_head" '$0 == h {f=1;next} /^#/{f=0} f' "$_file")
    [ -n "$(printf '%s' "$_sec" | tr -d '[:space:]')" ] || return 2
    printf '%s' "$_sec" | grep -q '<[^>]*>' && return 3
    return 0
}

# Move a finished folder into the archive under a timestamp, then commit it.
# Used by investigations; tasks archive as cards (tasks.sh). The timestamp
# format is what /orient reads back as "recent history".
verb_archive() {
    _root=$1; _src=$2; _name=$3; _kind=$4; _text=$5
    _stamp=$(date +%Y-%m-%d_%H%M)
    _dest="$_root/ai/archive/${_stamp}_${_name}"
    [ -e "$_dest" ] && die "$(t verbs_archive_exists path="$_dest")"
    mkdir -p "$_root/ai/archive" || die "$(t verbs_err_mkdir path=ai/archive/)"
    mv "$_src" "$_dest" || die "$(t verbs_archive_move_failed)"
    ok "$(t verbs_archived path="ai/archive/${_stamp}_${_name}")"
    verb_commit "$_root" "$_kind" "$_text" "ai/tasks" "ai/investigations" "ai/archive" ||
        warn "$(t verbs_commit_failed)"
}

# One commit format for the whole system. Kinds mirror the procedures that produce them.
verb_commit() {
    _root=$1; _kind=$2; _text=$3
    shift 3
    verb_is_git "$_root" || return 0
    config_is_on commit_verbs "$_root" || { dim "  $(t verbs_commit_off)"; return 0; }
    [ $# -gt 0 ] || return 0
    for _p in "$@"; do
        [ -e "$_root/$_p" ] || continue
        git -C "$_root" add -- "$_p" >/dev/null 2>&1 || true
    done
    git -C "$_root" diff --cached --quiet 2>/dev/null && return 0
    # The trailer is what lets `fraim undo` tell our save points from everyone else's,
    # mechanically, in a repository we may not own. It stays out of the subject line,
    # so `git log --oneline` reads exactly as before.
    git -C "$_root" commit -q -m "$_kind: $_text" -m "fraim: $(fraim_version)" || return 1
    ok "$(t verbs_committed subject="$_kind: $_text")"
}

# --- investigate-new / investigate-seal -------------------------------------
# An investigation has exactly the same mechanics as a task — a folder, a provenance
# stamp, an archive with a timestamp — and until now it had none of them: /investigate
# created the folder, typed the schema and archived with its own commit message by hand.
# Its exit also has a real precondition, and it is the one the system can least afford
# to leave to good intentions: the cleanup of everything the scout touched.
verb_investigate_new() {
    _root=$1; _slug=$2
    printf '%s' "$_slug" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' ||
        die "$(t verbs_inv_slug)"
    [ -d "$_root/ai/investigations" ] ||
        die "$(t verbs_inv_no_dir)"
    _dir="$_root/ai/investigations/$_slug"
    [ -e "$_dir" ] && die "$(t verbs_inv_exists slug="$_slug")"
    _tpl=$(verb_template investigation/findings.md) || die "$(t verbs_no_template_broken)"

    mkdir -p "$_dir" || die "$(t verbs_err_mkdir path="$_dir")"
    _prov=$(verb_provenance "$_root")
    awk -v slug="$_slug" -v prov="$_prov" '
        { gsub(/\{\{SLUG\}\}/, slug); if ($0 == "{{PROVENANCE}}") { print prov; next } print }
    ' "$_tpl" > "$_dir/findings.md" || die "$(t verbs_err_write file=findings.md)"

    ok "ai/investigations/$_slug/findings.md"
    dim "  $(t verbs_inv_manifests)"
}

verb_investigate_seal() {
    _root=$1; _slug=$2
    _dir="$_root/ai/investigations/$_slug"
    [ -d "$_dir" ] || die "$(t verbs_inv_missing slug="$_slug")"
    _f="$_dir/findings.md"
    [ -f "$_f" ] || die "$(t verbs_inv_no_findings)"
    grep -q "$SCAFFOLD_STUB" "$_f" &&
        die "$(t verbs_inv_stub marker="$SCAFFOLD_STUB")"
    lang_check "findings.md" "$(cat "$_f")"

    # Exactly one outcome branch. None means the investigation was abandoned; both
    # means it was never landed — and a dead-end recorded honestly is a success here.
    _filled=0; _which=
    for _b in '### DIAGNOSIS' '### DEAD-END'; do
        if verb_section_filled "$_f" "$_b"; then
            _filled=$((_filled + 1)); _which=$_b
        fi
    done
    [ "$_filled" -eq 0 ] &&
        die "$(t verbs_inv_no_outcome)"
    [ "$_filled" -gt 1 ] &&
        die "$(t verbs_inv_two_outcomes)"

    _rc=0; verb_section_filled "$_f" '## Restored to baseline' || _rc=$?
    case $_rc in
        1) die "$(t verbs_inv_no_restored)" ;;
        2) die "$(t verbs_inv_restored_empty)" ;;
        3) die "$(t verbs_inv_restored_holes)" ;;
    esac

    ok "$(t verbs_inv_outcome branch="$(printf '%s' "$_which" | sed 's/^### //')")"
    verb_archive "$_root" "$_dir" "investigate_$_slug" archive "investigate $_slug"
}

# --- stack-passport ---------------------------------------------------------
# STACK.md has a fixed schema and a standing directive that must survive verbatim —
# an LLM retyping it from prose drops a section every few projects. The shape is
# the template's; only the facts are the workflow's.
verb_stack_passport() {
    _root=$1
    _dst="$_root/STACK.md"
    [ -e "$_dst" ] && die "$(t verbs_stack_exists)"
    _r=$(fraim_root) || die "$(t verbs_no_templates_broken)"
    _tpl="$_r/installer/templates/stack/STACK.md"
    [ -f "$_tpl" ] || die "$(t verbs_no_template path="$_tpl")"
    sed "s/{{PROJECT}}/$(basename -- "$_root")/g" "$_tpl" > "$_dst" || die "$(t verbs_err_write file=STACK.md)"
    ok "$(t verbs_stack_created)"
    dim "  $(t verbs_stack_hint)"
}

# --- prune-mark -------------------------------------------------------------
# The prune anchor is the commit, not a line in a log file. It always was for
# `wm_check_foundation`, which finds the last `prune: ` commit; the marker written into
# ai/hotfix_log.md existed only for the hotfix counter, and went with it.
verb_prune_mark() {
    _root=$1
    _date=$(date +%Y-%m-%d)
    verb_is_git "$_root" || die "$(t verbs_prune_no_git)"

    _before=$(git -C "$_root" rev-parse HEAD 2>/dev/null)
    verb_commit "$_root" prune "reconcile foundation $_date" \
        ARCHITECTURE.md CONVENTIONS.md DECISIONS.md ai/archive ||
        warn "$(t verbs_commit_failed)"
    _after=$(git -C "$_root" rev-parse HEAD 2>/dev/null)

    # A prune that honestly found nothing to change still has to leave the anchor, or the
    # verdict keeps asking for the gardening that just happened. Nothing was committed
    # exactly when HEAD did not move.
    if [ "$_before" = "$_after" ]; then
        git -C "$_root" commit -q --allow-empty \
            -m "prune: reconcile foundation $_date" -m "fraim: $(fraim_version)" ||
            { warn "$(t verbs_prune_mark_failed)"; return 0; }
        ok "$(t verbs_prune_marked)"
    fi
}

# --- undo -------------------------------------------------------------------
# The system tells people to work boldly because there is a save point behind them.
# That promise is empty if getting back to one requires `git reset --hard HEAD~1` — the
# person who most needs the way back is the least likely to know it exists.
#
# Undo is a REVERT, never a reset: it adds a commit that takes the change back out. History
# is not rewritten, so this is safe in a repository shared with other people and with a
# remote — and it is the same rule the system already applies to DECISIONS.md: supersede,
# never delete. Two steps on purpose (list, then name one): showing is not doing.
verb_undo_list() {
    _root=$1
    git -C "$_root" log -n 8 --grep='^fraim: ' --format='%h%x09%ad%x09%s' --date=short 2>/dev/null
}

verb_undo_show() {
    _root=$1
    _rows=$(verb_undo_list "$_root")
    [ -n "$_rows" ] && [ -n "$(printf '%s' "$_rows" | tr -d '[:space:]')" ] ||
        die "$(t verbs_undo_none)"
    say "${C_BLD}$(t verbs_undo_title)${C_OFF}"
    printf '%s\n' "$_rows" | while IFS='	' read -r _h _d _s; do
        [ -n "$_h" ] || continue
        printf '  %s  %s  %s\n' "$_h" "$_d" "$_s"
    done
    say ""
    dim "  $(t verbs_undo_hint_pick)"
    dim "  $(t verbs_undo_hint_revert)"
}

verb_undo() {
    _root=$1; _ref=$2
    verb_is_git "$_root" || die "$(t verbs_undo_no_git)"
    git -C "$_root" cat-file -e "$_ref^{commit}" 2>/dev/null || die "$(t verbs_undo_no_commit ref="$_ref")"

    # Ours or not. We do not undo what we did not do — in someone else's repository that
    # is the difference between a tool and an accident.
    git -C "$_root" log -1 --format=%B "$_ref" 2>/dev/null | grep -q '^fraim: ' ||
        die "$(t verbs_undo_not_ours)"

    # Only the files this commit touched have to be settled. The rest of the tree is the
    # human's work in progress, and it is none of our business — the same rule as everywhere:
    # we look at what we changed, and nothing else.
    _files=$(git -C "$_root" show --pretty= --name-only "$_ref" 2>/dev/null)
    if [ -n "$_files" ]; then
        _busy=$(printf '%s\n' "$_files" | while IFS= read -r _f; do
                    [ -n "$_f" ] || continue
                    git -C "$_root" status --porcelain --untracked-files=no -- "$_f" 2>/dev/null
                done)
        [ -z "$_busy" ] ||
            die "$(t verbs_undo_busy)"
    fi

    _subj=$(git -C "$_root" log -1 --format=%s "$_ref")
    # A merge commit has to say which side to keep. Ours are made by the fleet's trunk
    # write (`dispatch accept`), and there the first parent is the trunk as it stood — so
    # -m 1 undoes exactly the build that was merged in. Without this, undoing a trunk write
    # died with "the changes overlapped", which is the wrong sentence for "this is a merge".
    _mflag=
    [ "$(git -C "$_root" rev-list --parents -n 1 "$_ref" 2>/dev/null | wc -w)" -gt 2 ] && _mflag='-m 1'
    if git -C "$_root" revert --no-edit $_mflag "$_ref" >/dev/null 2>&1; then
        ok "$(t verbs_undo_done subject="$_subj")"
        dim "  $(t verbs_undo_done_hint)"
    else
        git -C "$_root" revert --abort >/dev/null 2>&1 || true
        die "$(t verbs_undo_conflict)"
    fi
}

# --- restore ----------------------------------------------------------------
# The working-tree half of the same need, and the one /investigate lives on: put back
# exactly the paths named, and nothing else. `git restore .` would take the user's own
# unfinished work with it — which is why the workflow used to demand a clean tree before
# it would start, handing a git chore to the person least able to do it.
verb_restore() {
    _root=$1
    shift
    [ $# -gt 0 ] || die "$(t verbs_restore_usage)"
    verb_is_git "$_root" || die "$(t verbs_restore_no_git)"
    for _p in "$@"; do
        case $_p in
            /*|.|..|*..*|"") die "$(t verbs_restore_bad_path path="$_p")" ;;
        esac
    done
    for _p in "$@"; do
        if git -C "$_root" ls-files --error-unmatch -- "$_p" >/dev/null 2>&1; then
            if git -C "$_root" restore --source=HEAD -- "$_p" >/dev/null 2>&1 ||
               git -C "$_root" checkout HEAD -- "$_p" >/dev/null 2>&1; then
                ok "$(t verbs_restored path="$_p")"
            else
                warn "$(t verbs_restore_failed path="$_p")"
            fi
        elif [ -e "$_root/$_p" ]; then
            rm -rf -- "$_root/$_p" && ok "$(t verbs_restore_removed path="$_p")" ||
                warn "$(t verbs_restore_rm_failed path="$_p")"
        else
            dim "  $(t verbs_restore_gone path="$_p")"
        fi
    done
}

# --- decide / pitfall: writing INTO the foundation ---------------------------
# Appending to the foundation was the largest block of mechanics still left to the
# model. `DECISIONS.md` alone is written by three procedures (run-task 7.2,
# reconcile-task 2, prune) and its shape is described a fourth time in the template:
# four descriptions of one format, executed by prose (A3 + B1). What is mechanical
# here is placement, heading and date — never the wording, which is why the body
# arrives on stdin instead of through argv. A multi-line entry squeezed through a
# command-line argument is how a verb starts damaging content (AUDIT-VERBS 4.4).
#
# Neither verb commits. The save point stays in `fraim commit`, called by the
# procedure with the rest of the paths it touched — one implementation of a commit,
# and no surprise second commit inside a step that only meant to append a line.

# A verb's text arrives on stdin. Two ways that can go wrong, and both must end in a
# refusal that shows the right form, never in a hang:
#   · stdin is a terminal — nobody is going to type a body;
#   · stdin is open but nothing is coming — an agent harness or a script that runs every
#     command with an inherited pipe. `cat` then waits for an EOF that never arrives, and
#     the verb looks exactly like a hung session.
# So the read runs in the background and the verb waits for the FIRST byte only, a few
# seconds at most. A body that has started arriving is read to the end, however long.
# The descriptor is passed explicitly: an asynchronous command in a non-interactive shell
# otherwise gets /dev/null for stdin, and would always read nothing.
FRAIM_BODY_WAIT=${FRAIM_BODY_WAIT:-30}   # tenths of a second

verb_read_body() {
    [ -t 0 ] && { warn "$(t verbs_body_tty)"; return 1; }
    _rb_tmp=$(mktemp) || return 1
    exec 3<&0
    cat <&3 > "$_rb_tmp" &
    _rb_pid=$!
    exec 3<&-
    _rb_t=0
    while kill -0 "$_rb_pid" 2>/dev/null; do
        if [ -s "$_rb_tmp" ]; then wait "$_rb_pid" || :; break; fi
        if [ "$_rb_t" -ge "$FRAIM_BODY_WAIT" ]; then
            kill "$_rb_pid" 2>/dev/null || :
            rm -f "$_rb_tmp"
            warn "$(t verbs_body_timeout sec="$((FRAIM_BODY_WAIT / 10))")"
            return 1
        fi
        if sleep 0.1 2>/dev/null; then _rb_t=$((_rb_t + 1)); else sleep 1; _rb_t=$((_rb_t + 10)); fi
    done
    cat "$_rb_tmp"
    rm -f "$_rb_tmp"
}

verb_decide() {
    _root=$1; _title=$2; _supersedes=${3:-}
    _file="$_root/DECISIONS.md"
    [ -f "$_file" ] || die "$(t verbs_decide_no_file)"
    [ -n "$_title" ] || die "$(t verbs_decide_no_title)"

    _body=$(verb_read_body) ||
        die "$(t verbs_decide_usage)"
    [ -n "$(printf '%s' "$_body" | tr -d '[:space:]')" ] || die "$(t verbs_decide_empty)"
    lang_check "the decision title" "$_title"
    lang_check "the decision body" "$_body"
    _body=$(printf '%s\n' "$_body" | fnd_wrap)

    # Superseding by name moves the old entry to the archive (foundation.sh). Resolved
    # BEFORE anything is written: an ambiguous name is a refusal, not a guess, and the
    # new entry must not be the one it matches.
    _match=
    if [ -n "$_supersedes" ]; then
        _m=$(fnd_decision_matches "$_file" "$_supersedes")
        _mn=$(printf '%s' "$_m" | grep -c . || true)
        if [ "$_mn" -gt 1 ]; then
            die "$(t verbs_decide_ambiguous count="$_mn" title="$_supersedes")
$(printf '%s\n' "$_m" | sed 's/^## /  · /')"
        fi
        if [ "$_mn" -eq 1 ]; then
            _match=$_m
            _supersedes=${_m#\#\# }
        fi
    fi

    _date=$(date +%Y-%m-%d)
    _entry="## $_date — $_title"
    _tmp="$_file.fraim.tmp"

    if [ -n "$_match" ]; then
        fnd_move_decision "$_root" "$_match" || die "$(t verbs_decide_archive_failed)"
    fi

    # Newest on top: the entry goes above the first existing one, and when there is
    # none yet, after the header block. The stub marker goes away with the first real
    # entry — a file with a decision in it is no longer an unfilled scaffold (D1).
    # Short text travels through ENVIRON, not -v: awk -v expands backslash escapes, and a
    # body that quotes a regex or a Windows path would be silently rewritten. The body can
    # be long and travels through a file (fnd_text_file in foundation.sh).
    _bf=$(fnd_text_file "$_body") || die "$(t fnd_err_tmp)"
    FND_ENTRY=$_entry FND_BODY_FILE=$_bf FND_SUP=$_supersedes FND_STUB=$SCAFFOLD_STUB awk "$FND_SLURP"'
        BEGIN { entry = ENVIRON["FND_ENTRY"]; body = slurp("FND_BODY_FILE")
                sup = ENVIRON["FND_SUP"]; stub = ENVIRON["FND_STUB"] }
        index($0, stub) { next }
        !done && /^## / {
            print entry
            if (sup != "") print "> Supersedes: " sup
            print ""
            print body
            print ""
            done = 1
        }
        { print }
        END {
            if (!done) {
                print ""
                print entry
                if (sup != "") print "> Supersedes: " sup
                print ""
                print body
            }
        }
    ' "$_file" > "$_tmp" || { rm -f "$_tmp" "$_bf"; die "$(t verbs_err_write file=DECISIONS.md)"; }
    rm -f "$_bf"
    mv "$_tmp" "$_file" || die "$(t verbs_err_write file=DECISIONS.md)"

    ok "DECISIONS.md ← $_entry"
    if [ -n "$_match" ]; then
        ok "$(t verbs_decide_moved title="${_match#\#\# }")"
        dim "  $(t verbs_decide_unsaved_both)"
    else
        [ -n "$_supersedes" ] && dim "  $(t verbs_decide_not_found title="$_supersedes")"
        dim "  $(t verbs_decide_unsaved)"
    fi
}

verb_pitfall() {
    _root=$1; shift
    _file="$_root/CONVENTIONS.md"
    _head='## Known Pitfalls / Lessons'
    [ -f "$_file" ] || die "$(t verbs_pitfall_no_file)"
    grep -q "^$_head\$" "$_file" || die "$(t verbs_pitfall_no_section section="$_head")"

    if [ $# -gt 0 ]; then
        _lines=$(for _l in "$@"; do printf '%s\n' "$_l"; done)
    else
        _lines=$(verb_read_body) ||
            die "$(t verbs_pitfall_usage)"
    fi
    [ -n "$(printf '%s' "$_lines" | tr -d '[:space:]')" ] || die "$(t verbs_pitfall_empty)"
    lang_check "the pitfall" "$_lines"

    _tmp="$_file.fraim.tmp"
    _items=$(printf '%s\n' "$_lines" | grep '[^[:space:]]' | sed 's/^/- /' | fnd_wrap)
    # Appended at the END of that one section, not at the end of the file: the
    # section is what every session reads first, and a line that lands under the
    # wrong heading is a lesson nobody will ever be shown again.
    # The lines can arrive on stdin and be long: they travel through a file.
    _if=$(fnd_text_file "$_items") || die "$(t fnd_err_tmp)"
    FND_HEAD=$_head FND_ITEMS_FILE=$_if awk "$FND_SLURP"'
        BEGIN { head = ENVIRON["FND_HEAD"]; items = slurp("FND_ITEMS_FILE") }
        $0 == head { inside = 1; print; next }
        inside && /^## / {
            print items
            inside = 0; done = 1
            print ""
            print
            next
        }
        inside && $0 == "- None yet." { next }
        { print }
        END { if (inside && !done) print items }
    ' "$_file" > "$_tmp" || { rm -f "$_tmp" "$_if"; die "$(t verbs_err_write file=CONVENTIONS.md)"; }
    rm -f "$_if"
    mv "$_tmp" "$_file" || die "$(t verbs_err_write file=CONVENTIONS.md)"

    _n=$(printf '%s\n' "$_lines" | grep -c '[^[:space:]]')
    ok "$(tp "$_n" verbs_pitfall_added section="$_head")"
    dim "  $(t verbs_pitfall_unsaved)"
}
