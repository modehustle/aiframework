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
# Every variable here is prefixed `_menu_`. POSIX sh has no locals, and the watchman
# writes plain `_w`, `_n`, `_msg` while it works: a card that computed its width before
# calling wm_run got «Illegal number: точек сохранения» and rendered one blank line —
# on exactly the projects that have the most to report.
menu_width() {
    _menu_cols=$(tput cols 2>/dev/null) || _menu_cols=
    case $_menu_cols in ''|*[!0-9]*) _menu_cols=80 ;; esac
    [ "$_menu_cols" -gt 78 ] && _menu_cols=78
    [ "$_menu_cols" -lt 44 ] && _menu_cols=44
    printf '%s\n' "$_menu_cols"
}

# Cut a string to a display width, adding an ellipsis. The verdict on a live project can
# be thirty lines long and each line longer than the terminal; a card that wraps is not a
# card. What does not fit is still reachable — item 1 prints the full verdict.
menu_clip() {
    _menu_s=$1; _menu_max=$2
    _menu_len=$(str_len "$_menu_s")
    if [ "$_menu_len" -le "$_menu_max" ]; then
        printf '%s' "$_menu_s"; return
    fi
    # Cut at the colon rather than at a column: every long finding is «что случилось: с
    # чем именно», and the head is the half worth keeping. Cutting by column would need a
    # character-aware `cut`, which in the C locale counts bytes and slices Cyrillic in half.
    _menu_head=${_menu_s%%:*}
    if [ "$_menu_head" != "$_menu_s" ] &&
       [ "$(str_len "$_menu_head")" -le "$_menu_max" ]; then
        printf '%s: …' "$_menu_head"; return
    fi
    printf '%s…' "$(printf '%s' "$_menu_s" | cut -c1-$(( _menu_max - 1 )) 2>/dev/null ||
                    printf '%s' "$_menu_s")"
}

menu_rule() {
    _menu_n=$1; _menu_out=
    while [ "$_menu_n" -gt 0 ]; do _menu_out="$_menu_out─"; _menu_n=$((_menu_n - 1)); done
    printf '%s' "$_menu_out"
}

# The title bar. Reverse video across the full width is what makes this read as
# a screen rather than as scrollback, and it costs one escape sequence.
menu_bar() {
    _menu_w=$1; _menu_left=$2; _menu_right=$3
    _menu_pad=$(( _menu_w - 2 - $(str_len "$_menu_left") - $(str_len "$_menu_right") - 1 ))
    [ "$_menu_pad" -lt 1 ] && _menu_pad=1
    printf '\033[7m %s' "$_menu_left"
    while [ "$_menu_pad" -gt 0 ]; do printf ' '; _menu_pad=$((_menu_pad - 1)); done
    printf '%s \033[0m\n' "$_menu_right"
}

# --- items ------------------------------------------------------------------
# label \t hint. The action lives in menu_exec, keyed by the same index, so
# adding an entry means one line here and one branch there. The agent-launch
# work goes in as items 7+ without touching anything else.
menu_items() {
    cat <<'ITEMS'
Скан проекта	что происходит здесь и сейчас
Чистка	прибрать всё, что чинится без суждения
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
MENU_CARD_LINES=6
menu_card() {
    _menu_root=$(pwd -P)
    if wm_managed "$_menu_root"; then
        WM_FINDINGS=
        wm_run "$_menu_root"
    else
        WM_FINDINGS=
    fi
    # Width AFTER wm_run: the watchman writes globals while it works.
    _menu_w=$(menu_width)
    _menu_body=$(
        if ! wm_managed "$_menu_root"; then
            printf '  %s·%s каталог не под системой — %s/onboard%s или %sfraim scaffold%s\n' \
                "$C_DIM" "$C_OFF" "$C_BLD" "$C_OFF" "$C_BLD" "$C_OFF"
        elif [ -z "$WM_FINDINGS" ]; then
            printf '  %s✓%s всё чисто\n' "$C_GRN" "$C_OFF"
        else
            _menu_shown=0
            printf '%s\n' "$WM_FINDINGS" | while IFS='	' read -r _menu_id _menu_sev _menu_msg _menu_act; do
                [ -n "$_menu_id" ] || continue
                _menu_shown=$((_menu_shown + 1))
                [ "$_menu_shown" -gt "$MENU_CARD_LINES" ] && continue
                if [ "$_menu_sev" = attention ]; then _menu_m="$C_YEL!$C_OFF"
                else _menu_m="$C_DIM·$C_OFF"; fi
                printf '  %s %s\n' "$_menu_m" "$(menu_clip "$_menu_msg" $(( _menu_w - 6 )))"
            done
            _menu_total=$(printf '%s\n' "$WM_FINDINGS" | grep -c '[^[:space:]]' || true)
            if [ "${_menu_total:-0}" -gt "$MENU_CARD_LINES" ]; then
                printf '    %s…и ещё %s — «Скан проекта» покажет всё%s\n' \
                    "$C_DIM" "$(( _menu_total - MENU_CARD_LINES ))" "$C_OFF"
            fi
        fi
    )
    MENU_CARD=$_menu_body
}

menu_draw() {
    _menu_sel=$1
    _menu_w=$(menu_width)

    printf '\033[H\033[J'
    printf '\n'
    menu_bar "$_menu_w" "▌ FRAIM $(fraim_version)" "$(basename -- "$(pwd -P)")"
    printf '\n'
    printf '%s\n' "$MENU_CARD"
    printf '\n  %s%s%s\n\n' "$C_DIM" "$(menu_rule $(( _menu_w - 2 )))" "$C_OFF"

    _menu_i=0
    menu_items | while IFS='	' read -r _menu_label _menu_hint; do
        _menu_i=$((_menu_i + 1))
        if [ "$_menu_i" = "$_menu_sel" ]; then
            printf '  %s%s▸ %s%s  %s%s%s\n' "$C_BLD" "$C_GRN" \
                "$(wm_pad "$_menu_label" 22)" "$C_OFF" "$C_DIM" "$_menu_hint" "$C_OFF"
        else
            printf '    %s  %s%s%s\n' "$(wm_pad "$_menu_label" 22)" "$C_DIM" "$_menu_hint" "$C_OFF"
        fi
    done

    printf '\n  %s↑↓ выбор · Enter запустить · 1-%s сразу · q выход%s\n' \
        "$C_DIM" "$(menu_count)" "$C_OFF"
}

# --- keys -------------------------------------------------------------------
# Returns one word: up | down | enter | quit | <digit> | other.
#
# Every variable here is `_menu_`-prefixed for the same reason as the drawing
# primitives: this runs inside a command substitution today, but one refactor
# away from running in the loop's own shell, where a bare `_t` or `_c` would
# land in the middle of the watchman's namespace.
menu_getkey() {
    _menu_c=$(dd bs=1 count=1 2>/dev/null | od -An -tu1 | tr -dc '0-9')
    case $_menu_c in
        '')       printf 'quit\n' ;;                       # stdin closed
        10|13)    printf 'enter\n' ;;
        113|81)   printf 'quit\n' ;;                       # q Q
        107)      printf 'up\n' ;;                         # k
        106)      printf 'down\n' ;;                       # j
        27)
            # An arrow is ESC [ A/B; a bare Esc is just ESC. Read the tail with
            # a timeout so a lone Esc does not block waiting for two more keys.
            stty min 0 time 3 2>/dev/null
            _menu_t=$(dd bs=1 count=2 2>/dev/null | tr -dc 'A-Z')
            stty min 1 time 0 2>/dev/null
            # A bare Esc is ignored, not treated as quit: over a slow link the
            # three bytes of an arrow can arrive split, and losing the screen
            # because a keystroke was late is worse than ignoring an Esc.
            case $_menu_t in
                *A) printf 'up\n' ;;
                *B) printf 'down\n' ;;
                *)  printf 'other\n' ;;
            esac
            ;;
        4[89]|5[0-7]) printf '%s\n' "$(( _menu_c - 48 ))" ;;     # 0-9
        *)        printf 'other\n' ;;
    esac
}

# --- actions ----------------------------------------------------------------
# Every command runs in a subshell: cmd_status and the verbs end in `exit`,
# and without the subshell the first scan would close the menu.
#
# And every subshell ends in `|| true`, which is not belt-and-braces: the CLI runs
# under `set -e`, and `fraim status` exits 1 whenever the project has anything
# needing the human — the normal case for the person who opened the menu to look.
# Without it, choosing «Скан проекта» printed the verdict and then killed the whole
# process mid-screen, leaving the terminal in raw mode with the cursor hidden. The
# menu must survive every exit code its own items produce, including the refusals
# that are answers rather than failures.
menu_exec() {
    _menu_choice=$1
    menu_cooked
    printf '\033[H\033[J\n'
    case $_menu_choice in
        1) ( cmd_status ) || true ;;
        2) ( cmd_clean ) || true ;;
        3) ( cmd_init ) || true ;;
        4) ( cmd_doctor ) || true ;;
        5) ( cmd_projects list ) || true ;;
        6) ( registry_init; _menu_p=$(pwd -P)
             if registry_add "$_menu_p"; then ok "в реестре: $_menu_p"; else warn "не удалось добавить: $_menu_p"; fi ) || true ;;
        7) ( cmd_config show ) || true ;;
    esac
    printf '\n  %sEnter — назад%s ' "$C_DIM" "$C_OFF"
    read -r _menu_ignored 2>/dev/null || true
    menu_card
    menu_raw
}

# --- loop -------------------------------------------------------------------
# The loop's own state is UPPERCASE on purpose, like MENU_CARD and MENU_STTY.
# It has to survive calls into the watchman (menu_card) and into every command
# (menu_exec), and POSIX sh has no locals: `_n` held the number of items until
# menu_card ran the watchman, whose queue check writes a plain `_n` of its own.
# From that moment the item count was 0, so `[ "$_sel" -gt "$_n" ]` was true on
# every arrow and put the cursor back on line 1 — the menu redrew perfectly and
# never moved — while `[ "$_k" -le "$_n" ]` rejected every digit, so 1-8 did
# nothing either. A prefix is not enough here; only a namespace no other module
# writes is.
MENU_SEL=1
MENU_N=0
MENU_KEY=
menu_run() {
    if ! menu_supported; then
        # Not a terminal: behave exactly as before. This branch is what keeps
        # `fraim` usable from an agent, a pipe, cron and CI.
        usage
        return 0
    fi
    MENU_N=$(menu_count)
    MENU_SEL=1
    menu_card
    menu_raw
    # EXIT as well as the signals: whatever ends this process — a signal, an
    # unexpected non-zero under `set -e`, a plain return — must not leave the
    # operator with a terminal that has no echo and no cursor.
    trap 'menu_cooked' EXIT
    trap 'menu_cooked; printf "\n"; exit 0' INT TERM HUP
    while :; do
        menu_draw "$MENU_SEL"
        MENU_KEY=$(menu_getkey)
        case $MENU_KEY in
            up)    MENU_SEL=$((MENU_SEL - 1)); [ "$MENU_SEL" -lt 1 ] && MENU_SEL=$MENU_N ;;
            down)  MENU_SEL=$((MENU_SEL + 1)); [ "$MENU_SEL" -gt "$MENU_N" ] && MENU_SEL=1 ;;
            quit)  break ;;
            enter) [ "$MENU_SEL" = "$MENU_N" ] && break; menu_exec "$MENU_SEL" ;;
            [1-9])
                [ "$MENU_KEY" -le "$MENU_N" ] || continue
                MENU_SEL=$MENU_KEY
                [ "$MENU_SEL" = "$MENU_N" ] && break
                menu_exec "$MENU_SEL" ;;
            0)     break ;;
            *)     : ;;
        esac
    done
    menu_cooked
    printf '\033[H\033[J'
    return 0
}
