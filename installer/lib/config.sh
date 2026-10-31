#!/bin/sh
# config.sh — settings on two levels, and the ability to say where a value came from.
#
#   default        baked in here
#   machine        ~/.fraim/config       — per machine, not in git
#   project        ai/fraim.conf         — travels with the repository
#
# Project beats machine beats default. The point of `fraim config` is not to show a file
# but to answer "what is in effect right now, and who set it" — that is what makes
# settings legible to someone who did not write them.
#
# Format is `key = value`, one per line, `#` comments. Deliberately not JSON or YAML:
# it must stay editable by hand and parsable without a dependency.

# key|default|section|type   (the description is the catalog message cfg_desc_<key>)
#
# section: general · watchman · saving · fleet · expert — the order of the settings screen.
# type:    on/off · int · enum:<a>,<b> · text — what `fraim config set` accepts.
#
# Twenty keys used to sit here in one flat list; several said the same thing (check_update,
# update_check), several could not sensibly be turned off (check_git, check_language), and
# a threshold came with its own on/off switch. Now a threshold of 0 means «do not check»,
# one key answers one question, and the retired names are still read — see config_legacy.
config_table() {
    cat <<'TBL'
lang||general|lang
updates|notify|general|enum:notify,off
update_check_days|1|general|int
foundation_lag_commits|10|watchman|int
lessons_lag_commits|25|watchman|int
unpushed_threshold|5|watchman|int
check_parallel|on|watchman|on/off
abandon_after_days|30|watchman|int
commit_verbs|on|saving|on/off
build_check||fleet|text
fleet_ready_timeout|120|fleet|int
check_dirty|on|expert|on/off
check_investigations|on|expert|on/off
check_shape|on|expert|on/off
TBL
}

# Open-ended key families: a key per agent or per procedure. Shown in `fraim config`,
# accepted by `fraim config set`, never listed one by one in config_table.
# prefix|section   (the description is the catalog message cfg_fam_<prefix without _>)
config_families() {
    cat <<'FAM'
tier_|models
role_|models
launchcmd_|expert
readypattern_|expert
modelcmd_|expert
FAM
}

# Retired names. Still read, so no project breaks: an old ai/fraim.conf with
# `check_foundation = off` keeps the check off. Never written — `fraim config set` on one
# of them names the key that replaced it.
# old|new|how the old value maps
config_legacy() {
    cat <<'LEG'
check_update|updates|off→off
update_check|updates|off→off
check_foundation|foundation_lag_commits|off→0
check_lessons|lessons_lag_commits|off→0
check_remote|unpushed_threshold|off→0
check_worktrees|check_parallel|off→off
check_ade|check_parallel|off→off
fleet_ready_timeout_ms|fleet_ready_timeout|ms→s
check_git||always on
check_language||always on
LEG
}

config_machine_file() { printf '%s/config\n' "$FRAIM_HOME"; }
config_project_file() { printf '%s/ai/fraim.conf\n' "$1"; }

config_default()  { config_table | awk -F'|' -v k="$1" '$1 == k { print $2; exit }'; }
config_section()  { config_table | awk -F'|' -v k="$1" '$1 == k { print $3; exit }'; }
config_type()     { config_table | awk -F'|' -v k="$1" '$1 == k { print $4; exit }'; }
config_describe() { t "cfg_desc_$1"; }
config_known()    { config_table | cut -d'|' -f1 | grep -qx "$1"; }

# The family a key belongs to (tier_, role_, launchcmd_…), or nothing.
config_family() {
    config_families | while IFS='|' read -r _cf_p _cf_s; do
        case $1 in "$_cf_p"?*) printf '%s\n' "$_cf_p"; break ;; esac
    done
}

# The key that replaced a retired one; empty output and status 1 when it is not retired.
config_replacement() {
    _cr_line=$(config_legacy | awk -F'|' -v k="$1" '$1 == k { print; exit }')
    [ -n "$_cr_line" ] || return 1
    printf '%s\n' "$_cr_line" | cut -d'|' -f2
}

# Read one key from one file. Empty output means "not set here".
config_read_file() {
    _f=$1; _k=$2
    [ -f "$_f" ] || return 0
    sed -n "s/^[[:space:]]*$_k[[:space:]]*=[[:space:]]*//p" "$_f" 2>/dev/null |
        sed 's/[[:space:]]*$//; s/[[:space:]]*#.*$//' | head -1
}

# A value set explicitly in the project or on the machine (project wins); empty when
# neither file sets it.
config_explicit() {
    _ce_root=${2:-}; _ce_k=$1; _ce_v=
    if [ -n "$_ce_root" ]; then
        _ce_v=$(config_read_file "$(config_project_file "$_ce_root")" "$_ce_k")
    fi
    [ -n "$_ce_v" ] || _ce_v=$(config_read_file "$(config_machine_file)" "$_ce_k")
    printf '%s\n' "$_ce_v"
}

# What the retired keys say about a current one, or nothing. A retired switch only ever
# matters when it was turned off: on was its default.
config_from_legacy() {
    _cl_root=${2:-}; _cl_k=$1
    _cl_rows=$(config_legacy | awk -F'|' -v k="$_cl_k" '$2 == k')
    [ -n "$_cl_rows" ] || return 0
    _cl_ifs=$IFS
    IFS='
'
    for _cl_row in $_cl_rows; do
        IFS=$_cl_ifs
        _cl_old=${_cl_row%%|*}
        _cl_map=${_cl_row##*|}
        _cl_v=$(config_explicit "$_cl_old" "$_cl_root")
        [ -n "$_cl_v" ] || continue
        case $_cl_map in
            'off→off') [ "$_cl_v" = off ] && { printf 'off\n'; return 0; } ;;
            'off→0')   [ "$_cl_v" = off ] && { printf '0\n'; return 0; } ;;
            'ms→s')    case $_cl_v in *[!0-9]*) ;; *) printf '%s\n' $(( (_cl_v + 999) / 1000 )); return 0 ;; esac ;;
        esac
    done
    IFS=$_cl_ifs
    return 0
}

# The effective value. Project wins, then machine, then what a retired key said, then the
# built-in default.
config_get() {
    _root=${2:-}; _k=$1
    _v=$(config_explicit "$_k" "$_root")
    [ -n "$_v" ] && { printf '%s\n' "$_v"; return; }
    _v=$(config_from_legacy "$_k" "$_root")
    [ -n "$_v" ] && { printf '%s\n' "$_v"; return; }
    config_default "$_k"
}

# Validate a value against the key's type. Silent; status 1 when it does not fit.
config_valid() {
    case $(config_type "$1") in
        on/off) case $2 in on|off) return 0 ;; esac; return 1 ;;
        int)    case $2 in ''|*[!0-9]*) return 1 ;; esac; return 0 ;;
        lang)   [ -z "$2" ] || [ "$2" = auto ] && return 0
                i18n_languages | cut -d'|' -f1 | grep -qxF -- "$2" ;;
        enum:*) _cv_set=$(config_type "$1"); _cv_set=${_cv_set#enum:}
                printf '%s\n' "$_cv_set" | tr ',' '\n' | grep -qxF -- "$2" ;;
        *)      return 0 ;;
    esac
}

# Where the effective value came from: project path, machine, a retired key, or default.
config_source() {
    _root=${2:-}; _k=$1
    if [ -n "$_root" ] && [ -n "$(config_read_file "$(config_project_file "$_root")" "$_k")" ]; then
        printf 'ai/fraim.conf\n'; return
    fi
    if [ -n "$(config_read_file "$(config_machine_file)" "$_k")" ]; then
        printf '~/.fraim/config\n'; return
    fi
    if [ -n "$(config_from_legacy "$_k" "$_root")" ]; then
        t cfg_src_legacy; printf '\n'; return
    fi
    t cfg_src_default; printf '\n'
}

# A threshold check is on unless its threshold is 0.
config_threshold_on() { [ "$(config_get "$1" "${2:-}")" != 0 ]; }

config_is_on() { [ "$(config_get "$1" "${2:-}")" = on ]; }

# Remove a key from one of the two files (back to what the next level says).
config_unset_file() {
    _f=$1; _k=$2
    [ -f "$_f" ] || return 0
    _tmp="$_f.fraim.$$"
    grep -v "^[[:space:]]*$_k[[:space:]]*=" "$_f" > "$_tmp" 2>/dev/null || : > "$_tmp"
    mv "$_tmp" "$_f"
}

# The commented list of defaults in ai/fraim.conf, rewritten from config_table. Settings
# the project actually made (uncommented lines) are kept as they are, in their order;
# comments for retired keys go. Prints «changed» when the file was rewritten.
config_conf_refresh() {
    _cr_f=$(config_project_file "$1")
    [ -f "$_cr_f" ] || return 0
    _cr_tmp="$_cr_f.fraim.$$"
    {
        config_conf_header
        grep -v '^[[:space:]]*#' "$_cr_f" | grep '[^[:space:]]' || :
        printf '#\n'
        config_table | while IFS='|' read -r _cr_k _cr_v _cr_s _cr_t; do
            [ -n "$(config_read_file "$_cr_f" "$_cr_k")" ] && continue
            printf '# %s = %s\n' "$_cr_k" "$_cr_v"
        done
    } > "$_cr_tmp"
    if cmp -s "$_cr_tmp" "$_cr_f"; then rm -f "$_cr_tmp"; return 0; fi
    mv "$_cr_tmp" "$_cr_f"
    printf 'changed\n'
}

config_conf_header() {
    printf '# fraim — settings of this project. They travel in git with the repository.\n'
    printf '# What is in effect and where it came from, with descriptions: fraim config\n'
}

# Write a key into one of the two files, replacing any existing line.
config_set_file() {
    _f=$1; _k=$2; _v=$3
    mkdir -p "$(dirname -- "$_f")" || return 1
    [ -f "$_f" ] || printf '# fraim settings — see `fraim config`\n' > "$_f"
    _tmp="$_f.fraim.$$"
    grep -v "^[[:space:]]*$_k[[:space:]]*=" "$_f" > "$_tmp" 2>/dev/null || : > "$_tmp"
    printf '%s = %s\n' "$_k" "$_v" >> "$_tmp"
    mv "$_tmp" "$_f"
}
