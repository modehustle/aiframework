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
    [ -z "$PUB_HOST" ] || printf '  %s %s\n' "$(wm_pad 'на хосте' 9)" "$(publish_host_line)"
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

# --- транспорт --------------------------------------------------------------
# Адрес и доступ — разные вещи, и до сих пор продукт их путал. Владелец получил
# `Permission denied (publickey)`, подсказка сказала «через gh это чинит gh auth login»,
# он честно её выполнил — `gh auth login` с протоколом HTTPS кладёт credential helper для
# https и НЕ кладёт ssh-ключ, — адрес остался ssh-овым, отправка снова упала, и цикл
# замкнулся. Подсказка была не просто бесполезной: она уводила от единственного рабочего
# действия.
#
# Пол здесь тот же, что и у всего модуля: URL. Если ключ не приняли, а gh уже держит
# авторизацию для https того же самого репозитория — меняется транспорт, и только он.
# Хост, имя, видимость, ветка не меняются: человек ратифицировал именно этот репозиторий,
# и он остаётся тем же. Замена говорится вслух и остаётся в ремоуте — молчаливая правка
# чужого репозитория здесь была бы хуже отказа.

publish_ssh_to_https() {
    case $1 in
        ssh://git@*) printf '%s\n' "$1" | sed 's#^ssh://git@#https://#' ;;
        # Двоеточие режется ровно одно — то, что отделяет хост от пути. Наивное
        # «убрать первое двоеточие» после подстановки схемы съело бы двоеточие самой
        # https:// и выдало бы адрес, которого не существует.
        git@*)       printf '%s\n' "$1" | sed 's#^git@\([^:/]*\):#https://\1/#' ;;
        *)           return 1 ;;
    esac
}

# Умеет ли git сам подставить логин для https этого хоста. Пустой ответ значит «нет»:
# переключить адрес и упереться в запрос пароля — это тот же тупик, только другими словами.
publish_https_credentials() {
    [ -n "$(git config --get-urlmatch credential.helper "$1" 2>/dev/null)" ]
}

# Возвращает 0, если транспорт заменён. Молча ничего не делает: каждая ветка отказа
# печатает, чего именно не хватило.
publish_transport_https() {
    _pub_root=$1
    _pub_have=$(publish_remote_url "$_pub_root")
    _pub_alt=$(publish_ssh_to_https "$_pub_have") || return 1
    publish_github_slug "$_pub_have" >/dev/null 2>&1 || return 1
    publish_cli_state gh || return 1

    if ! publish_https_credentials https://github.com; then
        # Это не «настроить машину за человека»: gh auth setup-git лишь дописывает в git
        # тот вход, который человек уже сделал командой gh auth login. Идемпотентно и
        # называется вслух — как и всё остальное, что эта команда трогает вне проекта.
        gh auth setup-git >/dev/null 2>&1 || return 1
        publish_https_credentials https://github.com || return 1
        dim "  git научен брать логин у gh (gh auth setup-git)"
    fi

    git -C "$_pub_root" remote set-url origin "$_pub_alt" 2>/dev/null || return 1
    say ""
    ok "адрес переключён на https: $_pub_alt"
    dim "  ssh-ключ этой машины хост не принял, а вход gh для https уже есть —"
    dim "  репозиторий тот же самый, поменялся только транспорт"
    return 0
}

# Что сказать, когда переключить нечем. Каждая строка — действие, а не диагноз.
publish_transport_hint() {
    _pub_have=$1
    _pub_alt=$(publish_ssh_to_https "$_pub_have") || {
        dim "    хост не принял логин — проверь доступ к репозиторию под своей учёткой"
        return 0
    }
    dim "    хост не принял ssh-ключ этой машины. Два выхода, оба рабочие:"
    dim "    · по https (ключ не нужен):  fraim publish --url $_pub_alt"
    case $_pub_have in
        *github.com*) dim "      для GitHub логин к https даёт gh: gh auth login, затем gh auth setup-git" ;;
        *)            dim "      логин к https спросит хост — понадобится токен доступа" ;;
    esac
    dim "    · по ssh (ключ нужен):       ssh-keygen -t ed25519, затем ключ на хост"
    case $_pub_have in
        *github.com*) dim "      для GitHub это одна команда: gh ssh-key add ~/.ssh/id_ed25519.pub" ;;
    esac
    return 0
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
        # Одна и только одна повторная попытка, и только при отказе по ключу: транспорт
        # меняется на тот, вход к которому уже есть. Повторять что-либо ещё было бы
        # надеждой, а не действием.
        _pub_retried=0
        case $_pub_out in
            *'Permission denied'*|*publickey*)
                if publish_transport_https "$_pub_root"; then
                    _pub_have=$(publish_remote_url "$_pub_root")
                    say ""
                    say "Отправляю $_pub_branch → $_pub_have"
                    _pub_retried=1
                fi ;;
        esac
        if [ "$_pub_retried" = 1 ]; then
            _pub_out=$(git -C "$_pub_root" push -u origin "$_pub_branch" 2>&1) || _pub_retried=2
        fi
        if [ "$_pub_retried" != 1 ]; then
            warn "отправка не удалась"
            printf '%s\n' "$_pub_out" | sed 's/^/    /' | while read -r _pub_l; do dim "$_pub_l"; done
            publish_push_hint "$_pub_out" "$_pub_have"
            return 1
        fi
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
            publish_transport_hint "${2:-}" ;;
        *'rejected'*|*'non-fast-forward'*|*'fetch first'*)
            dim "    в репозитории на хосте уже есть своя история — возьми пустой репозиторий или другое имя" ;;
        *'could not read Username'*|*'Authentication failed'*)
            dim "    хост просит логин к https по этому адресу:"
            case ${2:-} in
                *github.com*) dim "    · gh auth login, затем gh auth setup-git — дальше git берёт логин сам" ;;
                *)            dim "    · нужен токен доступа этого хоста, либо ssh-адрес и ключ на хосте" ;;
            esac ;;
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
        # Адрес в той форме, к которой у этой машины есть вход. `gh auth login` с
        # протоколом https не кладёт ssh-ключ, и sshUrl на такой машине — заведомо
        # нерабочий адрес: спрашиваем у gh, каким протоколом он сам живёт.
        github)
            if [ "$(gh config get git_protocol 2>/dev/null)" = ssh ]; then
                gh repo view "$2" --json sshUrl --jq .sshUrl 2>/dev/null
            else
                _pub_u=$(gh repo view "$2" --json url --jq .url 2>/dev/null)
                [ -n "$_pub_u" ] && printf '%s.git\n' "$_pub_u"
            fi ;;
        gitlab) glab repo view "$2" 2>/dev/null | sed -n 's#.*\(git@[^ ]*\.git\).*#\1#p' | head -1 ;;
    esac
    return 0
}

# --- правда с хоста ---------------------------------------------------------
# Локальная бухгалтерия «уехало / не уехало» — это `refs/remotes`, то есть память ЭТОЙ
# машины о прошлом push. Она врёт ровно в тех случаях, ради которых проверка и нужна:
# репозиторий на хосте создали и не наполнили, ветку там удалили, историю туда положили
# из другого места. Спросить можно только сам хост — поэтому это делает `publish`
# (команда человека, которой можно в сеть), а не сторож (D4: он без сети и без действий).
#
# PUB_HOST — одно слово, PUB_HOST_SHA — то, что лежит на хосте, когда оно там есть:
#   unreachable  хост не ответил
#   empty        на хосте нет ни одной ветки — «создан, но пуст»
#   synced       наша ветка там и совпадает с HEAD
#   behind       наша ветка там отстаёт, или её там нет вовсе
#   diverged     на хосте есть работа, которой нет здесь
PUB_HOST=
PUB_HOST_SHA=
PUB_HOST_ERR=
publish_host_state() {
    _pub_root=$1; _pub_br=$2
    PUB_HOST=; PUB_HOST_SHA=; PUB_HOST_ERR=
    # stderr ловится вместе с stdout, потому что причина отказа — это ответ, а не шум:
    # «хост не ответил» и «хост не принял твой ключ» чинятся разными руками, и второе
    # чинится нами. Строки рефов отбираются по форме (sha + refs/…), иначе безобидное
    # «Warning: Permanently added 'github.com' …» посчиталось бы веткой.
    if _pub_ls=$(git -C "$_pub_root" ls-remote --heads origin 2>&1); then
        _pub_ls=$(printf '%s\n' "$_pub_ls" | grep -E '^[0-9a-f]{7,40}[[:space:]]+refs/' || true)
    else
        PUB_HOST_ERR=$_pub_ls
        case $_pub_ls in
            *'Permission denied'*|*publickey*|*'Authentication failed'*|*'could not read Username'*)
                PUB_HOST=denied ;;
            *)  PUB_HOST=unreachable ;;
        esac
        return 0
    fi
    if [ -z "$_pub_ls" ]; then PUB_HOST=empty; return 0; fi
    PUB_HOST_SHA=$(printf '%s\n' "$_pub_ls" |
        awk -v b="refs/heads/$_pub_br" '$2 == b { print $1; exit }')
    if [ -z "$PUB_HOST_SHA" ]; then PUB_HOST=behind; return 0; fi
    _pub_local=$(publish_head "$_pub_root")
    if [ "$PUB_HOST_SHA" = "$_pub_local" ]; then PUB_HOST=synced; return 0; fi
    # Объекта с хоста может не быть у нас вовсе — тогда сверять нечем, и это по
    # определению расхождение: там лежит то, чего здесь не видели.
    if git -C "$_pub_root" cat-file -e "$PUB_HOST_SHA^{commit}" 2>/dev/null &&
       git -C "$_pub_root" merge-base --is-ancestor "$PUB_HOST_SHA" "$_pub_local" 2>/dev/null; then
        PUB_HOST=behind
    else
        PUB_HOST=diverged
    fi
    return 0
}

publish_host_line() {
    case $PUB_HOST in
        denied)      printf 'хост не принял доступ по этому адресу — сверить не с чем\n' ;;
        unreachable) printf 'хост не ответил — сверить не с чем\n' ;;
        empty)       printf 'репозиторий создан, но ПУСТ — история туда не доехала\n' ;;
        synced)      printf 'там ровно то же, что здесь\n' ;;
        behind)      printf 'там старее, чем здесь — часть точек не доехала\n' ;;
        diverged)    printf 'там есть работа, которой нет здесь\n' ;;
        *)           printf '\n' ;;
    esac
}

# --- задание агенту ---------------------------------------------------------
# Два места, где команда обязана остановиться и где «сделай сам» было бы просьбой о
# экспертизе, которой у пользователя может не быть (P0): секрет, уже лежащий в истории,
# и расхождение с хостом. Обе задачи требуют суждения и обе делаются инструментами,
# которых у системы нет и не будет: чистка истории — это ПЕРЕПИСЫВАНИЕ истории, а его
# fraim себе не позволяет нигде (`fraim undo` — встречный коммит, и это не случайность).
#
# Поэтому отказ печатает не совет, а готовое задание: самодостаточное, с фактами внутри
# и с границами, за которые агенту выходить нельзя. Блок печатается без цвета и без рамок
# по краям строк — его копируют целиком.
PUB_RULE='────────────────────────────────────────────────────────────────'

publish_brief_open() {
    say ""
    say "  ${C_BLD}Отдай это агенту — скопируй всё между линиями:${C_OFF}"
    printf '  %s%s%s\n' "$C_DIM" "$PUB_RULE" "$C_OFF"
}
publish_brief_close() {
    printf '  %s%s%s\n' "$C_DIM" "$PUB_RULE" "$C_OFF"
}

publish_refuse_secret() {
    _pub_root=$1; _pub_why=${2:-public}
    _pub_n=$(pub_count "$PUB_STOP")
    say ""
    printf '%s✗%s публикация остановлена: %s %s %s уезжать туда, где %s прочитают чужие\n' \
        "$C_RED" "$C_OFF" "$_pub_n" \
        "$(wm_plural "$_pub_n" находка находки находок)" \
        "$(wm_plural "$_pub_n" "не должна" "не должны" "не должны")" \
        "$(wm_plural "$_pub_n" "её" "их" "их")"
    say ""
    if [ "$_pub_why" = unknown ]; then
        say "  Кто увидит эту копию — неизвестно: адрес не GitHub или вход не сделан,"
        say "  проверить нечем. В приватную копию это можно отправить, приняв риск:"
        say "  скажи об этом явно — ${C_BLD}fraim publish --private${C_OFF} — или запусти команду в терминале"
        say "  и ответь на вопрос. Публичной копии находки не отдаются вовсе."
        say ""
    else
        say "  Репозиторий ${C_BLD}публичный${C_OFF} ($PUB_VIS_SRC): всё, что уедет, увидит любой."
        say "  Здесь нет варианта «приму риск» — принимать его пришлось бы не тебе одному."
        say ""
    fi
    say "  По порядку:"
    say "  1. Смени сам ключ там, где он выдан — он уже полежал в файле, это не отменить."
    if [ -z "$(publish_remote_url "$_pub_root")" ]; then
        say "  2. Копии нет: файл видели только на этой машине, спешки нет."
    else
        say "  2. Копия уже есть — считай, что файл там. Ключ меняется в любом случае."
    fi
    say "  3. Убрать его из истории — это переписывание истории. Единственная операция,"
    say "     которую система себе не позволяет: это работа для агента, не для fraim."

    publish_brief_secret "$_pub_root"
    say ""
    dim "  Если находка ложная (тестовая фикстура, пример в документации) — fraim publish --force."
    return 0
}

# То же задание, печатаемое по требованию: `fraim publish --brief`. Отказ — не единственный
# момент, когда его хотят: приняв риск однажды, чистку обычно заказывают позже и спокойно.
publish_brief_secret() {
    _pub_root=$1
    publish_brief_open
    printf 'Проект: %s\n' "$_pub_root"
    printf 'Задача: убрать из истории git то, что нельзя публиковать, и довести проект\n'
    printf 'до первой публикации.\n\n'
    printf 'Что нашёл `fraim publish` (смотрел всю историю, а не только рабочую папку):\n'
    _pub_ifs=$IFS; IFS='
'
    for _pub_line in $PUB_STOP; do
        [ -n "$_pub_line" ] || continue
        printf -- '  - %s — %s\n' "${_pub_line%%	*}" "${_pub_line#*	}"
    done
    IFS=$_pub_ifs
    cat <<'BRIEF'

Порядок работы:
1. Перечисли, какие именно ключи нужно отозвать и где это делается. Отзываю и
   меняю их я сам — ты только называешь, что и где.
2. Посмотри, публиковался ли репозиторий: git remote -v, git ls-remote.
3. Предложи, как вычистить найденное из ВСЕЙ истории (git filter-repo или BFG).
   Покажи команду и скажи, что именно она затрёт. Не запускай без моего «да»:
   это переписывание истории, откатить его нельзя.
4. После чистки прогони `fraim publish --check` — он должен сказать «чисто».

Границы:
- ничего не публиковать и не пушить;
- `fraim publish --force` не предлагать: он отправит найденное как есть;
- `fraim commit`, `fraim undo` и `fraim restore` историю не переписывают,
  для этой задачи они не подходят.
BRIEF
    publish_brief_close
    return 0
}

publish_refuse_diverged() {
    _pub_root=$1; _pub_url=$2; _pub_br=$3
    _pub_local=$(publish_head "$_pub_root")
    say ""
    printf '%s✗%s на хосте есть работа, которой нет здесь — отправлять нельзя\n' "$C_RED" "$C_OFF"
    say ""
    say "  Это не поломка, а развилка: кто-то отправлял в эту копию не с этой машины"
    say "  (вторая машина, веб-сессия, CI, другой человек). Свести их — суждение, и"
    say "  единственный способ сделать это «одной кнопкой» затёр бы чью-то работу."

    publish_brief_open
    printf 'Проект: %s\n' "$_pub_root"
    printf 'Задача: свести расхождение между этой машиной и удалённой копией.\n\n'
    printf 'Состояние (по `fraim publish`):\n'
    printf -- '  адрес:    %s\n' "$_pub_url"
    printf -- '  ветка:    %s\n' "$_pub_br"
    printf -- '  здесь:    %s\n' "$_pub_local"
    printf -- '  на хосте: %s — этого коммита здесь нет\n' "$PUB_HOST_SHA"
    printf '\nПорядок работы:\n'
    printf '1. Покажи, что там: git fetch origin, затем git log --oneline HEAD..origin/%s\n' "$_pub_br"
    cat <<'BRIEF'
2. Скажи словами, откуда это взялось и что будет потеряно в каждом варианте:
   взять ту работу сюда или отправить эту туда.
3. Ничего не сводить без моего «да». force-push не предлагать вовсе.
4. Когда сведено — я запущу `fraim publish`, он сверится с хостом сам.
BRIEF
    publish_brief_close
    return 0
}

# --- кому это будет видно ---------------------------------------------------
# Цена утечки ключа целиком определяется тем, кто сможет его прочитать, и одинаковый
# ответ на публичный и приватный репозиторий — плохой ответ в обе стороны. Для публичного
# «стоп» это единственно верное поведение. Для приватного тот же стоп превращается в
# стену на ровном месте: человек ЗНАЕТ, что копию видит только он, и требование сначала
# переписать историю не защищает его ни от чего — оно просто не даёт работать.
#
# Поэтому решает не находка, а видимость: приватный — находки становятся РАТИФИКАЦИЕЙ
# (показаны поимённо, отдельным явным «да», каждый раз), публичный — остаются стопом.
# Это ровно граница B5: стоп ради правильности остаётся, стоп ради права исчезает.
#
# Настройкой это не становится намеренно. Ключ вида `publish_secrets = off` выключил бы
# предупреждение НАВСЕГДА и молча — а по D3 обход обязан быть видимым. Ратификация видна
# каждый раз и стоит одного нажатия.
PUB_VIS=
PUB_VIS_SRC=

publish_github_slug() {
    case $1 in
        *github.com[:/]*) ;;
        *) return 1 ;;
    esac
    printf '%s' "$1" | sed 's#^.*github\.com[:/]##; s#\.git$##; s#/*$##'
}

# Что говорит сам хост. Работает только для GitHub через gh — там, где можно проверить,
# слово хоста бьёт любое утверждение человека: «у меня приватный» и «на самом деле
# публичный» это ровно тот случай, ради которого проверка и нужна.
publish_host_visibility() {
    _pub_url=$1
    _pub_slug=$(publish_github_slug "$_pub_url") || { printf 'unknown\n'; return 0; }
    publish_cli_state gh || { printf 'unknown\n'; return 0; }
    case $(gh repo view "$_pub_slug" --json isPrivate --jq .isPrivate 2>/dev/null) in
        true)  printf 'private\n' ;;
        false) printf 'public\n' ;;
        *)     printf 'unknown\n' ;;
    esac
}

# Итог: private / public / unknown — и откуда это известно. Порядок источников не
# случаен: сначала то, что можно проверить, и только потом то, что сказали.
publish_visibility_effective() {
    _pub_root=$1; _pub_vis=$2; _pub_prov=${3:-}
    _pub_have=$(publish_remote_url "$_pub_root")
    if [ -z "$_pub_have" ] && [ "$_pub_prov" != url ] &&
       { [ "$_pub_vis" = private ] || [ "$_pub_vis" = public ]; }; then
        # Репозиторий ещё не существует, и создаём его мы — здесь видимость не со слов,
        # а из той самой команды, которая его сейчас заведёт.
        PUB_VIS=$_pub_vis; PUB_VIS_SRC="создаём таким"
        return 0
    fi
    if [ -n "$_pub_have" ]; then
        _pub_hv=$(publish_host_visibility "$_pub_have")
        if [ "$_pub_hv" != unknown ]; then
            PUB_VIS=$_pub_hv; PUB_VIS_SRC="по данным хоста"
            return 0
        fi
    fi
    case $_pub_vis in
        private|public) PUB_VIS=$_pub_vis; PUB_VIS_SRC="с твоих слов" ;;
        *)              PUB_VIS=unknown;   PUB_VIS_SRC= ;;
    esac
    return 0
}

publish_ask_private() {
    say "${C_BLD}Кто сможет прочитать эту копию?${C_OFF}" >&2
    printf '  Проверить сами мы не можем: адрес не GitHub или вход не сделан.\n' >&2
    printf '  1) приватный %s— беру риск на себя, находки уедут как есть%s\n' "$C_DIM" "$C_OFF" >&2
    printf '  2) публичный или не знаю %s— остановиться (по умолчанию)%s\n' "$C_DIM" "$C_OFF" >&2
    printf '  Номер [2]: ' >&2
    read -r _pub_ans || _pub_ans=
    case $_pub_ans in
        1) printf 'private\n' ;;
        *) printf 'public\n' ;;
    esac
}

# Принятие риска говорится вслух и полностью: что именно уедет, куда, и чего это НЕ
# отменяет. Обещать «в приватном ничего не страшно» продукт не имеет права — приватный
# репозиторий переключается в публичный одной кнопкой, и история едет вместе с ним.
publish_accept_notice() {
    _pub_n=$1
    say ""
    printf '%s!%s %s %s %s в приватную копию как есть — %sпринято%s\n' \
        "$C_YEL" "$C_OFF" "$_pub_n" \
        "$(wm_plural "$_pub_n" "находка" "находки" "находок")" \
        "$(wm_plural "$_pub_n" "уедет" "уедут" "уедут")" "$C_BLD" "$C_OFF"
    dim "  приватность известна: $PUB_VIS_SRC"
    dim "  чего это не отменяет: ключ увидят все, у кого есть доступ к репозиторию, и он"
    dim "  останется в истории, если репозиторий когда-нибудь станет публичным"
    dim "  вычистить, а не принимать — fraim publish --brief (задание для агента)"
    return 0
}
