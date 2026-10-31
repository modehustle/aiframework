#!/bin/sh
# harness.sh — where each target agent keeps its skills, and how we notice it.
#
# One artifact (an Agent Skills directory) covers every P0 harness; the only
# thing that differs is the destination path and the global instructions file.
# So the harness layer is a table, not code. Adding a harness is adding a row.

# Columns, tab-separated:
#   key   label   probe   skills-dir[,skills-dir]   instructions-file
# probe  — see harness_present: binaries and paths, comma-separated.
# instructions-file — the harness's GLOBAL context file, where we leave the
#          pointer block. `-` means the harness has no global one on disk (its
#          rules live in a settings screen); never leave the cell empty — a tab
#          separator collapses empty fields. Where a harness reads a rules
#          DIRECTORY rather than one file (Kiro, Augment, Continue), the cell
#          names our own file inside it.
#
# Every fact below was read in the harness's source or its official docs
# (installer/HARNESS_TARGETS.md has the sources); a row is never filled from a
# third-party list of paths.
#
# ONE COPY IN THE SHARED DIRECTORY. `~/.agents/skills` is the open standard's
# user location and most harnesses read it next to their own directory. Several of
# them warn on a second copy of the same name (Gemini CLI on screen, pi, omp,
# Hermes), so a harness that reads `~/.agents/skills` gets its skills THERE and
# nowhere else; only a harness that does not read it gets its own directory
# (Claude Code, Hermes, Antigravity, Factory Droid, Grok, Kiro, Junie, Continue).
# Copies are still seen twice where a harness also reads another harness's own
# directory (`~/.claude/skills` is read by Kilo, Cursor, Crush, Goose, Grok, Warp,
# Augment, OpenCode, Copilot in VS Code) — the same text, so either copy is right.
# The probe of a shared-directory row names the harness's own home: the parent of
# `~/.agents/skills` says nothing about which product is installed.
#
# The same reasoning holds for the context file: `~/.agents/AGENTS.md` is read by
# Cline, Warp, Goose and Kimi Code alike, so they share it and see one block.
#
# Antigravity is the one row where neither cell is the obvious one, and both
# choices are load-bearing:
#
#   · the binary is `agy`, not `antigravity` — that is the name its installer
#     puts on PATH;
#   · skills go to two directories: `~/.gemini/config/skills` is read by the IDE
#     and Antigravity 2.0, `~/.gemini/antigravity-cli/skills` by the CLI (Google's
#     own agents-cli installs into both). Neither reads `~/.agents/skills`;
#   · the pointer block goes to `~/.gemini/AGENTS.md`, not `~/.gemini/GEMINI.md`.
#     Antigravity reads both, but GEMINI.md is Gemini CLI's global context, and
#     the Gemini CLI row writes there — Antigravity would see the block twice.
#
# The presence probe derives the Antigravity home from the skills path, which is
# `~/.gemini/config` rather than `~/.gemini` — deliberately. `~/.gemini` alone
# is shared with Gemini CLI, which is detected by its binary or by
# `~/.gemini/settings.json`, a file only Gemini CLI writes.
#
# OpenCode keeps its global rules in `~/.config/opencode/AGENTS.md`; it falls back
# to `~/.claude/CLAUDE.md` only while that file does not exist, so the file our block
# creates ends that fallback for the human's own global rules too. Its skills go to
# the shared directory, which it reads by default; its home is `~/.config/opencode`,
# never the bare `~/.config` every Linux machine has.
#
# pi and omp keep their agent home one level down, in `~/.pi/agent` and
# `~/.omp/agent`; earlier rows wrote to `~/.pi` and `~/.omp`, which neither reads
# (the retired table below takes those copies back). Devin for Terminal lives in
# `~/.config/devin`, not `~/.devin`. Hermes has no global AGENTS.md: the one file
# it always loads is `SOUL.md`, its identity text, which it seeds itself — we do not
# write into it. OpenClaw's always-loaded file is its workspace AGENTS.md, which its
# onboarding seeds from a template — we do not write into that either.
#
# ZCode is Z.ai's desktop agent for its GLM models; it ships no CLI we could name, so it
# is recognised by its home or its macOS app bundle. Its own `~/.zcode/skills` is used
# rather than the shared directory: only one secondary source says it reads
# `~/.agents/skills`, two agree on its own. Its docs host was unreachable — the row
# rests on a quoted summary of them (`~/.zcode/AGENTS.md`, read every session).
#
# Not here, on purpose: Roo Code (shut down 2026-05-15, repository archived),
# Windsurf (Cascade became Devin Desktop, which shares `~/.config/devin` with the
# Devin row), Amp and Trae (no primary source could be read for their paths).
harness_table() {
    cat <<'TBL'
hermes	Hermes Agent	hermes	$HOME/.hermes/skills	-
claude	Claude Code	claude	$HOME/.claude/skills	$HOME/.claude/CLAUDE.md
codex	Codex	codex,$HOME/.codex	$HOME/.agents/skills	$HOME/.codex/AGENTS.md
omp	omp	omp,$HOME/.omp/agent	$HOME/.agents/skills	$HOME/.omp/agent/AGENTS.md
pi	pi	pi,$HOME/.pi/agent	$HOME/.agents/skills	$HOME/.pi/agent/AGENTS.md
devin	Devin CLI	devin,$HOME/.config/devin	$HOME/.agents/skills	$HOME/.config/devin/AGENTS.md
antigravity	Antigravity	agy	$HOME/.gemini/config/skills,$HOME/.gemini/antigravity-cli/skills	$HOME/.gemini/AGENTS.md
opencode	OpenCode	opencode,$HOME/.config/opencode	$HOME/.agents/skills	$HOME/.config/opencode/AGENTS.md
gemini	Gemini CLI	gemini,$HOME/.gemini/settings.json	$HOME/.agents/skills	$HOME/.gemini/GEMINI.md
qwen	Qwen Code	qwen,$HOME/.qwen	$HOME/.agents/skills	$HOME/.qwen/AGENTS.md
kimi	Kimi Code	kimi,$HOME/.kimi-code	$HOME/.agents/skills	$HOME/.agents/AGENTS.md
vibe	Mistral Vibe	vibe,$HOME/.vibe	$HOME/.agents/skills	$HOME/.vibe/AGENTS.md
goose	Goose	goose,$HOME/.config/goose	$HOME/.agents/skills	$HOME/.agents/AGENTS.md
crush	Crush	crush,$HOME/.config/crush	$HOME/.agents/skills	$HOME/.config/crush/CRUSH.md
droid	Factory Droid	droid	$HOME/.factory/skills	$HOME/.factory/AGENTS.md
grok	Grok Build	grok	$HOME/.grok/skills	$HOME/.grok/AGENTS.md
openclaw	OpenClaw	openclaw,$HOME/.openclaw	$HOME/.agents/skills	-
copilot	GitHub Copilot	copilot,$HOME/.copilot	$HOME/.agents/skills	$HOME/.copilot/copilot-instructions.md
cursor	Cursor	cursor-agent,cursor,$HOME/.cursor	$HOME/.agents/skills	-
cline	Cline	cline,$HOME/.cline	$HOME/.agents/skills	$HOME/.agents/AGENTS.md
kilo	Kilo Code	kilo,kilocode,$HOME/.config/kilo,$HOME/.kilo,$HOME/.kilocode	$HOME/.agents/skills	$HOME/.config/kilo/AGENTS.md
zed	Zed	zed,zeditor,$HOME/.config/zed	$HOME/.agents/skills	$HOME/.config/zed/AGENTS.md
warp	Warp	warp,warp-terminal,$HOME/.warp,$HOME/.config/warp-terminal	$HOME/.agents/skills	$HOME/.agents/AGENTS.md
augment	Augment	auggie,$HOME/.augment	$HOME/.agents/skills	$HOME/.augment/rules/fraim.md
kiro	Kiro	kiro-cli,kiro	$HOME/.kiro/skills	$HOME/.kiro/steering/fraim.md
junie	Junie	junie	$HOME/.junie/skills	$HOME/.junie/AGENTS.md
continue	Continue	cn	$HOME/.continue/skills	$HOME/.continue/rules/fraim.md
zcode	ZCode	$HOME/.zcode,/Applications/ZCode.app	$HOME/.zcode/skills	$HOME/.zcode/AGENTS.md
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
skills	$HOME/.codex/skills
skills	$HOME/.config/opencode/skills
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
