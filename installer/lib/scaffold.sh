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

    say ""
    if [ "$_skipped" -eq 0 ]; then
        ok "создано: $_created"
    else
        ok "создано: $_created, оставлено как было: $_skipped"
    fi
    return 0
}

# Is a foundation file still an unfilled scaffold?
scaffold_is_stub() { [ -f "$1" ] && grep -q "$SCAFFOLD_STUB" "$1" 2>/dev/null; }
