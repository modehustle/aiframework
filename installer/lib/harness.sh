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
#          pointer block. `-` means the harness has no global one on disk (its
#          rules live in a settings screen); never leave the cell empty — a tab
#          separator collapses empty fields.
#
# Antigravity is the one row where neither cell is the obvious one, and both
# choices are load-bearing:
#
#   · the binary is `agy`, not `antigravity` — that is the name its installer
#     puts on PATH;
#   · skills go to `~/.gemini/config/skills`, which is the single directory all
#     three flavours read (IDE, CLI, and the agent itself). The older paths —
#     `~/.gemini/skills`, `~/.gemini/antigravity/global_skills`,
#     `~/.gemini/antigravity-cli/skills` — are each read by only some of them;
#   · the pointer block goes to `~/.gemini/AGENTS.md`, not `~/.gemini/GEMINI.md`.
#     Antigravity reads both, but Gemini CLI writes GEMINI.md as its own global
#     context, and the two products share the directory: writing there would put
#     our block into a file another tool owns and rewrites.
#
# The presence probe derives the harness home from the skills path, which here
# is `~/.gemini/config` rather than `~/.gemini` — deliberately. `~/.gemini` alone
# means Gemini CLI, which is not this harness; the `config/` subtree is
# Antigravity's own.
#
# OpenCode keeps everything under XDG, `~/.config/opencode/`: skills in `skills/` (plural —
# older third-party pages still show `skill/`), the global rules in `AGENTS.md`. The probe
# home is therefore `~/.config/opencode`, never the bare `~/.config` that every Linux
# machine has. Two of its Claude Code fallbacks touch us: it also reads `~/.claude/skills`,
# so on a machine with both our skills are found twice under the same names — the same
# text, so either copy is right; and it reads `~/.claude/CLAUDE.md` only while its own
# `AGENTS.md` does not exist, so the file our block creates ends that fallback for the
# human's own global rules too.
harness_table() {
    cat <<'TBL'
hermes	Hermes Agent	hermes	$HOME/.hermes/skills	$HOME/.hermes/AGENTS.md
claude	Claude Code	claude	$HOME/.claude/skills	$HOME/.claude/CLAUDE.md
codex	Codex	codex	$HOME/.codex/skills	$HOME/.codex/AGENTS.md
omp	omp	omp	$HOME/.omp/skills	$HOME/.omp/AGENTS.md
pi	pi	pi	$HOME/.pi/skills	$HOME/.pi/AGENTS.md
devin	Devin CLI	devin	$HOME/.devin/skills	$HOME/.devin/AGENTS.md
antigravity	Antigravity	agy	$HOME/.gemini/config/skills	$HOME/.gemini/AGENTS.md
opencode	OpenCode	opencode	$HOME/.config/opencode/skills	$HOME/.config/opencode/AGENTS.md
TBL
}

# Expand the literal $HOME in a table cell without eval'ing arbitrary text.
harness_expand() { printf '%s\n' "$1" | sed "s|\$HOME|$HOME|g"; }

# A harness is present if its binary is on PATH or its home directory exists.
# Both matter: a harness may be installed but not yet on PATH in this shell,
# and it may be on PATH before it has ever been run.
#
# The probe cell is a comma-separated list. A bare word is a binary on PATH; an
# entry starting with `$HOME` or `/` is a path whose existence counts. When the
# cell names no path, the home is the parent of the skills directory — the usual
# case. A row names its paths only when that parent is wrong: shared with another
# product (`~/.gemini` holds both Gemini CLI and Antigravity), or not created by
# the product at all (a shared `~/.agents/skills`).
harness_present() {
    _hp_probe=$1; _hp_skills=$2; _hp_paths=0
    _hp_ifs=$IFS; IFS=,
    for _hp_p in $_hp_probe; do
        case $_hp_p in
            '$HOME'*|/*)
                _hp_paths=1
                [ -e "$(harness_expand "$_hp_p")" ] && { IFS=$_hp_ifs; return 0; } ;;
            ?*) command -v "$_hp_p" >/dev/null 2>&1 && { IFS=$_hp_ifs; return 0; } ;;
        esac
    done
    IFS=$_hp_ifs
    [ "$_hp_paths" -eq 1 ] && return 1
    [ -d "$(dirname -- "${_hp_skills%%,*}")" ] && return 0
    return 1
}

# The skills cell may name several directories, comma-separated, when one product
# reads different ones in its different shapes (Antigravity: the IDE and the CLI).
# Prints one directory per line; the first is the one presence and status look at.
harness_dirs() {
    printf '%s\n' "$1" | tr ',' '\n' | grep -v '^$' || :
}

# Emit one line per detected harness: key<TAB>label<TAB>skills-dir<TAB>instructions
harness_detect() {
    harness_table | while IFS='	' read -r _key _label _probe _skills _instr; do
        [ -n "$_key" ] || continue
        _skills=$(harness_expand "$_skills")
        [ "$_instr" = - ] && _instr=
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

# ---------------------------------------------------------------------------
# Retired locations
#
# Where earlier versions put our skills and our block, and the harness turned out
# not to read: the row was wrong, or the harness moved. Nothing reads these copies,
# so `fraim init` takes ours back — skills marked `source: fraim` and the block
# between our markers, nothing else. A path some row of the table still uses is
# never swept, whatever this list says.
#   kind (skills | context)   path
harness_retired_table() {
    cat <<'TBL'
skills	$HOME/.pi/skills
context	$HOME/.pi/AGENTS.md
skills	$HOME/.omp/skills
context	$HOME/.omp/AGENTS.md
skills	$HOME/.devin/skills
context	$HOME/.devin/AGENTS.md
context	$HOME/.hermes/AGENTS.md
TBL
}

# Is this path in use by any row of the table (as a skills directory or a context file)?
harness_path_in_use() {
    _hpu_path=$1
    harness_table | while IFS='	' read -r _hpu_k _hpu_l _hpu_p _hpu_s _hpu_i; do
        [ -n "$_hpu_k" ] || continue
        harness_dirs "$(harness_expand "$_hpu_s")"
        harness_expand "$_hpu_i"
    done | grep -qxF "$_hpu_path"
}

# Sweep the retired locations. Prints one line per path it took something from.
harness_sweep_retired() {
    harness_retired_table | while IFS='	' read -r _hsr_kind _hsr_path; do
        [ -n "$_hsr_kind" ] || continue
        _hsr_path=$(harness_expand "$_hsr_path")
        harness_path_in_use "$_hsr_path" && continue
        case $_hsr_kind in
            skills)
                [ -d "$_hsr_path" ] || continue
                _hsr_n=0
                for _hsr_d in "$_hsr_path"/*/; do
                    [ -f "$_hsr_d/SKILL.md" ] || continue
                    grep -q '^  source: fraim$' "$_hsr_d/SKILL.md" 2>/dev/null || continue
                    rm -rf "$_hsr_d" && _hsr_n=$((_hsr_n + 1))
                done
                rmdir "$_hsr_path" 2>/dev/null || :
                [ "$_hsr_n" -gt 0 ] && printf '%s\n' "$_hsr_path"
                ;;
            context)
                context_uninstall "$_hsr_path" && printf '%s\n' "$_hsr_path"
                ;;
        esac
    done
    return 0
}
