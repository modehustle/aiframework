#!/bin/sh
# lang.sh — what the verbs write into a project is English, and the verbs check it.
#
# The rule is old (CONVENTIONS, 2026-10-27): the product and every project under it are
# English inside, whatever language the human speaks to the agent. A rule in a prompt is
# a wish, though: models that talk to the human in Russian drift into Russian in the
# decision they write a minute later, and nothing stops them. The verbs are the only door
# into the foundation, so the door checks — and refuses with a message the agent reads
# and acts on, the same way it refuses an empty body.
#
# Two tests, both deterministic, both on bytes (LC_ALL=C — no locale, no UTF-8 awk):
#   · script: letters of a non-Latin script (Cyrillic, Greek, Hebrew, Arabic, Indic, CJK,
#     Hangul…) above a fifth of the letters of any one unit — a paragraph, a list item, a
#     table row, a heading. Per unit, not per text: a Russian paragraph inside a long
#     English template (findings.md) is a fifth of nothing, and would pass.
#   · Latin-script languages (Spanish, German, French, Polish…) have the same letters as
#     English, so they are told by their words: in any one unit, three or more of their
#     everyday function words (el, der, les, che, nie…) or words with diacritics, and more
#     of them than English function words (the, of, and, is…). Both lists hold only words
#     that are not English words too, so terse English — a list of names, a pitfall line,
#     a table — never trips it, and the odd «per se», «Zürich» or «café» is outweighed.
# What is quoted is not measured: `code`, fenced blocks, «…», “…” and "…" — the place for
# a name in another language or the human's own words. That is the way out of a false
# alarm too, and the refusal says so.

# Reads the text on stdin. Prints nothing and returns 0 for English; otherwise prints
# «script|words SHARE SAMPLE» for the first failing unit — for every one with `all` — and
# returns 1.
lang_measure() {
    LC_ALL=C awk -v all="${1:-}" '
        BEGIN {
            n = split("the of and is are were be been being it its this that these " \
                      "those with from not or which when what where who has have had " \
                      "does into than then they their there should would could must " \
                      "can only but if each every any all for by", w, " ")
            for (i = 1; i <= n; i++) en[w[i]] = 1
            # es · de · fr · it · pt · nl · pl — none of them an English word
            n = split("el los las que del una por para como pero esta este eso " \
                      "der das und ist nicht ein eine einen mit zu den dem von sich " \
                      "auch auf wird werden nach oder wenn aber " \
                      "le les des du et est une qui dans pour pas sur avec ce sont mais " \
                      "il che di della delle sono gli nel anche questo " \
                      "os uma em com mais isso seu sua " \
                      "het een van niet dat op voor zijn ook " \
                      "na jest jak ale tylko oraz przez " \
                      "de la en un se es lo", w, " ")
            for (i = 1; i <= n; i++) xx[w[i]] = 1
        }
        # One unit is over: judge it.
        function flush(  r) {
            r = ""
            if (uf + ul > 0 && uf * 5 > uf + ul)
                r = sprintf("script %d%% %s", int(uf * 100 / (uf + ul)), usample)
            else if (ux >= 3 && ux > uen)
                r = sprintf("words %d %s", ux, ufirst)
            if (r != "" && (all != "" || !nfail)) print r
            if (r != "") nfail++
            uf = ul = ux = uen = 0; usample = ufirst = ""
        }
        /^[ \t]*(```|~~~)/ { flush(); fence = !fence; next }
        fence || /^[ \t]*<!--/ { next }
        /^[ \t]*$/ { flush(); next }
        {
            if (/^[ \t]*\|/ || /^#/ || /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/) flush()
            if (ufirst == "") ufirst = $0
            t = $0
            # quoted and code spans are not measured
            gsub(/`[^`]*`/, " ", t)
            gsub(/\302\253[^\302]*\302\273/, " ", t)
            gsub(/\342\200\234[^\342]*\342\200\235/, " ", t)
            gsub(/"[^"]*"/, " ", t)
            # non-Latin letters: U+0380–U+0FFF, U+1000–U+1FFF except Latin Extended
            # Additional (U+1E00–U+1EFF), U+3000–U+DFFF
            f = gsub(/[\316-\340][\200-\277]+/, " ", t)
            f += gsub(/\341[\200-\267\274-\277][\200-\277]/, " ", t)
            f += gsub(/[\343-\355][\200-\277][\200-\277]/, " ", t)
            # Latin with diacritics is Latin, and marks its word
            d = gsub(/[\303-\311][\200-\277]/, "\177", t)
            d += gsub(/\341[\270-\273][\200-\277]/, "\177", t)
            uf += f; ul += d + gsub(/[A-Za-z]/, "&", t)
            if (f > 0 && usample == "") usample = $0
            m = split(tolower(t), w, /[^a-z\177]+/)
            for (i = 1; i <= m; i++) {
                if (w[i] in en) uen++
                else if (w[i] in xx || index(w[i], "\177")) ux++
            }
            if (/^[ \t]*\|/ || /^#/) flush()
        }
        END { flush(); exit nfail > 0 }
    '
}

# lang_check WHAT TEXT — WHAT names the text in the refusal («the decision body», «the
# commit message»). The text is an argument, not a stream: a check at the end of a pipe
# runs in a subshell, and its refusal would stop the subshell, not the verb. Refuses
# (exit 2) with a message addressed to the agent: the agent is the one who must rewrite,
# and a refusal in the operator's language is exactly the push towards that language this
# check exists to stop.
lang_check() {
    _lc_what=$1
    _lc_out=$(printf '%s\n' "$2" | lang_measure) && return 0
    _lc_kind=${_lc_out%% *}; _lc_rest=${_lc_out#* }
    _lc_share=${_lc_rest%% *}; _lc_line=${_lc_rest#* }
    _lc_line=$(printf '%s\n' "$_lc_line" | lang_clip)
    if [ "$_lc_kind" = script ]; then
        _lc_why="$_lc_share of its letters are not Latin"
    else
        _lc_why="$_lc_share of its words belong to another language"
    fi
    die "refused: $_lc_what is not in English — $_lc_why.
  at: $_lc_line
  Everything written into the project — foundation, cards, backlog, commit messages — is
  English, whatever language you speak with the human. Rewrite it in English and call the
  verb again; nothing was written. A name or the human's own words in another language go
  in quotes («…», \"…\") or \`backticks\` — quoted text is not measured."
}

# --- what a save point adds ---------------------------------------------------------
# The verbs above check the text they are handed. Everything else reaches the project as
# a file edited by hand — the foundation itself when the agent skips the verbs, and code
# comments, which no verb ever writes. `fraim commit` is where both pass, so it checks the
# lines the save point ADDS: old text is not this commit's business, and a project with a
# Russian past can still save its English present.
#
# What is measured depends on the file:
#   · the foundation (ARCHITECTURE, CONVENTIONS, DECISIONS, STACK) and ai/**/*.md — all text;
#   · code, by extension — comments only. String literals are code: the operator's
#     messages live there legitimately, in the operator's language.
#   · anything else (README, docs, data) — nothing.
# Comments are found by their markers outside string literals: `#` (shell, Python, Ruby,
# YAML…), `//` and `/* */` (C family, JS/TS, Go, Rust, Java…), `--` (SQL, Lua, Haskell),
# `<!-- -->` (HTML, XML, Vue, Svelte). It is a scanner, not a parser: docstrings, which
# are string literals, are not seen.

# Reads a unified diff (`git diff -U0`) on stdin; writes the text to measure of each
# file into DIR/N and prints «N<TAB>path» for each.
lang_extract() {
    LC_ALL=C awk -v dir="$1" '
        BEGIN { q1 = sprintf("%c", 39) }
        function kindof(p,  b, e) {
            if (p ~ /^(ARCHITECTURE|CONVENTIONS|DECISIONS|STACK)\.md$/ || p ~ /^ai\/.*\.md$/)
                return "prose"
            b = p; sub(/.*\//, "", b)
            if (b ~ /^(Makefile|Dockerfile|Containerfile|Rakefile|Gemfile)$/) return "hash"
            if (b !~ /\./) return ""
            e = tolower(b); sub(/.*\./, "", e)
            if (e ~ /^(sh|bash|zsh|ksh|fish|py|pyi|rb|pl|pm|r|jl|ex|exs|nim|cr|tcl|ps1|yaml|yml|toml|tf|hcl|cmake|mk|conf|cfg|ini|env|dockerfile|gitignore)$/) return "hash"
            if (e ~ /^(c|h|cc|cpp|cxx|hpp|hh|m|mm|cs|java|kt|kts|scala|groovy|gradle|go|rs|swift|dart|js|jsx|mjs|cjs|ts|tsx|php|proto|css|scss|sass|less|zig|v|sol)$/) return "slash"
            if (e ~ /^(sql|lua|hs|elm|ada|adb|ads)$/) return "dash"
            if (e ~ /^(html|htm|xml|xhtml|svg|vue|svelte)$/) return "html"
            return ""
        }
        function open_file(p) {
            close_file()
            path = p; kind = kindof(p); inblock = 0; wrote = 0
            if (kind == "") return
            n++; out = dir "/" n; printf "" > out
            printf "%d\t%s\n", n, path
        }
        function close_file() { if (out != "") close(out); out = "" }
        function gap() { if (wrote) print "" > out; wrote = 0 }
        # The comment on one line of code, or "" when there is none.
        function comment(s,  i, c, q, L, r) {
            L = length(s); q = ""; r = ""
            if (kind == "html") {
                if (inblock) {
                    i = index(s, "-->")
                    if (i) { inblock = 0; return substr(s, 1, i - 1) }
                    return s
                }
                i = index(s, "<!--"); if (!i) return ""
                r = substr(s, i + 4); c = index(r, "-->")
                if (c) return substr(r, 1, c - 1)
                inblock = 1; return r
            }
            if (kind == "slash") {
                if (inblock) {
                    i = index(s, "*/")
                    if (i) { inblock = 0; s = substr(s, 1, i - 1) }
                    sub(/^[ \t]*\*+/, "", s); return s
                }
                if (s ~ /^[ \t]*\*([ \t]|$)/) { sub(/^[ \t]*\*/, "", s); return s }
            }
            for (i = 1; i <= L; i++) {
                c = substr(s, i, 1)
                if (q != "") {
                    if (c == "\\") i++
                    else if (c == q) q = ""
                    continue
                }
                if (c == "\"" || c == "`" || c == q1) { q = c; continue }
                if (kind == "hash" && c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t]/)) {
                    if (i == 1 && substr(s, 1, 2) == "#!") return ""
                    return substr(s, i + 1)
                }
                if (kind == "dash" && substr(s, i, 2) == "--") return substr(s, i + 2)
                if (kind == "slash" && substr(s, i, 2) == "//" && (i == 1 || substr(s, i - 1, 1) != ":"))
                    return substr(s, i + 2)
                if (kind == "slash" && substr(s, i, 2) == "/*") {
                    r = substr(s, i + 2); c = index(r, "*/")
                    if (c) return substr(r, 1, c - 1)
                    inblock = 1; return r
                }
            }
            return ""
        }
        /^\+\+\+ / { p = substr($0, 5); sub(/^b\//, "", p); if (p == "/dev/null") p = ""; open_file(p); next }
        /^(diff |index |--- |new file|deleted file|similarity|rename |old mode|new mode|Binary )/ { next }
        /^@@/ { if (out != "") gap(); inblock = 0; next }
        out == "" { next }
        /^\+/ {
            s = substr($0, 2)
            if (kind == "prose") {
                if (s ~ /^[ \t]*$/) gap(); else { print s > out; wrote = 1 }
                next
            }
            t = comment(s)
            gsub(/^[\/*#!;-]+/, "", t); sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
            if (t == "") { gap(); next }
            print t > out; wrote = 1
            next
        }
        { if (out != "") gap() }
        END { close_file() }
    '
}

# The diff a save point over PATHS would record: tracked changes against HEAD, and new
# files whole, as if every line were added. Text files only.
lang_pending_diff() {
    _pd_root=$1; shift
    if git -C "$_pd_root" rev-parse -q --verify HEAD >/dev/null 2>&1; then
        git -C "$_pd_root" diff --no-color --no-ext-diff -U0 HEAD -- "$@" 2>/dev/null
    else
        git -C "$_pd_root" diff --no-color --no-ext-diff -U0 --cached -- "$@" 2>/dev/null
    fi
    git -C "$_pd_root" ls-files --others --exclude-standard -- "$@" 2>/dev/null |
    while IFS= read -r _pd_f; do
        [ -f "$_pd_root/$_pd_f" ] && grep -Iq . "$_pd_root/$_pd_f" 2>/dev/null || continue
        printf '+++ b/%s\n@@\n' "$_pd_f"
        sed 's/^/+/' "$_pd_root/$_pd_f"
    done
}

# Measures a diff on stdin file by file; prints «path<TAB>failure» for every file that
# is not English and returns 1 if there was one.
lang_scan_diff() {
    _sd_dir=$(mktemp -d) || return 0
    _sd_out=$(lang_extract "$_sd_dir" | while IFS="$(printf '\t')" read -r _sd_n _sd_p; do
        _sd_r=$(lang_measure < "$_sd_dir/$_sd_n") || printf '%s\t%s\n' "$_sd_p" "$_sd_r"
    done)
    rm -rf "$_sd_dir"
    [ -z "$_sd_out" ] && return 0
    printf '%s\n' "$_sd_out"
    return 1
}

# `fraim commit` over PATHS: refuses (exit 2) when what it would add is not English.
lang_check_commit() {
    _cc_root=$1; shift
    _cc_bad=$(lang_pending_diff "$_cc_root" "$@" | lang_scan_diff) && return 0
    _cc_list=$(printf '%s\n' "$_cc_bad" | while IFS="$(printf '\t')" read -r _cc_p _cc_r; do
        _cc_l=${_cc_r#* }; _cc_l=${_cc_l#* }
        printf '  %s: %s\n' "$_cc_p" "$(printf '%s\n' "$_cc_l" | lang_clip)"
    done)
    die "refused: this save point adds text that is not in English.
$_cc_list
  The foundation, cards, backlog and code comments are English, whatever language you
  speak with the human. Rewrite those lines in English and call fraim commit again;
  nothing was committed. Strings in code are not checked — the operator's messages live
  there. A name or the human's own words go in quotes («…», \"…\") or \`backticks\`."
}

# One line of sample, cut at 100 characters, not bytes: a cut inside a letter prints a
# broken one.
lang_clip() {
    LC_ALL=C awk '{
        sub(/^[ \t]*/, ""); out = ""; n = 0
        for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (c !~ /[\200-\277]/ && ++n > 100) { out = out "…"; break }
            out = out c
        }
        print out; exit }'
}
