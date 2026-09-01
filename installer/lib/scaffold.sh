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
        dim "  .gitignore — секреты уже закрыты, не трогаю"
    else
        {
            printf '\n# fraim — секреты не место в истории\n'
            for _pat in $_added; do printf '%s\n' "$_pat"; done
        } >> "$_gi" || return 1
        ok ".gitignore — дописано:$_added"
    fi

    # .gitignore does nothing about a file git already tracks, and this is exactly the
    # project shape where that happens — code and history predate the system.
    if git -C "$_root" rev-parse --git-dir >/dev/null 2>&1; then
        _tracked=$(git -C "$_root" ls-files -- '.env' '.env.*' 2>/dev/null | grep -v '\.example$' | head -3)
        if [ -n "$_tracked" ]; then
            warn ".env уже в истории git — .gitignore его оттуда не убирает"
            printf '%s\n' "$_tracked" | while read -r _f; do dim "    $_f"; done
            dim "    смени секреты и убери файл из индекса; чистка истории — отдельная работа"
        fi
    fi
    return 0
}

scaffold_run() {
    _root=$1
    _tpl=$(scaffold_templates) || die "не найдены шаблоны фундамента — установка повреждена"
    [ -d "$_tpl" ] || die "не найдены шаблоны фундамента: $_tpl"
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
            _skipped=$((_skipped + 1)); dim "  $_rel — уже есть, не трогаю"
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
    mkdir -p "$_root/ai/tasks" "$_root/ai/archive" "$_root/ai/investigations"
    for _d in tasks archive investigations; do
        [ -f "$_root/ai/$_d/.gitkeep" ] || : > "$_root/ai/$_d/.gitkeep"
    done
    ok "ai/tasks/ ai/archive/ ai/investigations/"

    # A project-level settings file, so thresholds travel with the repository.
    if [ ! -f "$_root/ai/fraim.conf" ]; then
        {
            printf '# fraim — настройки этого проекта. Едут в git вместе с репозиторием.\n'
            printf '# Показать, что действует и откуда: fraim config\n#\n'
            config_table | while IFS='|' read -r _k _v _d; do
                printf '# %s\n# %s = %s\n' "$_d" "$_k" "$_v"
            done
        } > "$_root/ai/fraim.conf"
        _created=$((_created + 1)); ok "ai/fraim.conf"
    else
        dim "  ai/fraim.conf — уже есть, не трогаю"
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
                dim "  $_ctx — блок fraim обновлён, остальное не тронуто"
            fi
        else
            warn "не удалось записать $_ctx"
        fi
    done

    scaffold_git "$_root"

    # The skeleton is only a save point if it is committed — an uncommitted skeleton
    # leaves `fraim undo` with nothing to show and the invariant "every save point is a
    # commit" false on the very first command a project runs.
    verb_commit "$_root" scaffold "разворачиваю фундамент" \
        README.md ARCHITECTURE.md CONVENTIONS.md DECISIONS.md \
        AGENTS.md CLAUDE.md .gitignore ai

    say ""
    if [ "$_skipped" -eq 0 ]; then
        ok "создано: $_created"
    else
        ok "создано: $_created, оставлено как было: $_skipped"
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
        warn "git не найден — точек сохранения не будет"
        dim "    установи git: без него глаголы не могут сохранить ни одного изменения"
        return 0
    }
    if git -C "$_root" rev-parse --show-toplevel >/dev/null 2>&1; then
        _top=$(git -C "$_root" rev-parse --show-toplevel 2>/dev/null)
        if [ "$_top" = "$_root" ]; then
            dim "  git — репозиторий уже есть, не трогаю"
        else
            dim "  git — проект внутри репозитория $_top, свой не завожу"
        fi
    else
        git -C "$_root" init -q >/dev/null 2>&1 || {
            warn "не удалось завести репозиторий"
            return 0
        }
        ok "git — репозиторий заведён"
    fi

    if [ -z "$(git -C "$_root" config user.email 2>/dev/null)" ]; then
        git -C "$_root" config user.email "fraim@localhost" 2>/dev/null || return 0
        git -C "$_root" config user.name "${USER:-fraim}" 2>/dev/null || return 0
        dim "  подписи коммитов не были настроены — поставил локальные для этого проекта"
        dim "    сменить: git config user.name \"Имя\" && git config user.email \"почта\""
    fi
    return 0
}

# Said once, at setup, and never again: the history lives in this same folder.
#
# A copy outside this machine is NOT this product's job — where it lives (a hosting
# service, another disk, a synced folder) is an environment choice with no single right
# answer, and setting one up happens once per project. That is a conversation with the
# agent, not a verb: verbs exist for mechanics that repeat. What we owe the user is only
# the truth about the boundary of the guarantee we do give — and the truth includes what
# git does not carry: the data and the secrets were never in it, by our own rule.
scaffold_copy_notice() {
    _root=$1
    verb_is_git "$_root" 2>/dev/null || return 0
    [ -z "$(git -C "$_root" remote 2>/dev/null)" ] || return 0
    say ""
    dim "История проекта лежит в этой же папке — копии вне этой машины нет."
    dim "Нужна копия кода и истории (данные и секреты в неё не попадают) — попроси агента настроить."
    return 0
}

# Is a foundation file still an unfilled scaffold?
scaffold_is_stub() { [ -f "$1" ] && grep -q "$SCAFFOLD_STUB" "$1" 2>/dev/null; }
