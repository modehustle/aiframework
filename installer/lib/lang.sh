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
# one line «script|words SHARE SAMPLE» and returns 1.
lang_measure() {
    LC_ALL=C awk '
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
        # One unit is over: judge it, keep the first failure.
        function flush() {
            if (fail == "" && uf + ul > 0 && uf * 5 > uf + ul)
                fail = sprintf("script %d%% %s", int(uf * 100 / (uf + ul)), usample)
            if (fail == "" && ux >= 3 && ux > uen)
                fail = sprintf("words %d %s", ux, ufirst)
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
        END {
            flush()
            if (fail != "") { print fail; exit 1 }
        }
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
    # cut at 100 characters, not bytes: a cut inside a letter prints a broken one
    _lc_line=$(printf '%s\n' "$_lc_line" | LC_ALL=C awk '{
        sub(/^[ \t]*/, ""); out = ""; n = 0
        for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (c !~ /[\200-\277]/ && ++n > 100) { out = out "…"; break }
            out = out c
        }
        print out }')
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
