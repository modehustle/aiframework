#!/bin/sh
# menu.sh — the full-screen interface behind a bare `fraim` (and `fraim menu`).
#
# A program of its own in the terminal, the way an editor or OpenCode is: it takes the
# alternate screen and gives the terminal back exactly as it was. Sections on the left
# (project, board, backlog, decisions, projects, settings, maintenance), the section on the
# right, key hints at the bottom, a command palette (ctrl+p) and dialogs with a filter.
#
# Still POSIX shell (PRODUCT.md, «CLI language — decided: POSIX shell throughout»). What
# that costs and how it is paid:
#   - one frame is composed by ONE awk process (ui_frame_awk) that fits every line to its
#     column width — CJK as two columns, colour escapes as none — and draws the box;
#   - data is read once per section and cached (UI_CACHE_*), never on an arrow key;
#   - anything that needs the full terminal (an update, cleanup, the roles picker) leaves
#     the alternate screen, runs the ordinary command, and comes back.
#
# Hard rule, unchanged: the screen appears ONLY when stdin and stdout are both terminals.
# Most calls to this CLI are made by an agent through a pipe, and a command that waits for
# a keypress there hangs the session silently.
#
# Namespace: state is UPPERCASE `UI_*` — it must survive calls into the watchman and every
# command, and POSIX sh has no locals (the watchman writes plain `_n`, `_w`, `_msg`).
# Temporaries are `_ui_*`.

# --- capability -------------------------------------------------------------
menu_supported() {
    [ -t 0 ] || return 1
    [ -t 1 ] || return 1
    case ${TERM:-} in ''|dumb) return 1 ;; esac
    command -v stty >/dev/null 2>&1 || return 1
    command -v dd   >/dev/null 2>&1 || return 1
    command -v od   >/dev/null 2>&1 || return 1
    return 0
}

# --- terminal ---------------------------------------------------------------
UI_STTY=
UI_ON=
ui_enter() {
    [ -n "$UI_STTY" ] || UI_STTY=$(stty -g 2>/dev/null)
    stty -icanon -echo -isig min 1 time 0 2>/dev/null
    printf '\033[?1049h\033[?25l\033[H\033[2J'
    UI_ON=1
}
ui_leave() {
    [ -n "$UI_ON" ] || return 0
    printf '\033[0m\033[?25h\033[?1049l'
    [ -n "$UI_STTY" ] && stty "$UI_STTY" 2>/dev/null
    UI_ON=
    return 0
}

UI_ROWS=24
UI_COLS=80
ui_size() {
    _ui_sz=$(stty size 2>/dev/null) || _ui_sz=
    UI_ROWS=${_ui_sz% *}; UI_COLS=${_ui_sz#* }
    case $UI_ROWS in ''|*[!0-9]*) UI_ROWS=24 ;; esac
    case $UI_COLS in ''|*[!0-9]*) UI_COLS=80 ;; esac
    [ "$UI_ROWS" -lt 16 ] && UI_ROWS=16
    [ "$UI_COLS" -lt 60 ] && UI_COLS=60
    return 0
}

# --- theme ------------------------------------------------------------------
# fraim: dark with an orange accent, 256 colours where the terminal has them and the
# basic eight where it does not. mono: brightness and reverse video only — for a light
# terminal, a screen reader's terminal, or taste.
ui_theme() {
    E=$(printf '\033')
    UI_OFF="$E[0m"; UI_B="$E[1m"
    _ui_th=$(config_get theme 2>/dev/null)
    _ui_colors=$(tput colors 2>/dev/null) || _ui_colors=8
    case $_ui_colors in ''|*[!0-9]*) _ui_colors=8 ;; esac
    if [ "$_ui_th" = mono ] || [ -n "${NO_COLOR:-}" ]; then
        UI_ACC="$E[1m"; UI_DIM="$E[2m"; UI_BD="$E[2m"; UI_HL="$E[7m"
        UI_WARN="$E[1m"; UI_OK=""; UI_KEY="$E[1m"
    elif [ "$_ui_colors" -ge 256 ]; then
        UI_ACC="$E[38;5;215m"; UI_DIM="$E[38;5;245m"; UI_BD="$E[38;5;240m"
        UI_HL="$E[48;5;237m$E[38;5;255m"; UI_WARN="$E[38;5;221m"; UI_OK="$E[38;5;114m"
        UI_KEY="$E[1m$E[38;5;252m"
    else
        UI_ACC="$E[33m"; UI_DIM="$E[2m"; UI_BD="$E[2m"; UI_HL="$E[7m"
        UI_WARN="$E[33m"; UI_OK="$E[32m"; UI_KEY="$E[1m"
    fi
}

# --- layout engine ------------------------------------------------------------
# Width-aware fitting, in awk under the C locale: bytes, never the terminal's idea of a
# character. A UTF-8 lead byte tells the length of the character; \343-\355 (U+3000–U+DFFF:
# CJK, kana, Hangul) take two columns; an escape sequence takes none. Too long → clipped
# with «…»; short → padded with spaces; colour reset at the end so nothing bleeds.
UI_AWK_LIB='
function wide_ff(s, i,    c2) { c2 = substr(s, i + 1, 1); return substr(s, i, 1) == "\357" && (c2 == "\274" || c2 == "\275") }
function w_of(s,    i, n, c, w) {
    w = 0; n = length(s); i = 1
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\033") { while (i <= n && substr(s, i, 1) != "m") i++; i++; continue }
        if (c < "\200") { i += 1; w += 1 }
        else if (c < "\300") { i += 1 }
        else if (c < "\340") { i += 2; w += 1 }
        else if (c < "\360") { w += (c >= "\343" && c <= "\355" || wide_ff(s, i)) ? 2 : 1; i += 3 }
        else { i += 4; w += 2 }
    }
    return w
}
function cut(s, max,    i, n, c, w, cw, len, out) {
    out = ""; w = 0; n = length(s); i = 1
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\033") { j = i; while (j <= n && substr(s, j, 1) != "m") j++; out = out substr(s, i, j - i + 1); i = j + 1; continue }
        if (c < "\200") { len = 1; cw = 1 }
        else if (c < "\300") { len = 1; cw = 0 }
        else if (c < "\340") { len = 2; cw = 1 }
        else if (c < "\360") { len = 3; cw = (c >= "\343" && c <= "\355" || wide_ff(s, i)) ? 2 : 1 }
        else { len = 4; cw = 2 }
        if (w + cw > max) break
        out = out substr(s, i, len); w += cw; i += len
    }
    CUTW = w
    return out
}
function fit(s, width,    w, out, pad) {
    if (width <= 0) return ""
    w = w_of(s)
    if (w > width) { out = cut(s, width - 1) "…"; w = CUTW + 1 }
    else out = s
    pad = ""
    while (w < width) { pad = pad " "; w++ }
    return out "\033[0m" pad
}
function rep(ch, n,    o) { o = ""; while (n-- > 0) o = o ch; return o }
'

# The frame. Input on stdin: sidebar lines, a line holding only \036, main lines. The
# rest through ENVIRON (never awk -v: it expands backslashes in the text).
ui_frame_awk() {
    LC_ALL=C awk "$UI_AWK_LIB"'
    BEGIN { part = 0; ns = 0; nm = 0 }
    $0 == "\036" { part = 1; next }
    { if (part == 0) side[++ns] = $0; else mainl[++nm] = $0 }
    END {
        W = ENVIRON["_UF_W"] + 0; H = ENVIRON["_UF_H"] + 0; SW = ENVIRON["_UF_SW"] + 0
        bd = ENVIRON["_UF_BD"]; acc = ENVIRON["_UF_ACC"]; dim = ENVIRON["_UF_DIM"]; off = "\033[0m"
        MW = W - SW - 3; BH = H - 3
        tl = ENVIRON["_UF_TL"]; tr = ENVIRON["_UF_TR"]
        tlw = w_of(tl); trw = w_of(tr)
        if (tlw + trw + 10 > W) { tr = ""; trw = 0 }
        fill = trw ? W - 8 - tlw - trw : W - 6 - tlw
        if (fill < 1) fill = 1
        top = bd "╭─ " off acc tl off bd " " rep("─", fill)
        if (trw) top = top " " off dim tr off bd " ─╮" off; else top = top "─╮" off
        printf "\033[H%s", top
        for (r = 1; r <= BH; r++)
            printf "\r\n%s│%s%s%s│%s%s%s│%s", bd, off, fit(side[r], SW), bd, off, fit(mainl[r], MW), bd, off
        printf "\r\n%s╰%s┴%s╯%s", bd, rep("─", SW), rep("─", MW), off
        printf "\r\n%s", fit(ENVIRON["_UF_FOOT"], W)
    }'
}

# A dialog over the frame: drawn with absolute cursor positions, so the frame under it
# needs no recomposition. Input: the dialog's body lines; title and geometry via ENVIRON.
ui_dialog_awk() {
    LC_ALL=C awk "$UI_AWK_LIB"'
    { body[++n] = $0 }
    END {
        X = ENVIRON["_UD_X"] + 0; Y = ENVIRON["_UD_Y"] + 0; DW = ENVIRON["_UD_W"] + 0
        acc = ENVIRON["_UD_ACC"]; off = "\033[0m"; t = ENVIRON["_UD_T"]
        fill = DW - 5 - w_of(t); if (fill < 1) fill = 1
        printf "\033[%d;%dH%s╭─ %s%s ─%s╮%s", Y, X, acc, t, acc, rep("─", fill - 1), off
        for (i = 1; i <= n; i++)
            printf "\033[%d;%dH%s│%s%s%s│%s", Y + i, X, acc, off, fit(body[i], DW - 2), acc, off
        printf "\033[%d;%dH%s╰%s╯%s", Y + n + 1, X, acc, rep("─", DW - 2), off
    }'
}

# Word-wrap lines to a display width (fold counts bytes and breaks Cyrillic at half width).
ui_wrap() {
    _UF_FW=$1 LC_ALL=C awk "$UI_AWK_LIB"'
    {
        W = ENVIRON["_UF_FW"] + 0; line = ""; lw = 0
        if (w_of($0) <= W) { print; next }
        n = split($0, words, " ")
        if (n == 0) { print ""; next }
        for (i = 1; i <= n; i++) {
            ww = w_of(words[i])
            if (lw > 0 && lw + 1 + ww > W && ww <= W) { print line; line = ""; lw = 0 }
            # A run with no spaces wider than the line (Chinese, Japanese, a long path) is
            # broken by width, character by character.
            while (ww > W - lw - (lw > 0)) {
                if (lw > 0) { line = line " "; lw++ }
                head = cut(words[i], W - lw); print line head; line = ""; lw = 0
                words[i] = substr(words[i], length(head) + 1); ww = w_of(words[i])
                if (length(head) == 0) break
            }
            if (ww == 0) continue
            if (lw > 0) { line = line " "; lw++ }
            line = line words[i]; lw += ww
        }
        print line
    }'
}

# Fit lines to a width (used by tests and by the reader's wrapping).
ui_fit() {
    _UF_FW=$1 LC_ALL=C awk "$UI_AWK_LIB"'{ print fit($0, ENVIRON["_UF_FW"] + 0) }'
}

# --- sections -----------------------------------------------------------------
UI_SECTIONS='project board backlog decisions projects settings maint'
ui_sec_id()  { printf '%s\n' $UI_SECTIONS | sed -n "${1}p"; }
ui_sec_n()   { printf '%s\n' $UI_SECTIONS | wc -l | tr -d ' '; }

UI_ROOT=
UI_MANAGED=
ui_counts() {
    UI_N_BOARD=; UI_N_BACKLOG=; UI_N_DECISIONS=
    UI_N_PROJECTS=$(registry_list | grep -c . || true)
    [ -n "$UI_MANAGED" ] || return 0
    UI_N_BOARD=$(tasks_scan "$UI_ROOT" 2>/dev/null | grep -c . || true)
    UI_N_BACKLOG=$(backlog_scan "$UI_ROOT" 2>/dev/null | grep -c . || true)
    UI_N_DECISIONS=$(grep -c '^## ' "$UI_ROOT/DECISIONS.md" 2>/dev/null || true)
    return 0
}

# The sidebar: one line per section, the current one marked; the focus decides the mark.
ui_sidebar() {
    _ui_i=0
    printf '\n'
    for _ui_s in $UI_SECTIONS; do
        _ui_i=$((_ui_i + 1))
        [ "$_ui_s" = settings ] && printf ' %s─────────────────%s\n' "$UI_BD" "$UI_OFF"
        case $_ui_s in
            board)     _ui_c=${UI_N_BOARD:-} ;;
            backlog)   _ui_c=${UI_N_BACKLOG:-} ;;
            decisions) _ui_c=${UI_N_DECISIONS:-} ;;
            projects)  _ui_c=${UI_N_PROJECTS:-} ;;
            *)         _ui_c= ;;
        esac
        [ "$_ui_c" = 0 ] && _ui_c=
        _ui_l=$(t "ui_sec_$_ui_s")
        if [ "$_ui_i" = "$UI_SEC" ]; then
            if [ "$UI_FOCUS" = side ] && [ -z "$UI_DLG" ]; then
                printf '%s%s ▌ %s%s %s\n' "$UI_HL" "$UI_ACC" "$_ui_l" "$UI_OFF" "$UI_DIM$_ui_c"
            else
                printf ' %s▌ %s%s %s\n' "$UI_ACC" "$_ui_l" "$UI_OFF" "$UI_DIM$_ui_c"
            fi
        else
            printf '   %s %s\n' "$_ui_l" "$UI_DIM$_ui_c"
        fi
    done
}

# A section's body: UI_LINES (what is drawn) and UI_KEYS (one per line: «-» for a line
# that cannot be selected, otherwise what Enter acts on). Cached per section until
# something changes; an arrow key never recomputes it.
ui_load() {
    _ui_id=$(ui_sec_id "$UI_SEC")
    eval "_ui_cached=\${UI_CACHE_$_ui_id-}"
    if [ -n "$_ui_cached" ]; then
        eval "UI_LINES=\$UI_CACHE_$_ui_id; UI_KEYS=\$UI_CKEYS_$_ui_id"
        return 0
    fi
    UI_LINES=; UI_KEYS=
    "ui_build_$_ui_id"
    eval "UI_CACHE_$_ui_id=\$UI_LINES; UI_CKEYS_$_ui_id=\$UI_KEYS"
}
ui_flush() {
    for _ui_s in $UI_SECTIONS; do eval "UI_CACHE_$_ui_s=; UI_CKEYS_$_ui_s="; done
    ui_counts
}

# Append one line to the body being built.
ui_add() { # key line
    if [ -z "$UI_LINES$UI_KEYS" ]; then UI_LINES=$2; UI_KEYS=$1
    else UI_LINES="$UI_LINES
$2"; UI_KEYS="$UI_KEYS
$1"; fi
}
# Append captured output, every line unselectable.
ui_add_text() {
    _ui_old=$IFS
    IFS='
'
    for _ui_ln in $1; do IFS=$_ui_old; ui_add - "  $_ui_ln"; done
    IFS=$_ui_old
}

ui_unmanaged_note() {
    ui_add - ""
    ui_add - "  $UI_DIM$(t ui_unmanaged)$UI_OFF"
}

ui_build_project() {
    ui_add - ""
    if [ -z "$UI_MANAGED" ]; then ui_unmanaged_note; return 0; fi
    WM_FINDINGS=
    wm_run "$UI_ROOT" 2>/dev/null || :
    _ui_f=$WM_FINDINGS
    _ui_att=$(printf '%s\n' "$_ui_f" | awk -F'\t' '$2 == "attention"' | grep -c . || true)
    if [ "$_ui_att" -gt 0 ]; then
        ui_add - "  $UI_B$(t ui_watchman)$UI_OFF  $UI_WARN$(tp "$_ui_att" ui_attention)$UI_OFF"
    else
        ui_add - "  $UI_B$(t ui_watchman)$UI_OFF"
    fi
    if [ -z "$_ui_f" ]; then
        ui_add - "  $UI_OK✓$UI_OFF $(t ui_all_clean)"
    else
        _ui_old=$IFS
        IFS='
'
        for _ui_row in $_ui_f; do
            IFS=$_ui_old
            _ui_sev=$(printf '%s' "$_ui_row" | cut -f2)
            _ui_msg=$(printf '%s' "$_ui_row" | cut -f3)
            _ui_act=$(printf '%s' "$_ui_row" | cut -f4)
            if [ "$_ui_sev" = attention ]; then _ui_m="$UI_WARN!$UI_OFF"; else _ui_m="$UI_DIM·$UI_OFF"; fi
            ui_add "status" "  $_ui_m $_ui_msg${_ui_act:+  $UI_ACC→ $_ui_act$UI_OFF}"
        done
        IFS=$_ui_old
    fi
    ui_add - ""
    ui_add - "  $UI_B$(t ui_sec_board)$UI_OFF  $UI_DIM$(if [ "${UI_N_BOARD:-0}" -gt 0 ]; then tp "$UI_N_BOARD" ui_open_cards; else t ui_board_empty; fi)$UI_OFF"
    ui_add - "  $UI_B$(t ui_sec_backlog)$UI_OFF  $UI_DIM$(tp "${UI_N_BACKLOG:-0}" ui_questions)$UI_OFF"
    backlog_scan "$UI_ROOT" 2>/dev/null | head -3 | while IFS="$TASK_SEP" read -r _ui_s _ui_c _ui_fr _ui_t; do
        printf '%s\n' "$_ui_s	$_ui_t"
    done > "${UI_TMP}.bl"
    while IFS='	' read -r _ui_s _ui_t; do
        ui_add "backlog:$_ui_s" "    $UI_ACC?$UI_OFF $_ui_s $UI_DIM— $_ui_t$UI_OFF"
    done < "${UI_TMP}.bl"
    if [ -f "$UI_ROOT/DECISIONS.md" ]; then
        ui_add - ""
        ui_add - "  $UI_B$(t ui_recent_decisions)$UI_OFF"
        _ui_i=0
        sed -n 's/^## //p' "$UI_ROOT/DECISIONS.md" | head -3 > "${UI_TMP}.dc"
        while IFS= read -r _ui_h; do
            _ui_i=$((_ui_i + 1))
            _ui_d=${_ui_h%% — *}; _ui_tt=${_ui_h#* — }
            ui_add "decision:$_ui_i" "    $UI_DIM${_ui_d#????-}$UI_OFF  $_ui_tt"
        done < "${UI_TMP}.dc"
    fi
}

ui_build_board() {
    if [ -z "$UI_MANAGED" ]; then ui_unmanaged_note; return 0; fi
    ui_add - ""
    ui_add_text "$( ( verb_tasks "$UI_ROOT" ) 2>&1 || true)"
    ui_add - ""
    ui_add - "  $UI_DIM$(t ui_board_hint)$UI_OFF"
}

ui_build_backlog() {
    if [ -z "$UI_MANAGED" ]; then ui_unmanaged_note; return 0; fi
    ui_add - ""
    backlog_scan "$UI_ROOT" 2>/dev/null > "${UI_TMP}.bl" || :
    if [ ! -s "${UI_TMP}.bl" ]; then
        ui_add - "  $UI_OK✓$UI_OFF $(t ui_backlog_empty)"
    else
        while IFS="$TASK_SEP" read -r _ui_s _ui_c _ui_fr _ui_t; do
            ui_add "backlog:$_ui_s" "  $UI_ACC?$UI_OFF $UI_B$_ui_s$UI_OFF"
            ui_add - "    $_ui_t  $UI_DIM$_ui_c$UI_OFF"
        done < "${UI_TMP}.bl"
    fi
    ui_add - ""
    ui_add - "  $UI_DIM$(t ui_backlog_hint)$UI_OFF"
}

ui_build_decisions() {
    if [ -z "$UI_MANAGED" ] || [ ! -f "$UI_ROOT/DECISIONS.md" ]; then ui_unmanaged_note; return 0; fi
    ui_add - ""
    _ui_i=0
    sed -n 's/^## //p' "$UI_ROOT/DECISIONS.md" > "${UI_TMP}.dc"
    while IFS= read -r _ui_h; do
        _ui_i=$((_ui_i + 1))
        _ui_d=${_ui_h%% — *}; _ui_tt=${_ui_h#* — }
        ui_add "decision:$_ui_i" "  $UI_DIM$_ui_d$UI_OFF  $_ui_tt"
    done < "${UI_TMP}.dc"
}

ui_build_projects() {
    ui_add - ""
    registry_list > "${UI_TMP}.pr"
    if [ ! -s "${UI_TMP}.pr" ]; then
        ui_add - "  $UI_DIM$(t ui_projects_empty)$UI_OFF"
    fi
    while IFS= read -r _ui_p; do
        if [ "$_ui_p" = "$UI_ROOT" ]; then _ui_m="$UI_ACC▸$UI_OFF"; else _ui_m=" "; fi
        if [ -d "$_ui_p" ]; then
            ui_add "project:$_ui_p" "  $_ui_m $UI_B$(basename -- "$_ui_p")$UI_OFF  $UI_DIM$_ui_p$UI_OFF"
        else
            ui_add "project:$_ui_p" "  $_ui_m $UI_DIM$(basename -- "$_ui_p")  $(t ui_project_gone)$UI_OFF"
        fi
    done < "${UI_TMP}.pr"
    if [ -n "$UI_MANAGED" ] && ! grep -qxF "$UI_ROOT" "${UI_TMP}.pr"; then
        ui_add - ""
        ui_add "act:register" "  $UI_ACC+$UI_OFF $(t ui_act_register)"
    fi
}

# Where a setting of this key is written from the screen: the operator's own (general,
# models) on the machine, the rest in the project when there is one.
ui_cfg_scope() {
    case $(config_section "$1") in
        general) printf 'machine\n'; return ;;
    esac
    case $1 in tier_*|role_*|launchcmd_*|readypattern_*|modelcmd_*) printf 'machine\n'; return ;; esac
    if [ -n "$UI_MANAGED" ]; then printf 'project\n'; else printf 'machine\n'; fi
}
ui_cfg_file() {
    if [ "$(ui_cfg_scope "$1")" = machine ]; then config_machine_file
    else config_project_file "$UI_ROOT"; fi
}

# How a value reads on screen.
ui_cfg_value() {
    _ui_k=$1; _ui_v=$(config_get "$_ui_k" "$UI_ROOT")
    case $(config_type "$_ui_k") in
        on/off) if [ "$_ui_v" = on ]; then t cfg_val_on; else t cfg_val_off; fi ;;
        lang)
            if [ -z "$_ui_v" ] || [ "$_ui_v" = auto ]; then
                t cfg_val_lang_auto lang="$(ui_lang_name "$I18N_LANG")"
            else ui_lang_name "$_ui_v"; fi ;;
        enum:notify,off) if [ "$_ui_v" = off ]; then t cfg_val_updates_off; else t cfg_val_notify; fi ;;
        *) if [ -n "$_ui_v" ]; then printf '%s' "$_ui_v"; else t cfg_val_empty; fi ;;
    esac
}
ui_lang_name() { i18n_languages | awk -F'|' -v c="$1" '$1 == c { print $2; f = 1 } END { if (!f) print c }'; }

ui_cfg_row() { # key label
    _ui_v=$(ui_cfg_value "$1")
    _ui_src=$(config_source "$1" "$UI_ROOT")
    case $_ui_src in
        ai/fraim.conf)    _ui_w=$(t cfg_where_project) ;;
        '~/.fraim/config') _ui_w=$(t cfg_where_machine) ;;
        *)                _ui_w="$UI_DIM$_ui_src$UI_OFF" ;;
    esac
    # Label, value, and where it is written — the last only when there is room: the
    # description under the list says it for the selected row anyway.
    _ui_mw=$((UI_COLS - 25))
    if [ "$UI_COLS" -ge 100 ]; then
        ui_add "cfg:$1" "  $(ui_cols "$2" $((_ui_mw - 37)) "$_ui_v" 24) $_ui_w"
    else
        ui_add "cfg:$1" "  $(ui_cols "$2" $((_ui_mw - 22)) "$_ui_v" 20)"
    fi
}
# Two columns padded to widths; the awk fit does the measuring.
ui_cols() {
    printf '%s\n%s\n' "$1" "$3" | _UF_A=$2 _UF_B=$4 LC_ALL=C awk "$UI_AWK_LIB"'
        NR == 1 { a = fit($0, ENVIRON["_UF_A"] - 1) " " } NR == 2 { printf "%s%s", a, fit($0, ENVIRON["_UF_B"] + 0) }'
}

ui_build_settings() {
    for _ui_sec in general watchman saving models fleet expert; do
        ui_add - ""
        ui_add - "  $UI_ACC$(t "cfg_sec_$_ui_sec")$UI_OFF"
        config_table > "${UI_TMP}.ct"
        while IFS='|' read -r _ui_k _ui_d _ui_s _ui_ty; do
            [ "$_ui_s" = "$_ui_sec" ] || continue
            ui_cfg_row "$_ui_k" "$(t "cfg_label_$_ui_k")"
        done < "${UI_TMP}.ct"
        if [ "$_ui_sec" = models ]; then
            for _ui_tier in cheap capable strong; do
                ui_cfg_row "tier_$_ui_tier" "$(t "ui_tier_$_ui_tier")"
            done
            for _ui_rk in $(config_family_keys role_ "$UI_ROOT"); do
                ui_cfg_row "$_ui_rk" "$_ui_rk"
            done
        fi
        if [ "$_ui_sec" = expert ]; then
            for _ui_p in launchcmd_ readypattern_ modelcmd_; do
                for _ui_fk in $(config_family_keys "$_ui_p" "$UI_ROOT"); do ui_cfg_row "$_ui_fk" "$_ui_fk"; done
            done
            ui_add - "  $UI_DIM$(t ui_expert_hint)$UI_OFF"
        fi
    done
}

ui_build_maint() {
    ui_add - ""
    for _ui_a in status clean publish update upgrade doctor; do
        ui_add "act:$_ui_a" "  $(ui_cols "$(t "ui_act_$_ui_a")" 26 "$UI_DIM$(t "ui_act_${_ui_a}_hint")$UI_OFF" $((UI_COLS - 52)))"
    done
}

# --- the main pane --------------------------------------------------------------
UI_SEL=0
UI_TOP=0
UI_READER=
UI_READER_TITLE=

# The selectable line numbers of the current body, one per line.
ui_selectable() { printf '%s\n' "$UI_KEYS" | awk '$0 != "-" { print NR }'; }

# Keep the selection on a selectable line and inside the visible window.
ui_clamp() {
    _ui_bh=$((UI_ROWS - 3))
    _ui_total=$(printf '%s\n' "$UI_LINES" | wc -l | tr -d ' ')
    if [ -n "$UI_READER" ]; then
        _ui_total=$(printf '%s\n' "$UI_READER" | wc -l | tr -d ' ')
        [ "$UI_TOP" -gt $((_ui_total - _ui_bh)) ] && UI_TOP=$((_ui_total - _ui_bh))
        [ "$UI_TOP" -lt 0 ] && UI_TOP=0
        return 0
    fi
    _ui_sl=$(ui_selectable)
    if [ -z "$_ui_sl" ]; then
        UI_SEL=0
        [ "$UI_TOP" -gt $((_ui_total - _ui_bh + 4)) ] && UI_TOP=$((_ui_total - _ui_bh + 4))
        [ "$UI_TOP" -lt 0 ] && UI_TOP=0
        return 0
    fi
    printf '%s\n' "$_ui_sl" | grep -qx "$UI_SEL" || UI_SEL=$(printf '%s\n' "$_ui_sl" | head -1)
    [ "$UI_SEL" -le "$UI_TOP" ] && UI_TOP=$((UI_SEL - 2))
    [ "$UI_SEL" -gt $((UI_TOP + _ui_bh - 5)) ] && UI_TOP=$((UI_SEL - _ui_bh + 5))
    [ "$UI_TOP" -lt 0 ] && UI_TOP=0
    return 0
}

ui_move() { # +1 | -1
    if [ -n "$UI_READER" ] || [ -z "$(ui_selectable)" ]; then
        UI_TOP=$((UI_TOP + $1)); return 0
    fi
    if [ "$1" -gt 0 ]; then
        _ui_n=$(ui_selectable | awk -v s="$UI_SEL" '$1 > s { print; exit }')
        [ -n "$_ui_n" ] || _ui_n=$(ui_selectable | head -1)
    else
        _ui_n=$(ui_selectable | awk -v s="$UI_SEL" '$1 < s { p = $1 } END { print p }')
        [ -n "$_ui_n" ] || _ui_n=$(ui_selectable | tail -1)
    fi
    UI_SEL=$_ui_n
}

ui_key_at() {
    [ "${1:-0}" -ge 1 ] 2>/dev/null || return 0
    printf '%s\n' "$UI_KEYS" | sed -n "${1}p"
}

# What the main pane shows: the body with the selection highlighted, or the reader; the
# settings section adds the description of the selected key at the bottom.
ui_main_lines() {
    _ui_bh=$((UI_ROWS - 3))
    if [ -n "$UI_READER" ]; then
        printf '\n  %s%s%s\n\n' "$UI_ACC" "$UI_READER_TITLE" "$UI_OFF"
        printf '%s\n' "$UI_READER" | sed -n "$((UI_TOP + 1)),$((UI_TOP + _ui_bh - 3))p"
        return 0
    fi
    _ui_rows=$_ui_bh
    _ui_desc=
    _ui_k=$(ui_key_at "$UI_SEL")
    case $_ui_k in cfg:*)
        _ui_ck=${_ui_k#cfg:}
        _ui_fam=$(config_family "$_ui_ck")
        if [ -n "$_ui_fam" ]; then _ui_desc=$(t "cfg_fam_${_ui_fam%_}")
        else _ui_desc=$(t "cfg_desc_$_ui_ck"); fi
        _ui_rows=$((_ui_bh - 5)) ;;
    esac
    printf '%s\n' "$UI_LINES" | awk -v top="$UI_TOP" -v n="$_ui_rows" -v sel="$UI_SEL" \
        -v on="$UI_HL" -v focus="$UI_FOCUS" '
        NR > top && NR <= top + n {
            if (NR == sel && focus == "main") { gsub(/\033\[0m/, "\033[0m" on); print on $0 }
            else print
        }'
    if [ -n "$_ui_desc" ]; then
        _ui_have=$(printf '%s\n' "$UI_LINES" | awk -v top="$UI_TOP" -v n="$_ui_rows" 'NR > top && NR <= top + n' | wc -l)
        while [ "$_ui_have" -lt "$_ui_rows" ]; do printf '\n'; _ui_have=$((_ui_have + 1)); done
        printf '  %s%s%s\n' "$UI_BD" "$(menu_rule $((UI_COLS - 26)))" "$UI_OFF"
        printf '%s\n' "$_ui_desc" | ui_wrap $((UI_COLS - 28)) | sed 's/^/  /' | head -3
        printf '  %s%s%s\n' "$UI_DIM" "$(t ui_written_to file="$(ui_cfg_file "$_ui_ck" | sed "s|^$HOME|~|; s|^$UI_ROOT/||")")" "$UI_OFF"
    fi
}

menu_rule() {
    _menu_n=$1; _menu_out=
    while [ "$_menu_n" -gt 0 ]; do _menu_out="$_menu_out─"; _menu_n=$((_menu_n - 1)); done
    printf '%s' "$_menu_out"
}

ui_footer() {
    if [ -n "$UI_MSG" ]; then printf ' %s' "$UI_MSG"; return; fi
    if [ -n "$UI_DLG" ]; then _ui_h=$(t ui_hint_dialog)
    elif [ -n "$UI_READER" ]; then _ui_h=$(t ui_hint_reader)
    elif [ "$UI_FOCUS" = side ]; then _ui_h=$(t ui_hint_side)
    elif [ "$(ui_sec_id "$UI_SEC")" = settings ]; then _ui_h=$(t ui_hint_settings)
    else _ui_h=$(t ui_hint_main); fi
    # Keys in the hint are written «[key] words»: the key is bright, the words dim.
    printf ' %s' "$_ui_h" | sed "s/\\[\\([^]]*\\)\\]/$UI_KEY\\1$UI_OFF$UI_DIM/g; s/^/$UI_DIM/"
}

UI_MSG=
ui_paint() {
    ui_size
    ui_clamp
    _ui_branch=
    [ -n "$UI_MANAGED" ] && _ui_branch=$(git -C "$UI_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) || :
    _ui_tr=$(basename -- "$UI_ROOT")${_ui_branch:+ · $_ui_branch}
    _ui_tl=fraim
    _ui_sid=$(ui_sec_id "$UI_SEC")
    [ "$_ui_sid" = project ] || _ui_tl="fraim · $(t "ui_sec_$_ui_sid")"
    {
        ui_sidebar
        printf '\036\n'
        ui_main_lines
    } | _UF_W=$UI_COLS _UF_H=$UI_ROWS _UF_SW=20 _UF_BD=$UI_BD _UF_ACC=$UI_ACC _UF_DIM=$UI_DIM \
        _UF_TL=$_ui_tl _UF_TR=$_ui_tr _UF_FOOT="$(ui_footer)" ui_frame_awk
    [ -n "$UI_DLG" ] && ui_dialog_paint
    UI_MSG=
    return 0
}

# --- dialogs: palette, choice ----------------------------------------------------
# One list dialog serves the palette, the language picker and any choice of values:
# UI_DLG_ITEMS holds «value<TAB>label<TAB>hint» lines; typing filters them; Enter hands the
# chosen value to ui_dlg_accept_<kind>.
UI_DLG=
UI_DLG_KIND=
UI_DLG_TITLE=
UI_DLG_ITEMS=
UI_DLG_Q=
UI_DLG_SEL=1
UI_DLG_KEY=
UI_DLG_CUR=

ui_dlg_open() { # kind title items [key]
    UI_DLG=1; UI_DLG_KIND=$1; UI_DLG_TITLE=$2; UI_DLG_ITEMS=$3; UI_DLG_KEY=${4:-}
    UI_DLG_Q=; UI_DLG_SEL=1
}
ui_dlg_close() { UI_DLG=; UI_DLG_KIND=; UI_DLG_ITEMS=; UI_DLG_Q=; }

# Filtering is case-insensitive in the operator's own locale (grep -i folds Cyrillic only
# under a UTF-8 locale), on the label and the hint, never on the hidden value.
ui_dlg_filtered() {
    if [ -z "$UI_DLG_Q" ]; then printf '%s\n' "$UI_DLG_ITEMS"; return; fi
    printf '%s\n' "$UI_DLG_ITEMS" | while IFS='	' read -r _ui_v _ui_l _ui_h; do
        printf '%s\t%s\t%s\t%s %s\n' "$_ui_v" "$_ui_l" "$_ui_h" "$_ui_l" "$_ui_h"
    done | LC_ALL=$UI_LOCALE grep -iF -- "$UI_DLG_Q" | cut -f1-3
}

ui_dialog_paint() {
    _ui_dw=$((UI_COLS * 2 / 3)); [ "$_ui_dw" -lt 46 ] && _ui_dw=46; [ "$_ui_dw" -gt 70 ] && _ui_dw=70
    _ui_max=$((UI_ROWS - 10)); [ "$_ui_max" -gt 12 ] && _ui_max=12
    _ui_list=$(ui_dlg_filtered | head -"$_ui_max")
    _ui_cnt=$(printf '%s' "$_ui_list" | grep -c . || true)
    [ "$UI_DLG_SEL" -gt "$_ui_cnt" ] && UI_DLG_SEL=$_ui_cnt
    [ "$UI_DLG_SEL" -lt 1 ] && UI_DLG_SEL=1
    {
        printf ' %s>%s %s%s_%s\n\n' "$UI_ACC" "$UI_OFF" "$UI_DLG_Q" "$UI_ACC" "$UI_OFF"
        if [ "$_ui_cnt" -eq 0 ]; then printf '   %s%s%s\n' "$UI_DIM" "$(t ui_dlg_nothing)" "$UI_OFF"; fi
        printf '%s\n' "$_ui_list" | awk -F'\t' -v sel="$UI_DLG_SEL" -v on="$UI_HL" -v dim="$UI_DIM" \
            -v off="$UI_OFF" -v cur="$UI_DLG_CUR" -v w="$((_ui_dw - 6))" '
            NF >= 2 {
                mark = ($1 == cur && cur != "") ? " ✓" : ""
                if (NR == sel) printf "%s ▸ %s%s  %s%s%s\n", on, $2, mark, $3, off, ""
                else printf "   %s%s  %s%s%s\n", $2, mark, dim, $3, off
            }'
        printf '\n %s%s%s\n' "$UI_DIM" "$(t ui_dlg_keys)" "$UI_OFF"
    } | _UD_X=$(( (UI_COLS - _ui_dw) / 2 + 1 )) _UD_Y=3 _UD_W=$_ui_dw _UD_ACC=$UI_ACC \
        _UD_T=$UI_DLG_TITLE ui_dialog_awk
}

ui_dlg_choice() {
    ui_dlg_filtered | sed -n "${UI_DLG_SEL}p" | cut -f1
}

# The palette: every section, every action, every setting — by a few letters.
ui_palette_items() {
    for _ui_s in $UI_SECTIONS; do
        printf 'sec:%s\t%s\t%s\n' "$_ui_s" "$(t "ui_sec_$_ui_s")" "$(t ui_pal_section)"
    done
    for _ui_a in status clean publish update upgrade doctor; do
        printf 'act:%s\t%s\t%s\n' "$_ui_a" "$(t "ui_act_$_ui_a")" "$(t ui_sec_maint)"
    done
    config_table | while IFS='|' read -r _ui_k _ui_d _ui_s _ui_ty; do
        printf 'cfg:%s\t%s…\t%s\n' "$_ui_k" "$(t "cfg_label_$_ui_k")" "$(t ui_sec_settings)"
    done
    printf 'help:\t%s\t\n' "$(t ui_pal_help)"
    printf 'quit:\t%s\tq\n' "$(t ui_pal_quit)"
}

ui_lang_items() {
    printf 'auto\t%s\t\n' "$(t cfg_val_lang_auto lang="$(ui_lang_name "$(FRAIM_LANG= FRAIM_HOME=/nonexistent i18n_detect "$(i18n_dir)")")")"
    i18n_languages | while IFS='|' read -r _ui_c _ui_n _ui_st; do
        _ui_st2=
        [ "$_ui_st" = beta ] && _ui_st2=beta
        printf '%s\t%s\t%s %s\n' "$_ui_c" "$_ui_n" "$_ui_c" "$_ui_st2"
    done
}

# --- acting ---------------------------------------------------------------------
# Leave the screen, run an ordinary command with the whole terminal, come back. Every
# command runs in a subshell and ends in `|| true`: cmd_status and the verbs end in `exit`,
# the CLI runs under `set -e`, and `fraim status` exits 1 whenever the project needs the
# human — the normal case for someone who opened the screen to look.
ui_external() {
    ui_leave
    printf '\033[H\033[2J\n'
    ( "$@" ) || true
    printf '\n  %s%s%s ' "$C_DIM" "$(t ui_enter_back)" "$C_OFF"
    read -r _ui_ignored 2>/dev/null || true
    ui_enter
    ui_flush
}

# A line of text typed at the bottom of the screen, in the terminal's own line editing
# (backspace over any script, paste). Empty input keeps the old value.
ui_prompt() { # label current → UI_INPUT
    UI_INPUT=
    printf '\033[%d;1H\033[2K %s%s:%s ' "$UI_ROWS" "$UI_ACC" "$1" "$UI_OFF"
    printf '\033[?25h'
    [ -n "$UI_STTY" ] && stty "$UI_STTY" 2>/dev/null
    read -r UI_INPUT 2>/dev/null || UI_INPUT=
    stty -icanon -echo -isig min 1 time 0 2>/dev/null
    printf '\033[?25l'
}

ui_cfg_write() { # key value
    _ui_f=$(ui_cfg_file "$1")
    if config_set_file "$_ui_f" "$1" "$2"; then
        UI_MSG="$UI_OK✓$UI_OFF $1 = $2"
    else
        UI_MSG="$UI_WARN!$UI_OFF $(t cfg_err_write)"
    fi
    ui_after_cfg "$1"
}
ui_after_cfg() {
    case $1 in
        lang)  i18n_load ;;
        theme) ui_theme ;;
    esac
    ui_flush
}

ui_edit_cfg() {
    _ui_k=$1
    case $(config_type "$_ui_k") in
        on/off)
            if [ "$(config_get "$_ui_k" "$UI_ROOT")" = on ]; then ui_cfg_write "$_ui_k" off
            else ui_cfg_write "$_ui_k" on; fi ;;
        lang)
            UI_DLG_CUR=$(config_explicit lang); [ -n "$UI_DLG_CUR" ] || UI_DLG_CUR=auto
            ui_dlg_open lang "$(t cfg_label_lang)" "$(ui_lang_items)" lang ;;
        enum:*)
            UI_DLG_CUR=$(config_get "$_ui_k" "$UI_ROOT")
            _ui_set=$(config_type "$_ui_k"); _ui_set=${_ui_set#enum:}
            _ui_items=$(printf '%s\n' "$_ui_set" | tr ',' '\n' | while read -r _ui_o; do
                case $_ui_k:$_ui_o in
                    updates:notify) _ui_lab=$(t cfg_val_notify) ;;
                    updates:off)    _ui_lab=$(t cfg_val_updates_off) ;;
                    *)              _ui_lab=$_ui_o ;;
                esac
                [ "$_ui_lab" = "$_ui_o" ] && _ui_hint= || _ui_hint=$_ui_o
                printf '%s\t%s\t%s\n' "$_ui_o" "$_ui_lab" "$_ui_hint"
            done)
            ui_dlg_open value "$(t "cfg_label_$_ui_k")" "$_ui_items" "$_ui_k" ;;
        *)
            case $_ui_k in
                tier_*|role_*) ui_external cmd_roles_set "$_ui_k"; return 0 ;;
            esac
            ui_prompt "$_ui_k" ""
            [ -n "$UI_INPUT" ] || return 0
            if config_known "$_ui_k" && ! config_valid "$_ui_k" "$UI_INPUT"; then
                UI_MSG="$UI_WARN!$UI_OFF $(t cfg_err_value value="$UI_INPUT" key="$_ui_k" need="$(config_type_words "$_ui_k" 2>/dev/null || t cfg_type_text)")"
                return 0
            fi
            ui_cfg_write "$_ui_k" "$UI_INPUT" ;;
    esac
}

ui_reset_cfg() {
    _ui_k=$1
    config_unset_file "$(ui_cfg_file "$_ui_k")" "$_ui_k"
    UI_MSG="$UI_OK✓$UI_OFF $(t ui_reset_done key="$_ui_k")"
    ui_after_cfg "$_ui_k"
}

ui_act() {
    case $1 in
        status)   ui_external cmd_status "$UI_ROOT" ;;
        clean)    ui_external cmd_clean ;;
        publish)  ui_external cmd_publish ;;
        update)   ui_external cmd_update ;;
        upgrade)  ui_external cmd_upgrade ;;
        doctor)   ui_external cmd_doctor ;;
        register) registry_init; registry_add "$UI_ROOT" && UI_MSG="$UI_OK✓$UI_OFF $(t ui_registered)"; ui_flush ;;
    esac
}

ui_open_reader() { # title text
    UI_READER_TITLE=$1
    UI_READER=$(printf '%s\n' "$2" | ui_wrap $((UI_COLS - 26)) | sed 's/^/  /')
    UI_TOP=0
}

ui_activate() {
    _ui_k=$(ui_key_at "$UI_SEL")
    case $_ui_k in
        ''|-)        return 0 ;;
        status)      ui_act status ;;
        act:*)       ui_act "${_ui_k#act:}" ;;
        cfg:*)       ui_edit_cfg "${_ui_k#cfg:}" ;;
        backlog:*)   _ui_s=${_ui_k#backlog:}
                     ui_open_reader "$_ui_s" "$(sed '1{/^---$/,/^---$/d}' "$UI_ROOT/ai/backlog/$_ui_s.md" 2>/dev/null)" ;;
        decision:*)  _ui_n=${_ui_k#decision:}
                     _ui_txt=$(awk -v n="$_ui_n" '/^## /{c++} c == n' "$UI_ROOT/DECISIONS.md")
                     ui_open_reader "$(printf '%s\n' "$_ui_txt" | head -1 | sed 's/^## //')" \
                        "$(printf '%s\n' "$_ui_txt" | sed 1d)" ;;
        project:*)   ui_external cmd_status "${_ui_k#project:}" ;;
    esac
}

ui_dlg_accept() {
    _ui_v=$(ui_dlg_choice)
    _ui_kind=$UI_DLG_KIND; _ui_key=$UI_DLG_KEY
    ui_dlg_close
    [ -n "$_ui_v" ] || return 0
    case $_ui_kind in
        palette)
            case $_ui_v in
                sec:*)  ui_goto "${_ui_v#sec:}" ;;
                act:*)  ui_act "${_ui_v#act:}" ;;
                cfg:*)  ui_goto settings; UI_FOCUS=main
                        ui_load; UI_SEL=$(printf '%s\n' "$UI_KEYS" | grep -nx "$_ui_v" | head -1 | cut -d: -f1)
                        ui_edit_cfg "${_ui_v#cfg:}" ;;
                help:)  ui_help ;;
                quit:)  UI_QUIT=1 ;;
            esac ;;
        lang)
            if [ "$_ui_v" = auto ]; then ui_cfg_write lang auto; else ui_cfg_write lang "$_ui_v"; fi ;;
        value) ui_cfg_write "$_ui_key" "$_ui_v" ;;
    esac
}

ui_goto() {
    _ui_i=0
    for _ui_s in $UI_SECTIONS; do
        _ui_i=$((_ui_i + 1))
        [ "$_ui_s" = "$1" ] && { UI_SEC=$_ui_i; UI_SEL=0; UI_TOP=0; UI_READER=; ui_load; return 0; }
    done
}

ui_help() {
    ui_open_reader "$(t ui_help_title)" "$(t ui_help_body)"
    UI_FOCUS=main
}

# --- keys -----------------------------------------------------------------------
# One word per key: up down left right enter esc tab bs pgup pgdn home end palette quit
# help slash, `chr:<the character>` for printable input, or other.
#
# The tail of an escape sequence is read with a short timeout, so a lone Esc closes a
# dialog instead of waiting for two more bytes.
ui_byte() { dd bs=1 count=1 2>/dev/null | od -An -tu1 | tr -dc '0-9'; }
menu_getkey() {
    _ui_c=$(ui_byte)
    case $_ui_c in
        '')       printf 'quit\n' ;;
        10|13)    printf 'enter\n' ;;
        9)        printf 'tab\n' ;;
        3)        printf 'quit\n' ;;                        # ctrl+c (isig is off)
        16)       printf 'palette\n' ;;                     # ctrl+p
        8|127)    printf 'bs\n' ;;
        27)
            stty min 0 time 2 2>/dev/null
            _ui_t=$(dd bs=1 count=3 2>/dev/null | od -An -c | tr -d ' \n')
            stty min 1 time 0 2>/dev/null
            case $_ui_t in
                '')                printf 'esc\n' ;;
                \[A*|OA*)          printf 'up\n' ;;
                \[B*|OB*)          printf 'down\n' ;;
                \[C*|OC*)          printf 'right\n' ;;
                \[D*|OD*)          printf 'left\n' ;;
                \[5*)              printf 'pgup\n' ;;
                \[6*)              printf 'pgdn\n' ;;
                \[H*|OH*|\[1~*)    printf 'home\n' ;;
                \[F*|OF*|\[4~*)    printf 'end\n' ;;
                *)                 printf 'other\n' ;;
            esac ;;
        *)
            if [ "$_ui_c" -lt 32 ]; then printf 'other\n'; return; fi
            # A whole UTF-8 character: the lead byte says how many follow.
            if   [ "$_ui_c" -ge 240 ]; then _ui_more=3
            elif [ "$_ui_c" -ge 224 ]; then _ui_more=2
            elif [ "$_ui_c" -ge 192 ]; then _ui_more=1
            else _ui_more=0; fi
            _ui_ch=$(printf "\\$(printf '%03o' "$_ui_c")")
            [ "$_ui_more" -gt 0 ] && _ui_ch=$_ui_ch$(dd bs=1 count=$_ui_more 2>/dev/null)
            printf 'chr:%s\n' "$_ui_ch" ;;
    esac
}

# Remove the last CHARACTER of a string, not the last byte: drop bytes until one that is
# not a UTF-8 continuation byte has gone. Bytes are compared under the C locale.
ui_backspace() {
    printf '%s' "$1" | LC_ALL=C awk '{ s = s (NR > 1 ? "\n" : "") $0 } END {
        n = length(s); while (n > 0) { c = substr(s, n, 1); n--; if (c < "\200" || c >= "\300") break }
        printf "%s", substr(s, 1, n) }'
}

ui_key() {
    _ui_key=$1
    if [ -n "$UI_DLG" ]; then
        case $_ui_key in
            esc|quit)  ui_dlg_close ;;
            up)        UI_DLG_SEL=$((UI_DLG_SEL - 1)) ;;
            down|tab)  UI_DLG_SEL=$((UI_DLG_SEL + 1)) ;;
            enter)     ui_dlg_accept ;;
            bs)        UI_DLG_Q=$(ui_backspace "$UI_DLG_Q"); UI_DLG_SEL=1 ;;
            chr:*)     UI_DLG_Q=$UI_DLG_Q${_ui_key#chr:}; UI_DLG_SEL=1 ;;
        esac
        return 0
    fi
    case $_ui_key in
        palette|chr:/|chr::)
            UI_DLG_CUR=
            ui_dlg_open palette "$(t ui_pal_title)" "$(ui_palette_items)"; return 0 ;;
        chr:\?) ui_help; return 0 ;;
        chr:q|chr:Q|quit) UI_QUIT=1; return 0 ;;
    esac
    if [ -n "$UI_READER" ]; then
        case $_ui_key in
            esc|left|bs|chr:h) UI_READER= ;;
            up|chr:k)   UI_TOP=$((UI_TOP - 1)) ;;
            down|chr:j|enter) UI_TOP=$((UI_TOP + 1)) ;;
            pgup)       UI_TOP=$((UI_TOP - UI_ROWS + 6)) ;;
            pgdn|chr:\ ) UI_TOP=$((UI_TOP + UI_ROWS - 6)) ;;
            home)       UI_TOP=0 ;;
        esac
        return 0
    fi
    case $_ui_key in
        chr:[1-7])
            UI_SEC=${_ui_key#chr:}; UI_SEL=0; UI_TOP=0; ui_load; return 0 ;;
    esac
    if [ "$UI_FOCUS" = side ]; then
        case $_ui_key in
            up|chr:k)   UI_SEC=$((UI_SEC - 1)); [ "$UI_SEC" -lt 1 ] && UI_SEC=$(ui_sec_n)
                        UI_SEL=0; UI_TOP=0; ui_load ;;
            down|chr:j) UI_SEC=$((UI_SEC + 1)); [ "$UI_SEC" -gt "$(ui_sec_n)" ] && UI_SEC=1
                        UI_SEL=0; UI_TOP=0; ui_load ;;
            right|enter|tab|chr:l) UI_FOCUS=main ;;
        esac
        return 0
    fi
    case $_ui_key in
        esc|left|tab|chr:h) UI_FOCUS=side ;;
        up|chr:k)    ui_move -1 ;;
        down|chr:j)  ui_move 1 ;;
        pgup)        UI_TOP=$((UI_TOP - UI_ROWS + 6)); UI_SEL=0 ;;
        pgdn)        UI_TOP=$((UI_TOP + UI_ROWS - 6)); UI_SEL=0 ;;
        enter|right|chr:\ ) ui_activate ;;
        chr:d)       case $(ui_key_at "$UI_SEL") in cfg:*) ui_reset_cfg "$(ui_key_at "$UI_SEL" | cut -d: -f2-)" ;; esac ;;
        chr:r)       ui_flush; ui_load; UI_MSG="$UI_OK✓$UI_OFF $(t ui_refreshed)" ;;
    esac
}

# --- loop -------------------------------------------------------------------------
UI_SEC=1
UI_FOCUS=side
UI_QUIT=
menu_run() {
    if ! menu_supported; then
        # Not a terminal: behave exactly as before. This branch is what keeps `fraim`
        # usable from an agent, a pipe, cron and CI.
        usage
        return 0
    fi
    UI_ROOT=$(pwd -P)
    UI_MANAGED=
    wm_managed "$UI_ROOT" && UI_MANAGED=1
    # The operator's locale for filtering; the screen itself never depends on it.
    UI_LOCALE=${LC_ALL:-${LC_CTYPE:-${LANG:-C.UTF-8}}}
    UI_TMP=$(mktemp "${TMPDIR:-/tmp}/fraim-ui.XXXXXX") || UI_TMP=/tmp/fraim-ui.$$
    ui_theme
    ui_size
    ui_counts
    UI_SEC=1; UI_FOCUS=side; UI_QUIT=
    # EXIT as well as the signals: whatever ends this process must not leave the operator
    # with a terminal that has no echo and no cursor, stuck on the alternate screen.
    trap 'ui_leave; rm -f "$UI_TMP" "$UI_TMP".*' EXIT
    trap 'ui_leave; rm -f "$UI_TMP" "$UI_TMP".*; exit 0' INT TERM HUP
    ui_enter
    ui_load
    # The first start, when nobody has chosen a language yet: ask once.
    if [ -z "${FRAIM_LANG:-}" ] && [ -z "$(config_explicit lang)" ]; then
        UI_DLG_CUR=$I18N_LANG
        ui_dlg_open lang "$(t ui_first_lang)" "$(ui_lang_items)" lang
    fi
    while [ -z "$UI_QUIT" ]; do
        ui_paint
        UI_PRESSED=$(menu_getkey)
        ui_key "$UI_PRESSED"
    done
    ui_leave
    rm -f "$UI_TMP" "$UI_TMP".*
    return 0
}
