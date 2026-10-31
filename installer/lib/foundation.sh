#!/bin/sh
# foundation.sh — reading the foundation whole, finding in it, and writing into it.
#
# Two failures this exists for, both seen in live sessions with strong models.
#
# Reading: an agent opens ARCHITECTURE.md with `head -200` or a reader that stops at a
# line budget, and works from a third of the map without knowing it. And grep returns a
# line, not the entry the line belongs to — a sentence out of a DECISIONS paragraph with
# no heading to say which decision it was. `fraim brief` prints the whole foundation in
# one stream and SAYS at the end that nothing was cut; `fraim find` returns whole entries.
#
# Writing: the agent edits the foundation by hand and puts an entry at the bottom, deletes
# a heading, or writes a paragraph as one 900-character line that the next reader's tool
# truncates. Here the agent supplies only the text; the verb decides where it goes, and
# wraps it.

FND_WIDTH=100

# Wrap long prose lines at FND_WIDTH characters. Tables, fenced code, headings, HTML
# comments and frontmatter pass through untouched — rewrapping those changes what they
# mean. A list item continues under its own text; a quote continues as a quote.
#
# Characters, not bytes: under LC_ALL=C awk's length() counts bytes and every Cyrillic
# letter is two, so the width is measured with UTF-8 continuation bytes removed — the
# same trick as str_len in core.sh, and it needs no locale.
#
# `fnd_wrap read` is for output only (brief, find): it wraps table rows and headings too,
# with a hanging indent. That breaks a table as markdown and keeps it whole as text — the
# right trade for a reader that truncates long lines, the wrong one for a file on disk.
fnd_wrap() {
    _fw_mode=${1:-write}
    LC_ALL=C awk -v W="$FND_WIDTH" -v mode="$_fw_mode" '
        function clen(s,  t) { t = s; gsub(/[\200-\277]/, "", t); return length(t) }
        NR == 1 && $0 == "---" { fm = 1; print; next }
        fm { print; if ($0 == "---") fm = 0; next }
        /^[ \t]*(```|~~~)/ { fence = !fence; print; next }
        fence { print; next }
        /^[ \t]*$/ || /^[ \t]*<!--/ { print; next }
        mode != "read" && (/^[ \t]*\|/ || /^#/) { print; next }
        clen($0) <= W { print; next }
        {
            match($0, /^[ \t]*/)
            lead = substr($0, 1, RLENGTH); rest = substr($0, RLENGTH + 1)
            ind = lead
            if (rest ~ /^>/) ind = lead "> "
            else if (rest ~ /^(\||#)/) ind = lead "    "
            else if (match(rest, /^([-*+]|[0-9]+[.)])[ \t]+/)) {
                ind = lead
                for (i = 0; i < RLENGTH; i++) ind = ind " "
            }
            n = split(rest, w, /[ \t]+/)
            line = lead; cur = clen(lead); first = 1
            for (i = 1; i <= n; i++) {
                if (w[i] == "") continue
                wl = clen(w[i])
                if (!first && cur + 1 + wl > W) {
                    print line
                    line = ind w[i]; cur = clen(ind) + wl
                    continue
                }
                if (first) { line = line w[i]; cur += wl; first = 0 }
                else { line = line " " w[i]; cur += 1 + wl }
            }
            print line
        }'
}

# The files that make up the foundation, in reading order.
FND_FILES='ARCHITECTURE.md CONVENTIONS.md DECISIONS.md STACK.md'

# DECISIONS as the living decisions only, condensed: every heading, its Supersedes line,
# and its decision paragraph — «Decision:» or its older Russian equivalent, or the first
# paragraph when the entry has no such label. The full text is one `fraim find` away.
fnd_decisions_condensed() {
    awk '
        /^## / {
            if (h != "") flush()
            h = $0; got = ""; para = ""; first = ""; sup = ""; inpara = 0; next
        }
        h == "" { next }
        /^> Supersedes:/ { sup = $0; next }
        /^[[:space:]]*$/ {
            if (inpara && first == "") first = para
            if (inpara && para ~ /^(Decision|Решение):/) got = para
            inpara = 0; para = ""; next
        }
        { para = inpara ? para "\n" $0 : $0; inpara = 1 }
        function flush() {
            if (inpara) { if (first == "") first = para; if (para ~ /^(Decision|Решение):/) got = para }
            print h
            if (sup != "") print sup
            print ""
            print (got != "" ? got : first)
            print ""
        }
        END { if (h != "") flush() }
    ' "$1"
}

# --- brief ------------------------------------------------------------------
verb_brief() {
    _root=$1
    _n_out=0
    _tmp=$(mktemp) || die "$(t fnd_err_tmp)"
    {
        printf '# fraim brief — %s · fraim %s\n\n' "$(basename -- "$_root")" "$(fraim_version)"
        printf 'The whole foundation of this project in one stream. Nothing is cut: there is a mark at the end.\n\n'

        printf '## How to work here\n\n'
        vt_brief
        printf '\n'

        for _f in $FND_FILES; do
            _p="$_root/$_f"
            [ -f "$_p" ] || continue
            printf '=== %s ===\n\n' "$_f"
            if scaffold_is_stub "$_p"; then
                printf '(a scaffold — not filled in yet: /bootstrap or /onboard)\n\n'
                continue
            fi
            if [ "$_f" = DECISIONS.md ]; then
                printf '(living decisions, condensed; full text — fraim find <word> or DECISIONS.md)\n\n'
                fnd_decisions_condensed "$_p" | fnd_wrap read
            else
                fnd_wrap read < "$_p"
            fi
            printf '\n'
        done

        printf '=== board ===\n\n'
        ( C_DIM=; C_BLD=; C_OFF=; C_GRN=; C_YEL=; C_RED=; verb_tasks "$_root" 2>&1 )
        printf '\n'
    } > "$_tmp"
    cat "$_tmp"
    _n_out=$(wc -l < "$_tmp" | tr -d ' ')
    rm -f "$_tmp"
    printf -- '— end of brief: %s lines, nothing cut. No need to read the foundation files separately. —\n' "$((_n_out + 1))"
}

# --- find -------------------------------------------------------------------
# Every unit of text in the foundation and the board, one per line, as
#   file <US> heading <US> text-with-<GS>-for-newlines
# A unit is what a reader means by «the entry»: a whole DECISIONS entry, a whole card,
# a table row, a list item with its continuation, or a paragraph — always with the
# heading it sits under, so a hit is never a sentence with no address.
FND_US=$(printf '\037')
FND_GS=$(printf '\035')

fnd_units() {
    _root=$1
    for _rel in $FND_FILES ai/archive/decisions_log.md; do
        [ -f "$_root/$_rel" ] && fnd_units_file "$_root/$_rel" "$_rel"
    done
    for _p in "$_root"/ai/tasks/*.md "$_root"/ai/backlog/*.md \
              "$_root"/ai/archive/tasks/*.md "$_root"/ai/archive/backlog/*.md \
              "$_root"/ai/investigations/*/findings.md; do
        [ -f "$_p" ] || continue
        fnd_units_file "$_p" "${_p#"$_root"/}"
    done
    return 0
}

fnd_units_file() {
    case $2 in
        DECISIONS.md|ai/archive/decisions_log.md) _mode=section ;;
        ai/tasks/*|ai/backlog/*|ai/archive/tasks/*|ai/archive/backlog/*) _mode=whole ;;
        *) _mode=block ;;
    esac
    awk -v file="$2" -v mode="$_mode" -v US="$FND_US" -v GS="$FND_GS" '
        function emit() {
            if (buf != "") print file US head US buf
            buf = ""
        }
        function add(s) { buf = (buf == "") ? s : buf GS s }
        NR == 1 && $0 == "---" { fm = 1; next }
        fm { if ($0 == "---") fm = 0; next }
        mode == "whole" { if (head == "" && /^# /) head = substr($0, 3); add($0); next }
        /^#+ / {
            if (mode == "section" && /^## /) { emit(); head = $0; sub(/^#+ /, "", head); add($0); next }
            if (mode == "block") { emit(); head = $0; sub(/^#+ /, "", head); next }
        }
        mode == "section" { if (head != "") add($0); next }
        /^[[:space:]]*$/ { emit(); next }
        /^\|/ { emit(); if ($0 !~ /^\|[-:| ]+\|?[[:space:]]*$/) { add($0); emit() }; next }
        /^([-*+]|[0-9]+[.)]) / { emit(); add($0); next }
        { add($0) }
        END { emit() }
    ' "$1"
}

verb_find() {
    _root=$1; shift
    [ $# -gt 0 ] || die "$(t fnd_err_find_keys)"
    _args=
    for _k in "$@"; do
        [ -n "$_k" ] || continue
        _args="$_args -e $(printf '%s' "$_k" | sed "s/'/'\\\\''/g; s/^/'/; s/\$/'/")"
    done
    # Case folding for Cyrillic needs a UTF-8 locale; under C grep folds ASCII only. Take
    # the caller's locale when it is UTF-8, otherwise ask for C.UTF-8 — a system without
    # it silently falls back to C, which still finds every exact-case match.
    _loc=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
    case $_loc in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;; *) _loc=C.UTF-8 ;; esac
    _hits=$(fnd_units "$_root" | eval "LC_ALL=\$_loc grep -i -F $_args" || true)
    if [ -z "$_hits" ]; then
        warn "$(t fnd_find_nothing keys="$*")"
        return 1
    fi
    _n=$(printf '%s\n' "$_hits" | grep -c . || true)
    printf '%s\n' "$_hits" | while IFS="$FND_US" read -r _file _head _text; do
        if [ -n "$_head" ]; then printf '%s › %s\n' "$_file" "$_head"
        else printf '%s\n' "$_file"; fi
        printf '%s\n' "$_text" | tr "$FND_GS" '\n' | fnd_wrap read | sed 's/^/  /'
        printf '\n'
    done
    printf '%s\n' "$(t fnd_find_footer count="$_n" keys="$*")"
}

# --- arch: replace one section of the map -------------------------------------
# The map is not append-only: a section is rewritten whole. The verb finds the heading,
# replaces everything up to the next heading of the same or a higher level, and keeps
# the rest of the file byte for byte. A heading that does not exist is a refusal that
# lists the ones that do — a typo would otherwise grow a second «Components» section.
verb_arch() {
    _root=$1; shift
    _file=ARCHITECTURE.md; _sec=; _new=0
    while [ $# -gt 0 ]; do
        case $1 in
            --new) _new=1 ;;
            --in) [ $# -ge 2 ] || die "$(t fnd_err_in_file)"; _file=$2; shift ;;
            -*) die "$(t fnd_err_unknown_flag flag="$1")" ;;
            *) [ -z "$_sec" ] || die "$(t fnd_err_extra_arg arg="$1")"; _sec=$1 ;;
        esac
        shift
    done
    case $_file in
        ARCHITECTURE.md|CONVENTIONS.md|STACK.md) ;;
        DECISIONS.md) die "$(t fnd_err_decisions_top)" ;;
        *) die "$(t fnd_err_arch_files)" ;;
    esac
    [ -n "$_sec" ] || die "$(t fnd_err_need_section)"
    case $_sec in
        "Known Pitfalls / Lessons") die "$(t fnd_err_pitfall_line)" ;;
    esac
    _p="$_root/$_file"
    [ -f "$_p" ] || die "$(t fnd_err_no_file file="$_file")"
    _body=$(verb_read_body) || die "$(t fnd_err_body_stdin section="$_sec")"
    [ -n "$(printf '%s' "$_body" | tr -d '[:space:]')" ] || die "$(t fnd_err_body_empty)"
    printf '%s\n' "$_body" | grep -q '^#' &&
        die "$(t fnd_err_body_headings)"
    if [ "$_new" = 1 ]; then lang_check "the section name" "$_sec"; fi
    lang_check "the section body" "$_body"

    _have=$(grep -c "^## $(printf '%s' "$_sec" | sed 's/[][\.*^$/]/\\&/g')\$" "$_p" || true)
    if [ "$_new" = 1 ]; then
        [ "$_have" -eq 0 ] || die "$(t fnd_err_section_exists file="$_file" section="$_sec")"
    elif [ "$_have" -eq 0 ]; then
        _list=$(sed -n 's/^## //p' "$_p" | sed 's/^/  · /')
        die "$(t fnd_err_no_section list="$_list" file="$_file" section="$_sec")"
    elif [ "$_have" -gt 1 ]; then
        die "$(t fnd_err_section_dup count="$_have" file="$_file" section="$_sec")"
    fi

    _wrapped=$(printf '%s\n' "$_body" | fnd_wrap)
    _tmp="$_p.fraim.tmp"
    if [ "$_new" = 1 ]; then
        { cat "$_p"; printf '\n## %s\n%s\n' "$_sec" "$_wrapped"; } > "$_tmp"
    else
        # Text travels through ENVIRON, not -v: awk -v expands backslash escapes, and a
        # table cell's `\|` would lose its slash and split the cell.
        FND_HEAD="## $_sec" FND_BODY=$_wrapped awk '
            BEGIN { h = ENVIRON["FND_HEAD"]; body = ENVIRON["FND_BODY"] }
            $0 == h { print; print body; print ""; skip = 1; next }
            skip && /^#{1,2} / { skip = 0 }
            skip { next }
            { print }
        ' "$_p" > "$_tmp"
    fi || { rm -f "$_tmp"; die "$(t fnd_err_write file="$_file")"; }
    # Every other heading must survive. A rewrite that loses one is a bug in this verb,
    # and the file is left as it was rather than saved half-right.
    _before=$(grep '^#' "$_p" | sort); _after=$(grep '^#' "$_tmp" | sort)
    if [ "$_new" = 0 ] && [ "$_before" != "$_after" ]; then
        rm -f "$_tmp"; die "$(t fnd_err_headings_touched file="$_file")"
    fi
    mv "$_tmp" "$_p" || die "$(t fnd_err_write file="$_file")"
    _fa_msg=fnd_arch_replaced; [ "$_new" = 1 ] && _fa_msg=fnd_arch_added
    ok "$(t "$_fa_msg" file="$_file" section="$_sec")"
    dim "  $(t fnd_arch_unsaved file="$_file")"
}

# --- decisions: superseding moves the old entry out ------------------------------
# The root file keeps living decisions only. When an entry is superseded by name, the
# verb moves it — whole, unchanged — to the top of ai/archive/decisions_log.md. That was
# /prune's work, done by hand every few weeks or never; it is mechanical once the new
# entry says which one it replaces.
FND_MOVED=

fnd_decision_matches() {
    grep '^## ' "$1" | grep -F -- "$2" || true
}

fnd_move_decision() {
    _md_root=$1; _md_head=$2
    _md_src="$_md_root/DECISIONS.md"; _md_log="$_md_root/ai/archive/decisions_log.md"
    mkdir -p "$_md_root/ai/archive" || return 1
    # Text travels through ENVIRON, not -v: awk -v expands backslash escapes.
    _md_entry=$(FND_HEAD=$_md_head awk 'BEGIN { h = ENVIRON["FND_HEAD"] }
        $0 == h { f = 1; print; next } f && /^## / { exit } f { print }' "$_md_src")
    [ -n "$_md_entry" ] || return 1
    FND_HEAD=$_md_head awk 'BEGIN { h = ENVIRON["FND_HEAD"] }
        $0 == h { skip = 1; next } skip && /^## / { skip = 0 } skip { next } { print }' \
        "$_md_src" > "$_md_src.fraim.tmp" && mv "$_md_src.fraim.tmp" "$_md_src" || return 1
    if [ ! -f "$_md_log" ]; then
        printf '# DECISIONS — archive (append-only)\n\n> Superseded entries moved out of DECISIONS.md, newest on top.\n' > "$_md_log"
    fi
    FND_ENTRY=$_md_entry awk 'BEGIN { entry = ENVIRON["FND_ENTRY"] }
        !done && /^## / { print entry; print ""; done = 1 }
        { print }
        END { if (!done) { print ""; print entry } }
    ' "$_md_log" > "$_md_log.fraim.tmp" && mv "$_md_log.fraim.tmp" "$_md_log" || return 1
    FND_MOVED=$_md_head
}
