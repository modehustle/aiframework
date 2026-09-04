#!/bin/sh
# menu.sh — the interactive screen behind a bare `fraim`.
#
# Line-based, not a curses app: one full redraw per keypress, no windows, no
# resize handling, no second language. That keeps the whole product in POSIX
# shell (PRODUCT.md, «Язык CLI — решено: POSIX shell целиком») while still
# giving the operator a front door instead of a list of twenty commands.
#
# Hard rule: the menu appears ONLY when stdin and stdout are both terminals.
# Most calls to this CLI are made by an agent through a pipe, and a command
# that waits for a keypress there hangs the session silently.

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

# --- terminal modes ---------------------------------------------------------
MENU_STTY=
menu_raw() {
    [ -n "$MENU_STTY" ] || MENU_STTY=$(stty -g 2>/dev/null)
    stty -icanon -echo min 1 time 0 2>/dev/null
    printf '\033[?25l'          # hide the cursor while we own the screen
}
menu_cooked() {
    printf '\033[?25h'
    [ -n "$MENU_STTY" ] && stty "$MENU_STTY" 2>/dev/null
    return 0
}

# --- drawing primitives -----------------------------------------------------
menu_width() {
    _w=$(tput cols 2>/dev/null) || _w=
    case $_w in ''|*[!0-9]*) _w=80 ;; esac
    [ "$_w" -gt 78 ] && _w=78
    [ "$_w" -lt 44 ] && _w=44
    printf '%s\n' "$_w"
}

menu_rule() {
    _n=$1; _out=
    while [ "$_n" -gt 0 ]; do _out="$_out─"; _n=$((_n - 1)); done
    printf '%s' "$_out"
}

# The title bar. Reverse video across the full width is what makes this read as
# a screen rather than as scrollback, and it costs one escape sequence.
menu_bar() {
    _w=$1; _left=$2; _right=$3
    _pad=$(( _w - 2 - $(printf '%s' "$_left" | wc -m | tr -d ' ') \
                    - $(printf '%s' "$_right" | wc -m | tr -d ' ') - 1 ))
    [ "$_pad" -lt 1 ] && _pad=1
    printf '\033[7m %s' "$_left"
    while [ "$_pad" -gt 0 ]; do printf ' '; _pad=$((_pad - 1)); done
    printf '%s \033[0m\n' "$_right"
}

# --- items ------------------------------------------------------------------
# label \t hint. The action lives in menu_exec, keyed by the same index, so
# adding an entry means one line here and one branch there. The agent-launch
# work goes in as items 7+ without touching anything else.
menu_items() {
    cat <<'ITEMS'
Скан проекта	что происходит здесь и сейчас
Обновить	поставить и обновить скиллы во всех харнесах
Доктор	что и куда установлено, что разошлось
Реестр проектов	все проекты, которые ведёт система
Добавить этот проект	зарегистрировать текущий каталог
Настройки	что действует и откуда
Выход	
ITEMS
}

menu_count() { menu_items | wc -l | tr -d ' '; }

# --- one screen -------------------------------------------------------------
# The project card: the deterministic watchman's verdict, rendered once and
# reused on every redraw. Recomputed only after an action, because an arrow key
# must not cost a `git log` on a large repository.
MENU_CARD=
menu_card() {
    _root=$(pwd -P)
    _w=$(menu_width)
    MENU_CARD=$(
        if wm_managed "$_root"; then
            WM_FINDINGS=
            wm_run "$_root"
            if [ -z "$WM_FINDINGS" ]; then
                printf '  %s✓%s всё чисто\n' "$C_GRN" "$C_OFF"
            else
                printf '%s\n' "$WM_FINDINGS" | while IFS='	' read -r _id _sev _msg _act; do
                    [ -n "$_id" ] || continue
                    if [ "$_sev" = attention ]; then _m="$C_YEL!$C_OFF"; else _m="$C_DIM·$C_OFF"; fi
                    if [ -n "$_act" ]; then
                        printf '  %s %s %s→ %s%s\n' "$_m" \
                            "$(wm_pad "$_msg" $(( _w - 26 )))" "$C_DIM" "$_act" "$C_OFF"
                    else
                        printf '  %s %s\n' "$_m" "$_msg"
                    fi
                done
            fi
        else
            printf '  %s·%s каталог не под системой — %s/onboard%s или %sfraim scaffold%s\n' \
                "$C_DIM" "$C_OFF" "$C_BLD" "$C_OFF" "$C_BLD" "$C_OFF"
        fi
    )
}

menu_draw() {
    _sel=$1
    _w=$(menu_width)

    printf '\033[H\033[J'
    printf '\n'
    menu_bar "$_w" "▌ FRAIM $(fraim_version)" "$(basename -- "$(pwd -P)")"
    printf '\n'
    printf '%s\n' "$MENU_CARD"
    printf '\n  %s%s%s\n\n' "$C_DIM" "$(menu_rule $(( _w - 2 )))" "$C_OFF"

    _i=0
    menu_items | while IFS='	' read -r _label _hint; do
        _i=$((_i + 1))
        if [ "$_i" = "$_sel" ]; then
            printf '  %s%s▸ %s%s  %s%s%s\n' "$C_BLD" "$C_GRN" \
                "$(wm_pad "$_label" 22)" "$C_OFF" "$C_DIM" "$_hint" "$C_OFF"
        else
            printf '    %s  %s%s%s\n' "$(wm_pad "$_label" 22)" "$C_DIM" "$_hint" "$C_OFF"
        fi
    done

    printf '\n  %s↑↓ выбор · Enter запустить · 1-%s сразу · q выход%s\n' \
        "$C_DIM" "$(menu_count)" "$C_OFF"
}

# --- keys -------------------------------------------------------------------
# Returns one word: up | down | enter | quit | <digit> | other.
menu_getkey() {
    _c=$(dd bs=1 count=1 2>/dev/null | od -An -tu1 | tr -dc '0-9')
    case $_c in
        '')       printf 'quit\n' ;;                       # stdin closed
        10|13)    printf 'enter\n' ;;
        113|81)   printf 'quit\n' ;;                       # q Q
        107)      printf 'up\n' ;;                         # k
        106)      printf 'down\n' ;;                       # j
        27)
            # An arrow is ESC [ A/B; a bare Esc is just ESC. Read the tail with
            # a timeout so a lone Esc does not block waiting for two more keys.
            stty min 0 time 3 2>/dev/null
            _t=$(dd bs=1 count=2 2>/dev/null | tr -dc 'A-Z')
            stty min 1 time 0 2>/dev/null
            # A bare Esc is ignored, not treated as quit: over a slow link the
            # three bytes of an arrow can arrive split, and losing the screen
            # because a keystroke was late is worse than ignoring an Esc.
            case $_t in
                *A) printf 'up\n' ;;
                *B) printf 'down\n' ;;
                *)  printf 'other\n' ;;
            esac
            ;;
        4[89]|5[0-7]) printf '%s\n' "$(( _c - 48 ))" ;;     # 0-9
        *)        printf 'other\n' ;;
    esac
}

# --- actions ----------------------------------------------------------------
# Every command runs in a subshell: cmd_status and the verbs end in `exit`,
# and without the subshell the first scan would close the menu.
menu_exec() {
    _n=$1
    menu_cooked
    printf '\033[H\033[J\n'
    case $_n in
        1) ( cmd_status ) ;;
        2) ( cmd_init ) ;;
        3) ( cmd_doctor ) ;;
        4) ( cmd_projects list ) ;;
        5) ( registry_init; _p=$(pwd -P)
             if registry_add "$_p"; then ok "в реестре: $_p"; else warn "не удалось добавить: $_p"; fi ) ;;
        6) ( cmd_config show ) ;;
    esac
    printf '\n  %sEnter — назад%s ' "$C_DIM" "$C_OFF"
    read -r _ignored 2>/dev/null || true
    menu_card
    menu_raw
}

# --- loop -------------------------------------------------------------------
menu_run() {
    if ! menu_supported; then
        # Not a terminal: behave exactly as before. This branch is what keeps
        # `fraim` usable from an agent, a pipe, cron and CI.
        usage
        return 0
    fi
    _n=$(menu_count)
    _sel=1
    menu_card
    menu_raw
    trap 'menu_cooked; printf "\n"; exit 0' INT TERM HUP
    while :; do
        menu_draw "$_sel"
        _k=$(menu_getkey)
        case $_k in
            up)    _sel=$((_sel - 1)); [ "$_sel" -lt 1 ] && _sel=$_n ;;
            down)  _sel=$((_sel + 1)); [ "$_sel" -gt "$_n" ] && _sel=1 ;;
            quit)  break ;;
            enter) [ "$_sel" = "$_n" ] && break; menu_exec "$_sel" ;;
            [1-9])
                [ "$_k" -le "$_n" ] || continue
                _sel=$_k
                [ "$_sel" = "$_n" ] && break
                menu_exec "$_sel" ;;
            0)     break ;;
            *)     : ;;
        esac
    done
    menu_cooked
    printf '\033[H\033[J'
    return 0
}
