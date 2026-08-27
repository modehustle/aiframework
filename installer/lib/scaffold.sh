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

scaffold_run() {
    _root=$1
    _tpl=$(scaffold_templates) || die "не найдены шаблоны фундамента — установка повреждена"
    [ -d "$_tpl" ] || die "не найдены шаблоны фундамента: $_tpl"
    _project=$(basename -- "$_root")

    _created=0; _skipped=0
    for _rel in README.md ARCHITECTURE.md CONVENTIONS.md DECISIONS.md \
                ai/README.md ai/hotfix_log.md ai/archive/decisions_log.md; do
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
    _res=$(scaffold_file "$_tpl/gitignore" "$_root/.gitignore" "$_project") || return 1
    if [ "$_res" = created ]; then _created=$((_created + 1)); ok ".gitignore"
    else _skipped=$((_skipped + 1)); dim "  .gitignore — уже есть, не трогаю"; fi

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

    scaffold_git "$_root"

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

# Is a foundation file still an unfilled scaffold?
scaffold_is_stub() { [ -f "$1" ] && grep -q "$SCAFFOLD_STUB" "$1" 2>/dev/null; }
