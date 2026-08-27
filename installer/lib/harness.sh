#!/bin/sh
# harness.sh — where each target agent keeps its skills, and how we notice it.
#
# One artifact (an Agent Skills directory) covers every P0 harness; the only
# thing that differs is the destination path and the global instructions file.
# So the harness layer is a table, not code. Adding a harness is adding a row.

# Columns, tab-separated:
#   key   label   probe   skills-dir   instructions-file
# probe  — a binary name on PATH, or a directory; the harness counts as present
#          if either the binary resolves or the directory exists.
# instructions-file — the harness's GLOBAL context file, where we leave the
#          pointer block. Empty means the harness has no global one.
harness_table() {
    cat <<'TBL'
hermes	Hermes Agent	hermes	$HOME/.hermes/skills	$HOME/.hermes/AGENTS.md
claude	Claude Code	claude	$HOME/.claude/skills	$HOME/.claude/CLAUDE.md
codex	Codex	codex	$HOME/.codex/skills	$HOME/.codex/AGENTS.md
omp	omp	omp	$HOME/.omp/skills	$HOME/.omp/AGENTS.md
pi	pi	pi	$HOME/.pi/skills	$HOME/.pi/AGENTS.md
devin	Devin CLI	devin	$HOME/.devin/skills	$HOME/.devin/AGENTS.md
TBL
}

# Expand the literal $HOME in a table cell without eval'ing arbitrary text.
harness_expand() { printf '%s\n' "$1" | sed "s|\$HOME|$HOME|g"; }

# A harness is present if its binary is on PATH or its home directory exists.
# Both matter: a harness may be installed but not yet on PATH in this shell,
# and it may be on PATH before it has ever been run.
harness_present() {
    _probe=$1; _skills=$2
    command -v "$_probe" >/dev/null 2>&1 && return 0
    _home=$(dirname -- "$_skills")
    [ -d "$_home" ] && return 0
    return 1
}

# Emit one line per detected harness: key<TAB>label<TAB>skills-dir<TAB>instructions
harness_detect() {
    harness_table | while IFS='	' read -r _key _label _probe _skills _instr; do
        [ -n "$_key" ] || continue
        _skills=$(harness_expand "$_skills")
        _instr=$(harness_expand "$_instr")
        if harness_present "$_probe" "$_skills"; then
            printf '%s\t%s\t%s\t%s\n' "$_key" "$_label" "$_skills" "$_instr"
        fi
    done
}

# Copy the built skill tree into one harness's skills directory.
# Only fraim-owned skills are touched: each is identified by `source: fraim`
# in its frontmatter, so a stale one from an older version is removed while
# the user's own skills next to it are left alone.
harness_install() {
    _label=$1; _dest=$2; _build=$3
    mkdir -p "$_dest" || { warn "$_label: не удалось создать $_dest"; return 1; }

    # Remove skills we own that no longer exist upstream.
    for _d in "$_dest"/*/; do
        [ -d "$_d" ] || continue
        _n=$(basename -- "$_d")
        [ -f "$_d/SKILL.md" ] || continue
        grep -q '^  source: fraim$' "$_d/SKILL.md" 2>/dev/null || continue
        [ -d "$_build/$_n" ] || rm -rf "$_d"
    done

    _n_installed=0
    for _s in "$_build"/*/; do
        [ -d "$_s" ] || continue
        _n=$(basename -- "$_s")
        mkdir -p "$_dest/$_n"
        cp "$_s/SKILL.md" "$_dest/$_n/SKILL.md" || return 1
        _n_installed=$((_n_installed + 1))
    done
    printf '%s\n' "$_n_installed"
}
