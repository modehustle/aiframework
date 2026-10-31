#!/bin/sh
# core.sh — paths, output, and the frontmatter reader every other module builds on.
#
# The frontmatter of each procedure is the single source of truth for the
# procedure list: name, description and model tier all live there, so no
# generator ever hardcodes the roster (HARNESS_TARGETS.md, "A manifest is needed").

FRAIM_NAME=fraim
FRAIM_HOME=${FRAIM_HOME:-$HOME/.fraim}

# --- output -----------------------------------------------------------------
# Colour only when stdout is a terminal, so piped and cron output stays clean.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_DIM=$(printf '\033[2m');  C_RED=$(printf '\033[31m')
    C_YEL=$(printf '\033[33m'); C_GRN=$(printf '\033[32m')
    C_BLD=$(printf '\033[1m');  C_OFF=$(printf '\033[0m')
else
    C_DIM=; C_RED=; C_YEL=; C_GRN=; C_BLD=; C_OFF=
fi

# Display width in CHARACTERS, in any locale. `wc -m` counts characters only when the
# locale says the input is multibyte; under LC_ALL=C — cron, CI, a server with no locale
# set — it counts bytes, and every Cyrillic character counts twice. That silently halved
# every column and clipped Russian messages mid-sentence. Dropping UTF-8 continuation
# bytes (10xxxxxx) leaves exactly one byte per character, and octal ranges in `tr` are
# POSIX, so this needs no locale at all.
str_len() {
    printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | LC_ALL=C wc -c | tr -d ' '
}

# Display width in terminal COLUMNS. CJK ideographs, kana and Hangul take two columns
# each; str_len counts them as one, and a Chinese or Japanese label sheared every column
# after it. Their UTF-8 lead bytes are \343-\355 (U+3000–U+DFFF) — counting those bytes
# adds the second column, again with no locale.
str_width() {
    _sw_n=$(str_len "$1")
    _sw_w=$(printf '%s' "$1" | LC_ALL=C tr -cd '\343-\355' | LC_ALL=C wc -c | tr -d ' ')
    printf '%s\n' $(( _sw_n + _sw_w ))
}

say()  { printf '%s\n' "$*"; }
dim()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }
ok()   { printf '%s✓%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()  { printf '%s✗%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 2; }

# --- locating ourselves -----------------------------------------------------
# Follow symlinks by hand: readlink -f is GNU-only and missing on macOS.
fraim_resolve() {
    _p=$1
    while [ -L "$_p" ]; do
        _d=$(dirname -- "$_p")
        _l=$(readlink -- "$_p")
        case $_l in
            /*) _p=$_l ;;
            *)  _p=$_d/$_l ;;
        esac
    done
    _d=$(cd -- "$(dirname -- "$_p")" && pwd -P) || return 1
    printf '%s/%s\n' "$_d" "$(basename -- "$_p")"
}

# FRAIM_ROOT is the source tree: the directory holding procedures/ and installer/.
fraim_root() {
    [ -n "${FRAIM_ROOT:-}" ] && { printf '%s\n' "$FRAIM_ROOT"; return 0; }
    _self=$(fraim_resolve "$0") || return 1
    _root=$(cd -- "$(dirname -- "$_self")/../.." && pwd -P) || return 1
    [ -d "$_root/procedures" ] || return 1
    printf '%s\n' "$_root"
}

fraim_version() {
    _r=$(fraim_root) || { printf 'unknown\n'; return; }
    if [ -f "$_r/installer/VERSION" ]; then
        tr -d ' \n\r' < "$_r/installer/VERSION"; printf '\n'
    else
        printf 'unknown\n'
    fi
}

# --- frontmatter ------------------------------------------------------------
# Reads one key out of the leading `---` block. Handles both top-level keys
# (name, description) and the two-space-indented keys under `metadata:`.
# Deliberately not a YAML parser: the frontmatter we generate is flat by
# construction, and a real parser would mean a runtime dependency.
fm_get() {
    _file=$1; _key=$2
    awk -v key="$_key" '
        NR == 1 && $0 != "---" { exit 1 }
        NR == 1 { next }
        $0 == "---" { exit }
        {
            line = $0
            sub(/^[ \t]+/, "", line)
            idx = index(line, ":")
            if (idx == 0) next
            k = substr(line, 1, idx - 1)
            if (k != key) next
            v = substr(line, idx + 1)
            sub(/^[ \t]+/, "", v)
            sub(/[ \t]+$/, "", v)
            # A double-quoted YAML scalar: strip the quotes and unescape.
            # Descriptions must be quoted because they contain colons, which
            # an unquoted scalar reads as a mapping and fails to parse.
            if (v ~ /^".*"$/) {
                v = substr(v, 2, length(v) - 2)
                gsub(/\\"/, "\"", v)
                gsub(/\\\\/, "\\", v)
            }
            print v
            exit
        }
    ' "$_file"
}

# Every procedure, ordered by metadata.order. Emits one name per line.
# This is the roster: everything that enumerates procedures goes through here.
fraim_procedures() {
    _r=$(fraim_root) || die "$(t core_no_procedures)"
    for _f in "$_r"/procedures/*.md; do
        [ -f "$_f" ] || continue
        _n=$(fm_get "$_f" name)
        _o=$(fm_get "$_f" order)
        [ -n "$_n" ] || continue
        printf '%s\t%s\n' "${_o:-99}" "$_n"
    done | sort -n | cut -f2
}

fraim_procedure_file() {
    _r=$(fraim_root) || return 1
    _f="$_r/procedures/$1.md"
    [ -f "$_f" ] || return 1
    printf '%s\n' "$_f"
}

# --- the operator's language ---------------------------------------------------
# Everything the CLI says to the HUMAN comes from a message catalog; everything it writes
# for the AGENT or into a project stays English in the code (CONVENTIONS, «Language»).
#
#   installer/locale/en/<module>.sh     the source: M_<key>='text'
#   installer/locale/<lang>/<module>.sh the same keys, translated; a missing one falls
#                                       back to English, a missing English one to the key
#   installer/locale/languages          code|native name|status — what the picker offers
#
# The language: FRAIM_LANG, then `lang` in ~/.fraim/config (the operator's, never a
# project's — a project travels to other people), then LC_ALL / LC_MESSAGES / LANG, then
# English. Catalogs are plain shell, sourced once at start: a lookup is one `eval`, no
# fork, which matters in a screen that redraws on every key.
I18N_LANG=
i18n_dir() {
    if [ -n "${FRAIM_LOCALE_DIR:-}" ]; then printf '%s\n' "$FRAIM_LOCALE_DIR"; return; fi
    _i18n_r=$(fraim_root 2>/dev/null) || return 1
    printf '%s/installer/locale\n' "$_i18n_r"
}

# Map a POSIX locale name (pt_BR.UTF-8, zh_CN, de_DE@euro) or a code (pt-BR) to a code
# we ship, or nothing.
i18n_match() {
    _im_dir=$1; _im_v=${2%%.*}; _im_v=${_im_v%%@*}
    case $_im_v in ''|C|POSIX) return 0 ;; esac
    _im_v=$(printf '%s' "$_im_v" | tr '_' '-')
    _im_lang=${_im_v%%-*}
    # Exact code first (pt-BR, zh-CN), then the language alone (de-AT → de, pt-PT → pt-BR,
    # zh-SG → zh-CN): a near variant reads better than English for most people.
    for _im_try in "$_im_v" "$_im_lang"; do
        [ -d "$_im_dir/$_im_try" ] && { printf '%s\n' "$_im_try"; return 0; }
    done
    for _im_d in "$_im_dir"/"$_im_lang"-*; do
        [ -d "$_im_d" ] && { basename -- "$_im_d"; return 0; }
    done
    return 0
}

# The configured language or nothing (auto). Read straight from the file: core.sh comes
# before config.sh.
i18n_configured() {
    [ -f "$FRAIM_HOME/config" ] || return 0
    sed -n 's/^[[:space:]]*lang[[:space:]]*=[[:space:]]*//p' "$FRAIM_HOME/config" 2>/dev/null |
        sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//' | head -1
}

i18n_detect() {
    _id_dir=$1
    # An explicit choice that we do not ship gives English, not the system's locale: that
    # is the honest answer to «I asked for X».
    for _id_v in "${FRAIM_LANG:-}" "$(i18n_configured)"; do
        [ -n "$_id_v" ] || continue
        _id_m=$(i18n_match "$_id_dir" "$_id_v")
        printf '%s\n' "${_id_m:-en}"; return 0
    done
    for _id_v in "${LC_ALL:-}" "${LC_MESSAGES:-}" "${LANG:-}"; do
        [ -n "$_id_v" ] || continue
        _id_m=$(i18n_match "$_id_dir" "$_id_v")
        [ -n "$_id_m" ] && { printf '%s\n' "$_id_m"; return 0; }
    done
    printf 'en\n'
}

i18n_load() {
    _il_dir=$(i18n_dir) || { I18N_LANG=en; return 0; }
    I18N_LANG=$(i18n_detect "$_il_dir")
    for _il_f in "$_il_dir"/en/*.sh; do [ -f "$_il_f" ] && . "$_il_f"; done
    if [ "$I18N_LANG" != en ]; then
        for _il_f in "$_il_dir/$I18N_LANG"/*.sh; do [ -f "$_il_f" ] && . "$_il_f"; done
    fi
    return 0
}

# The languages we ship: code|native name|status, in the picker's order.
i18n_languages() {
    _ils_dir=$(i18n_dir) || return 0
    [ -f "$_ils_dir/languages" ] || return 0
    grep -v '^#' "$_ils_dir/languages" | grep '|'
}

# t KEY [name=value]… — the message, with {name} replaced. No trailing newline, so it
# composes: say "$(t KEY)", die "$(t KEY path="$p")".
t() {
    _t_k=$1; shift
    eval "_t_s=\${M_$_t_k-}"
    [ -n "$_t_s" ] || _t_s=$_t_k
    for _t_a in "$@"; do
        _t_n=${_t_a%%=*}; _t_v=${_t_a#*=}
        _t_out=
        while :; do
            case $_t_s in
                *"{$_t_n}"*) _t_out=$_t_out${_t_s%%"{$_t_n}"*}$_t_v; _t_s=${_t_s#*"{$_t_n}"} ;;
                *) break ;;
            esac
        done
        _t_s=$_t_out$_t_s
    done
    printf '%s' "$_t_s"
}

# The plural category of N in the current language: one | few | many | other.
i18n_plural() {
    _ip_n=$1
    case $I18N_LANG in
        ru|uk|pl)
            _ip_10=$(( _ip_n % 10 )); _ip_100=$(( _ip_n % 100 ))
            if [ "$_ip_100" -ge 11 ] && [ "$_ip_100" -le 14 ]; then printf 'many'
            elif [ "$_ip_10" = 1 ] && [ "$I18N_LANG" != pl ]; then printf 'one'
            elif [ "$_ip_n" = 1 ]; then printf 'one'
            elif [ "$_ip_10" -ge 2 ] && [ "$_ip_10" -le 4 ]; then printf 'few'
            else printf 'many'; fi ;;
        fr|pt-BR) if [ "$_ip_n" -le 1 ]; then printf 'one'; else printf 'other'; fi ;;
        zh-CN|ja|ko|tr) printf 'other' ;;
        *)  if [ "$_ip_n" = 1 ]; then printf 'one'; else printf 'other'; fi ;;
    esac
}

# tp N KEY [name=value]… — the plural form of KEY for N, with {n} set. A catalog defines
# KEY_one, KEY_few, KEY_many, KEY_other as its language needs; a missing form falls back
# to _other, then _many, then _one.
tp() {
    _tp_n=$1; _tp_k=$2; shift 2
    _tp_c=$(i18n_plural "$_tp_n")
    for _tp_f in "$_tp_c" other many one; do
        eval "_tp_s=\${M_${_tp_k}_$_tp_f-}"
        [ -n "$_tp_s" ] && { t "${_tp_k}_$_tp_f" n="$_tp_n" "$@"; return 0; }
    done
    t "$_tp_k" n="$_tp_n" "$@"
}

i18n_load
