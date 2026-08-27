#!/bin/sh
# registry.sh — the list of projects the fleet sweep walks.
#
# A plain newline-separated file of absolute paths. Deliberately not a
# database: it is state, but tiny state, and a text file stays readable and
# repairable by hand.

registry_file() { printf '%s/projects\n' "$FRAIM_HOME"; }

registry_init() {
    mkdir -p "$FRAIM_HOME"
    [ -f "$(registry_file)" ] || : > "$(registry_file)"
}

# A project counts as "under the system" when it has the loop directory.
# ai/ is created by bootstrap and by onboard, and by nothing else.
project_is_managed() { [ -d "$1/ai" ]; }

registry_list() {
    _f=$(registry_file)
    [ -f "$_f" ] || return 0
    # Drop blanks and comments; keep the file's own order stable.
    grep -v '^[[:space:]]*$' "$_f" 2>/dev/null | grep -v '^#' || true
}

registry_add() {
    _p=$(cd -- "$1" 2>/dev/null && pwd -P) || { warn "нет такого каталога: $1"; return 1; }
    registry_init
    if registry_list | grep -qxF "$_p"; then
        return 0
    fi
    printf '%s\n' "$_p" >> "$(registry_file)"
    return 0
}

registry_rm() {
    _p=$(cd -- "$1" 2>/dev/null && pwd -P) || _p=$1
    registry_init
    _f=$(registry_file)
    _tmp="$_f.tmp.$$"
    grep -vxF "$_p" "$_f" > "$_tmp" 2>/dev/null || : > "$_tmp"
    mv "$_tmp" "$_f"
}

# Drop entries whose directory is gone. Called by doctor, never silently:
# a project moved on disk is something the operator should hear about.
registry_stale() {
    registry_list | while read -r _p; do
        [ -d "$_p" ] || printf '%s\n' "$_p"
    done
}
