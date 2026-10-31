#!/bin/sh
# scaffold.sh — lay the project skeleton deterministically.
#
# The shape of a project — which files, which folders, which headings — is a fixed
# structure, so it is code. Only the CONTENT is text, and that is what /bootstrap and
# /onboard write. Before this existed, the model re-created the layout from prose on
# every project, which meant two projects laid down a month apart could disagree about
# their own section names, and /prune and /orient had to cope with the variation.
#
# There is deliberately no prose fallback. A deterministic action has exactly one
# implementation; if the CLI is absent the procedure stops, the same way /docker-deploy
# stops for host-level actions.

# Every scaffolded foundation file carries this marker. It is what lets the watchman
# tell "not laid" from "laid but not filled in" — without it, empty files would report
# the project as healthy, which is worse than having no files at all.
SCAFFOLD_STUB='fraim:stub'

scaffold_templates() {
    _r=$(fraim_root) || return 1
    printf '%s/installer/templates/foundation\n' "$_r"
}

# Copy one template, substituting the project name. Never overwrites: scaffolding is
# additive by construction, so running it on a live project is safe.
scaffold_file() {
    _src=$1; _dst=$2; _project=$3
    if [ -e "$_dst" ]; then
        printf 'skip\n'; return 0
    fi
    mkdir -p "$(dirname -- "$_dst")" || return 1
    sed "s/{{PROJECT}}/$_project/g" "$_src" > "$_dst" || return 1
    printf 'created\n'
}

# Add the secret rules to a .gitignore that already exists, and say what was added.
# Silence here would be the worst outcome: the user would believe the protection is in
# place because scaffold printed a tick, when the file it ticked never mentioned `.env`.
scaffold_gitignore_extend() {
    _root=$1
    _gi="$_root/.gitignore"
    _added=
    for _pat in '.env' '.env.*' '!.env.example'; do
        grep -qxF -- "$_pat" "$_gi" 2>/dev/null && continue
        _added="$_added $_pat"
    done

    if [ -z "$_added" ]; then
        dim "  $(t scaf_gitignore_closed)"
    else
        {
            printf '\n# fraim — secrets do not belong in the history\n'
            for _pat in $_added; do printf '%s\n' "$_pat"; done
        } >> "$_gi" || return 1
        ok "$(t scaf_gitignore_added patterns="$_added")"
    fi

    # .gitignore does nothing about a file git already tracks, and this is exactly the
    # project shape where that happens — code and history predate the system.
    if git -C "$_root" rev-parse --git-dir >/dev/null 2>&1; then
        _tracked=$(git -C "$_root" ls-files -- '.env' '.env.*' 2>/dev/null | grep -v '\.example$' | head -3)
        if [ -n "$_tracked" ]; then
            warn "$(t scaf_env_tracked)"
            printf '%s\n' "$_tracked" | while read -r _f; do dim "    $_f"; done
            dim "    $(t scaf_env_tracked_hint)"
        fi
    fi
    return 0
}

scaffold_run() {
    _root=$1
    _tpl=$(scaffold_templates) || die "$(t scaf_no_templates_broken)"
    [ -d "$_tpl" ] || die "$(t scaf_no_templates path="$_tpl")"
    _project=$(basename -- "$_root")

    _created=0; _skipped=0
    for _rel in README.md ARCHITECTURE.md CONVENTIONS.md DECISIONS.md \
                ai/README.md ai/archive/decisions_log.md; do
        case $_rel in
            ai/archive/decisions_log.md) _from="$_tpl/ai/decisions_log.md" ;;
            *) _from="$_tpl/$_rel" ;;
        esac
        [ -f "$_from" ] || continue
        _res=$(scaffold_file "$_from" "$_root/$_rel" "$_project") || return 1
        if [ "$_res" = created ]; then
            _created=$((_created + 1)); ok "$_rel"
        else
            _skipped=$((_skipped + 1)); dim "  $(t scaf_exists path="$_rel")"
        fi
    done

    # .gitignore is scaffolded because the two lines that matter are universal and are
    # about secrets, not about the stack.
    #
    # "Never overwrite" is right for a file, and wrong for this one taken as a whole: every
    # real repository already has a .gitignore, so skipping it meant the secret rules — the
    # one thing here that is about safety rather than taste — never landed on exactly the
    # projects that already have code and a remote. So an existing file is EXTENDED, not
    # replaced, and only with the lines about secrets: `data/` is a shape decision and a
    # project may legitimately track it, while `.env` in a pushed history is an incident.
    if [ ! -f "$_root/.gitignore" ]; then
        _res=$(scaffold_file "$_tpl/gitignore" "$_root/.gitignore" "$_project") || return 1
        [ "$_res" = created ] && { _created=$((_created + 1)); ok ".gitignore"; }
    else
        scaffold_gitignore_extend "$_root" || return 1
    fi

    # Empty directories git will not carry on its own.
    mkdir -p "$_root/ai/tasks" "$_root/ai/backlog" "$_root/ai/archive" "$_root/ai/investigations"
    for _d in tasks backlog archive investigations; do
        [ -f "$_root/ai/$_d/.gitkeep" ] || : > "$_root/ai/$_d/.gitkeep"
    done
    ok "ai/tasks/ ai/backlog/ ai/archive/ ai/investigations/"

    # A project-level settings file, so thresholds travel with the repository.
    if [ ! -f "$_root/ai/fraim.conf" ]; then
        {
            config_conf_header
            printf '#\n'
            config_table | while IFS='|' read -r _k _v _s _t _d; do
                printf '# %s = %s\n' "$_k" "$_v"
            done
        } > "$_root/ai/fraim.conf"
        _created=$((_created + 1)); ok "ai/fraim.conf"
    else
        dim "  $(t scaf_exists path=ai/fraim.conf)"
    fi

    # The repository has to describe itself to whoever opens it. Until this existed the
    # foundation travelled in git while the instruction to honour it stayed on the machine
    # that ran `fraim init` — so a web session, a cloud agent, CI or a second machine
    # cloned the files and had no reason to open them. AGENTS.md is the cross-agent
    # standard (C3: aim at the standard, do not invent a format); CLAUDE.md points at it.
    for _ctx in AGENTS.md CLAUDE.md; do
        case $_ctx in
            AGENTS.md) _fn=context_project_block ;;
            *)         _fn=context_pointer_block ;;
        esac
        _existed=no; [ -f "$_root/$_ctx" ] && _existed=yes
        if context_install "$_root/$_ctx" "$_fn"; then
            if [ "$_existed" = no ]; then
                _created=$((_created + 1)); ok "$_ctx"
            else
                dim "  $(t scaf_ctx_updated file="$_ctx")"
            fi
        else
            warn "$(t scaf_err_write file="$_ctx")"
        fi
    done

    scaffold_git "$_root"

    # The skeleton is only a save point if it is committed — an uncommitted skeleton
    # leaves `fraim undo` with nothing to show and the invariant "every save point is a
    # commit" false on the very first command a project runs.
    verb_commit "$_root" scaffold "lay down the foundation" \
        README.md ARCHITECTURE.md CONVENTIONS.md DECISIONS.md \
        AGENTS.md CLAUDE.md .gitignore ai

    say ""
    if [ "$_skipped" -eq 0 ]; then
        ok "$(t scaf_created created="$_created")"
    else
        ok "$(t scaf_created_skipped created="$_created" skipped="$_skipped")"
    fi
    return 0
}

# The repository is part of the skeleton, not a prerequisite the user has to arrange.
#
# Every save point in this system is a commit, so a project without a repository has no
# save points at all — and the person least likely to create one by hand is exactly the
# person this product is for. So we create it, under one guard: only when there is no
# repository here OR ANYWHERE ABOVE. A project living inside someone else's checkout
# gets nothing — a nested repository would quietly detach their files from their history.
#
# The identity is the second half of the same problem. On a machine where git has never
# been configured, every commit fails with a message about setting user.email — a wall
# for someone who does not know what git is. We set a repository-local identity only when
# none is resolvable, and say so out loud, so it can be changed by anyone who cares.
scaffold_git() {
    _root=$1
    command -v git >/dev/null 2>&1 || {
        warn "$(t scaf_git_missing)"
        dim "    $(t scaf_git_missing_hint)"
        return 0
    }
    if git -C "$_root" rev-parse --show-toplevel >/dev/null 2>&1; then
        _top=$(git -C "$_root" rev-parse --show-toplevel 2>/dev/null)
        if [ "$_top" = "$_root" ]; then
            dim "  $(t scaf_git_exists)"
        else
            dim "  $(t scaf_git_nested top="$_top")"
        fi
    else
        git -C "$_root" init -q >/dev/null 2>&1 || {
            warn "$(t scaf_git_init_failed)"
            return 0
        }
        ok "$(t scaf_git_init_done)"
    fi

    if [ -z "$(git -C "$_root" config user.email 2>/dev/null)" ]; then
        git -C "$_root" config user.email "fraim@localhost" 2>/dev/null || return 0
        git -C "$_root" config user.name "${USER:-fraim}" 2>/dev/null || return 0
        dim "  $(t scaf_git_identity)"
        dim "    $(t scaf_git_identity_hint)"
    fi
    return 0
}

# Said once, at setup, and never again: the history lives in this same folder.
#
# WHERE the copy lives is still not ours to decide — a hosting service, a self-hosted one,
# somebody else's — and that fork is asked, not defaulted. What changed with `fraim publish`
# is only who carries the mechanics around the fork, so this notice now names a command
# instead of asking the user to open a conversation they may not know how to start. The
# boundary of the guarantee stays in the text: git carries code and history, and the data
# and the secrets were never in it, by our own rule.
scaffold_copy_notice() {
    _root=$1
    verb_is_git "$_root" 2>/dev/null || return 0
    [ -z "$(git -C "$_root" remote 2>/dev/null)" ] || return 0
    say ""
    dim "$(t scaf_copy_notice_where)"
    dim "$(t scaf_copy_notice_how)"
    return 0
}

# Is a foundation file still an unfilled scaffold?
scaffold_is_stub() { [ -f "$1" ] && grep -q "$SCAFFOLD_STUB" "$1" 2>/dev/null; }

# --- bringing an existing project up to the current standard ------------------
# Scaffolding is additive, so re-running it already lands the FILES a newer release
# added. What it could not do is repair a file that exists but predates a section the
# system now reads: `## Known Pitfalls / Lessons` is where `fraim pitfall` writes and
# what /make-task reads before planning, and a CONVENTIONS.md from before it existed
# breaks both — silently, because every other check passes.
#
# Only sections that CODE depends on are repaired here. Everything else about the
# contents belongs to /bootstrap, /onboard and /prune: the verb owns form, not text.
scaffold_section_source() {
    _tpl=$(scaffold_templates) || return 1
    awk -v h="$2" '$0 == h {f=1} f' "$_tpl/$1"
}

# The count comes back in a global, not on stdout: this function also PRINTS progress,
# and mixing a return value into the same stream is how `[ "$n" -gt 0 ]` starts reading
# a tick mark as a number.
SCAFFOLD_SECTIONS_ADDED=0
scaffold_sections() {
    _root=$1
    SCAFFOLD_SECTIONS_ADDED=0
    _f="$_root/CONVENTIONS.md"
    _head='## Known Pitfalls / Lessons'
    if [ -f "$_f" ] && ! grep -q "^$_head\$" "$_f"; then
        {
            printf '\n'
            scaffold_section_source CONVENTIONS.md "$_head"
        } >> "$_f" || return 1
        ok "$(t scaf_section_added section="$_head")"
        SCAFFOLD_SECTIONS_ADDED=$((SCAFFOLD_SECTIONS_ADDED + 1))
    fi
    return 0
}
