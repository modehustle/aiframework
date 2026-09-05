#!/bin/sh
# publish.sh — the way out of "this project exists on one disk".
#
# The watchman has long said «нет удалённой копии — проект живёт только на этой машине»
# and stopped there, because BACKLOG §3 ruled that setting a copy up is a one-off action
# with a real fork inside (which host, private or public) and therefore a conversation
# with the agent rather than a verb. The revision is recorded in BACKLOG §3: the fork is
# real and stays a QUESTION, but everything around it — is the tooling installed and
# authorised, is there a secret in the history that must not leave the machine, wiring the
# remote, pushing, verifying that what arrived is what we have — is mechanics, it repeats
# on every push, and by P0 it is exactly the expertise the user may not have. So the fork
# is asked, and the mechanics belong here.
#
# Three properties this module holds on to:
#
#   1. The floor is a URL. Provider CLIs (gh, glab) are accelerators: whenever one is
#      missing, unauthorised, or behaves differently than we expect, the answer is never
#      "нельзя" — it is «создай репозиторий в браузере и дай ссылку». No dependency is
#      hard, so no user is locked out by an install they cannot perform.
#   2. Nothing reaches the network before a human says yes (B5). The plan is printed in
#      full — host, name, visibility, what is going, what the scan found. Through a pipe
#      without --yes the command prints that plan and stops, exactly like `fraim clean`.
#   3. The scan looks at what actually leaves: every path that ever existed in the
#      history, not just the working tree. A `.env` committed in March and deleted in
#      April is still in the pack and still travels on the first push.

PUB_STOP=
PUB_WARN=

pub_stop_add() { PUB_STOP="$PUB_STOP$1	$2
"; }
pub_warn_add() { PUB_WARN="$PUB_WARN$1	$2
"; }
# grep -c prints 0 and exits 1 on no match; under `set -e` that would kill the caller, and
# a `|| printf 0` would print a second zero. The count is the printed one, the status is
# swallowed.
pub_count() { printf '%s' "$1" | grep -c '[^[:space:]]' 2>/dev/null || true; }

# --- providers --------------------------------------------------------------
# key|label|cli|creates the repository itself
publish_providers() {
    cat <<'TBL'
github|GitHub|gh|yes
gitlab|GitLab|glab|yes
url|Другой хост (по ссылке)||no
TBL
}

publish_provider_field() {
    publish_providers | awk -F'|' -v k="$1" -v n="$2" '$1 == k { print $n; exit }'
}

publish_provider_known() { publish_providers | cut -d'|' -f1 | grep -qx "$1"; }

# --- dependencies -----------------------------------------------------------
# Never installs anything. The environment is the user's choice (C1), and a product that
# runs a package manager on someone's machine has stopped being a workflow layer. What we
# owe instead is the exact line to paste — by P0, "поставь gh" is not an instruction to
# somebody who has never installed a CLI.
publish_os() {
    case $(uname -s 2>/dev/null) in
        Darwin) printf 'macos\n' ;;
        Linux)
            if [ -f /etc/os-release ]; then
                . /etc/os-release 2>/dev/null || true
                case "${ID:-}${ID_LIKE:-}" in
                    *debian*|*ubuntu*) printf 'debian\n' ;;
                    *fedora*|*rhel*|*centos*) printf 'fedora\n' ;;
                    *arch*) printf 'arch\n' ;;
                    *) printf 'linux\n' ;;
                esac
            else
                printf 'linux\n'
            fi
            ;;
        *) printf 'other\n' ;;
    esac
}

publish_install_hint() {
    _pub_cli=$1
    case $_pub_cli in
        gh)
            case $(publish_os) in
                macos)  dim "    brew install gh" ;;
                debian) dim "    sudo apt install gh   (если пакета нет: https://cli.github.com)" ;;
                fedora) dim "    sudo dnf install gh" ;;
                arch)   dim "    sudo pacman -S github-cli" ;;
                *)      dim "    https://cli.github.com — установка под твою систему" ;;
            esac
            dim "    потом один раз: gh auth login"
            ;;
        glab)
            case $(publish_os) in
                macos)  dim "    brew install glab" ;;
                arch)   dim "    sudo pacman -S glab" ;;
                *)      dim "    https://gitlab.com/gitlab-org/cli — установка под твою систему" ;;
            esac
            dim "    потом один раз: glab auth login"
            ;;
    esac
    return 0
}

# 0 — готово к работе, 1 — CLI нет, 2 — CLI есть, но вход не сделан.
publish_cli_state() {
    _pub_cli=$1
    [ -n "$_pub_cli" ] || return 0
    command -v "$_pub_cli" >/dev/null 2>&1 || return 1
    case $_pub_cli in
        gh)   gh auth status >/dev/null 2>&1 || return 2 ;;
        glab) glab auth status >/dev/null 2>&1 || return 2 ;;
    esac
    return 0
}

publish_cli_account() {
    case $1 in
        gh)   gh api user --jq .login 2>/dev/null || gh auth status 2>&1 |
                  sed -n 's/.*account \([^ ]*\).*/\1/p' | head -1 ;;
        glab) glab auth status 2>&1 | sed -n 's/.*as \([^ ]*\).*/\1/p' | head -1 ;;
    esac
    return 0
}

# The dependency screen. Answers "чего мне не хватает" for every provider at once, so the
# user picks with the answer in front of them instead of discovering it after choosing.
publish_deps_report() {
    say "${C_BLD}Чем можно опубликовать${C_OFF}"
    if command -v git >/dev/null 2>&1; then
        printf '  %s✓%s %s %s\n' "$C_GRN" "$C_OFF" "$(wm_pad git 26)" "$(git --version 2>/dev/null)"
    else
        printf '  %s✗%s %s %s\n' "$C_RED" "$C_OFF" "$(wm_pad git 26)" "не установлен — без него ничего не поедет"
        publish_install_hint git
    fi
    publish_providers | while IFS='|' read -r _pub_k _pub_lbl _pub_cli _pub_creates; do
        [ -n "$_pub_k" ] || continue
        if [ -z "$_pub_cli" ]; then
            printf '  %s·%s %s %s\n' "$C_DIM" "$C_OFF" "$(wm_pad "$_pub_lbl" 26)" \
                "ничего ставить не нужно: --url ССЫЛКА"
            continue
        fi
        publish_cli_state "$_pub_cli" && _pub_st=0 || _pub_st=$?
        case $_pub_st in
            0) printf '  %s✓%s %s %s\n' "$C_GRN" "$C_OFF" "$(wm_pad "$_pub_lbl ($_pub_cli)" 26)" \
                   "готов$(_pub_acc=$(publish_cli_account "$_pub_cli"); [ -n "$_pub_acc" ] && printf ', вход: %s' "$_pub_acc")" ;;
            1) printf '  %s·%s %s %s\n' "$C_DIM" "$C_OFF" "$(wm_pad "$_pub_lbl ($_pub_cli)" 26)" "не установлен"
               publish_install_hint "$_pub_cli" ;;
            2) printf '  %s!%s %s %s\n' "$C_YEL" "$C_OFF" "$(wm_pad "$_pub_lbl ($_pub_cli)" 26)" \
                   "установлен, вход не сделан"
               dim "    $_pub_cli auth login" ;;
        esac
    done
    return 0
}

# --- what is in this repository --------------------------------------------
# All four answer «пусто», never «ошибка»: a project with no remote and a project with no
# commits are both normal states here, and the CLI runs under `set -e` — a bare failing
# `git remote get-url` inside a command substitution would end the command instead of
# reporting the state it was asked about.
publish_remote_url() { git -C "$1" remote get-url origin 2>/dev/null || true; }
publish_branch()     { git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null || true; }
# --verify, not a bare rev-parse: in a repository with no commits `git rev-parse HEAD`
# prints the string "HEAD" and fails, and «пусто» read as a commit id is exactly the kind
# of not-data-that-looks-like-data D1 is about.
publish_head()       { git -C "$1" rev-parse -q --verify HEAD 2>/dev/null || true; }
publish_commits()    { git -C "$1" rev-list --count HEAD 2>/dev/null || true; }

publish_unpushed() {
    _pub_n=$(git -C "$1" rev-list --count HEAD --not --remotes 2>/dev/null || true)
    printf '%s\n' "${_pub_n:-0}"
}

# Every path that has ever existed anywhere in this repository's history. This is the
# honest measure of what a push carries (D5): the working tree says nothing about a file
# deleted three commits ago, and that file is exactly the one that hurts.
publish_history_paths() {
    git -C "$1" rev-list --objects --all 2>/dev/null |
        awk 'NF > 1 { $1 = ""; sub(/^ /, ""); print }' | sort -u
}

# --- the security scan ------------------------------------------------------
# Two halves, and the boundary between them is stated out loud in the report rather than
# implied, because a check that claims more than it does is worse than no check (D1):
#
#   names    — across the WHOLE history. Cheap, and catches the classic incident.
#   contents — in the CURRENT snapshot only. Grepping every blob of every commit is a
#              different tool (git-filter-repo, trufflehog) and a different runtime.
#
# Matched secret VALUES are never printed. The report gives path and line number; the
# value stays where it is, out of the terminal, out of scrollback, out of any log.
publish_scan() {
    _pub_root=$1
    PUB_STOP=; PUB_WARN=

    verb_is_git "$_pub_root" || {
        pub_stop_add "-" "здесь нет репозитория — отправлять нечего"
        return 0
    }
    [ -n "$(publish_head "$_pub_root")" ] || {
        pub_stop_add "-" "нет ни одной точки сохранения — отправлять нечего"
        return 0
    }

    _pub_paths=$(publish_history_paths "$_pub_root")

    # Names, over the whole history. `.env.example` and friends are the documented
    # counterpart of a secret file and are supposed to travel — excluded by name.
    _pub_paths_real=$(printf '%s\n' "$_pub_paths" |
        grep -Ev '\.(example|sample|template|dist)$' || true)

    publish_scan_names "$_pub_paths_real" '(^|/)\.env($|\.)' \
        "файл окружения — в нём живут пароли и ключи"
    publish_scan_names "$_pub_paths_real" '(^|/)id_(rsa|dsa|ecdsa|ed25519)$|(^|/)\.ssh/' \
        "приватный ssh-ключ"
    # .asc и .gpg сюда не входят: подписи релизов и файлы sops/git-crypt лежат в
    # репозиториях законно и зашифрованными, а ложный стоп учит проходить стоп.
    publish_scan_names "$_pub_paths_real" '\.(pem|key|p12|pfx|jks|keystore|ppk)$' \
        "ключ или сертификат"
    publish_scan_names "$_pub_paths_real" '(^|/)\.(npmrc|pypirc|netrc|htpasswd)$' \
        "файл с токеном доступа"
    publish_scan_names "$_pub_paths_real" '(^|/)(credentials|secrets?)\.(json|ya?ml|toml|ini)$|(^|/)service[-_]account[^/]*\.json$' \
        "файл учётных данных"

    # Contents, current snapshot. -I skips binaries; the pattern set is deliberately the
    # shape of issued credentials (prefix + length), not the word "password", because a
    # scanner that fires on every README is a scanner people learn to wave through.
    publish_scan_content "$_pub_root" '-----BEGIN [A-Z ]*PRIVATE KEY-----' "приватный ключ прямо в файле"
    publish_scan_content "$_pub_root" 'AKIA[0-9A-Z]{16}' "ключ AWS"
    publish_scan_content "$_pub_root" '(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})' "токен GitHub"
    publish_scan_content "$_pub_root" 'glpat-[A-Za-z0-9_-]{16,}' "токен GitLab"
    publish_scan_content "$_pub_root" 'sk-(ant-)?[A-Za-z0-9_-]{24,}' "ключ API (OpenAI / Anthropic)"
    publish_scan_content "$_pub_root" 'xox[baprs]-[A-Za-z0-9-]{10,}' "токен Slack"
    publish_scan_content "$_pub_root" 'AIza[0-9A-Za-z_-]{35}' "ключ Google"

    # Below the line: visible in the plan, never blocking. Each of these is legitimate in
    # somebody's project, and a stop that is wrong half the time teaches the user to pass
    # --force by reflex — which is how the real stop above stops working.
    publish_scan_warn_names "$_pub_paths" '(^|/)(node_modules|venv|\.venv|__pycache__|vendor)/' \
        "воспроизводимые зависимости в истории — клон будет тяжёлым"
    # Без .sql: миграции — это код, и они лежат в истории у всех.
    publish_scan_warn_names "$_pub_paths" '\.(sqlite3?|db|dump|tfstate)$' \
        "похоже на данные, а не на код — проверь, что там нет живых записей"

    publish_scan_size "$_pub_root"
    publish_scan_worktree "$_pub_root"
    return 0
}

# Each helper walks its matches with IFS set to newline, never as words: a path with a
# space in it is not exotic on a laptop, and splitting on spaces would report a file that
# does not exist while missing the one that does. Nothing is written to disk to do this —
# scanning somebody's project must not mean creating files inside it.
publish_scan_names() {
    _pub_ifs=$IFS; IFS='
'
    for _pub_p in $(printf '%s\n' "$1" | grep -Ei -- "$2" 2>/dev/null | head -10); do
        [ -n "$_pub_p" ] || continue
        pub_stop_add "$_pub_p" "$3"
    done
    IFS=$_pub_ifs
    return 0
}

publish_scan_warn_names() {
    _pub_ifs=$IFS; IFS='
'
    for _pub_p in $(printf '%s\n' "$1" | grep -Ei -- "$2" 2>/dev/null |
                    sed 's#\(^\|/\)\(node_modules\|venv\|\.venv\|__pycache__\|vendor\)/.*#\1\2/#' |
                    sort -u | head -5); do
        [ -n "$_pub_p" ] || continue
        pub_warn_add "$_pub_p" "$3"
    done
    IFS=$_pub_ifs
    return 0
}

# `git grep` prints path:line:CONTENT, and the content is the secret. Only the first two
# fields ever leave this function.
publish_scan_content() {
    _pub_ifs=$IFS; IFS='
'
    for _pub_hit in $(git -C "$1" grep -I -n -E -e "$2" HEAD -- . 2>/dev/null |
                      sed 's/^HEAD://' | cut -d: -f1,2 | head -5); do
        [ -n "$_pub_hit" ] || continue
        pub_stop_add "$_pub_hit" "$3"
    done
    IFS=$_pub_ifs
    return 0
}

# Big blobs. The number matters more than the noun: "12 МБ в истории" is a fact the
# human can act on, "большой файл" is not.
publish_scan_size() {
    _pub_root=$1
    _pub_big=$(git -C "$_pub_root" rev-list --objects --all 2>/dev/null |
        git -C "$_pub_root" cat-file --batch-check='%(objecttype) %(objectsize) %(rest)' 2>/dev/null |
        awk '$1 == "blob" && $2 > 5242880 { size = int($2 / 1048576 + 0.5); $1 = ""; $2 = "";
             sub(/^  /, ""); if ($0 != "") print size "\t" $0 }' |
        sort -rn | head -3)
    [ -n "$_pub_big" ] || return 0
    _pub_ifs=$IFS; IFS='
'
    for _pub_line in $_pub_big; do
        pub_warn_add "${_pub_line#*	}" "$(printf '%s МБ в истории' "${_pub_line%%	*}")"
    done
    IFS=$_pub_ifs
    return 0
}

# A secret that is NOT in the history yet, sitting in the folder unignored, is one
# careless `git add` from being in it. Saying so here is the cheapest moment there is.
publish_scan_worktree() {
    _pub_root=$1
    for _pub_f in .env .env.local .env.production secrets.json credentials.json; do
        [ -f "$_pub_root/$_pub_f" ] || continue
        git -C "$_pub_root" check-ignore -q "$_pub_f" 2>/dev/null && continue
        git -C "$_pub_root" ls-files --error-unmatch "$_pub_f" >/dev/null 2>&1 && continue
        pub_warn_add "$_pub_f" "лежит в папке и не закрыт .gitignore — закрой (fraim upgrade)"
    done
    return 0
}

publish_scan_show() {
    _pub_ns=$(pub_count "$PUB_STOP")
    _pub_nw=$(pub_count "$PUB_WARN")
    if [ "$_pub_ns" -eq 0 ] && [ "$_pub_nw" -eq 0 ]; then
        ok "проверка безопасности: ничего похожего на секреты и данные не нашлось"
        dim "  имена — по всей истории, содержимое — в текущем снимке"
        return 0
    fi
    say "${C_BLD}Проверка безопасности${C_OFF}"
    _pub_ifs=$IFS; IFS='
'
    for _pub_line in $PUB_STOP; do
        [ -n "$_pub_line" ] || continue
        printf '  %s✗%s %s %s— %s%s\n' "$C_RED" "$C_OFF" "${_pub_line%%	*}" \
            "$C_DIM" "${_pub_line#*	}" "$C_OFF"
    done
    for _pub_line in $PUB_WARN; do
        [ -n "$_pub_line" ] || continue
        printf '  %s!%s %s %s— %s%s\n' "$C_YEL" "$C_OFF" "${_pub_line%%	*}" \
            "$C_DIM" "${_pub_line#*	}" "$C_OFF"
    done
    IFS=$_pub_ifs
    dim "  имена — по всей истории, содержимое — в текущем снимке; значения ключей не печатаются"
    return 0
}

# --- naming -----------------------------------------------------------------
# GitHub and GitLab both accept only [A-Za-z0-9._-] in a repository name. A folder called
# «платежи api» is a perfectly good folder, so the name is sanitised rather than refused —
# and the substitution is printed, because a repository that quietly got a different name
# than the folder is a small mystery for later.
publish_repo_name() {
    _pub_name=$(printf '%s' "$1" | sed 's#[^A-Za-z0-9._/-]#-#g; s#--*#-#g; s#^-##; s#-$##')
    # A folder named entirely in Cyrillic sanitises to nothing. Refusing would be honest
    # and useless; the plan prints the name it is about to use, and --name overrides it.
    [ -n "$_pub_name" ] || _pub_name=project
    printf '%s\n' "$_pub_name"
}

publish_vis_label() {
    case $1 in
        private) printf 'приватный — видишь только ты и те, кого позовёшь\n' ;;
        public)  printf '%sПУБЛИЧНЫЙ — код и вся история видны всему интернету%s\n' "$C_YEL" "$C_OFF" ;;
        *)       printf 'приватность задаётся при создании репозитория на хосте\n' ;;
    esac
}

# --- the plan ---------------------------------------------------------------
# Printed in full before anything happens, and it is the same text whether the answer will
# come from a keypress or from --yes. Everything irreversible about this command is in
# these lines: where it goes, under what name, who will be able to read it.
publish_plan_show() {
    _pub_root=$1; _pub_prov=$2; _pub_name=$3; _pub_url=$4; _pub_vis=$5
    _pub_branch=$(publish_branch "$_pub_root")
    _pub_n=$(publish_commits "$_pub_root")
    _pub_size=$(du -sh "$_pub_root/.git" 2>/dev/null | cut -f1)
    _pub_have=$(publish_remote_url "$_pub_root")

    say "${C_BLD}Публикация проекта $(basename -- "$_pub_root")${C_OFF}"
    say ""
    # wm_pad, not printf's %-10s: %-Ns counts BYTES, and every Cyrillic letter is two of
    # them — «доступ» and «что едет» would sit in different columns.
    if [ -n "$_pub_have" ]; then
        printf '  %s %s\n' "$(wm_pad куда 9)" "$_pub_have (ремоут уже настроен)"
    elif [ "$_pub_prov" = url ]; then
        printf '  %s %s\n' "$(wm_pad куда 9)" "$_pub_url"
    else
        printf '  %s %s\n' "$(wm_pad куда 9)" \
            "$(publish_provider_field "$_pub_prov" 2), репозиторий «$_pub_name» — будет создан"
    fi
    printf '  %s %s\n' "$(wm_pad доступ 9)" "$(publish_vis_label "$_pub_vis")"
    printf '  %s %s\n' "$(wm_pad 'что едет' 9)" \
        "ветка $_pub_branch, $_pub_n $(wm_plural "${_pub_n:-0}" \
        "точка сохранения" "точки сохранения" "точек сохранения")${_pub_size:+, история ~$_pub_size}"
    dim "            едет код и история; данные и секреты в неё не клали — их не приходится оттуда убирать"
    say ""
    publish_scan_show
    return 0
}

# --- asking -----------------------------------------------------------------
# The fork BACKLOG §3 called real is real, and it stays a question. What changed is only
# who carries it: it used to be a conversation the user had to know how to start, and now
# it is two numbered lines with the state of each option already filled in.
publish_ask_provider() {
    say "${C_BLD}Где будет жить копия${C_OFF}" >&2
    _pub_i=0
    _pub_def=
    publish_providers | while IFS='|' read -r _pub_k _pub_lbl _pub_cli _pub_creates; do
        [ -n "$_pub_k" ] || continue
        _pub_i=$((_pub_i + 1))
        if [ -z "$_pub_cli" ]; then
            printf '  %s) %s %sработает всегда%s\n' "$_pub_i" "$(wm_pad "$_pub_lbl" 34)" \
                "$C_DIM" "$C_OFF" >&2
            continue
        fi
        publish_cli_state "$_pub_cli" && _pub_st=0 || _pub_st=$?
        case $_pub_st in
            0) printf '  %s) %s %s%s готов%s\n' "$_pub_i" "$(wm_pad "$_pub_lbl" 34)" \
                   "$C_GRN" "$_pub_cli" "$C_OFF" >&2 ;;
            1) printf '  %s) %s %s%s не установлен%s\n' "$_pub_i" "$(wm_pad "$_pub_lbl" 34)" \
                   "$C_DIM" "$_pub_cli" "$C_OFF" >&2 ;;
            2) printf '  %s) %s %s%s без входа, нужен %s auth login%s\n' "$_pub_i" \
                   "$(wm_pad "$_pub_lbl" 34)" "$C_YEL" "$_pub_cli" "$_pub_cli" "$C_OFF" >&2 ;;
        esac
    done
    # Умолчанием стоит первый готовый вариант, а не первый по списку: предлагать GitHub
    # там, где gh не установлен, значит вести человека в отказ через два экрана.
    _pub_def=$(publish_default_provider)
    printf '  Номер [%s]: ' "$_pub_def" >&2
    read -r _pub_ans || _pub_ans=
    [ -n "$_pub_ans" ] || _pub_ans=$_pub_def
    _pub_pick=$(publish_providers | sed -n "${_pub_ans}p" | cut -d'|' -f1 2>/dev/null)
    [ -n "$_pub_pick" ] || return 1
    printf '%s\n' "$_pub_pick"
}

# Номер первого варианта, которым прямо сейчас можно воспользоваться. Пол (URL) готов
# всегда, поэтому ответ есть при любом состоянии машины.
publish_default_provider() {
    _pub_i=0; _pub_found=
    publish_providers | while IFS='|' read -r _pub_k _pub_lbl _pub_cli _pub_creates; do
        [ -n "$_pub_k" ] || continue
        _pub_i=$((_pub_i + 1))
        if [ -z "$_pub_cli" ]; then printf '%s\n' "$_pub_i"; break; fi
        if publish_cli_state "$_pub_cli"; then printf '%s\n' "$_pub_i"; break; fi
    done | head -1
}

publish_ask_visibility() {
    say "${C_BLD}Кто сможет это читать${C_OFF}" >&2
    printf '  1) приватный %s— видишь только ты (по умолчанию)%s\n' "$C_DIM" "$C_OFF" >&2
    printf '  2) публичный %s— виден всему интернету, вместе со всей историей%s\n' "$C_DIM" "$C_OFF" >&2
    printf '  Номер [1]: ' >&2
    read -r _pub_ans || _pub_ans=
    case $_pub_ans in
        2) printf 'public\n' ;;
        *) printf 'private\n' ;;
    esac
}

publish_ask_url() {
    say "${C_BLD}Ссылка на пустой репозиторий${C_OFF}" >&2
    dim "  создай его на своём хосте (GitHub, GitLab, Gitea, Codeberg — всё равно) и" >&2
    dim "  скопируй адрес: git@host:имя/проект.git или https://host/имя/проект.git" >&2
    printf '  Ссылка: ' >&2
    read -r _pub_ans || _pub_ans=
    [ -n "$_pub_ans" ] || return 1
    printf '%s\n' "$_pub_ans"
}

# --- doing it ---------------------------------------------------------------
# Create (when the provider can), wire the remote, push, and then CHECK that what is on
# the host is what is here. The check is the half that makes the tick honest: a push can
# report success and still leave the branch behind on a host that rejected a hook.
publish_do() {
    _pub_root=$1; _pub_prov=$2; _pub_name=$3; _pub_url=$4; _pub_vis=$5
    _pub_branch=$(publish_branch "$_pub_root")
    [ -n "$_pub_branch" ] && [ "$_pub_branch" != HEAD ] ||
        { warn "ветка не определена (detached HEAD) — отправлять нечего"; return 1; }

    if [ -z "$(publish_remote_url "$_pub_root")" ]; then
        case $_pub_prov in
            url)
                git -C "$_pub_root" remote add origin "$_pub_url" 2>/dev/null ||
                    { warn "не удалось прописать адрес: $_pub_url"; return 1; }
                ok "адрес прописан: $_pub_url"
                ;;
            *)
                publish_create "$_pub_root" "$_pub_prov" "$_pub_name" "$_pub_vis" || return 1
                ;;
        esac
    fi

    _pub_have=$(publish_remote_url "$_pub_root")
    say ""
    say "Отправляю $_pub_branch → $_pub_have"
    if ! _pub_out=$(git -C "$_pub_root" push -u origin "$_pub_branch" 2>&1); then
        warn "отправка не удалась"
        printf '%s\n' "$_pub_out" | sed 's/^/    /' | while read -r _pub_l; do dim "$_pub_l"; done
        publish_push_hint "$_pub_out"
        return 1
    fi
    ok "отправлено"

    # Verification, not optimism.
    _pub_local=$(publish_head "$_pub_root")
    _pub_remote=$(git -C "$_pub_root" ls-remote origin "refs/heads/$_pub_branch" 2>/dev/null | cut -f1)
    if [ -n "$_pub_remote" ] && [ "$_pub_remote" = "$_pub_local" ]; then
        ok "проверено: на хосте лежит ровно то, что здесь ($(printf '%s' "$_pub_local" | cut -c1-7))"
    else
        warn "отправка прошла, но сверка не сошлась — на хосте ${_pub_remote:-ничего не видно}"
        dim "    проверь репозиторий глазами, прежде чем считать копию сделанной"
        return 1
    fi

    say ""
    ok "копия есть: $_pub_have"
    dim "  дальше точки сохранения уезжают той же командой: fraim publish"
    dim "  это копия кода и истории, а не бэкап данных — данных в истории нет"
    return 0
}

publish_push_hint() {
    case $1 in
        *'Permission denied'*|*'publickey'*)
            dim "    хост не узнал твой ключ. Через gh это чинит 'gh auth login', иначе — ключ SSH на хосте" ;;
        *'rejected'*|*'non-fast-forward'*|*'fetch first'*)
            dim "    в репозитории на хосте уже есть своя история — возьми пустой репозиторий или другое имя" ;;
        *'could not read Username'*|*'Authentication failed'*)
            dim "    хост просит логин: 'gh auth login' для GitHub, иначе — SSH-адрес вместо https" ;;
        *'not found'*|*'does not appear to be a git repository'*)
            dim "    адрес не найден — проверь ссылку: fraim publish --url ССЫЛКА" ;;
    esac
    return 0
}

# Creating the repository through a provider CLI. Every failure here lands on the same
# floor: the URL path. That is deliberate — the CLIs change flags between releases and we
# refuse to be a product that breaks when they do.
publish_create() {
    _pub_root=$1; _pub_prov=$2; _pub_name=$3; _pub_vis=$4
    _pub_cli=$(publish_provider_field "$_pub_prov" 3)
    publish_cli_state "$_pub_cli" && _pub_st=0 || _pub_st=$?
    case $_pub_st in
        1) warn "$_pub_cli не установлен — создать репозиторий нечем"
           publish_install_hint "$_pub_cli"
           dim "    или создай репозиторий в браузере и запусти: fraim publish --url ССЫЛКА"
           return 1 ;;
        2) warn "$_pub_cli установлен, но вход не сделан"
           dim "    $_pub_cli auth login"
           dim "    или создай репозиторий в браузере и запусти: fraim publish --url ССЫЛКА"
           return 1 ;;
    esac

    say ""
    say "Создаю репозиторий «$_pub_name» ($_pub_vis) через $_pub_cli"
    case $_pub_prov in
        github)
            _pub_out=$(gh repo create "$_pub_name" "--$_pub_vis" \
                --source "$_pub_root" --remote origin 2>&1) || {
                warn "gh не смог создать репозиторий"
                printf '%s\n' "$_pub_out" | while read -r _pub_l; do dim "    $_pub_l"; done
                dim "    имя занято — попробуй 'fraim publish --name другое-имя'"
                dim "    нет прав на создание — 'gh auth refresh -s repo'"
                return 1
            }
            ;;
        gitlab)
            _pub_out=$(cd "$_pub_root" && glab repo create "$_pub_name" "--$_pub_vis" 2>&1) || {
                warn "glab не смог создать репозиторий"
                printf '%s\n' "$_pub_out" | while read -r _pub_l; do dim "    $_pub_l"; done
                dim "    создай репозиторий в браузере и запусти: fraim publish --url ССЫЛКА"
                return 1
            }
            ;;
    esac

    # Whether the CLI wired the remote itself is its business and changes between versions.
    # Ours is that the remote exists afterwards — so we look, and if it is not there we ask
    # the CLI for the address rather than guessing the host's URL shape.
    if [ -z "$(publish_remote_url "$_pub_root")" ]; then
        _pub_addr=$(publish_created_url "$_pub_prov" "$_pub_name")
        if [ -n "$_pub_addr" ]; then
            git -C "$_pub_root" remote add origin "$_pub_addr" 2>/dev/null || true
        fi
    fi
    _pub_have=$(publish_remote_url "$_pub_root")
    [ -n "$_pub_have" ] || {
        warn "репозиторий создан, но адрес не прописался"
        dim "    возьми ссылку на него и запусти: fraim publish --url ССЫЛКА"
        return 1
    }
    ok "репозиторий создан: $_pub_have"
    return 0
}

publish_created_url() {
    case $1 in
        github) gh repo view "$2" --json sshUrl --jq .sshUrl 2>/dev/null ;;
        gitlab) glab repo view "$2" 2>/dev/null | sed -n 's#.*\(git@[^ ]*\.git\).*#\1#p' | head -1 ;;
    esac
    return 0
}
