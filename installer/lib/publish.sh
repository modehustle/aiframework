#!/bin/sh
# publish.sh — the way out of "this project exists on one disk".
#
# The watchman has long said «no remote copy — the project lives only on this machine»
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
#      "cannot" — it is «create the repository in the browser and give me the link». No
#      dependency is hard, so no user is locked out by an install they cannot perform.
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
# The url row's label is words, not a brand: it comes from the catalog (pub_prov_url),
# and `-` here only holds the column.
publish_providers() {
    cat <<'TBL'
github|GitHub|gh|yes
gitlab|GitLab|glab|yes
url|-||no
TBL
}

publish_provider_field() {
    publish_providers | awk -F'|' -v k="$1" -v n="$2" '$1 == k { print $n; exit }'
}

publish_provider_known() { publish_providers | cut -d'|' -f1 | grep -qx "$1"; }

# --- dependencies -----------------------------------------------------------
# Never installs anything. The environment is the user's choice (C1), and a product that
# runs a package manager on someone's machine has stopped being a workflow layer. What we
# owe instead is the exact line to paste — by P0, "install gh" is not an instruction to
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
                debian) dim "    sudo apt install gh   ($(t pub_hint_no_pkg url=https://cli.github.com))" ;;
                fedora) dim "    sudo dnf install gh" ;;
                arch)   dim "    sudo pacman -S github-cli" ;;
                *)      dim "    https://cli.github.com — $(t pub_hint_install_page)" ;;
            esac
            dim "    $(t pub_hint_then_login cmd='gh auth login')"
            ;;
        glab)
            case $(publish_os) in
                macos)  dim "    brew install glab" ;;
                arch)   dim "    sudo pacman -S glab" ;;
                *)      dim "    https://gitlab.com/gitlab-org/cli — $(t pub_hint_install_page)" ;;
            esac
            dim "    $(t pub_hint_then_login cmd='glab auth login')"
            ;;
    esac
    return 0
}

# 0 — ready to work, 1 — no CLI, 2 — CLI present, but not logged in.
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

# The dependency screen. Answers "what am I missing" for every provider at once, so the
# user picks with the answer in front of them instead of discovering it after choosing.
publish_deps_report() {
    say "${C_BLD}$(t pub_deps_title)${C_OFF}"
    if command -v git >/dev/null 2>&1; then
        printf '  %s✓%s %s %s\n' "$C_GRN" "$C_OFF" "$(wm_pad git 26)" "$(git --version 2>/dev/null)"
    else
        printf '  %s✗%s %s %s\n' "$C_RED" "$C_OFF" "$(wm_pad git 26)" "$(t pub_deps_git_missing)"
        publish_install_hint git
    fi
    publish_providers | while IFS='|' read -r _pub_k _pub_lbl _pub_cli _pub_creates; do
        [ -n "$_pub_k" ] || continue
        [ "$_pub_k" != url ] || _pub_lbl=$(t pub_prov_url)
        if [ -z "$_pub_cli" ]; then
            printf '  %s·%s %s %s\n' "$C_DIM" "$C_OFF" "$(wm_pad "$_pub_lbl" 26)" \
                "$(t pub_deps_url_free)"
            continue
        fi
        publish_cli_state "$_pub_cli" && _pub_st=0 || _pub_st=$?
        case $_pub_st in
            0) printf '  %s✓%s %s %s\n' "$C_GRN" "$C_OFF" "$(wm_pad "$_pub_lbl ($_pub_cli)" 26)" \
                   "$(t pub_deps_ready)$(_pub_acc=$(publish_cli_account "$_pub_cli"); [ -n "$_pub_acc" ] && t pub_deps_account account="$_pub_acc")" ;;
            1) printf '  %s·%s %s %s\n' "$C_DIM" "$C_OFF" "$(wm_pad "$_pub_lbl ($_pub_cli)" 26)" "$(t pub_deps_not_installed)"
               publish_install_hint "$_pub_cli" ;;
            2) printf '  %s!%s %s %s\n' "$C_YEL" "$C_OFF" "$(wm_pad "$_pub_lbl ($_pub_cli)" 26)" \
                   "$(t pub_deps_no_login)"
               dim "    $_pub_cli auth login" ;;
        esac
    done
    return 0
}

# --- what is in this repository --------------------------------------------
# All four answer «empty», never «error»: a project with no remote and a project with no
# commits are both normal states here, and the CLI runs under `set -e` — a bare failing
# `git remote get-url` inside a command substitution would end the command instead of
# reporting the state it was asked about.
publish_remote_url() { git -C "$1" remote get-url origin 2>/dev/null || true; }
publish_branch()     { git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null || true; }
# --verify, not a bare rev-parse: in a repository with no commits `git rev-parse HEAD`
# prints the string "HEAD" and fails, and «empty» read as a commit id is exactly the kind
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
#
# A stop records a KIND (env, ssh, aws…), not words: the same finding is said to the human in
# their language (pub_find_<kind>) and to the agent, in the brief, in English
# (publish_finding_en). A warning is only ever shown to the human, so it records the words.
publish_scan() {
    _pub_root=$1
    PUB_STOP=; PUB_WARN=

    verb_is_git "$_pub_root" || {
        pub_stop_add "-" no_repo
        return 0
    }
    [ -n "$(publish_head "$_pub_root")" ] || {
        pub_stop_add "-" no_commits
        return 0
    }

    _pub_paths=$(publish_history_paths "$_pub_root")

    # Names, over the whole history. `.env.example` and friends are the documented
    # counterpart of a secret file and are supposed to travel — excluded by name.
    _pub_paths_real=$(printf '%s\n' "$_pub_paths" |
        grep -Ev '\.(example|sample|template|dist)$' || true)

    publish_scan_names "$_pub_paths_real" '(^|/)\.env($|\.)' env
    publish_scan_names "$_pub_paths_real" '(^|/)id_(rsa|dsa|ecdsa|ed25519)$|(^|/)\.ssh/' ssh
    # .asc and .gpg are not included: release signatures and sops/git-crypt files live in
    # repositories legitimately and encrypted, and a false stop teaches people to walk past stops.
    publish_scan_names "$_pub_paths_real" '\.(pem|key|p12|pfx|jks|keystore|ppk)$' keyfile
    publish_scan_names "$_pub_paths_real" '(^|/)\.(npmrc|pypirc|netrc|htpasswd)$' tokenfile
    publish_scan_names "$_pub_paths_real" '(^|/)(credentials|secrets?)\.(json|ya?ml|toml|ini)$|(^|/)service[-_]account[^/]*\.json$' \
        credfile

    # Contents, current snapshot. -I skips binaries; the pattern set is deliberately the
    # shape of issued credentials (prefix + length), not the word "password", because a
    # scanner that fires on every README is a scanner people learn to wave through.
    publish_scan_content "$_pub_root" '-----BEGIN [A-Z ]*PRIVATE KEY-----' pem
    publish_scan_content "$_pub_root" 'AKIA[0-9A-Z]{16}' aws
    publish_scan_content "$_pub_root" '(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})' github
    publish_scan_content "$_pub_root" 'glpat-[A-Za-z0-9_-]{16,}' gitlab
    publish_scan_content "$_pub_root" 'sk-(ant-)?[A-Za-z0-9_-]{24,}' api
    publish_scan_content "$_pub_root" 'xox[baprs]-[A-Za-z0-9-]{10,}' slack
    publish_scan_content "$_pub_root" 'AIza[0-9A-Za-z_-]{35}' google

    # Below the line: visible in the plan, never blocking. Each of these is legitimate in
    # somebody's project, and a stop that is wrong half the time teaches the user to pass
    # --force by reflex — which is how the real stop above stops working.
    publish_scan_warn_names "$_pub_paths" '(^|/)(node_modules|venv|\.venv|__pycache__|vendor)/' \
        "$(t pub_warn_deps)"
    # No .sql: migrations are code, and they sit in everyone's history.
    publish_scan_warn_names "$_pub_paths" '\.(sqlite3?|db|dump|tfstate)$' \
        "$(t pub_warn_data)"

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

# Big blobs. The number matters more than the noun: "12 MB in history" is a fact the
# human can act on, "a big file" is not.
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
        pub_warn_add "${_pub_line#*	}" "$(t pub_warn_size mb="${_pub_line%%	*}")"
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
        pub_warn_add "$_pub_f" "$(t pub_warn_unignored)"
    done
    return 0
}

publish_scan_show() {
    _pub_ns=$(pub_count "$PUB_STOP")
    _pub_nw=$(pub_count "$PUB_WARN")
    if [ "$_pub_ns" -eq 0 ] && [ "$_pub_nw" -eq 0 ]; then
        ok "$(t pub_scan_clean)"
        dim "  $(t pub_scan_scope)"
        return 0
    fi
    say "${C_BLD}$(t pub_scan_title)${C_OFF}"
    _pub_ifs=$IFS; IFS='
'
    for _pub_line in $PUB_STOP; do
        [ -n "$_pub_line" ] || continue
        printf '  %s✗%s %s %s— %s%s\n' "$C_RED" "$C_OFF" "${_pub_line%%	*}" \
            "$C_DIM" "$(t "pub_find_${_pub_line#*	}")" "$C_OFF"
    done
    for _pub_line in $PUB_WARN; do
        [ -n "$_pub_line" ] || continue
        printf '  %s!%s %s %s— %s%s\n' "$C_YEL" "$C_OFF" "${_pub_line%%	*}" \
            "$C_DIM" "${_pub_line#*	}" "$C_OFF"
    done
    IFS=$_pub_ifs
    dim "  $(t pub_scan_scope_values)"
    return 0
}

# The agent's words for a stop kind — the brief is English whatever the operator's language.
publish_finding_en() {
    case $1 in
        no_repo)    printf 'there is no repository here — nothing to send' ;;
        no_commits) printf 'there is not a single save point — nothing to send' ;;
        env)        printf 'environment file — passwords and keys live in it' ;;
        ssh)        printf 'private ssh key' ;;
        keyfile)    printf 'key or certificate' ;;
        tokenfile)  printf 'file with an access token' ;;
        credfile)   printf 'credentials file' ;;
        pem)        printf 'private key right in the file' ;;
        aws)        printf 'AWS key' ;;
        github)     printf 'GitHub token' ;;
        gitlab)     printf 'GitLab token' ;;
        api)        printf 'API key (OpenAI / Anthropic)' ;;
        slack)      printf 'Slack token' ;;
        google)     printf 'Google key' ;;
        *)          printf '%s' "$1" ;;
    esac
}

# --- naming -----------------------------------------------------------------
# GitHub and GitLab both accept only [A-Za-z0-9._-] in a repository name. A folder called
# «payments api» written in Cyrillic is a perfectly good folder, so the name is sanitised
# rather than refused — and the substitution is printed, because a repository that quietly
# got a different name than the folder is a small mystery for later.
publish_repo_name() {
    _pub_name=$(printf '%s' "$1" | sed 's#[^A-Za-z0-9._/-]#-#g; s#--*#-#g; s#^-##; s#-$##')
    # A folder named entirely in Cyrillic sanitises to nothing. Refusing would be honest
    # and useless; the plan prints the name it is about to use, and --name overrides it.
    [ -n "$_pub_name" ] || _pub_name=project
    printf '%s\n' "$_pub_name"
}

publish_vis_label() {
    case $1 in
        private) printf '%s\n' "$(t pub_vis_private)" ;;
        public)  printf '%s%s%s\n' "$C_YEL" "$(t pub_vis_public)" "$C_OFF" ;;
        *)       printf '%s\n' "$(t pub_vis_host)" ;;
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

    say "${C_BLD}$(t pub_plan_title name="$(basename -- "$_pub_root")")${C_OFF}"
    say ""
    # wm_pad, not printf's %-10s: %-Ns counts BYTES, and every Cyrillic letter is two of
    # them — the labels "access" and "what goes" would sit in different columns.
    if [ -n "$_pub_have" ]; then
        printf '  %s %s\n' "$(wm_pad "$(t pub_plan_where)" 9)" "$(t pub_plan_have url="$_pub_have")"
    elif [ "$_pub_prov" = url ]; then
        printf '  %s %s\n' "$(wm_pad "$(t pub_plan_where)" 9)" "$_pub_url"
    else
        printf '  %s %s\n' "$(wm_pad "$(t pub_plan_where)" 9)" \
            "$(t pub_plan_create host="$(publish_provider_field "$_pub_prov" 2)" name="$_pub_name")"
    fi
    [ -z "$PUB_HOST" ] || printf '  %s %s\n' "$(wm_pad "$(t pub_plan_host)" 9)" "$(publish_host_line)"
    printf '  %s %s\n' "$(wm_pad "$(t pub_plan_access)" 9)" "$(publish_vis_label "$_pub_vis")"
    printf '  %s %s%s\n' "$(wm_pad "$(t pub_plan_goes)" 9)" \
        "$(tp "${_pub_n:-0}" pub_plan_payload branch="$_pub_branch")" \
        "${_pub_size:+$(t pub_plan_size size="$_pub_size")}"
    dim "            $(t pub_plan_note)"
    say ""
    publish_scan_show
    return 0
}

# --- asking -----------------------------------------------------------------
# The fork BACKLOG §3 called real is real, and it stays a question. What changed is only
# who carries it: it used to be a conversation the user had to know how to start, and now
# it is two numbered lines with the state of each option already filled in.
publish_ask_provider() {
    say "${C_BLD}$(t pub_ask_where)${C_OFF}" >&2
    _pub_i=0
    _pub_def=
    publish_providers | while IFS='|' read -r _pub_k _pub_lbl _pub_cli _pub_creates; do
        [ -n "$_pub_k" ] || continue
        _pub_i=$((_pub_i + 1))
        [ "$_pub_k" != url ] || _pub_lbl=$(t pub_prov_url)
        if [ -z "$_pub_cli" ]; then
            printf '  %s) %s %s%s%s\n' "$_pub_i" "$(wm_pad "$_pub_lbl" 34)" \
                "$C_DIM" "$(t pub_ask_always)" "$C_OFF" >&2
            continue
        fi
        publish_cli_state "$_pub_cli" && _pub_st=0 || _pub_st=$?
        case $_pub_st in
            0) printf '  %s) %s %s%s%s\n' "$_pub_i" "$(wm_pad "$_pub_lbl" 34)" \
                   "$C_GRN" "$(t pub_ask_ready cli="$_pub_cli")" "$C_OFF" >&2 ;;
            1) printf '  %s) %s %s%s%s\n' "$_pub_i" "$(wm_pad "$_pub_lbl" 34)" \
                   "$C_DIM" "$(t pub_ask_missing cli="$_pub_cli")" "$C_OFF" >&2 ;;
            2) printf '  %s) %s %s%s%s\n' "$_pub_i" "$(wm_pad "$_pub_lbl" 34)" \
                   "$C_YEL" "$(t pub_ask_no_login cli="$_pub_cli")" "$C_OFF" >&2 ;;
        esac
    done
    # The default is the first READY option, not the first in the list: offering GitHub
    # where gh is not installed means leading the human into a refusal two screens later.
    _pub_def=$(publish_default_provider)
    printf '  %s ' "$(t pub_ask_number def="$_pub_def")" >&2
    read -r _pub_ans || _pub_ans=
    [ -n "$_pub_ans" ] || _pub_ans=$_pub_def
    _pub_pick=$(publish_providers | sed -n "${_pub_ans}p" | cut -d'|' -f1 2>/dev/null)
    [ -n "$_pub_pick" ] || return 1
    printf '%s\n' "$_pub_pick"
}

# The number of the first option that can be used right now. The floor (URL) is always
# ready, so there is an answer in any state of the machine.
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
    say "${C_BLD}$(t pub_ask_who)${C_OFF}" >&2
    printf '  1) %s %s— %s%s\n' "$(t pub_ask_private)" "$C_DIM" "$(t pub_ask_private_note)" "$C_OFF" >&2
    printf '  2) %s %s— %s%s\n' "$(t pub_ask_public)" "$C_DIM" "$(t pub_ask_public_note)" "$C_OFF" >&2
    printf '  %s ' "$(t pub_ask_number def=1)" >&2
    read -r _pub_ans || _pub_ans=
    case $_pub_ans in
        2) printf 'public\n' ;;
        *) printf 'private\n' ;;
    esac
}

publish_ask_url() {
    say "${C_BLD}$(t pub_ask_url_title)${C_OFF}" >&2
    dim "  $(t pub_ask_url_hint1)" >&2
    dim "  $(t pub_ask_url_hint2)" >&2
    printf '  %s ' "$(t pub_ask_url_prompt)" >&2
    read -r _pub_ans || _pub_ans=
    [ -n "$_pub_ans" ] || return 1
    printf '%s\n' "$_pub_ans"
}

# --- transport --------------------------------------------------------------
# Address and access are different things, and until now the product confused them. The
# owner got `Permission denied (publickey)`, the hint said "with gh this is fixed by gh auth
# login", he honestly ran it — `gh auth login` with the HTTPS protocol installs a credential
# helper for https and does NOT install an ssh key — the address stayed ssh, the push failed
# again, and the loop closed. The hint was not merely useless: it led away from the only
# action that worked.
#
# The floor here is the same as for the whole module: the URL. If the key was not accepted
# and gh already holds authorisation for https to the very same repository — the transport
# changes, and only the transport. Host, name, visibility, branch do not change: the human
# ratified exactly this repository, and it stays the same. The replacement is said out loud
# and stays in the remote — a silent edit of someone's repository would be worse than a refusal.

publish_ssh_to_https() {
    case $1 in
        ssh://git@*) printf '%s\n' "$1" | sed 's#^ssh://git@#https://#' ;;
        # Exactly one colon is cut — the one that separates the host from the path. A naive
        # "remove the first colon" after substituting the scheme would eat the colon of
        # https:// itself and produce an address that does not exist.
        git@*)       printf '%s\n' "$1" | sed 's#^git@\([^:/]*\):#https://\1/#' ;;
        *)           return 1 ;;
    esac
}

# Whether git can supply the login for https to this host by itself. An empty answer means
# "no": switching the address and hitting a password prompt is the same dead end in other words.
publish_https_credentials() {
    [ -n "$(git config --get-urlmatch credential.helper "$1" 2>/dev/null)" ]
}

# Returns 0 if the transport was replaced. Never does nothing silently: every refusal branch
# prints what exactly was missing.
publish_transport_https() {
    _pub_root=$1
    _pub_have=$(publish_remote_url "$_pub_root")
    _pub_alt=$(publish_ssh_to_https "$_pub_have") || return 1
    publish_github_slug "$_pub_have" >/dev/null 2>&1 || return 1
    publish_cli_state gh || return 1

    if ! publish_https_credentials https://github.com; then
        # This is not "setting up the machine for the human": gh auth setup-git only adds to
        # git the login the human already made with gh auth login. Idempotent and said out
        # loud — like everything else this command touches outside the project.
        gh auth setup-git >/dev/null 2>&1 || return 1
        publish_https_credentials https://github.com || return 1
        dim "  $(t pub_tr_setup_git)"
    fi

    git -C "$_pub_root" remote set-url origin "$_pub_alt" 2>/dev/null || return 1
    say ""
    ok "$(t pub_tr_switched url="$_pub_alt")"
    dim "  $(t pub_tr_why1)"
    dim "  $(t pub_tr_why2)"
    return 0
}

# What to say when there is nothing to switch to. Every line is an action, not a diagnosis.
publish_transport_hint() {
    _pub_have=$1
    _pub_alt=$(publish_ssh_to_https "$_pub_have") || {
        dim "    $(t pub_th_login)"
        return 0
    }
    dim "    $(t pub_th_key)"
    dim "    · $(wm_pad "$(t pub_th_https)" 26) fraim publish --url $_pub_alt"
    case $_pub_have in
        *github.com*) dim "      $(t pub_th_gh_https)" ;;
        *)            dim "      $(t pub_th_token)" ;;
    esac
    dim "    · $(wm_pad "$(t pub_th_ssh)" 26) $(t pub_th_ssh_do)"
    case $_pub_have in
        *github.com*) dim "      $(t pub_th_gh_ssh)" ;;
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
        { warn "$(t pub_do_detached)"; return 1; }

    if [ -z "$(publish_remote_url "$_pub_root")" ]; then
        case $_pub_prov in
            url)
                git -C "$_pub_root" remote add origin "$_pub_url" 2>/dev/null ||
                    { warn "$(t pub_do_addr_fail url="$_pub_url")"; return 1; }
                ok "$(t pub_do_addr_set url="$_pub_url")"
                ;;
            *)
                publish_create "$_pub_root" "$_pub_prov" "$_pub_name" "$_pub_vis" || return 1
                ;;
        esac
    fi

    _pub_have=$(publish_remote_url "$_pub_root")
    say ""
    say "$(t pub_do_sending branch="$_pub_branch" url="$_pub_have")"
    if ! _pub_out=$(git -C "$_pub_root" push -u origin "$_pub_branch" 2>&1); then
        # One and only one retry, and only on a key refusal: the transport changes to the one
        # for which a login already exists. Repeating anything else would be hope, not
        # action.
        _pub_retried=0
        case $_pub_out in
            *'Permission denied'*|*publickey*)
                if publish_transport_https "$_pub_root"; then
                    _pub_have=$(publish_remote_url "$_pub_root")
                    say ""
                    say "$(t pub_do_sending branch="$_pub_branch" url="$_pub_have")"
                    _pub_retried=1
                fi ;;
        esac
        if [ "$_pub_retried" = 1 ]; then
            _pub_out=$(git -C "$_pub_root" push -u origin "$_pub_branch" 2>&1) || _pub_retried=2
        fi
        if [ "$_pub_retried" != 1 ]; then
            warn "$(t pub_do_push_failed)"
            printf '%s\n' "$_pub_out" | sed 's/^/    /' | while read -r _pub_l; do dim "$_pub_l"; done
            publish_push_hint "$_pub_out" "$_pub_have"
            return 1
        fi
    fi
    ok "$(t pub_do_sent)"

    # Verification, not optimism.
    _pub_local=$(publish_head "$_pub_root")
    _pub_remote=$(git -C "$_pub_root" ls-remote origin "refs/heads/$_pub_branch" 2>/dev/null | cut -f1)
    if [ -n "$_pub_remote" ] && [ "$_pub_remote" = "$_pub_local" ]; then
        ok "$(t pub_do_verified sha="$(printf '%s' "$_pub_local" | cut -c1-7)")"
    else
        warn "$(t pub_do_mismatch remote="${_pub_remote:-$(t pub_do_nothing_seen)}")"
        dim "    $(t pub_do_look)"
        return 1
    fi

    say ""
    ok "$(t pub_do_done url="$_pub_have")"
    dim "  $(t pub_do_next)"
    dim "  $(t pub_do_not_backup)"
    return 0
}

publish_push_hint() {
    case $1 in
        *'Permission denied'*|*'publickey'*)
            publish_transport_hint "${2:-}" ;;
        *'rejected'*|*'non-fast-forward'*|*'fetch first'*)
            dim "    $(t pub_ph_rejected)" ;;
        *'could not read Username'*|*'Authentication failed'*)
            dim "    $(t pub_ph_https_login)"
            case ${2:-} in
                *github.com*) dim "    · $(t pub_ph_gh)" ;;
                *)            dim "    · $(t pub_ph_token)" ;;
            esac ;;
        *'not found'*|*'does not appear to be a git repository'*)
            dim "    $(t pub_ph_not_found)" ;;
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
        1) warn "$(t pub_cr_no_cli cli="$_pub_cli")"
           publish_install_hint "$_pub_cli"
           dim "    $(t pub_cr_or_browser)"
           return 1 ;;
        2) warn "$(t pub_cr_no_login cli="$_pub_cli")"
           dim "    $_pub_cli auth login"
           dim "    $(t pub_cr_or_browser)"
           return 1 ;;
    esac

    say ""
    say "$(t pub_cr_creating name="$_pub_name" vis="$_pub_vis" cli="$_pub_cli")"
    case $_pub_prov in
        github)
            _pub_out=$(gh repo create "$_pub_name" "--$_pub_vis" \
                --source "$_pub_root" --remote origin 2>&1) || {
                warn "$(t pub_cr_failed cli=gh)"
                printf '%s\n' "$_pub_out" | while read -r _pub_l; do dim "    $_pub_l"; done
                dim "    $(t pub_cr_name_taken)"
                dim "    $(t pub_cr_no_rights)"
                return 1
            }
            ;;
        gitlab)
            _pub_out=$(cd "$_pub_root" && glab repo create "$_pub_name" "--$_pub_vis" 2>&1) || {
                warn "$(t pub_cr_failed cli=glab)"
                printf '%s\n' "$_pub_out" | while read -r _pub_l; do dim "    $_pub_l"; done
                dim "    $(t pub_cr_browser)"
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
        warn "$(t pub_cr_no_addr)"
        dim "    $(t pub_cr_take_link)"
        return 1
    }
    ok "$(t pub_cr_done url="$_pub_have")"
    return 0
}

publish_created_url() {
    case $1 in
        # The address in the form this machine has a login for. `gh auth login` with the
        # https protocol does not install an ssh key, and sshUrl on such a machine is a
        # knowingly broken address: we ask gh which protocol it itself lives on.
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

# --- the truth from the host ------------------------------------------------
# Local "left / did not leave" bookkeeping is `refs/remotes`, i.e. THIS machine's memory of
# the last push. It lies in exactly the cases the check exists for: the repository on the
# host was created and not filled, the branch there was deleted, history was put there from
# somewhere else. Only the host itself can be asked — so this is done by `publish` (the
# human's command, which is allowed onto the network), not by the watchman (D4: it has no
# network and no actions).
#
# PUB_HOST — one word, PUB_HOST_SHA — what is on the host, when there is something there:
#   unreachable  the host did not answer
#   empty        the host has not a single branch — "created, but empty"
#   synced       our branch is there and matches HEAD
#   behind       our branch there lags behind, or is not there at all
#   diverged     the host has work that is not here
PUB_HOST=
PUB_HOST_SHA=
PUB_HOST_ERR=
publish_host_state() {
    _pub_root=$1; _pub_br=$2
    PUB_HOST=; PUB_HOST_SHA=; PUB_HOST_ERR=
    # stderr is captured together with stdout, because the reason for a refusal is an answer,
    # not noise: "the host did not answer" and "the host did not accept your key" are fixed
    # by different hands, and the second is fixed by us. Ref lines are picked by their shape
    # (sha + refs/…), otherwise a harmless "Warning: Permanently added 'github.com' …"
    # would count as a branch.
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
    # The object from the host may not exist here at all — then there is nothing to compare
    # against, and that is by definition divergence: there is something there not seen here.
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
        denied)      printf '%s\n' "$(t pub_host_denied)" ;;
        unreachable) printf '%s\n' "$(t pub_host_unreachable)" ;;
        empty)       printf '%s\n' "$(t pub_host_empty)" ;;
        synced)      printf '%s\n' "$(t pub_host_synced)" ;;
        behind)      printf '%s\n' "$(t pub_host_behind)" ;;
        diverged)    printf '%s\n' "$(t pub_host_diverged)" ;;
        *)           printf '\n' ;;
    esac
}

# --- a task for the agent ---------------------------------------------------
# Two places where the command must stop and where "do it yourself" would be a request for
# expertise the user may not have (P0): a secret already sitting in history, and divergence
# from the host. Both tasks need judgement and both are done with tools the system does not
# and will not have: cleaning history is REWRITING history, and fraim never allows itself
# that anywhere (`fraim undo` is a counter-commit, and that is no accident).
#
# So the refusal prints not advice but a ready task: self-contained, with the facts inside
# and with the boundaries the agent must not cross. The block is printed without colour and
# without borders at the line edges — it is copied whole.
PUB_RULE='────────────────────────────────────────────────────────────────'

publish_brief_open() {
    say ""
    say "  ${C_BLD}$(t pub_brief_hand)${C_OFF}"
    printf '  %s%s%s\n' "$C_DIM" "$PUB_RULE" "$C_OFF"
}
publish_brief_close() {
    printf '  %s%s%s\n' "$C_DIM" "$PUB_RULE" "$C_OFF"
}

publish_refuse_secret() {
    _pub_root=$1; _pub_why=${2:-public}
    _pub_n=$(pub_count "$PUB_STOP")
    say ""
    printf '%s✗%s %s\n' "$C_RED" "$C_OFF" "$(tp "$_pub_n" pub_refuse_stopped)"
    say ""
    if [ "$_pub_why" = unknown ]; then
        say "  $(t pub_rs_unknown1)"
        say "  $(t pub_rs_unknown2)"
        say "  $(t pub_rs_unknown3 cmd="${C_BLD}fraim publish --private${C_OFF}")"
        say "  $(t pub_rs_unknown4)"
        say ""
    else
        say "  $(t pub_rs_public public="${C_BLD}$(t pub_rs_public_word)${C_OFF}" src="$PUB_VIS_SRC")"
        say "  $(t pub_rs_no_accept)"
        say ""
    fi
    say "  $(t pub_rs_order)"
    say "  $(t pub_rs_step1)"
    if [ -z "$(publish_remote_url "$_pub_root")" ]; then
        say "  $(t pub_rs_step2_none)"
    else
        say "  $(t pub_rs_step2_copy)"
    fi
    say "  $(t pub_rs_step3a)"
    say "     $(t pub_rs_step3b)"

    publish_brief_secret "$_pub_root"
    say ""
    dim "  $(t pub_rs_false)"
    return 0
}

# The same task, printed on demand: `fraim publish --brief`. A refusal is not the only moment
# it is wanted: having accepted the risk once, the cleanup is usually ordered later and calmly.
publish_brief_secret() {
    _pub_root=$1
    publish_brief_open
    printf 'Project: %s\n' "$_pub_root"
    printf 'Task: remove from the git history what must not be published, and bring the\n'
    printf 'project to its first publication.\n\n'
    printf 'What `fraim publish` found (it read the whole history, not just the working tree):\n'
    _pub_ifs=$IFS; IFS='
'
    for _pub_line in $PUB_STOP; do
        [ -n "$_pub_line" ] || continue
        printf -- '  - %s — %s\n' "${_pub_line%%	*}" "$(publish_finding_en "${_pub_line#*	}")"
    done
    IFS=$_pub_ifs
    cat <<'BRIEF'

Steps:
1. List exactly which keys must be revoked and where that is done. I revoke and
   replace them myself — you only name what and where.
2. Check whether the repository was ever published: git remote -v, git ls-remote.
3. Propose how to remove the findings from the WHOLE history (git filter-repo or BFG).
   Show the command and say exactly what it will erase. Do not run it without my yes:
   it rewrites history and cannot be undone.
4. After the cleanup run `fraim publish --check` — it must report clean.

Limits:
- publish nothing and push nothing;
- do not suggest `fraim publish --force`: it would send the findings as they are;
- `fraim commit`, `fraim undo` and `fraim restore` do not rewrite history and do
  not fit this task.
BRIEF
    publish_brief_close
    return 0
}

publish_refuse_diverged() {
    _pub_root=$1; _pub_url=$2; _pub_br=$3
    _pub_local=$(publish_head "$_pub_root")
    say ""
    printf '%s✗%s %s\n' "$C_RED" "$C_OFF" "$(t pub_rd_title)"
    say ""
    say "  $(t pub_rd_1)"
    say "  $(t pub_rd_2)"
    say "  $(t pub_rd_3)"

    publish_brief_open
    printf 'Project: %s\n' "$_pub_root"
    printf 'Task: reconcile the divergence between this machine and the remote copy.\n\n'
    printf 'State (as `fraim publish` sees it):\n'
    printf -- '  url:     %s\n' "$_pub_url"
    printf -- '  branch:  %s\n' "$_pub_br"
    printf -- '  here:    %s\n' "$_pub_local"
    printf -- '  remote:  %s — this commit is not here\n' "$PUB_HOST_SHA"
    printf '\nSteps:\n'
    printf '1. Show what is there: git fetch origin, then git log --oneline HEAD..origin/%s\n' "$_pub_br"
    cat <<'BRIEF'
2. Say in words where it came from and what each option would lose:
   bring that work here, or send this work there.
3. Reconcile nothing without my yes. Never suggest a force-push.
4. Once reconciled, I run `fraim publish` — it checks against the remote itself.
BRIEF
    publish_brief_close
    return 0
}

# --- who will be able to see it ---------------------------------------------
# The cost of a leaked key is wholly determined by who will be able to read it, and the same
# answer for a public and a private repository is a bad answer both ways. For a public one a
# "stop" is the only correct behaviour. For a private one the same stop turns into a wall out
# of nowhere: the human KNOWS that only they see the copy, and a demand to rewrite history
# first protects them from nothing — it simply keeps them from working.
#
# So what decides is not the finding but the visibility: private — the findings become a
# RATIFICATION (shown one by one, with a separate explicit "yes", every time), public — they
# stay a stop. This is exactly the B5 line: a stop for correctness stays, a stop for
# permission disappears.
#
# This deliberately does not become a setting. A key like `publish_secrets = off` would turn
# the warning off FOREVER and silently — and by D3 a bypass must be visible. Ratification is
# visible every time and costs one keypress.
PUB_VIS=
PUB_VIS_SRC=

publish_github_slug() {
    case $1 in
        *github.com[:/]*) ;;
        *) return 1 ;;
    esac
    printf '%s' "$1" | sed 's#^.*github\.com[:/]##; s#\.git$##; s#/*$##'
}

# What the host itself says. Works only for GitHub through gh — where it can be checked, the
# host's word beats any claim by the human: "mine is private" and "actually public" is
# exactly the case the check exists for.
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

# Result: private / public / unknown — and how it is known. The order of sources is not
# accidental: first what can be checked, and only then what was said.
publish_visibility_effective() {
    _pub_root=$1; _pub_vis=$2; _pub_prov=${3:-}
    _pub_have=$(publish_remote_url "$_pub_root")
    if [ -z "$_pub_have" ] && [ "$_pub_prov" != url ] &&
       { [ "$_pub_vis" = private ] || [ "$_pub_vis" = public ]; }; then
        # The repository does not exist yet, and we are the ones creating it — here the
        # visibility is not hearsay but comes from the very command that is about to create it.
        PUB_VIS=$_pub_vis; PUB_VIS_SRC=$(t pub_vis_src_creating)
        return 0
    fi
    if [ -n "$_pub_have" ]; then
        _pub_hv=$(publish_host_visibility "$_pub_have")
        if [ "$_pub_hv" != unknown ]; then
            PUB_VIS=$_pub_hv; PUB_VIS_SRC=$(t pub_vis_src_host)
            return 0
        fi
    fi
    case $_pub_vis in
        private|public) PUB_VIS=$_pub_vis; PUB_VIS_SRC=$(t pub_vis_src_said) ;;
        *)              PUB_VIS=unknown;   PUB_VIS_SRC= ;;
    esac
    return 0
}

publish_ask_private() {
    say "${C_BLD}$(t pub_ap_title)${C_OFF}" >&2
    printf '  %s\n' "$(t pub_ap_cant)" >&2
    printf '  1) %s %s— %s%s\n' "$(t pub_ask_private)" "$C_DIM" "$(t pub_ap_private_note)" "$C_OFF" >&2
    printf '  2) %s %s— %s%s\n' "$(t pub_ap_public)" "$C_DIM" "$(t pub_ap_public_note)" "$C_OFF" >&2
    printf '  %s ' "$(t pub_ask_number def=2)" >&2
    read -r _pub_ans || _pub_ans=
    case $_pub_ans in
        1) printf 'private\n' ;;
        *) printf 'public\n' ;;
    esac
}

# Accepting the risk is said out loud and in full: what exactly will leave, where to, and what
# it does NOT undo. The product has no right to promise "nothing to fear in a private one" — a
# private repository is switched to public with one button, and the history goes along with it.
publish_accept_notice() {
    _pub_n=$1
    say ""
    printf '%s!%s %s — %s%s%s\n' "$C_YEL" "$C_OFF" "$(tp "$_pub_n" pub_accept_goes)" \
        "$C_BLD" "$(t pub_accept_accepted)" "$C_OFF"
    dim "  $(t pub_accept_src src="$PUB_VIS_SRC")"
    dim "  $(t pub_accept_not1)"
    dim "  $(t pub_accept_not2)"
    dim "  $(t pub_accept_no)"
    return 0
}

# "No" on the findings question is not "I do not want to publish", it is "not like this". The
# human wants a copy, but a clean one, and runs into exactly the operation the system does not
# have: removing a file from history means rewriting it, and fraim does that nowhere.
#
# This used to print one word — "cancelled". The human was left where they started: the
# findings in place, nothing said about what to do with them, and the single line about the
# task had scrolled off the top together with the risk acceptance they had just declined. The
# system's refusal already printed the task (publish_refuse_secret); the human's refusal prints
# the same — the moment is the same, and only the first sentence should differ.
publish_cancel_findings() {
    _pub_root=$1
    _pub_n=$(pub_count "$PUB_STOP")
    say ""
    say "  ${C_BLD}$(t pub_cancel_title)${C_OFF}"
    say "  $(tp "$_pub_n" pub_cancel_remain)"
    say "  $(t pub_cancel_agent)"
    publish_brief_secret "$_pub_root"
    say ""
    dim "  $(t pub_cancel_check)"
    dim "  $(t pub_cancel_then)"
    dim "  $(t pub_cancel_false)"
    return 0
}
