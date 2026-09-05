#!/bin/sh
# core.sh — paths, output, and the frontmatter reader every other module builds on.
#
# The frontmatter of each procedure is the single source of truth for the
# procedure list: name, description and model tier all live there, so no
# generator ever hardcodes the roster (HARNESS_TARGETS.md, "Нужен манифест").

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
    _r=$(fraim_root) || die "не найден каталог procedures/ — установка повреждена"
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
