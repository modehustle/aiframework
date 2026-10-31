#!/bin/sh
# run-tests.sh — end-to-end checks for the installer and the watchman.
#
# Runs against a throwaway HOME so nothing touches the operator's real
# harnesses or registry. Usage: sh installer/tests/run-tests.sh

set -u

REPO=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
FRAIM="$REPO/installer/bin/fraim"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3], got [$2]"; fi; }

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
export FRAIM_HOME="$HOME/.fraim"
mkdir -p "$HOME" "$FRAIM_HOME"
# The operator's messages come from installer/locale. The assertions below were written
# against the Russian catalog and keep checking it; the English source and the language
# choice have a section of their own («message catalogs»).
export FRAIM_LOCALE_DIR="$REPO/installer/locale"
export FRAIM_LANG=ru

# The fixtures below are deliberately minimal directories: they have neither AGENTS.md nor ai/fraim.conf,
# because each one checks a single thing. The standard-conformance check would fire on
# all of them at once and drown out what the fixture exists for. We turn it off with a machine setting
# and turn it back on in the project that actually tests it (project beats machine).
printf 'check_shape = off\n' > "$FRAIM_HOME/config"

# ---------------------------------------------------------------- procedures
printf '\nprocedures/\n'

N=$(ls "$REPO"/procedures/*.md | grep -v manifest | wc -l | tr -d ' ')
check "11 procedures on disk" "$N" "11"

BADFM=""
for f in "$REPO"/procedures/*.md; do
    n=$(sed -n 's/^name: //p' "$f" | head -1)
    d=$(sed -n 's/^description: //p' "$f" | head -1)
    t=$(sed -n 's/^  tier: //p' "$f" | head -1)
    o=$(sed -n 's/^  order: //p' "$f" | head -1)
    b=$(basename "$f" .md)
    [ "$n" = "$b" ]                                  || BADFM="$BADFM $b:name-mismatch"
    printf '%s' "$n" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' || BADFM="$BADFM $b:not-kebab"
    [ -n "$d" ]                                      || BADFM="$BADFM $b:no-desc"
    case $d in *'<'*|*'>'*) BADFM="$BADFM $b:angle-brackets";; esac
    [ -n "$t" ]                                      || BADFM="$BADFM $b:no-tier"
    [ -n "$o" ]                                      || BADFM="$BADFM $b:no-order"
done
check "frontmatter of all procedures is valid" "${BADFM:-clean}" "clean"

# --- rails ------------------------------------------------------------------
# `fraim commit` lived in two procedures for several releases, because nothing
# checked procedure text against the dispatcher. These three checks catch the class, not the case.

DISPATCH=$(awk '/^case \$_cmd in/,/^esac$/' "$REPO/installer/bin/fraim" |
           sed -n 's/^[[:space:]]*\([a-z|_-]*\)).*/\1/p' | tr '|' '\n' |
           grep -E '^[a-z][a-z-]*$' | sort -u)
# Only commands in code — with a backtick or at the start of a block line. Otherwise English
# prose like «a fraim project» reads as a command.
USED=$(grep -ohE '(^|`)fraim [a-z][a-z-]*' "$REPO"/procedures/*.md |
       sed 's/^`//; s/^fraim //' | sort -u)

UNKNOWN=""
for v in $USED; do
    printf '%s\n' "$DISPATCH" | grep -qx "$v" || UNKNOWN="$UNKNOWN $v"
done
check "every fraim command in procedures exists in the CLI" "${UNKNOWN:-none}" "none"

UNDOC=""
HELP=$("$REPO/installer/bin/fraim" help 2>/dev/null)
for v in $DISPATCH; do
    printf '%s\n' "$HELP" | grep -qw -- "$v" || UNDOC="$UNDOC $v"
done
check "every CLI command is described in fraim help" "$(printf '%s' "${UNDOC:-none}" | tr -s ' ')" "none"

# The agent learns the verb list from one table (verbtable.sh): brief, help and the master
# skill are built from it. A verb in the table that the dispatcher lacks is a promise that
# breaks on the very first call.
VTCMDS=$(sh -c '. "'"$REPO"'/installer/lib/core.sh"; . "'"$REPO"'/installer/lib/foundation.sh"; . "'"$REPO"'/installer/lib/verbtable.sh"; vt_table' |
         awk -F' ;; ' '{ split($3, w, " "); print w[2] }' | sort -u)
VTMISS=""
for v in $VTCMDS; do
    printf '%s\n' "$DISPATCH" | grep -qx "$v" || VTMISS="$VTMISS $v"
done
check "every verb in the table exists in the CLI" "${VTMISS:-none}" "none"

# Gates parse headings that the template prints. The test takes the literal from the gate's code
# and looks for it in the templates — not in its own copy of the format.
MISSING_HEAD=""
HEADS=$(grep -oE "verb_section_filled [^ ]+ '[^']+'" "$REPO/installer/lib/verbs.sh" |
        sed "s/.*'\(.*\)'/\1/" | sort -u)
OLDIFS=$IFS; IFS='
'
for h in $HEADS; do
    grep -rqF "$h" "$REPO/installer/templates" || MISSING_HEAD="$MISSING_HEAD [$h]"
done
IFS=$OLDIFS
check "headings read by gates exist in templates" "${MISSING_HEAD:-none}" "none"

# No procedure changes git state by hand — none, no exceptions.
# The list used to be a closed one and shrank to empty: scaffold creates the repository, commit
# puts the save point, undo and restore do the going back. Any match here is
# either a new verb or a bug.
GITHAND=$(grep -lE 'git (commit|add|init|restore|checkout|reset|stash|clean|push)' \
          "$REPO"/procedures/*.md | while read -r f; do basename "$f"; done | sort | tr '\n' ' ')
check "procedures do not touch git by hand" "$GITHAND" ""

# ---------------------------------------------------------------- message catalogs
printf '\nmessage catalogs (installer/locale)\n'
LOC="$REPO/installer/locale"

# Every catalog file is plain shell that parses.
LBAD=
for f in "$LOC"/*/*.sh; do sh -n "$f" 2>/dev/null || LBAD="$LBAD ${f#"$LOC"/}"; done
check "every catalog parses" "${LBAD:-clean}" "clean"

# Every shipped language has a directory, and every directory is a shipped language.
LCODES=$(grep -v '^#' "$LOC/languages" | cut -d'|' -f1 | sort)
LDIRS=$(cd "$LOC" && for d in */; do printf '%s\n' "${d%/}"; done | sort)
check "languages file and catalog directories agree" "$LDIRS" "$LCODES"

# The keys of a catalog: M_<key>, with a plural suffix folded to its base.
cat_keys() { sed -n "s/^M_\([A-Za-z0-9_]*\)=.*/\1/p" "$@" 2>/dev/null | sed 's/_\(one\|few\|many\|other\)$//' | sort -u; }
# key<TAB>sorted placeholders, one line per key (plural forms merged).
cat_holes() {
    sh -c 'for f in "$@"; do . "$f"; done; set | sed -n "s/^M_\([A-Za-z0-9_]*\)=.*/\1/p"' x "$@" 2>/dev/null |
    while read -r k; do
        v=$(sh -c 'for f in "$@"; do . "$f"; done; eval "printf %s \"\${M_'"$k"'}\""' x "$@" 2>/dev/null)
        base=$(printf '%s' "$k" | sed 's/_\(one\|few\|many\|other\)$//')
        printf '%s\t%s\n' "$base" "$(printf '%s' "$v" | grep -o '{[a-z_]*}' | grep -v '^{n}$' | sort -u | tr '\n' ' ')"
    done | sort -u
}
LUNK=; LHOLE=
for d in "$LOC"/*/; do
    l=$(basename "$d"); [ "$l" = en ] && continue
    for f in "$d"*.sh; do
        [ -f "$f" ] || continue
        m=$(basename "$f")
        extra=$(comm -13 "/dev/fd/3" "/dev/fd/4" 3<<EOF3 4<<EOF4
$(cat_keys "$LOC/en/$m")
EOF3
$(cat_keys "$f")
EOF4
)
        [ -z "$extra" ] || LUNK="$LUNK $l/$m:$(printf '%s' "$extra" | head -1)"
        diffh=$(comm -13 "/dev/fd/3" "/dev/fd/4" 3<<EOF3 4<<EOF4
$(cat_holes "$LOC/en/$m")
EOF3
$(cat_holes "$f")
EOF4
)
        [ -z "$diffh" ] || LHOLE="$LHOLE $l/$m:$(printf '%s' "$diffh" | head -1 | cut -f1)"
    done
done
check "no translation carries a key English does not have" "${LUNK:-clean}" "clean"
check "every translation keeps the placeholders of the English text" "${LHOLE:-clean}" "clean"

# Every key the code asks for exists in English.
USEDK=$(grep -ohE '\$\(t [a-z][a-z0-9_]*|\$\(tp [^ ]+ [a-z][a-z0-9_]*|^[[:space:]]*t [a-z][a-z0-9_]*' \
        "$REPO"/installer/lib/*.sh "$REPO/installer/bin/fraim" | awk '{print $NF}' | sort -u)
ENK=$(cat_keys "$LOC"/en/*.sh)
LMISS=
for k in $USEDK; do printf '%s\n' "$ENK" | grep -qx "$k" || LMISS="$LMISS $k"; done
check "every message the code asks for is in the English catalog" "${LMISS:-clean}" "clean"

# The language choice.
LCORE='. "'"$REPO"'/installer/lib/core.sh"'
check "FRAIM_LANG chooses" "$(FRAIM_LANG=en sh -c "$LCORE"'; printf %s "$I18N_LANG"')" "en"
check "the system locale chooses when nothing is set" \
      "$(env -u FRAIM_LANG LANG=ru_RU.UTF-8 LC_ALL= sh -c "$LCORE"'; printf %s "$I18N_LANG"')" "ru"
check "a locale we do not ship gives English" \
      "$(env -u FRAIM_LANG LANG=xx_XX.UTF-8 LC_ALL= sh -c "$LCORE"'; printf %s "$I18N_LANG"')" "en"
LH="$SANDBOX/langhome"; mkdir -p "$LH"; printf 'lang = en\n' > "$LH/config"
check "the machine setting wins over the system locale" \
      "$(env -u FRAIM_LANG FRAIM_HOME="$LH" LANG=ru_RU.UTF-8 sh -c "$LCORE"'; printf %s "$I18N_LANG"')" "en"
check "an explicit language we do not ship gives English, not the system's" \
      "$(FRAIM_LANG=xx LANG=ru_RU.UTF-8 sh -c "$LCORE"'; printf %s "$I18N_LANG"')" "en"
check "a placeholder is filled, every time it occurs" \
      "$(sh -c "$LCORE"'; M_x="{a} and {a} of {b}"; t x a=1 b="{a}"')" "1 and 1 of {a}"
check "a missing key prints the key, not nothing" "$(sh -c "$LCORE"'; t no_such_key')" "no_such_key"
PL='M_w_one="{n} коммит"; M_w_few="{n} коммита"; M_w_many="{n} коммитов"; for n in 1 2 5 11 21 112; do tp $n w; printf "|"; done'
check "Russian plural forms" "$(FRAIM_LANG=ru sh -c "$LCORE; $PL")" "1 коммит|2 коммита|5 коммитов|11 коммитов|21 коммит|112 коммитов|"
PL='M_w_one="{n} commit"; M_w_other="{n} commits"; for n in 1 2 0; do tp $n w; printf "|"; done'
check "English plural forms" "$(FRAIM_LANG=en sh -c "$LCORE; $PL")" "1 commit|2 commits|0 commits|"
check "display width counts a CJK character as two columns" "$(sh -c "$LCORE"'; str_width "日本語 ok"')" "9"
check "the English catalog speaks English" \
      "$(FRAIM_LANG=en "$FRAIM" config set check_git off 2>&1 | grep -c 'always on')" "1"
"$FRAIM" config set lang xx >/dev/null 2>&1
check "lang refuses a language we do not ship" "$?" "2"

# ---------------------------------------------------------------- menu
printf '\nfraim menu (screen)\n'

# The menu's most expensive property is not how it looks, but that it is absent where
# it must not be. The overwhelming majority of CLI calls are made by an agent through a
# pipe; a command waiting for a keypress would hang the session silently.
OUT=$(timeout 10 "$FRAIM" menu </dev/null 2>&1 | head -1)
check "menu without a terminal prints usage, does not wait for a key" \
      "$(printf '%s' "$OUT" | cut -c1-6)" "fraim "

OUT=$(timeout 10 "$FRAIM" </dev/null 2>&1 | head -1)
check "bare fraim without a terminal prints usage" \
      "$(printf '%s' "$OUT" | cut -c1-6)" "fraim "

# The menu card is drawn AFTER the watchman, and POSIX sh has no local variables: the watchman
# writes _w, _n, _msg while it runs. A menu that computed its width before wm_run got
# «Illegal number: точек сохранения» and drew one empty line — exactly on the projects
# with the most findings. The rail checks rendering on a project with a remote and
# unpushed save points, i.e. in that very situation.
CARD="$SANDBOX/cardproj"
mkdir -p "$CARD"
git init -q --bare "$SANDBOX/card-remote.git"
git -C "$CARD" init -q; git -C "$CARD" config user.email t@t; git -C "$CARD" config user.name t
cd "$CARD" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
git -C "$CARD" remote add origin "$SANDBOX/card-remote.git"
git -C "$CARD" push -q origin HEAD:main 2>/dev/null
git -C "$CARD" branch -u origin/main >/dev/null 2>&1
for i in 1 2 3 4 5 6; do
    printf 'c%s\n' "$i" >> "$CARD/app.py"
    git -C "$CARD" add app.py >/dev/null; git -C "$CARD" commit -qm "fix: c$i" >/dev/null
done
CARDOUT=$(sh -c '
    . "'"$REPO"'/installer/lib/core.sh"; . "'"$REPO"'/installer/lib/config.sh"
    . "'"$REPO"'/installer/lib/registry.sh"; . "'"$REPO"'/installer/lib/context.sh"
    . "'"$REPO"'/installer/lib/scaffold.sh"; . "'"$REPO"'/installer/lib/lang.sh"; . "'"$REPO"'/installer/lib/verbs.sh"; . "'"$REPO"'/installer/lib/tasks.sh"; . "'"$REPO"'/installer/lib/foundation.sh"; . "'"$REPO"'/installer/lib/verbtable.sh"
    . "'"$REPO"'/installer/lib/ade.sh"; . "'"$REPO"'/installer/lib/watchman.sh"; . "'"$REPO"'/installer/lib/update.sh"; . "'"$REPO"'/installer/lib/menu.sh"
    cd "'"$CARD"'" && menu_card && printf "%s\n" "$MENU_CARD"' 2>&1)
check "menu card does not crash on watchman numbers" "$(printf '%s' "$CARDOUT" | grep -c 'Illegal number')" "0"
check "menu card shows findings text" \
      "$(printf '%s' "$CARDOUT" | grep -c 'не уехали в удалённую копию')" "1"
# The card cuts a long line at the colon, not at a column: counting columns
# correctly is only possible knowing the locale, and under LC_ALL=C Cyrillic gets cut in half.
check "long finding is cut at a meaningful point" \
      "$(printf '%s' "$CARDOUT" | grep -c 'скелет развёрнут, но не заполнен: …')" "1"
cd "$SANDBOX" || exit 1

# Navigation after the watchman. POSIX sh has no local variables, and menu_card calls
# the watchman, which writes its own `_n` (queue counter). The menu item counter lived
# in the same `_n`, and after the very first card render it became zero: arrow down
# honestly moved the selection and immediately returned it to the first line, and digits 1-8 did not
# work at all. The rail reproduces exactly this sequence.
NAV=$(sh -c '
    . "'"$REPO"'/installer/lib/core.sh"; . "'"$REPO"'/installer/lib/config.sh"
    . "'"$REPO"'/installer/lib/registry.sh"; . "'"$REPO"'/installer/lib/context.sh"
    . "'"$REPO"'/installer/lib/scaffold.sh"; . "'"$REPO"'/installer/lib/lang.sh"; . "'"$REPO"'/installer/lib/verbs.sh"; . "'"$REPO"'/installer/lib/tasks.sh"; . "'"$REPO"'/installer/lib/foundation.sh"; . "'"$REPO"'/installer/lib/verbtable.sh"
    . "'"$REPO"'/installer/lib/ade.sh"; . "'"$REPO"'/installer/lib/watchman.sh"; . "'"$REPO"'/installer/lib/update.sh"; . "'"$REPO"'/installer/lib/menu.sh"
    cd "'"$CARD"'" || exit 1
    MENU_N=$(menu_count); MENU_SEL=1
    menu_card
    MENU_SEL=$((MENU_SEL + 1)); [ "$MENU_SEL" -gt "$MENU_N" ] && MENU_SEL=1
    printf "%s/%s\n" "$MENU_SEL" "$MENU_N"' 2>&1)
ITEMS_N=$(sh -c '. "'"$REPO"'/installer/lib/menu.sh"; menu_count')
check "arrow down moves selection after the watchman" "$NAV" "2/$ITEMS_N"

# The menu must survive the exit code of each of its items. The CLI runs under `set -e`,
# and `fraim status` exits with 1 as soon as the project has something to show the human — that
# is, in the most ordinary case. Without a guard, choosing «Скан проекта» printed the verdict and killed
# the process mid-screen, leaving the terminal without echo and without a cursor.
MBR=$(sed -n '/^menu_exec() {/,/^    esac$/p' "$REPO/installer/lib/menu.sh" |
      grep -cE '^        [0-9]+\)')
MGUARD=$(sed -n '/^menu_exec() {/,/^    esac$/p' "$REPO/installer/lib/menu.sh" |
      grep -c '|| true')
check "every menu action survives its exit code" "$MGUARD" "$MBR"

# A menu item and its action live in two places (menu_items and menu_exec). The rail
# catches the class: a line added — a branch forgotten. The last item («Выход») has
# no branch by construction.
ITEMS=$(sed -n '/^menu_items() {/,/^}/p' "$REPO/installer/lib/menu.sh" |
        sed -n '/<<.ITEMS./,/^ITEMS$/p' | grep -c '	')
BRANCH=$(sed -n '/^menu_exec() {/,/^}/p' "$REPO/installer/lib/menu.sh" |
         grep -cE '^        [0-9]+\)')
check "every menu item has an action" "$BRANCH" "$((ITEMS - 1))"

# ---------------------------------------------------------------- build
printf '\nfraim build\n'

"$FRAIM" build >/dev/null 2>&1
check "build succeeded" "$?" "0"

PLUG="$REPO/installer/claude-plugin/skills"
check "plugin: 12 skills" "$(find "$PLUG" -name SKILL.md | wc -l | tr -d ' ')" "12"

# The single-file rule is a compatibility constraint, not tidiness:
# Hermes fetches only SKILL.md when installing from a URL, and omp discovers
# skills non-recursively. Anything beside SKILL.md would arrive missing.
EXTRA=$(find "$PLUG" -type f ! -name SKILL.md | wc -l | tr -d ' ')
check "exactly one file per skill" "$EXTRA" "0"

# The text the agent reads must be the text under version control.
DIFFS=0
for d in "$PLUG"/*/; do
    n=$(basename "$d")
    src="$REPO/procedures/$n.md"
    [ -f "$src" ] || continue
    a=$(awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{f=0;next} !f' "$src" | md5sum | cut -d' ' -f1)
    b=$(awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{f=0;next} !f' "$d/SKILL.md" | md5sum | cut -d' ' -f1)
    [ "$a" = "$b" ] || DIFFS=$((DIFFS+1))
done
check "skill body matches source byte for byte" "$DIFFS" "0"

python3 -c "import json,sys;json.load(open('$REPO/procedures/manifest.json'))" 2>/dev/null
check "manifest is valid JSON" "$?" "0"

# ---------------------------------------------------------------- watchman
printf '\nfraim status (watchman)\n'

PROJ="$SANDBOX/proj"
mkdir -p "$PROJ"
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "project not under the system → exit 2" "$?" "2"

git -C "$PROJ" init -q
git -C "$PROJ" config user.email t@t; git -C "$PROJ" config user.name t
mkdir -p "$PROJ/ai/tasks"
printf '# Arch\n' > "$PROJ/ARCHITECTURE.md"
printf 'x\n' > "$PROJ/main.py"
git -C "$PROJ" add -A >/dev/null; git -C "$PROJ" commit -qm init
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "clean project → exit 0" "$?" "0"

# Drift is code commits since ARCHITECTURE.md last moved. It counts every mode of work,
# including the reactive one, which is why it replaced the hotfix counter.
printf 'foundation_lag_commits = 3\n' > "$PROJ/ai/fraim.conf"
i=1; while [ $i -le 2 ]; do
    printf 'line %s\n' "$i" >> "$PROJ/app.py"
    git -C "$PROJ" add app.py >/dev/null 2>&1
    git -C "$PROJ" commit -qm "fix: change $i" >/dev/null 2>&1
    i=$((i+1))
done
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "2 code commits (below threshold) → exit 0" "$?" "0"
printf 'line 3\n' >> "$PROJ/app.py"
git -C "$PROJ" add app.py >/dev/null 2>&1
git -C "$PROJ" commit -qm "fix: change 3" >/dev/null 2>&1
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "3 code commits (threshold) → exit 1" "$?" "1"
"$FRAIM" status "$PROJ" 2>/dev/null | grep -q '/prune'
check "verdict points to /prune" "$?" "0"

# The map moving is one anchor; a prune commit is the other, and the nearer one wins.
printf 'updated\n' >> "$PROJ/ARCHITECTURE.md"
git -C "$PROJ" add ARCHITECTURE.md >/dev/null 2>&1
git -C "$PROJ" commit -qm "prune: reconcile foundation" >/dev/null 2>&1
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "map update resets the counter → exit 0" "$?" "0"
rm -f "$PROJ/ai/fraim.conf"

# The board: an open card is information, never alarm. Nothing on a card can go stale or
# be blocked — it carries an intent, not a snapshot of the code.
printf -- '---\nkind: task\ncreated: 2026-01-01\n---\n# Do X\n\n## What and why\nx\n\n## Done when\nx\n' \
    > "$PROJ/ai/tasks/do-x.md"
git -C "$PROJ" add -A >/dev/null 2>&1; git -C "$PROJ" commit -qm "task: do-x" >/dev/null 2>&1
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "open task on the board → exit 0" "$?" "0"
"$FRAIM" status "$PROJ" 2>/dev/null | grep -q '1 открытая задача на доске'
check "board named in the verdict" "$?" "0"
"$FRAIM" status "$PROJ" --json 2>/dev/null | grep -q '"slug": "do-x", "kind": "task", "parent": ""'
check "json: card with kind and parent" "$?" "0"
printf 'y\n' >> "$PROJ/main.py"
git -C "$PROJ" commit -aqm second
"$FRAIM" status "$PROJ" --json 2>/dev/null | grep -qE '"id": "(stale-plan|plan-version|blocker|unsealed)"'
check "a card has no staleness, blockers or seals" "$?" "1"

# A task in the old format is somebody's intent too — the verdict sends it to upgrade.
mkdir -p "$PROJ/ai/tasks/old-plan"
printf '# Task\n' > "$PROJ/ai/tasks/old-plan/task.md"
printf 'check_shape = on\n' > "$PROJ/ai/fraim.conf"
"$FRAIM" status "$PROJ" 2>/dev/null | grep -q 'ai/tasks:старый-формат'
check "old-format task is a shape finding" "$?" "0"
rm -rf "$PROJ/ai/tasks/old-plan" "$PROJ/ai/fraim.conf"

python3 -c "import json,sys;json.load(sys.stdin)" < "$("$FRAIM" status "$PROJ" --json > "$SANDBOX/s.json" 2>/dev/null; echo "$SANDBOX/s.json")"
check "--json is valid JSON" "$?" "0"

# Lessons that never came back: work saved while CONVENTIONS.md stays frozen. Same
# arithmetic as the map check, one file over — and not a subset of it: the map here is
# fresh, only the lessons are not.
"$FRAIM" config set --machine lessons_lag_commits 3 >/dev/null 2>&1
printf '# Conventions\n\n## Known Pitfalls / Lessons\n- None yet.\n' > "$PROJ/CONVENTIONS.md"
git -C "$PROJ" add CONVENTIONS.md >/dev/null 2>&1
git -C "$PROJ" commit -qm "onboard: house rules" >/dev/null 2>&1
"$FRAIM" status "$PROJ" 2>/dev/null | grep -q 'грабли никуда не записывались'
check "fresh CONVENTIONS.md raises no alarm" "$?" "1"
for i in 1 2 3 4; do
    printf 'l%s\n' "$i" >> "$PROJ/app.py"
    git -C "$PROJ" add app.py >/dev/null 2>&1
    git -C "$PROJ" commit -qm "fix: reactive change $i" >/dev/null 2>&1
done
"$FRAIM" status "$PROJ" 2>/dev/null | grep -q 'грабли никуда не записывались'
check "work without a single lesson is noticed" "$?" "0"
printf -- '- Retry on a 200 that carries an error body.\n' >> "$PROJ/CONVENTIONS.md"
git -C "$PROJ" add CONVENTIONS.md >/dev/null 2>&1
git -C "$PROJ" commit -qm "fix: lesson recorded" >/dev/null 2>&1
"$FRAIM" status "$PROJ" 2>/dev/null | grep -q 'грабли никуда не записывались'
check "recorded lesson resets the counter" "$?" "1"
"$FRAIM" config set --machine lessons_lag_commits 25 >/dev/null 2>&1

# The watchman is read-only. Anything else and it could not be put on a cron.
BEFORE=$(find "$PROJ" -newer "$PROJ/ARCHITECTURE.md" -type f | md5sum)
"$FRAIM" status "$PROJ" >/dev/null 2>&1
AFTER=$(find "$PROJ" -newer "$PROJ/ARCHITECTURE.md" -type f | md5sum)
check "watchman writes nothing" "$BEFORE" "$AFTER"


# ---------------------------------------------------------------- scaffold
printf '\nfraim scaffold\n'

PROJ2="$SANDBOX/proj2"
mkdir -p "$PROJ2"
git -C "$PROJ2" init -q
git -C "$PROJ2" config user.email t@t; git -C "$PROJ2" config user.name t
printf 'x\n' > "$PROJ2/main.py"
cd "$PROJ2" || exit 1

"$FRAIM" scaffold >/dev/null 2>&1
check "scaffold succeeded" "$?" "0"

MISSING=""
for f in README.md ARCHITECTURE.md CONVENTIONS.md DECISIONS.md .gitignore \
         ai/README.md ai/fraim.conf ai/archive/decisions_log.md AGENTS.md CLAUDE.md; do
    [ -f "$PROJ2/$f" ] || MISSING="$MISSING $f"
done
for d in ai/tasks ai/archive ai/investigations; do
    [ -d "$PROJ2/$d" ] || MISSING="$MISSING $d/"
done
check "all scaffold files and folders created" "${MISSING:-none}" "none"

check "project name substituted" "$(grep -c 'ARCHITECTURE — proj2' "$PROJ2/ARCHITECTURE.md")" "1"

# The repository has to describe itself to an agent that has never heard of fraim —
# a cloud session, CI, a second machine. The pointer travels in git, not on the machine.
check "AGENTS.md carries the invariant" "$(grep -c 'golden rule' "$PROJ2/AGENTS.md")" "1"
check "AGENTS.md works without the CLI" "$(grep -c 'If `fraim` is not installed' "$PROJ2/AGENTS.md")" "1"
check "AGENTS.md starts with brief" "$(grep -c 'Start every session with `fraim brief`' "$PROJ2/AGENTS.md")" "1"
check "AGENTS.md maps human intents to actions" "$(grep -c 'work on a specific task from the board' "$PROJ2/AGENTS.md")" "1"
check "CLAUDE.md points to AGENTS.md" "$(grep -c '@AGENTS.md' "$PROJ2/CLAUDE.md")" "1"
check "AGENTS.md committed by scaffold" \
    "$(git -C "$PROJ2" ls-files --error-unmatch AGENTS.md >/dev/null 2>&1 && echo yes || echo no)" "yes"


# A scaffold must never masquerade as a filled foundation: that is worse than no
# files at all, because the agent reads them, finds nothing, and goes back to guessing.
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "unfilled scaffold → exit 1" "$?" "1"
"$FRAIM" status "$PROJ2" 2>/dev/null | grep -q 'не заполнен'
check "watchman tells a scaffold from a foundation" "$?" "0"

# Additive by construction: safe to run on a project that already has files.
printf 'MINE\n' > "$PROJ2/ARCHITECTURE.md"
"$FRAIM" scaffold >/dev/null 2>&1
check "scaffold does not overwrite existing files" "$(cat "$PROJ2/ARCHITECTURE.md")" "MINE"

for f in README.md ARCHITECTURE.md CONVENTIONS.md DECISIONS.md; do
    printf '# %s\nfilled\n' "$f" > "$PROJ2/$f"
done
git -C "$PROJ2" add -A >/dev/null; git -C "$PROJ2" commit -qm "bootstrap: foundation"
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "filled foundation → exit 0" "$?" "0"

# ---------------------------------------------------------------- mode
# There are no modes anymore (DECISIONS 2026-09-15): the conductor is a procedure run at the human's request.
# Projects switched to fleet earlier still have a mode line, a conductor block in
# AGENTS.md and a SessionStart hook. `fraim mode` removes exactly those, and the remaining hook
# (`fraim mode --hook`) must answer success silently — otherwise it breaks session start.
printf '\nfraim mode (fleet mode leftovers)\n'

cd "$PROJ2" || exit 1
check "ordinary project gets no conductor block" \
      "$(grep -c 'Fleet mode is on' "$PROJ2/AGENTS.md")" "0"

OUT=$("$FRAIM" mode --hook 2>&1)
check "leftover hook answers success" "$?" "0"
check "leftover hook is silent" "$OUT" ""

printf 'mode = parallel\nbuild_check = true\n' > "$PROJ2/ai/fraim.conf"
printf '\n## Fleet mode is on in this project — read this before anything else\nold\n' > "$SANDBOX/fleetblk"
awk -v f="$SANDBOX/fleetblk" '$0 == "<!-- fraim:end -->" { while ((getline l < f) > 0) print l } { print }' \
    "$PROJ2/AGENTS.md" > "$PROJ2/AGENTS.md.t" && mv "$PROJ2/AGENTS.md.t" "$PROJ2/AGENTS.md"
mkdir -p "$PROJ2/.claude"
cat > "$PROJ2/.claude/settings.json" <<'JSON'
{"permissions": {"allow": ["Bash(ls)"]},
 "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "fraim mode --hook", "timeout": 10}]},
                            {"hooks": [{"type": "command", "command": "echo mine"}]}]}}
JSON
"$FRAIM" mode >/dev/null 2>&1
check "fraim mode answers success" "$?" "0"
check "mode line removed" "$(grep -c '^mode' "$PROJ2/ai/fraim.conf")" "0"
check "other project settings intact" "$(grep -c '^build_check = true' "$PROJ2/ai/fraim.conf")" "1"
check "conductor block removed from AGENTS.md" "$(grep -c 'Fleet mode is on' "$PROJ2/AGENTS.md")" "0"
if command -v python3 >/dev/null 2>&1; then
    check "our hook removed" "$(grep -c 'fraim mode --hook' "$PROJ2/.claude/settings.json")" "0"
    check "foreign hook intact" "$(grep -c 'echo mine' "$PROJ2/.claude/settings.json")" "1"
    check "foreign permissions intact" "$(grep -c 'Bash(ls)' "$PROJ2/.claude/settings.json")" "1"
fi
check "rerun says there is nothing to remove" \
      "$("$FRAIM" mode 2>&1 | grep -c 'остатков старого режима здесь нет')" "1"
rm -rf "$PROJ2/.claude"
printf '' > "$PROJ2/ai/fraim.conf"
cd "$SANDBOX" || exit 1

# --- foundation: count changes, not time -----------------------------------
# It used to measure the time between the last code commit and the last map commit.
# In the task cycle that worked, but in reactive mode — the most frequent one — it inverted:
# a hundred commits in two weeks stayed silent, one commit after two weeks raised the alarm.
PROJ5="$SANDBOX/proj5"
mkdir -p "$PROJ5/ai/tasks"
git -C "$PROJ5" init -q
git -C "$PROJ5" config user.email t@t; git -C "$PROJ5" config user.name t
printf '# Arch\n' > "$PROJ5/ARCHITECTURE.md"
printf 'x\n' > "$PROJ5/main.py"
git -C "$PROJ5" add -A >/dev/null; git -C "$PROJ5" commit -qm "init" >/dev/null

i=1; while [ $i -le 9 ]; do
    printf 'l%s\n' "$i" >> "$PROJ5/main.py"
    git -C "$PROJ5" commit -qam "fix $i" >/dev/null
    i=$((i+1))
done
"$FRAIM" status "$PROJ5" >/dev/null 2>&1
check "9 code commits — below threshold" "$?" "0"

printf 'l10\n' >> "$PROJ5/main.py"; git -C "$PROJ5" commit -qam "fix 10" >/dev/null
"$FRAIM" status "$PROJ5" >/dev/null 2>&1
check "10 code commits without the map → exit 1" "$?" "1"
"$FRAIM" status "$PROJ5" 2>/dev/null | grep -q 'с последнего обновления ARCHITECTURE.md'
check "verdict names the map lag" "$?" "0"

# All ten fit into one day — by the old metric this would have been «0 days behind».
SPAN=$(git -C "$PROJ5" log -1 --format=%ct)
FIRST=$(git -C "$PROJ5" log --format=%ct -- ARCHITECTURE.md | tail -1)
check "and all of it within one day" "$(( (SPAN - FIRST) / 86400 ))" "0"

printf 'updated\n' >> "$PROJ5/ARCHITECTURE.md"
git -C "$PROJ5" commit -qam "task: карта обновлена" >/dev/null
"$FRAIM" status "$PROJ5" >/dev/null 2>&1
check "map update resets the counter" "$?" "0"

# A prune that honestly changed nothing in the map resets too: otherwise the verdict
# would ask for a weeding that has just happened.
i=1; while [ $i -le 10 ]; do
    printf 'r%s\n' "$i" >> "$PROJ5/main.py"
    git -C "$PROJ5" commit -qam "fix r$i" >/dev/null
    i=$((i+1))
done
"$FRAIM" status "$PROJ5" >/dev/null 2>&1
check "accumulated again → exit 1" "$?" "1"
git -C "$PROJ5" add -A >/dev/null
# --allow-empty: a prune that honestly changed nothing still has to leave the anchor,
# which is exactly what `fraim prune-mark` does.
git -C "$PROJ5" commit -q --allow-empty -m "prune: reconcile foundation" >/dev/null
"$FRAIM" status "$PROJ5" >/dev/null 2>&1
check "a completed /prune resets the counter" "$?" "0"

# --- git as a given ---------------------------------------------------------
# Every save point here is a commit, so a project without a repository is a project
# in which nothing can be undone. The repository is part of the scaffold, not something the user
# has to set up themselves.
PROJ3="$SANDBOX/proj3"
mkdir -p "$PROJ3"
"$FRAIM" scaffold "$PROJ3" >/dev/null 2>&1
check "scaffold created a repository where there was none" \
    "$([ -d "$PROJ3/.git" ] && echo yes || echo no)" "yes"
check "commit identity configured" \
    "$(git -C "$PROJ3" config user.email)" "fraim@localhost"

# But inside someone else's repository it does not create one: a nested repository would silently detach
# the human's files from their own history.
mkdir -p "$PROJ3/sub"
"$FRAIM" scaffold "$PROJ3/sub" >/dev/null 2>&1
check "nested repository is not created" \
    "$([ -d "$PROJ3/sub/.git" ] && echo yes || echo no)" "no"

PROJ4="$SANDBOX/proj4"
mkdir -p "$PROJ4/ai/tasks"
printf '# Arch\n' > "$PROJ4/ARCHITECTURE.md"
"$FRAIM" status "$PROJ4" 2>/dev/null | grep -q 'нет репозитория'
check "watchman sees a project without a repository" "$?" "0"

# ------------------------------------------------- existing foreign repository
# The shape every real onboarding has: history, a remote, its own README and .gitignore.
# Everything below used to be skipped silently on exactly this shape.
printf '\nforeign repository (onboarding)\n'

LEGACY="$SANDBOX/legacy"
ORIGIN="$SANDBOX/origin.git"
git init -q --bare "$ORIGIN"
mkdir -p "$LEGACY/src"
git -C "$LEGACY" init -q
git -C "$LEGACY" config user.email t@t; git -C "$LEGACY" config user.name t
printf '# Legacy\n' > "$LEGACY/README.md"
printf 'node_modules/\n' > "$LEGACY/.gitignore"
printf 'x\n' > "$LEGACY/src/index.js"
printf 'SECRET=xxx\n' > "$LEGACY/.env"
git -C "$LEGACY" add README.md .gitignore src/index.js >/dev/null 2>&1
git -C "$LEGACY" commit -qm "initial" >/dev/null 2>&1
git -C "$LEGACY" remote add origin "$ORIGIN" >/dev/null 2>&1

cd "$LEGACY" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
check "scaffold worked on a foreign repository" "$?" "0"
check "foreign README untouched" "$(cat "$LEGACY/README.md")" "# Legacy"
check "foreign .gitignore preserved" "$(grep -c '^node_modules/$' "$LEGACY/.gitignore")" "1"
check "secrets appended to foreign .gitignore" "$(grep -c '^\.env$' "$LEGACY/.gitignore")" "1"
check ".env is now ignored" \
    "$(git -C "$LEGACY" check-ignore -q .env && echo yes || echo no)" "yes"
check "data/ not imposed on a foreign project" "$(grep -c '^data/$' "$LEGACY/.gitignore")" "0"

# Idempotent: a second pass must not append the same lines again.
"$FRAIM" scaffold >/dev/null 2>&1
check "repeated scaffold does not duplicate lines" "$(grep -c '^\.env$' "$LEGACY/.gitignore")" "1"

# A tracked .env is not fixed by ignoring it, and silence there would be the dangerous
# outcome — the user would push believing the secret is covered.
printf 'SECRET=yyy\n' > "$LEGACY/.env2"
git -C "$LEGACY" add -f .env >/dev/null 2>&1
git -C "$LEGACY" commit -qm "oops" >/dev/null 2>&1
"$FRAIM" scaffold 2>&1 | grep -q 'уже в истории git'
check "tracked .env triggers a warning" "$?" "0"
rm -f "$LEGACY/.env2"

# Save points that never left this machine: detection only, never a reach for the network.
#
# Two different quantities, and measuring them with one would be a lie (D5). Here the address is set, but
# nothing has ever been pushed to it — that is unfinished setup, not a lagging copy, and the host
# at that moment usually holds an empty repository that looks existing from outside.
"$FRAIM" status "$LEGACY" 2>/dev/null | grep -q 'ни разу ничего не уезжало'
check "watchman sees unfinished remote setup" "$?" "0"

# And this is real lag: the copy is populated, and new points landed after it.
git -C "$LEGACY" push -q origin HEAD >/dev/null 2>&1
printf 'y\n' >> "$LEGACY/src/index.js"
git -C "$LEGACY" commit -qam "fix: y" >/dev/null 2>&1
printf 'z\n' >> "$LEGACY/src/index.js"
git -C "$LEGACY" commit -qam "fix: z" >/dev/null 2>&1
"$FRAIM" status "$LEGACY" 2>/dev/null | grep -q 'не уехали в удалённую копию'
check "watchman sees unpushed save points" "$?" "0"
"$FRAIM" config set unpushed_threshold 1 >/dev/null 2>&1
"$FRAIM" status "$LEGACY" >/dev/null 2>&1
check "above threshold is an alarm" "$?" "1"
"$FRAIM" config set unpushed_threshold 99 >/dev/null 2>&1

NOREMOTE="$SANDBOX/noremote"
mkdir -p "$NOREMOTE"; cd "$NOREMOTE" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
"$FRAIM" status "$NOREMOTE" 2>/dev/null | grep -q 'нет удалённой копии'
check "project without a remote is named honestly" "$?" "0"
"$FRAIM" config set unpushed_threshold 0 >/dev/null 2>&1
"$FRAIM" status "$NOREMOTE" 2>/dev/null | grep -c 'удалённой копии' | grep -q '^0$'
check "threshold 0 silences the remote check" "$?" "0"
"$FRAIM" config unset unpushed_threshold >/dev/null 2>&1
# A retired switch in an old ai/fraim.conf is still honoured.
printf 'check_remote = off\n' >> "$NOREMOTE/ai/fraim.conf"
"$FRAIM" status "$NOREMOTE" 2>/dev/null | grep -c 'удалённой копии' | grep -q '^0$'
check "retired check_remote = off still silences it" "$?" "0"
"$FRAIM" config 2>/dev/null | grep unpushed_threshold | grep -q 'старый ключ'
check "the value's source names the retired key" "$?" "0"
"$FRAIM" config set check_remote on >/dev/null 2>&1
check "a retired key is not written — the new one is named" "$?" "2"
"$FRAIM" config set check_remote on 2>&1 | grep -q 'unpushed_threshold'
check "the refusal names the replacement" "$?" "0"
grep -v '^check_remote' "$NOREMOTE/ai/fraim.conf" > "$NOREMOTE/ai/fraim.conf.t" && mv "$NOREMOTE/ai/fraim.conf.t" "$NOREMOTE/ai/fraim.conf"

# The blind spot that mattered once reactive work became the main mode: a foundation
# file that never entered history at all is invisible to --untracked-files=no.
rm -f "$NOREMOTE/AGENTS.md"
git -C "$NOREMOTE" rm -q --cached AGENTS.md >/dev/null 2>&1
git -C "$NOREMOTE" commit -qm "drop" >/dev/null 2>&1
printf 'brand new\n' > "$NOREMOTE/AGENTS.md"
"$FRAIM" status "$NOREMOTE" 2>/dev/null | grep -q 'после последней точки сохранения'
check "untracked foundation file noticed" "$?" "0"

cd "$PROJ2" || exit 1

# ---------------------------------------------------------------- config
printf '\nfraim config\n'

check "default value" "$("$FRAIM" config 2>/dev/null | grep foundation_lag_commits | awk '{print $2}')" "10"
"$FRAIM" config set foundation_lag_commits 3 >/dev/null 2>&1
check "project setting written" "$(grep -c 'foundation_lag_commits = 3' "$PROJ2/ai/fraim.conf")" "1"
check "value source shown" "$("$FRAIM" config 2>/dev/null | grep foundation_lag_commits | grep -c 'ai/fraim.conf')" "1"
"$FRAIM" config set --machine abandon_after_days 31 >/dev/null 2>&1
check "machine setting written" "$(grep -c 'abandon_after_days = 31' "$FRAIM_HOME/config")" "1"
"$FRAIM" config set nonsense_key 1 >/dev/null 2>&1
check "unknown key rejected" "$?" "2"
"$FRAIM" config set foundation_lag_commits many >/dev/null 2>&1
check "a number key refuses a word" "$?" "2"
"$FRAIM" config set updates sometimes >/dev/null 2>&1
check "an enum key refuses a value outside its list" "$?" "2"
"$FRAIM" config set check_git off >/dev/null 2>&1
check "an always-on check cannot be switched off" "$?" "2"
"$FRAIM" config set --machine launchcmd_devin 'devin --model %s' >/dev/null 2>&1
check "a family key is accepted" "$(grep -c '^launchcmd_devin = ' "$FRAIM_HOME/config")" "1"
"$FRAIM" config 2>/dev/null | grep -q 'launchcmd_devin'
check "a set family key is listed" "$?" "0"
"$FRAIM" config unset --machine launchcmd_devin >/dev/null 2>&1
check "unset removes the line" "$(grep -c '^launchcmd_devin' "$FRAIM_HOME/config")" "0"
"$FRAIM" config set role_investigate nonsense >/dev/null 2>&1
check "a role value is checked for agent:model:effort" "$?" "2"

# A check turned off must actually stop firing.
for i in 1 2 3; do
    printf 'drift %s\n' "$i" >> "$PROJ2/app.py"
    git -C "$PROJ2" add app.py >/dev/null 2>&1
    git -C "$PROJ2" commit -qm "fix: drift $i" >/dev/null 2>&1
done
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "drift above threshold → exit 1" "$?" "1"
"$FRAIM" config set foundation_lag_commits 0 >/dev/null 2>&1
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "threshold 0 — the check does not fire" "$?" "0"
"$FRAIM" config set foundation_lag_commits 10 >/dev/null 2>&1

# ---------------------------------------------------------------- verbs
printf '\ndeterministic verbs\n'

# --- board: task cards -------------------------------------------------------
card() { # title — the card body, as the agent sends it
    printf '# %s\n\n## What and why\nNeeded because it is needed.\n\n## Done when\nIt works.\n' "$1"
}
card "Add login" | "$FRAIM" task-new add-auth --task >/dev/null 2>&1
check "task-new created a card" "$([ -f "$PROJ2/ai/tasks/add-auth.md" ] && echo yes || echo no)" "yes"
check "frontmatter: kind" "$(sed -n 's/^kind: //p' "$PROJ2/ai/tasks/add-auth.md")" "task"
check "frontmatter: date" "$(grep -c '^created: 20' "$PROJ2/ai/tasks/add-auth.md")" "1"
check "card saved with a save point" "$(git -C "$PROJ2" log --oneline -1 --format=%s)" "task: add-auth — added"
# A card holds nothing that could go stale: no provenance, no plan.
check "card has no provenance" "$(grep -c 'Based on\|Plan provenance' "$PROJ2/ai/tasks/add-auth.md")" "0"
card "x" | "$FRAIM" task-new add-auth --task >/dev/null 2>&1
check "task-new does not overwrite an existing task" "$?" "2"
card "x" | "$FRAIM" task-new "Not Kebab" --task >/dev/null 2>&1
check "task-new requires kebab-case" "$?" "2"
"$FRAIM" task-new no-body --task </dev/null >/dev/null 2>&1
check "no card body — refused" "$?" "2"
printf '# Title only\n' | "$FRAIM" task-new no-sections --task >/dev/null 2>&1
check "no «What and why» and «Done when» — refused" "$?" "2"
printf -- '---\nkind: master\n---\n# x\n' | "$FRAIM" task-new own-fm --task >/dev/null 2>&1
check "frontmatter from the agent — refused" "$?" "2"
check "refusals left nothing behind" "$(ls "$PROJ2/ai/tasks" | grep -c 'no-body\|no-sections\|own-fm\|^\.')" "0"

# Project: a master task and subtasks, one level.
card "Web version" | "$FRAIM" task-new web --master >/dev/null 2>&1
check "master task created" "$(sed -n 's/^kind: //p' "$PROJ2/ai/tasks/web.md")" "master"
card "Login" | "$FRAIM" task-new web-login --parent web >/dev/null 2>&1
check "subtask knows its project" "$(sed -n 's/^parent: //p' "$PROJ2/ai/tasks/web-login.md")" "web"
card "x" | "$FRAIM" task-new bad-child --parent add-auth >/dev/null 2>&1
check "parent must be a master task" "$?" "2"
card "x" | "$FRAIM" task-new bad-master --master --parent web >/dev/null 2>&1
check "master task has no parent" "$?" "2"
"$FRAIM" tasks 2>/dev/null | grep -q '◆ web — Web version'
check "board shows the project" "$?" "0"
"$FRAIM" tasks 2>/dev/null | grep -q '      · web-login — Login'
check "subtask is under the project" "$?" "0"
"$FRAIM" tasks 2>/dev/null | grep -q 'не начата, 0 из 1'
check "project progress before the first closed one" "$?" "0"
python3 -c "import json,sys;json.load(sys.stdin)" < "$("$FRAIM" tasks --json > "$SANDBOX/t.json" 2>/dev/null; echo "$SANDBOX/t.json")"
check "tasks --json is valid JSON" "$?" "0"

# Closing: the card moves to the archive with an outcome line.
"$FRAIM" task-seal web "all of it" >/dev/null 2>&1
check "project with open subtasks cannot be closed" "$?" "2"
"$FRAIM" task-seal web-login >/dev/null 2>&1
check "no outcome line — refused" "$?" "2"
"$FRAIM" task-seal web-login "login works" >/dev/null 2>&1
check "subtask closed" "$?" "0"
check "card left the board" "$([ -f "$PROJ2/ai/tasks/web-login.md" ] && echo yes || echo no)" "no"
ARCH=$(find "$PROJ2/ai/archive/tasks" -name '*_web-login.md')
check "card in the archive" "$([ -n "$ARCH" ] && echo yes || echo no)" "yes"
check "archive: outcome" "$(sed -n 's/^outcome: //p' "$ARCH")" "done"
check "archive: result" "$(sed -n 's/^result: //p' "$ARCH")" '"login works"'
check "closing saved with a save point" "$(git -C "$PROJ2" log --oneline -1 --format=%s)" "archive: web-login — done"
"$FRAIM" tasks 2>/dev/null | grep -q 'в работе, 1 из 1'
check "project in progress — computed" "$?" "0"
"$FRAIM" task-seal add-auth --dropped "changed our mind" >/dev/null 2>&1
check "dropping is closing too" "$(sed -n 's/^outcome: //p' "$(find "$PROJ2/ai/archive/tasks" -name '*_add-auth.md')")" "dropped"
"$FRAIM" task-seal web "web version done" >/dev/null 2>&1
check "project without open subtasks closes" "$?" "0"

# The kind is never a default: a model asked for a project must not get a silent task.
card "No kind" | "$FRAIM" task-new no-kind >/dev/null 2>&1
check "task-new without --task / --master — refused" "$?" "2"
check "refused card was not written" "$([ -f "$PROJ2/ai/tasks/no-kind.md" ] && echo yes || echo no)" "no"
card "Both" | "$FRAIM" task-new both-kinds --task --master >/dev/null 2>&1
check "--task and --master together — refused" "$?" "2"

# A project is laid down with its breakdown: one call, every child a card, one save point.
proj() { # extra subtasks text — a master card with a «## Subtasks» section
    printf '# Mobile app

## What and why
People ask for it.

## Done when
It ships.

## Subtasks

%s

## Links
- issue 7
' "$1"
}
proj '### mob-api — Shared API
What and why: both clients read it.
Done when: the schema is in the repo.

### mob-ios — iOS client
What and why: half of the users.
Done when: it runs
  on a phone.
After: mob-api

### mob-docs: Docs page
What and why: people need to know.
Done when: the page is up.' | "$FRAIM" task-new mob --master >/dev/null 2>&1
check "master with subtasks created" "$?" "0"
check "every subtask is a card in the project" \
      "$(sed -n 's/^parent: //p' "$PROJ2/ai/tasks/mob-api.md" "$PROJ2/ai/tasks/mob-ios.md" "$PROJ2/ai/tasks/mob-docs.md" | tr '\n' ' ')" "mob mob mob "
check "subtask card: title and sections" \
      "$(grep -c '^# iOS client$\|^## What and why$\|^## Done when$' "$PROJ2/ai/tasks/mob-ios.md")" "3"
check "a continued field stays in its section" "$(grep -c '^on a phone\.$' "$PROJ2/ai/tasks/mob-ios.md")" "1"
check "after is written to the frontmatter" "$(sed -n 's/^after: //p' "$PROJ2/ai/tasks/mob-ios.md")" "mob-api"
check "the master does not keep a copy of its subtasks" "$(grep -c '^## Subtasks\|^### ' "$PROJ2/ai/tasks/mob.md")" "0"
check "sections after the subtasks stay on the master" "$(grep -c '^- issue 7$' "$PROJ2/ai/tasks/mob.md")" "1"
check "project and subtasks in one save point" \
      "$(git -C "$PROJ2" log -1 --format=%s)|$(git -C "$PROJ2" show --name-only --format= HEAD | grep -c '^ai/tasks/mob')" "task: mob — added with 3 subtasks|4"
"$FRAIM" tasks 2>/dev/null | grep -q '◆ mob — Mobile app .*можно брать: mob-api, mob-docs'
check "board names what can be taken next" "$?" "0"
"$FRAIM" tasks 2>/dev/null | grep -q '      · mob-ios — iOS client .*ждёт: mob-api'
check "board names what a waiting subtask waits for" "$?" "0"
"$FRAIM" tasks --json 2>/dev/null | grep -q '"slug": "mob-ios".*"waiting_on": \["mob-api"\]'
check "json: waiting_on" "$?" "0"

# Subtask refusals: nothing of the project is written when one child is wrong.
proj '### mob2-a — A
What and why: x.
Done when: y.
After: mob2-b

### mob2-b — B
What and why: x.
Done when: y.' | "$FRAIM" task-new mob2 --master >/dev/null 2>&1
check "After may name only a subtask above it" "$?" "2"
proj '### mob3-a — A
What and why: x.' | "$FRAIM" task-new mob3 --master >/dev/null 2>&1
check "a subtask without «Done when» — refused" "$?" "2"
proj 'First the API:
### mob4-a — A
What and why: x.
Done when: y.' | "$FRAIM" task-new mob4 --master >/dev/null 2>&1
check "text outside a subtask — refused" "$?" "2"
proj '### mob-api — Again
What and why: x.
Done when: y.' | "$FRAIM" task-new mob5 --master >/dev/null 2>&1
check "a subtask slug already on the board — refused" "$?" "2"
proj '### mob6-a — A
What and why: x.
Done when: y.' | "$FRAIM" task-new mob6 --task >/dev/null 2>&1
check "«## Subtasks» on an ordinary task — refused" "$?" "2"
check "refused projects left nothing behind" \
      "$(ls -a "$PROJ2/ai/tasks" | grep -c 'mob[2-6]\|^\.mob')" "0"

# One more subtask, ordered after an existing one.
card "Android client" | "$FRAIM" task-new mob-android --parent mob --after mob-api >/dev/null 2>&1
check "--after with --parent" "$(sed -n 's/^after: //p' "$PROJ2/ai/tasks/mob-android.md")" "mob-api"
card "x" | "$FRAIM" task-new mob-bad --parent mob --after add-auth >/dev/null 2>&1
check "--after naming a card outside the project — refused" "$?" "2"
card "x" | "$FRAIM" task-new mob-bad --task --after mob-api >/dev/null 2>&1
check "--after without --parent — refused" "$?" "2"

# Closing frees the queue: the seal names what can be taken now.
"$FRAIM" task-seal mob-api "schema in the repo" 2>/dev/null | grep -q 'можно брать: mob-android, mob-docs, mob-ios'
check "seal names what is free now" "$?" "0"
"$FRAIM" tasks 2>/dev/null | grep -q 'ждёт:'
check "nothing waits once the dependency is closed" "$?" "1"
for _s in mob-ios mob-android mob-docs; do "$FRAIM" task-seal "$_s" --dropped "test" >/dev/null 2>&1; done
"$FRAIM" task-seal mob "test" >/dev/null 2>&1

# An ordinary task becomes a project only through a verb — at the human's word.
card "A big one" | "$FRAIM" task-new big --task >/dev/null 2>&1
"$FRAIM" task-master big >/dev/null 2>&1
check "task-master makes a project" "$(sed -n 's/^kind: //p' "$PROJ2/ai/tasks/big.md")" "master"
"$FRAIM" task-seal big "x" >/dev/null 2>&1

# Removed verbs answer with words, not with «unknown command».
"$FRAIM" plan-seal x 2>&1 | grep -q 'задача теперь карточка'
check "removed verb explains where it went" "$?" "0"

# The reactive save point is the record of unplanned work: an ordinary commit verb.
mkdir -p "$PROJ2/src"; printf 'reactive\n' >> "$PROJ2/src/a.py"
"$FRAIM" commit fix "off-by-one" src/a.py >/dev/null 2>&1
check "reactive save point committed" "$(git -C "$PROJ2" log --oneline -1 --format=%s)" "fix: off-by-one"
check "save point marked with a trailer" "$(git -C "$PROJ2" log -1 --format=%b | grep -c '^fraim: ')" "1"

"$FRAIM" stack-passport >/dev/null 2>&1
check "stack-passport created STACK.md" "$([ -f "$PROJ2/STACK.md" ] && echo yes || echo no)" "yes"
check "project name substituted into the passport" "$(grep -c 'STACK PASSPORT — proj2' "$PROJ2/STACK.md")" "1"
check "passport marked as unfilled" "$(grep -c 'fraim:stub' "$PROJ2/STACK.md")" "1"
"$FRAIM" stack-passport >/dev/null 2>&1
check "stack-passport does not overwrite" "$?" "2"

"$FRAIM" prune-mark >/dev/null 2>&1
check "prune-mark left an anchor commit" "$(git -C "$PROJ2" log --oneline -1 --format=%s | grep -c '^prune: reconcile foundation')" "1"
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "marker reset the drift counter" "$?" "0"

# --- investigate-new / investigate-seal -------------------------------------
"$FRAIM" investigate-new selector-flicker >/dev/null 2>&1
check "investigate-new created an investigation" \
    "$([ -f "$PROJ2/ai/investigations/selector-flicker/findings.md" ] && echo yes || echo no)" "yes"
check "investigation provenance set" \
    "$(grep -c '^- Based on: HEAD ' "$PROJ2/ai/investigations/selector-flicker/findings.md")" "1"
check "slug substituted" \
    "$(grep -c 'INVESTIGATION — selector-flicker' "$PROJ2/ai/investigations/selector-flicker/findings.md")" "1"
"$FRAIM" investigate-seal selector-flicker >/dev/null 2>&1
check "gate: does not archive an investigation stub" "$?" "2"

FIND="$PROJ2/ai/investigations/selector-flicker/findings.md"
python3 - "$FIND" <<'PY2'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
t = "\n".join(l for l in p.read_text().splitlines() if "fraim:stub" not in l)
p.write_text(t + "\n")
PY2
"$FRAIM" investigate-seal selector-flicker >/dev/null 2>&1
check "gate: does not archive without an outcome" "$?" "2"

python3 - "$FIND" <<'PY2'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
t = t.replace("<root cause, plainly. Route: reactive fix (surgical or structural) | a task on the board | /prune.>",
              "The selector is rebuilt on every render; the observer attaches to the old node.")
p.write_text(t)
PY2
"$FRAIM" investigate-seal selector-flicker >/dev/null 2>&1
check "gate: does not archive without a cleanup report" "$?" "2"

python3 - "$FIND" <<'PY2'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
t = t.replace("<repo: what `git status` shows — and world: what was undone, counted against the baseline above>",
              "Repo: git status clean. World: 12 seeded rows deleted, lease released.")
t = t.replace("<what was ruled out, where exactly you got stuck, what the human must decide or provide.>", "")
t = t.replace("<every repo file created or modified during the investigation — this is the cleanup list>", "none")
t = t.replace("<baseline first: what the slice looked like before — row count, leases, worker state>", "none")
t = t.replace("<then every world-state mutation with its undo command, written live, the moment you mutate>", "")
t = t.replace("<the ONE unclear thing, as a question that can be answered>", "why does the selector flicker")
t = t.replace("| 1 | <hypothesis> | open / confirmed / excluded | <what was observed> |",
              "| 1 | stale node | confirmed | observer attached to detached node |")
t = t.replace("- <what was run or instrumented, and what it showed>", "- instrumented the observer")
p.write_text(t)
PY2
cp "$FIND" "$SANDBOX/findings.bak"
printf '\nСелектор мигает, потому что наблюдатель висит на отсоединённом узле.\n' >> "$FIND"
"$FRAIM" investigate-seal selector-flicker >/dev/null 2>&1
check "investigate-seal refuses findings not in English" "$?" "2"
cp "$SANDBOX/findings.bak" "$FIND"
"$FRAIM" investigate-seal selector-flicker >/dev/null 2>&1
check "investigate-seal archives an investigation with an outcome" "$?" "0"
check "investigation in the archive" \
    "$(find "$PROJ2/ai/archive" -maxdepth 1 -name '*_investigate_selector-flicker' | wc -l | tr -d ' ')" "1"
check "investigation archiving committed" \
    "$(git -C "$PROJ2" log --oneline -1 --format=%s)" "archive: investigate selector-flicker"

# --- investigation in progress ----------------------------------------------
"$FRAIM" investigate-new open-one >/dev/null 2>&1
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "investigation in progress raises no alarm" "$?" "0"
rm -rf "$PROJ2/ai/investigations/open-one"

# --- fraim commit -----------------------------------------------------------
"$FRAIM" commit test "no paths" >/dev/null 2>&1
check "commit without paths refuses" "$?" "2"
"$FRAIM" commit BAD "wrong kind" README.md >/dev/null 2>&1
check "commit checks the kind" "$?" "2"
printf 'x\n' >> "$PROJ2/README.md"
"$FRAIM" commit task "save point" README.md >/dev/null 2>&1
check "commit puts a save point" "$(git -C "$PROJ2" log --oneline -1 --format=%s)" "task: save point"

# --- undo / restore ---------------------------------------------------------
# The promise «work boldly, there is a save point» is empty if getting back to it is possible
# only via git reset. Undo is a reverting commit: we do not rewrite history.
printf 'undo-me\n' >> "$PROJ2/README.md"
"$FRAIM" commit task "an edit we will undo" README.md >/dev/null 2>&1
UNDO_REF=$(git -C "$PROJ2" rev-parse --short HEAD)
"$FRAIM" undo >/dev/null 2>&1
check "undo without an argument shows, does not act" \
    "$(git -C "$PROJ2" rev-parse --short HEAD)" "$UNDO_REF"
check "undo lists our points" "$("$FRAIM" undo 2>/dev/null | grep -c "$UNDO_REF")" "1"

"$FRAIM" undo "$UNDO_REF" >/dev/null 2>&1
check "undo reverted the change" "$(grep -c 'undo-me' "$PROJ2/README.md")" "0"
check "history not rewritten — a reverting commit added" \
    "$(git -C "$PROJ2" cat-file -e "$UNDO_REF^{commit}" 2>/dev/null; echo $?)" "0"

# Someone else's commit is never undone — in a foreign repository that is the difference between
# a tool and an incident.
printf 'theirs\n' >> "$PROJ2/main.py"
git -C "$PROJ2" commit -qam "их собственный коммит" >/dev/null 2>&1
"$FRAIM" undo "$(git -C "$PROJ2" rev-parse --short HEAD)" >/dev/null 2>&1
check "foreign commit is not undone" "$?" "2"

# Refusal when the point's own files are being edited right now: there is nothing to merge the undo with.
printf 'again\n' >> "$PROJ2/README.md"
"$FRAIM" commit task "second edit" README.md >/dev/null 2>&1
UNDO_REF2=$(git -C "$PROJ2" rev-parse --short HEAD)
printf 'dirty\n' >> "$PROJ2/README.md"
"$FRAIM" undo "$UNDO_REF2" >/dev/null 2>&1
check "undo refuses if the point's files are currently modified" "$?" "2"
git -C "$PROJ2" checkout -- README.md >/dev/null 2>&1
"$FRAIM" undo "$UNDO_REF2" >/dev/null 2>&1
check "after saving the edits, undo goes through" "$?" "0"

# restore — the working tree, by named paths. `git restore .` would sweep away, along with
# our debris, the human's unfinished work; that is exactly why /investigate used to
# demand a clean tree and pushed the git chore onto the user.
printf 'mine, unsaved\n' >> "$PROJ2/main.py"
printf 'scratch\n' > "$PROJ2/scratch-probe.py"
printf 'CHANGED\n' >> "$PROJ2/README.md"
"$FRAIM" restore README.md scratch-probe.py >/dev/null 2>&1
check "restore reverted a tracked file" "$(grep -c 'CHANGED' "$PROJ2/README.md")" "0"
check "restore deleted what was created" "$([ -e "$PROJ2/scratch-probe.py" ] && echo yes || echo no)" "no"
check "restore left the human's unfinished work alone" "$(grep -c 'mine, unsaved' "$PROJ2/main.py")" "1"
git -C "$PROJ2" checkout -- main.py >/dev/null 2>&1

"$FRAIM" restore >/dev/null 2>&1
check "restore without paths refuses" "$?" "2"
"$FRAIM" restore . >/dev/null 2>&1
check "restore «everything» refuses" "$?" "2"
"$FRAIM" restore ../outside >/dev/null 2>&1
check "restore outside the project refuses" "$?" "2"

# The watchman sees unsaved changes — but only what the verbs save themselves.
printf 'edited by hand\n' >> "$PROJ2/ARCHITECTURE.md"
"$FRAIM" status "$PROJ2" 2>/dev/null | grep -q 'после последней точки сохранения'
check "watchman sees an unsaved foundation" "$?" "0"
git -C "$PROJ2" checkout -- ARCHITECTURE.md >/dev/null 2>&1
printf 'work in progress\n' >> "$PROJ2/main.py"
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "human's uncommitted code raises no alarm" "$?" "0"
git -C "$PROJ2" checkout -- main.py >/dev/null 2>&1

# commit_verbs = off must actually stop the commits.
"$FRAIM" config set commit_verbs off >/dev/null 2>&1
BEFORE_N=$(git -C "$PROJ2" rev-list --count HEAD)
printf 'more\n' >> "$PROJ2/src/a.py"; "$FRAIM" commit fix "another" src/a.py >/dev/null 2>&1
check "commit_verbs = off disables the commit" "$(git -C "$PROJ2" rev-list --count HEAD)" "$BEFORE_N"
"$FRAIM" config set commit_verbs on >/dev/null 2>&1

cd "$REPO" || exit 1

# --- decide / pitfall: writing into the foundation --------------------------
cd "$PROJ2" || exit 1

printf 'Decision: sqlite in WAL mode, file at `C:\\temp\\new`.\n' | "$FRAIM" decide "storage engine" >/dev/null 2>&1
check "decide appended an entry" "$(grep -c '^## 20.* — storage engine$' "$PROJ2/DECISIONS.md")" "1"
check "decide removed the stub marker" "$(grep -c 'fraim:stub' "$PROJ2/DECISIONS.md")" "0"

printf 'Decision: retry with jitter.\n' | "$FRAIM" decide "retries" >/dev/null 2>&1
check "new decision landed on top" \
      "$(grep -m1 '^## 20' "$PROJ2/DECISIONS.md" | sed 's/.*— //')" "retries"
check "old decision remained" "$(grep -c '— storage engine$' "$PROJ2/DECISIONS.md")" "1"

printf 'Decision: postgres after all.\n' |
    "$FRAIM" decide "storage engine, take two" --supersedes "storage engine" >/dev/null 2>&1
# A superseded entry moves to the archive whole: only active decisions stay in the root,
# and the new entry names the superseded one by its full heading.
check "supersede recorded with the full heading" "$(grep -c '^> Supersedes: 20.* — storage engine$' "$PROJ2/DECISIONS.md")" "1"
check "superseded entry left the root" "$(grep -c '^## .*— storage engine$' "$PROJ2/DECISIONS.md")" "0"
check "and went to the decisions archive, not deleted" "$(grep -c '— storage engine$' "$PROJ2/ai/archive/decisions_log.md")" "1"
check "the moved entry kept its backslashes" "$(grep -cF 'C:\temp\new' "$PROJ2/ai/archive/decisions_log.md")" "1"
printf 'Decision: x.\n' | "$FRAIM" decide "ambiguous" --supersedes "20" >/dev/null 2>&1
check "ambiguous supersede — refused" "$?" "2"
check "and nothing written" "$(grep -c '— ambiguous$' "$PROJ2/DECISIONS.md")" "0"
printf 'Decision: y.\n' | "$FRAIM" decide "free text" --supersedes "an idea from a chat" >/dev/null 2>&1
check "unmatched supersede stays a reference" "$(grep -c '^> Supersedes: an idea from a chat$' "$PROJ2/DECISIONS.md")" "1"
# The body arrives as is: awk -v would silently expand backslashes.
printf 'Decision: path C:\\new\\table stays.\n' | "$FRAIM" decide "backslashes" >/dev/null 2>&1
check "backslashes in the body untouched" "$(grep -c 'C:\\new\\table' "$PROJ2/DECISIONS.md")" "1"
LONG="Decision: $(printf 'слово %.0s' $(seq 1 40))конец."
printf '%s\n' "$LONG" | "$FRAIM" decide "long line" >/dev/null 2>&1
check "long decision line wrapped" \
      "$(awk '/— long line$/,/конец/' "$PROJ2/DECISIONS.md" | LC_ALL=C awk '{ t=$0; gsub(/[\200-\277]/,"",t); if (length(t) > 100) n++ } END { print n+0 }')" "0"

"$FRAIM" decide "empty" </dev/null >/dev/null 2>&1
check "decide rejects an empty body" "$?" "2"
# Input is open but nothing comes — that is how a harness or script hands a command an inherited channel.
# The verb must refuse with a hint, not wait for end of stream forever.
rm -f "$SANDBOX/openfifo"; mkfifo "$SANDBOX/openfifo"; exec 4<>"$SANDBOX/openfifo"
OUTF=$(FRAIM_BODY_WAIT=5 "$FRAIM" decide "open but empty" < "$SANDBOX/openfifo" 2>&1)
check "open empty input — refusal, not a hang" "$?" "2"
check "refusal shows how to pass the text" "$(printf '%s' "$OUTF" | grep -c "<<'EOF'")" "1"
exec 4>&-
check "decide does not commit by itself" \
      "$(git -C "$PROJ2" log --oneline -1 --format=%s | grep -c '^decide')" "0"

# Earlier tests overwrote the foundation with a blank without sections — first check that
# the verb honestly refuses on such a file rather than appending into the void.
"$FRAIM" pitfall "nowhere to put this" >/dev/null 2>&1
check "pitfall refuses without a Known Pitfalls section" "$?" "2"
cp "$REPO/installer/templates/foundation/CONVENTIONS.md" "$PROJ2/CONVENTIONS.md"

"$FRAIM" pitfall "S3 client truncates keys over 1024 bytes." >/dev/null 2>&1
check "pitfall appended a line to its section" \
      "$(sed -n '/^## Known Pitfalls/,$p' "$PROJ2/CONVENTIONS.md" | grep -c 'S3 client truncates')" "1"
check "«None yet» placeholder removed" "$(grep -c '^- None yet\.$' "$PROJ2/CONVENTIONS.md")" "0"
"$FRAIM" pitfall "Tests fail unless TZ=UTC." >/dev/null 2>&1
check "second line landed next" \
      "$(sed -n '/^## Known Pitfalls/,$p' "$PROJ2/CONVENTIONS.md" | grep -c '^- ')" "2"
"$FRAIM" pitfall "$(printf 'lesson of %.0s' $(seq 1 40))" >/dev/null 2>&1
check "long lesson wrapped under its bullet" \
      "$([ "$(sed -n '/^## Known Pitfalls/,$p' "$PROJ2/CONVENTIONS.md" | grep -c '^  [a-z]')" -ge 1 ] && echo yes)" "yes"

# --- arch: a map section is rewritten whole ---------------------------------
printf '# A\n\n## Stack\nold stack\n\n## Data flow\nflow stays\n' > "$PROJ2/ARCHITECTURE.md"
printf 'new stack line\n' | "$FRAIM" arch "Stack" >/dev/null 2>&1
check "arch replaced the section body" "$(grep -c '^new stack line$' "$PROJ2/ARCHITECTURE.md")$(grep -c '^old stack$' "$PROJ2/ARCHITECTURE.md")" "10"
check "neighbouring section intact" "$(grep -c '^flow stays$' "$PROJ2/ARCHITECTURE.md")" "1"
# A table cell that quotes a pipe keeps its backslash: losing it splits the cell.
printf '| cmd | note |\n|---|---|\n| `a \\| b` | pipe, `\\n` |\n' | "$FRAIM" arch "Stack" >/dev/null 2>&1
check "arch keeps backslashes in the body" "$(grep -cF '| `a \| b` | pipe, `\n` |' "$PROJ2/ARCHITECTURE.md")" "1"
printf 'x\n' | "$FRAIM" arch "Stak" >/dev/null 2>&1
check "typo in section name — refusal, not a new section" "$?$(grep -c '^## Stak$' "$PROJ2/ARCHITECTURE.md")" "20"
printf 'deploy notes\n' | "$FRAIM" arch "Deployment" --new >/dev/null 2>&1
check "--new added a section" "$(grep -c '^## Deployment$' "$PROJ2/ARCHITECTURE.md")" "1"
printf '## Sneaky\nx\n' | "$FRAIM" arch "Stack" >/dev/null 2>&1
check "heading in the body — refused" "$?" "2"
printf 'x\n' | "$FRAIM" arch "Anything" --in DECISIONS.md >/dev/null 2>&1
check "DECISIONS.md is not editable via arch" "$?" "2"
mkdir -p "$PROJ2/src/deep"
(cd "$PROJ2/src/deep" && printf 'from below\n' | "$FRAIM" arch "Stack" >/dev/null 2>&1)
check "verb finds the project root from a subdirectory" "$(grep -c '^from below$' "$PROJ2/ARCHITECTURE.md")" "1"

# --- brief and find: the whole foundation and the whole entry ---------------
B=$("$FRAIM" brief 2>/dev/null)
check "brief ends with a completeness mark" "$(printf '%s\n' "$B" | tail -1 | grep -c 'nothing cut')" "1"
check "brief opens with verbs by situation" "$(printf '%s\n' "$B" | grep -c '^- finished a coherent piece → `fraim commit')" "1"
check "brief carries the map" "$(printf '%s\n' "$B" | grep -c '^from below$')" "1"
check "brief carries decisions in compact form" "$(printf '%s\n' "$B" | grep -c '^Decision: retry with jitter.$')" "1"
check "brief has no lines wider than the width" \
      "$(printf '%s\n' "$B" | LC_ALL=C awk '{ t=$0; gsub(/[\200-\277]/,"",t); if (length(t) > 100) n++ } END { print n+0 }')" "0"
F=$("$FRAIM" find jitter ДЖИТТЕР 2>/dev/null)
check "find returns the whole decision entry with its heading" \
      "$(printf '%s\n' "$F" | grep -c 'DECISIONS.md › 20.* — retries')$(printf '%s\n' "$F" | grep -c 'retry with jitter')" "11"
"$FRAIM" find nothing-like-this >/dev/null 2>&1
check "find with no matches — exit 1" "$?" "1"

# --- backlog: open questions -------------------------------------------------
printf '# Do we need a cache?\n\n## Question\nIt is slow.\n\n## Why it matters\nCold start.\n' |
    "$FRAIM" backlog-new cache-q --from сессия >/dev/null 2>&1
check "question written to the backlog" "$(sed -n 's/^from: //p' "$PROJ2/ai/backlog/cache-q.md")" "сессия"
check "question saved with a save point" "$(git -C "$PROJ2" log --oneline -1 --format=%s)" "backlog: cache-q — added"
printf '# x\n' | "$FRAIM" backlog-new bare-q >/dev/null 2>&1
check "question without «Question» and «Why it matters» — refused" "$?" "2"
"$FRAIM" backlog 2>/dev/null | grep -q 'cache-q — Do we need a cache?'
check "fraim backlog shows the question" "$?" "0"
"$FRAIM" find cache 2>/dev/null | grep -q 'ai/backlog/cache-q.md'
check "find searches the backlog too" "$?" "0"
printf '# Build the cache\n\n## What and why\nx\n\n## Done when\nx\n' | "$FRAIM" task-new add-cache --task --from cache-q >/dev/null 2>&1
check "question became a task" "$([ -f "$PROJ2/ai/tasks/add-cache.md" ] && [ ! -f "$PROJ2/ai/backlog/cache-q.md" ] && echo yes || echo no)" "yes"
check "question archive names the task" "$(grep -c 'became task add-cache' "$PROJ2"/ai/archive/backlog/*_cache-q.md)" "1"
check "card references the question" "$(grep -c 'From the backlog: `ai/archive/backlog/' "$PROJ2/ai/tasks/add-cache.md")" "1"
printf '# Q\n\n## Question\nq\n\n## Why it matters\nq\n' | "$FRAIM" backlog-new drop-q >/dev/null 2>&1
"$FRAIM" backlog-drop drop-q "no longer matters" >/dev/null 2>&1
check "dropped question archived with a reason" "$(sed -n 's/^outcome: //p' "$PROJ2"/ai/archive/backlog/*_drop-q.md)" "dropped"
"$FRAIM" task-seal add-cache "x" >/dev/null 2>&1

# --- language: what the verbs write into a project is English -----------------
# Models that talk to the human in Russian drift into Russian in the foundation. The verbs are
# the only door into it, so the door refuses — and says so in English, to the agent.
printf '\nlanguage of what the verbs write\n'
cp "$PROJ2/DECISIONS.md" "$SANDBOX/dec.before"
OUTL=$(printf 'Решение: храним сессии в sqlite, потому что так проще.\n' | "$FRAIM" decide "sessions" 2>&1)
check "decide refuses a body in Russian" "$?" "2"
check "the refusal tells the agent to rewrite in English" \
      "$(printf '%s' "$OUTL" | grep -c 'not in English\|Rewrite it in English')" "2"
printf 'Decision: sessions live in sqlite.\n' | "$FRAIM" decide "сессии" >/dev/null 2>&1
check "decide refuses a title in Russian" "$?" "2"
printf 'Decision: el agente guarda las sesiones en sqlite porque es más simple y no necesita un servidor aparte para nada en este proyecto pequeño de prueba.\n' |
    "$FRAIM" decide "sessions" >/dev/null 2>&1
check "decide refuses a Latin-script language that is not English" "$?" "2"
check "refusals wrote nothing" "$(cmp -s "$PROJ2/DECISIONS.md" "$SANDBOX/dec.before" && echo same)" "same"
printf 'Decision: sessions live in sqlite; the owner said «так проще» and `кэш` stays a name.\n' |
    "$FRAIM" decide "sessions" >/dev/null 2>&1
check "quoted words in another language are not measured" "$?" "0"
cp "$PROJ2/CONVENTIONS.md" "$SANDBOX/conv.before"
"$FRAIM" pitfall "кэш не сбрасывается после деплоя" >/dev/null 2>&1
check "pitfall refuses Russian" "$?" "2"
check "pitfall refusal wrote nothing" "$(cmp -s "$PROJ2/CONVENTIONS.md" "$SANDBOX/conv.before" && echo same)" "same"
printf 'стек поменялся\n' | "$FRAIM" arch "Stack" >/dev/null 2>&1
check "arch refuses a body in Russian" "$?" "2"
printf 'notes\n' | "$FRAIM" arch "Развёртывание" --new >/dev/null 2>&1
check "arch refuses a new section name in Russian" "$?" "2"
printf '# Добавить кэш\n\n## What and why\nМедленно.\n\n## Done when\nБыстро.\n' | "$FRAIM" task-new ru-card --task >/dev/null 2>&1
check "task-new refuses a card in Russian" "$?" "2"
check "no card left behind" "$(ls -a "$PROJ2/ai/tasks" | grep -c 'ru-card')" "0"
card "Language probe" | "$FRAIM" task-new lang-probe --task >/dev/null 2>&1
"$FRAIM" task-seal lang-probe "готово" >/dev/null 2>&1
check "task-seal refuses a result in Russian" "$?" "2"
check "the card stays on the board" "$([ -f "$PROJ2/ai/tasks/lang-probe.md" ] && echo yes)" "yes"
"$FRAIM" task-seal lang-probe "done" >/dev/null 2>&1
printf '# Нужен ли кэш?\n\n## Question\nМедленно.\n\n## Why it matters\nХолодный старт.\n' | "$FRAIM" backlog-new ru-q >/dev/null 2>&1
check "backlog-new refuses a question in Russian" "$?" "2"
printf '# Probe\n\n## Question\nq\n\n## Why it matters\nq\n' | "$FRAIM" backlog-new probe-q >/dev/null 2>&1
"$FRAIM" backlog-drop probe-q "уже не важно" >/dev/null 2>&1
check "backlog-drop refuses a reason in Russian" "$?" "2"
"$FRAIM" backlog-drop probe-q "no longer matters" >/dev/null 2>&1
printf 'lang\n' >> "$PROJ2/README.md"
LHEAD=$(git -C "$PROJ2" rev-parse HEAD)
"$FRAIM" commit docs "поправил ридми" README.md >/dev/null 2>&1
check "commit refuses a message in Russian" "$?" "2"
check "nothing was committed" "$(git -C "$PROJ2" rev-parse HEAD)" "$LHEAD"
"$FRAIM" commit docs "readme touched" README.md >/dev/null 2>&1
# fraim commit checks what the save point ADDS: the foundation and cards whole, code by its
# comments only. Old text is not the commit's business; strings in code are the operator's.
printf '\nОбычный абзац, дописанный руками в обход глаголов.\n' >> "$PROJ2/DECISIONS.md"
LHEAD=$(git -C "$PROJ2" rev-parse HEAD)
OUTC=$("$FRAIM" commit docs "decisions edited by hand" DECISIONS.md 2>&1)
check "commit refuses a hand edit of the foundation in Russian" "$?" "2"
check "the refusal names the file" "$(printf '%s' "$OUTC" | grep -c 'DECISIONS.md: Обычный абзац')" "1"
check "nothing was committed" "$(git -C "$PROJ2" rev-parse HEAD)" "$LHEAD"
git -C "$PROJ2" checkout -- DECISIONS.md
mkdir -p "$PROJ2/src"
printf 'def f():\n    # считаем сумму заново, кэш врёт\n    return 1\n' > "$PROJ2/src/calc.py"
"$FRAIM" commit feat "calc" src/calc.py >/dev/null 2>&1
check "commit refuses a new code comment in Russian" "$?" "2"
printf 'def f():\n    # recompute the sum, the cache lies\n    die("кэш врёт # совсем")  # the message is the operator\047s\n    return 1\n' > "$PROJ2/src/calc.py"
"$FRAIM" commit feat "calc" src/calc.py >/dev/null 2>&1
check "strings in code are not checked, English comments pass" "$?" "0"
printf 'const a = "http://x"; // сломано\n/*\n * подробности\n */\n' > "$PROJ2/src/a.js"
"$FRAIM" commit feat "js" src/a.js >/dev/null 2>&1
check "// and /* */ comments are checked too" "$?" "2"
printf 'const a = "http://x"; // works\n' > "$PROJ2/src/a.js"
"$FRAIM" commit feat "js" src/a.js >/dev/null 2>&1
check "old lines are not re-checked: only what is added" "$?" "0"

# The watchman reads the foundation as it is now: a hand edit saved past fraim commit
# still shows.
printf '\n## 2026-01-01 — правка руками\n\nРешение: обошли глаголы.\n' >> "$PROJ2/DECISIONS.md"
git -C "$PROJ2" commit -qam "plain git" >/dev/null 2>&1
SL=$("$FRAIM" status 2>&1)
check "watchman reports foundation text not in English" "$(printf '%s' "$SL" | grep -c 'не по-английски: DECISIONS.md (2)')" "1"
git -C "$PROJ2" revert -q --no-edit HEAD >/dev/null 2>&1

LM=$(sh -c '. "'"$REPO"'/installer/lib/core.sh"; . "'"$REPO"'/installer/lib/lang.sh"
    for t in "这破坏了项目的纯洁性" "Ο πράκτορας γράφει" \
             "Der Agent schreibt das Fundament in der Sprache des Operators, was die Reinheit bricht, deshalb soll das Werkzeug die Sprache prüfen, bevor es einen Eintrag in die Entscheidungen schreibt und dann ablehnt." \
             "short terse line: cache key ttl" "| a | b |"; do
        printf "%s\n" "$t" | lang_measure >/dev/null; printf "%s" "$?"
    done')
check "other scripts and German refused; terse English and tables pass" "$LM" "11100"

# ---------------------------------------------------------------- version
printf '\nfraim version (what exactly is installed)\n'

# The version number does not answer «has the update arrived»: between releases the branch
# moves a dozen commits ahead while the number stays put. So the command must also name
# the source — otherwise after git pull all that is left is guessing.
VOUT=$("$FRAIM" version 2>&1)
check "version prints the number on the first line" \
      "$(printf '%s' "$VOUT" | head -1)" "$(cat "$REPO/installer/VERSION")"
check "version names the branch and commit" "$(printf '%s' "$VOUT" | grep -c 'коммит')" "1"
# fraim_version itself stays single-line: its output goes into provenance stamps and
# skill frontmatter, and an extra line there would break both staleness checks.
STAMP=$(sh -c '. "'"$REPO"'/installer/lib/core.sh"; fraim_version' 2>/dev/null)
check "fraim_version stayed one line" "$(printf '%s' "$STAMP" | wc -l | tr -d ' ')" "0"

# ---------------------------------------------------------------- clean
printf '\nfraim clean (cleanup)\n'

CL="$SANDBOX/cleanproj"
mkdir -p "$CL/ai/tasks" "$CL/ai/investigations"
git -C "$CL" init -q; git -C "$CL" config user.email t@t; git -C "$CL" config user.name t
printf '# ARCHITECTURE\nmap\n'  > "$CL/ARCHITECTURE.md"
printf '# CONVENTIONS\nrules\n' > "$CL/CONVENTIONS.md"
printf '# DECISIONS\n'          > "$CL/DECISIONS.md"
printf '# README\n'             > "$CL/README.md"
printf 'check_shape = on\n'     > "$CL/ai/fraim.conf"
printf 'x\n' > "$CL/app.py"
git -C "$CL" add -A >/dev/null; git -C "$CL" commit -qm base >/dev/null
cd "$CL" || exit 1

# an old-format task: a plan in a folder. Clean converts it into a card via upgrade.
mkdir -p "$CL/ai/tasks/old-plan"
printf '# Task Context\n\n## Goal\nСделать Y.\n\n## Why\nНадо.\n' > "$CL/ai/tasks/old-plan/context.md"
printf '# Task\n\n## Summary\nДобавить Y.\n\n## Acceptance Criteria\n- [ ] Y есть\n' > "$CL/ai/tasks/old-plan/task.md"
# an open card — clean does NOT touch the board
printf '# Open one\n\n## What and why\nx\n\n## Done when\nx\n' | "$FRAIM" task-new open-card --task >/dev/null 2>&1
for i in 1 2 3; do
    printf 'c%s\n' "$i" >> "$CL/app.py"
    git -C "$CL" add app.py >/dev/null; git -C "$CL" commit -qm "fix: c$i" >/dev/null
done
# an abandoned investigation and one brought to an outcome
"$FRAIM" investigate-new abandoned-one >/dev/null 2>&1
touch -d '40 days ago' "$CL/ai/investigations/abandoned-one/findings.md" 2>/dev/null ||
    touch -t "$(date -v-40d +%Y%m%d0000 2>/dev/null || echo 202001010000)" \
        "$CL/ai/investigations/abandoned-one/findings.md"
# an investigation folder without findings.md — no outcome, no report; it was invisible to both
mkdir -p "$CL/ai/investigations/no-report"
printf 'заметки на коленке\n' > "$CL/ai/investigations/no-report/notes.md"
touch -d '40 days ago' "$CL/ai/investigations/no-report/notes.md" "$CL/ai/investigations/no-report" 2>/dev/null ||
    touch -t "$(date -v-40d +%Y%m%d0000 2>/dev/null || echo 202001010000)" \
        "$CL/ai/investigations/no-report/notes.md" "$CL/ai/investigations/no-report"
# and the same kind of folder, but fresh: it must not be touched — that is work in progress
mkdir -p "$CL/ai/investigations/fresh-no-report"
printf 'начали сегодня\n' > "$CL/ai/investigations/fresh-no-report/notes.md"
"$FRAIM" investigate-new solved-one >/dev/null 2>&1
python3 - "$CL/ai/investigations/solved-one/findings.md" <<'PYSOLVE'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
t = t.replace('<the ONE unclear thing, as a question that can be answered>', 'why the counter lies')
t = t.replace('<root cause, plainly. Route: reactive fix (surgical or structural) | a task on the board | /prune.>',
              'it counted folders, not runnable tasks')
t = t.replace('<what was ruled out, where exactly you got stuck, what the human must decide or provide.>', '')
t = t.replace('<repo: what `git status` shows — and world: what was undone, counted against the baseline above>',
              'repo: clean; world: untouched')
t = '\n'.join(l for l in t.splitlines() if 'fraim:stub' not in l)
p.write_text(t + '\n')
PYSOLVE

# Under a pipe without --yes, clean must only show the plan: «does it all itself» does not mean
# «without asking», and ratification does not disappear because there are many actions (B5).
PLAN=$("$FRAIM" clean </dev/null 2>&1)
check "clean without --yes does nothing" "$([ -d "$CL/ai/investigations/abandoned-one" ] && echo yes || echo no)" "yes"
check "clean shows the plan" "$(printf '%s' "$PLAN" | grep -c 'Чистка сделает')" "1"
check "plan includes the foundation" "$(printf '%s' "$PLAN" | grep -c 'до стандарта')" "1"
check "plan includes the abandoned investigation" "$(printf '%s' "$PLAN" | grep -c 'abandoned-one')" "1"
check "plan includes the finished investigation" "$(printf '%s' "$PLAN" | grep -c 'solved-one')" "1"
# A folder without findings.md survived any number of cleans silently: the walk went by file, not
# by folder. Now both the watchman and clean see it — but only when it has really
# stopped moving, otherwise clean would carry work in progress off to the archive.
check "plan includes the folder without findings.md" "$(printf '%s' "$PLAN" | grep -c 'no-report')" "1"
check "plan does NOT touch the fresh folder without findings.md" \
      "$(printf '%s' "$PLAN" | grep -c 'fresh-no-report')" "0"
check "watchman names the folder without findings.md" \
      "$("$FRAIM" status "$CL" 2>/dev/null | grep -c 'без findings.md')" "2"
check "plan does NOT touch the board" "$(printf '%s' "$PLAN" | grep -c 'open-card')" "0"

OUT=$("$FRAIM" clean --yes </dev/null 2>&1)
check "clean --yes ran" "$(printf '%s' "$OUT" | grep -c 'сделано:')" "1"
check "foundation brought up to standard" "$(grep -c '^## Known Pitfalls / Lessons$' "$CL/CONVENTIONS.md")" "1"
check "finished investigation archived" \
      "$(find "$CL/ai/archive" -maxdepth 1 -name '*investigate_solved-one' | wc -l | tr -d ' ')" "1"
check "abandoned investigation archived" \
      "$(find "$CL/ai/archive" -maxdepth 1 -name '*investigate_abandoned-one' | wc -l | tr -d ' ')" "1"
# The archive must tell the truth: not «done», but «abandoned, no outcome, cleanup never checked».
check "archive records that the investigation was abandoned" \
      "$(cat "$CL"/ai/archive/*investigate_abandoned-one/findings.md | grep -c '^## Abandoned$')" "1"
check "and that cleanup was never checked" \
      "$(cat "$CL"/ai/archive/*investigate_abandoned-one/findings.md | grep -c 'Cleanup was never checked')" "1"
check "old-format task became a card" "$(sed -n 's/^kind: //p' "$CL/ai/tasks/old-plan.md" 2>/dev/null)" "task"
check "intent carried over into the card" "$(grep -c '^Сделать Y.$' "$CL/ai/tasks/old-plan.md" 2>/dev/null)" "1"
check "old plan kept in the archive" "$([ -f "$CL/ai/archive/legacy-plans/old-plan/task.md" ] && echo yes || echo no)" "yes"
check "open card untouched" "$([ -f "$CL/ai/tasks/open-card.md" ] && echo yes || echo no)" "yes"
check "folder without findings.md archived" \
      "$(find "$CL/ai/archive" -maxdepth 1 -name '*investigate_no-report' | wc -l | tr -d ' ')" "1"
check "and got a report rather than going to the archive silently" \
      "$(cat "$CL"/ai/archive/*investigate_no-report/findings.md 2>/dev/null | grep -c '^## Abandoned$')" "1"
check "fresh folder without findings.md untouched" \
      "$([ -d "$CL/ai/investigations/fresh-no-report" ] && echo yes || echo no)" "yes"
check "clean had nothing to refuse" "$(printf '%s' "$OUT" | grep -c 'Осталось требующего тебя')" "0"

# A second pass must not find work where there is none left.
PLAN2=$("$FRAIM" clean </dev/null 2>&1)
check "repeated clean does not offer what is done" "$(printf '%s' "$PLAN2" | grep -c 'solved-one')" "0"
cd "$SANDBOX" || exit 1

# ------------------------------------------------- foundation standard and upgrade
printf '\nstandard conformance (shape) and fraim upgrade\n'

# An «old version» project: the foundation exists, but was set up before AGENTS.md/CLAUDE.md, before
# ai/fraim.conf and before the Known Pitfalls section. None of the previous checks fired
# on it — the watchman said «all clean» while fraim pitfall refused.
OLD="$SANDBOX/oldproj"
mkdir -p "$OLD/ai/tasks"
git -C "$OLD" init -q
git -C "$OLD" config user.email t@t; git -C "$OLD" config user.name t
printf '# ARCHITECTURE\nmap\n'    > "$OLD/ARCHITECTURE.md"
printf '# CONVENTIONS\nrules\n'   > "$OLD/CONVENTIONS.md"
printf '# DECISIONS\n'            > "$OLD/DECISIONS.md"
printf '# README\n'               > "$OLD/README.md"
printf 'check_shape = on\n'       > "$OLD/ai/fraim.conf"
git -C "$OLD" add -A >/dev/null 2>&1; git -C "$OLD" commit -qm base >/dev/null 2>&1

OUT=$("$FRAIM" status "$OLD" 2>/dev/null)
check "watchman sees lag behind the standard" "$(printf '%s' "$OUT" | grep -c 'отстал от стандарта')" "1"
check "AGENTS.md and CLAUDE.md named" \
      "$(printf '%s' "$OUT" | grep -c 'AGENTS.md')$(printf '%s' "$OUT" | grep -c 'CLAUDE.md')" "11"
check "missing section named" "$(printf '%s' "$OUT" | grep -c 'Known-Pitfalls')" "1"

cd "$OLD" || exit 1
"$FRAIM" pitfall "verb has nowhere to write" >/dev/null 2>&1
check "before upgrade the pitfall verb refuses" "$?" "2"

"$FRAIM" upgrade . >/dev/null 2>&1
check "upgrade succeeded" "$?" "0"
check "upgrade created AGENTS.md with the block" "$(grep -c 'fraim:begin' "$OLD/AGENTS.md")" "1"
check "upgrade created CLAUDE.md with the pointer" "$(grep -c 'AGENTS.md' "$OLD/CLAUDE.md")" "2"
check "upgrade appended the Known Pitfalls section" "$(grep -c '^## Known Pitfalls / Lessons$' "$OLD/CONVENTIONS.md")" "1"
check "old file contents untouched" "$(grep -c '^rules$' "$OLD/CONVENTIONS.md")" "1"
"$FRAIM" pitfall "now it lands" >/dev/null 2>&1
check "after upgrade the pitfall verb works" "$?" "0"
"$FRAIM" status "$OLD" >/dev/null 2>&1
check "after upgrade the standard check is silent" "$("$FRAIM" status "$OLD" 2>/dev/null | grep -c 'отстал от стандарта')" "0"
"$FRAIM" upgrade . >/dev/null 2>&1
check "upgrade is idempotent" "$("$FRAIM" status "$OLD" 2>/dev/null | grep -c 'отстал от стандарта')" "0"
# upgrade makes no judgement calls, it puts them on the board: a map without sections is an item of the migration task.
check "map without sections — a migration task" "$(grep -c 'ARCHITECTURE.md has no' "$OLD/ai/tasks/fraim-migration.md" 2>/dev/null)" "1"
check "repeated upgrade does not duplicate the item" "$(grep -c 'ARCHITECTURE.md has no' "$OLD/ai/tasks/fraim-migration.md" 2>/dev/null)" "1"
check "upgrade created the backlog" "$([ -d "$OLD/ai/backlog" ] && echo yes || echo no)" "yes"
check "upgrade keeps a setting the project made" "$(grep -c '^check_shape = on$' "$OLD/ai/fraim.conf")" "1"
check "upgrade lists the current settings as comments" "$(grep -c '^# check_parallel = on$' "$OLD/ai/fraim.conf")" "1"
printf '# check_blockers = on\n# mode = reactive\n' >> "$OLD/ai/fraim.conf"
"$FRAIM" upgrade . >/dev/null 2>&1
check "upgrade drops comments for removed keys" "$(grep -c 'check_blockers\|^# mode' "$OLD/ai/fraim.conf")" "0"
check "the settings refresh is a save point" "$(git -C "$OLD" status --porcelain -- ai/fraim.conf | grep -c .)" "0"
mkdir -p "$OLD/ai/tasks/empty-plan"; printf '# Task\n' > "$OLD/ai/tasks/empty-plan/task.md"
"$FRAIM" upgrade . >/dev/null 2>&1
check "unsorted task — a second item on the same card" \
      "$(grep -c '^- ' "$OLD/ai/tasks/fraim-migration.md")$(grep -c 'empty-plan' "$OLD/ai/tasks/fraim-migration.md")" "21"
check "items sit in «What and why», not after «Done when»" \
      "$(sed -n '/^## Done when/,$p' "$OLD/ai/tasks/fraim-migration.md" | grep -c '^- ')" "0"
check "old plan kept" "$([ -f "$OLD/ai/archive/legacy-plans/empty-plan/task.md" ] && echo yes || echo no)" "yes"
# Cards from before the English format: their headings are renamed in place, the body kept.
printf -- '---\nkind: task\ncreated: 2026-10-01\n---\n# Старая\n\n## Что и зачем\nтело\n\n## Готово, когда\nготово\n' > "$OLD/ai/tasks/ru-card.md"
"$FRAIM" upgrade . >/dev/null 2>&1
check "old card headings renamed" \
      "$(grep -c '^## What and why$' "$OLD/ai/tasks/ru-card.md")$(grep -c '^## Done when$' "$OLD/ai/tasks/ru-card.md")$(grep -c '^тело$' "$OLD/ai/tasks/ru-card.md")" "111"

# With no path, upgrade is a machine command: every registered project, plus the one the
# human stands in. A registry of its own, so the sandbox's other projects are not touched.
UPH="$SANDBOX/uphome"; mkdir -p "$UPH"
mkold() { # dir — a project laid down before AGENTS.md and the Known Pitfalls section
    mkdir -p "$1/ai/tasks"; git -C "$1" init -q
    git -C "$1" config user.email t@t; git -C "$1" config user.name t
    printf '# ARCHITECTURE\nmap\n' > "$1/ARCHITECTURE.md"; printf '# CONVENTIONS\nrules\n' > "$1/CONVENTIONS.md"
    printf '# DECISIONS\n' > "$1/DECISIONS.md"; printf '# README\n' > "$1/README.md"
    git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -qm base >/dev/null 2>&1
}
mkold "$SANDBOX/up a"; mkold "$SANDBOX/up-b"; mkold "$SANDBOX/up-here"
mkdir -p "$SANDBOX/up-plain"
printf '%s\n' "$SANDBOX/up a" "$SANDBOX/up-gone" "$SANDBOX/up-plain" "$SANDBOX/up-b" > "$UPH/projects"
cd "$SANDBOX/up-here" || exit 1
UPOUT=$(FRAIM_HOME="$UPH" "$FRAIM" upgrade </dev/null 2>&1)
check "sweep: exit 0 when nothing failed" "$?" "0"
check "sweep: every registered project upgraded, a path with a space too" \
      "$(grep -c '^## Known Pitfalls / Lessons$' "$SANDBOX/up a/CONVENTIONS.md" "$SANDBOX/up-b/CONVENTIONS.md" | grep -c ':1$')" "2"
check "sweep: the project the human stands in is upgraded" "$(grep -c 'fraim:begin' "$SANDBOX/up-here/AGENTS.md" 2>/dev/null)" "1"
check "sweep: and registered" "$(grep -cxF "$SANDBOX/up-here" "$UPH/projects")" "1"
check "sweep: a missing directory and a plain one are skipped, not failed" \
      "$(printf '%s' "$UPOUT" | grep -c 'доведено 3, пропущено 2, с ошибкой 0')" "1"
check "sweep: a folder not under the system is left alone" "$([ -e "$SANDBOX/up-plain/AGENTS.md" ] && echo yes || echo no)" "no"
: > "$UPH/projects"; cd "$SANDBOX" || exit 1
FRAIM_HOME="$UPH" "$FRAIM" upgrade </dev/null >/dev/null 2>&1
check "sweep: an empty registry outside a project — refused" "$?" "2"

# --- the queue and the foundation as data ------------------------------------
QP="$SANDBOX/queueproj"
mkdir -p "$QP"
git -C "$QP" init -q; git -C "$QP" config user.email t@t; git -C "$QP" config user.name t
cd "$QP" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
printf '# Project\n\n## What and why\nx\n\n## Done when\nx\n' | "$FRAIM" task-new proj-one --master >/dev/null 2>&1
printf '# Part\n\n## What and why\nx\n\n## Done when\nx\n' | "$FRAIM" task-new part-one --parent proj-one >/dev/null 2>&1
J=$("$FRAIM" status --json 2>/dev/null)
check "json: kind and parent of every card" \
      "$(printf '%s' "$J" | grep -c '"slug": "proj-one", "kind": "master", "parent": ""')$(printf '%s' "$J" | grep -c '"slug": "part-one", "kind": "task", "parent": "proj-one"')" "11"
check "counter counts cards on the board" \
      "$(printf '%s' "$J" | grep -c '2 открытые задачи на доске')" "1"
check "json: a stub is distinguishable from filled" \
      "$(printf '%s' "$J" | grep -c '"ARCHITECTURE.md": "stub"')" "1"
check "json: a missing file shows as missing" \
      "$(printf '%s' "$J" | grep -c '"STACK.md": "missing"')" "1"

# An empty state must not crash the watchman: grep -c on zero matches returns 1,
# and under set -e that silently killed the whole run.
EMPTY="$SANDBOX/emptyq"
mkdir -p "$EMPTY"; cd "$EMPTY" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
check "watchman does not die on an empty queue" "$("$FRAIM" status "$EMPTY" 2>/dev/null | grep -c 'скелет развёрнут')" "1"

cd "$PROJ2" || exit 1

# ---------------------------------------------------------------- publish
printf '\nfraim publish (off-machine copy)\n'

# Branches that ask the human are tested by calling the branch itself: the question is asked
# only on a terminal, and a pty cannot be set up in POSIX sh.
PUBLIB_CANCEL='. "'"$REPO"'/installer/lib/core.sh"; . "'"$REPO"'/installer/lib/config.sh"
    . "'"$REPO"'/installer/lib/registry.sh"; . "'"$REPO"'/installer/lib/context.sh"
    . "'"$REPO"'/installer/lib/scaffold.sh"; . "'"$REPO"'/installer/lib/lang.sh"; . "'"$REPO"'/installer/lib/verbs.sh"; . "'"$REPO"'/installer/lib/tasks.sh"; . "'"$REPO"'/installer/lib/foundation.sh"; . "'"$REPO"'/installer/lib/verbtable.sh"
    . "'"$REPO"'/installer/lib/ade.sh"; . "'"$REPO"'/installer/lib/watchman.sh"; . "'"$REPO"'/installer/lib/update.sh"; . "'"$REPO"'/installer/lib/publish.sh"'

# Everything here works without network and without gh: a local bare repository serves as the «host».
# This is not a simplification for the test — it is the same path --url takes, i.e. the floor
# any provider falls back to when its CLI is missing or misbehaves.
PUB="$SANDBOX/pub"
mkdir -p "$PUB"
cd "$PUB" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
printf 'print(1)\n' > app.py
git -C "$PUB" add app.py >/dev/null; git -C "$PUB" commit -qm "feat: app" >/dev/null

OUT=$("$FRAIM" publish --check 2>&1); RC=$?
check "check passes on a clean project" "$RC" "0"
check "check says there is no copy" "$(printf '%s' "$OUT" | grep -c 'Копии вне этой машины нет')" "1"
check "check lists what can publish" \
      "$(printf '%s' "$OUT" | grep -c 'Чем можно опубликовать')" "1"
check "missing CLI is explained, not just flagged" \
      "$(printf '%s' "$OUT" | grep -c 'gh auth login')" "1"

# Ratification. Under a pipe without --yes the command must print the plan and TOUCH nothing:
# this is the same contract as `fraim clean`, and it is checked by state, not by text.
git init -q --bare "$SANDBOX/pub-remote.git"
OUT=$("$FRAIM" publish --url "$SANDBOX/pub-remote.git" 2>&1)
check "plan without --yes sends nothing" "$(git -C "$PUB" remote | wc -l | tr -d ' ')" "0"
check "plan names what will be sent" "$(printf '%s' "$OUT" | grep -c 'что едет')" "1"

OUT=$("$FRAIM" publish --url "$SANDBOX/pub-remote.git" --yes 2>&1); RC=$?
check "publishing with --yes passes" "$RC" "0"
check "remote configured" "$(git -C "$PUB" remote get-url origin)" "$SANDBOX/pub-remote.git"
check "reconciliation with the host matched" "$(printf '%s' "$OUT" | grep -c 'на хосте лежит ровно то')" "1"
check "the host has the same point" \
      "$(git -C "$SANDBOX/pub-remote.git" rev-parse HEAD)" "$(git -C "$PUB" rev-parse HEAD)"

OUT=$("$FRAIM" publish 2>&1)
check "rerun does nothing" \
      "$(printf '%s' "$OUT" | grep -c 'совпадает с этой машиной')" "1"

printf 'print(2)\n' >> app.py
git -C "$PUB" commit -qam "fix: more" >/dev/null
"$FRAIM" publish --yes >/dev/null 2>&1
check "next point leaves with the same command" \
      "$(git -C "$SANDBOX/pub-remote.git" rev-parse HEAD)" "$(git -C "$PUB" rev-parse HEAD)"

# --- safety check ------------------------------------------------------------
# The key property: it looks at what WILL BE SENT, not at what lies in the folder.
# A file removed from the tree stays in the pack and leaves with the very first push.
PUBS="$SANDBOX/pubsec"
mkdir -p "$PUBS"
cd "$PUBS" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
printf 'DB_PASSWORD=hunter2\n' > .env
git -C "$PUBS" add -f .env >/dev/null; git -C "$PUBS" commit -qm "oops" >/dev/null
git -C "$PUBS" rm -q --cached .env >/dev/null; git -C "$PUBS" commit -qm "убрал" >/dev/null

OUT=$("$FRAIM" publish --check 2>&1); RC=$?
check "secret erased from the tree but alive in history — found" \
      "$(printf '%s' "$OUT" | grep -c '\.env')" "1"
check "finding in history fails the exit code" "$RC" "1"

OUT=$("$FRAIM" publish --url "$SANDBOX/pub-remote2.git" --yes 2>&1); RC=$?
check "gate stops publishing" "$RC" "2"
check "remote not configured on refusal" "$(git -C "$PUBS" remote | wc -l | tr -d ' ')" "0"
check "refusal names the override" "$(printf '%s' "$OUT" | grep -c 'находка ложная')" "1"
# The refusal hands over a ready task, not advice: «remove the file from history» is a request for
# expertise the user may not have.
check "refusal prints a task for the agent" \
      "$(printf '%s' "$OUT" | grep -c 'Отдай это агенту')" "1"
check "task is self-contained: it has the project path" \
      "$(printf '%s' "$OUT" | grep -c "Project: $PUBS")" "1"
check "task names what was found one by one" "$(printf '%s' "$OUT" | grep -c '  - \.env')" "1"
check "task sets limits for the agent" "$(printf '%s' "$OUT" | grep -c 'Limits:')" "1"
check "task does not advise rewriting history silently" \
      "$(printf '%s' "$OUT" | grep -c 'Do not run it without my yes')" "1"

git init -q --bare "$SANDBOX/pub-remote2.git"
OUT=$("$FRAIM" publish --url "$SANDBOX/pub-remote2.git" --yes --force 2>&1); RC=$?
check "--force passes and says what it does" "$RC" "0"
check "--force names the irreversibility" "$(printf '%s' "$OUT" | grep -c 'необратимо')" "1"

# --- a finding is resolved not on its own, but by who will read it ----------------------
# Its own fixture: the previous project already has a remote, while the question «who will read this»
# arises exactly before the copy exists.
PUBV="$SANDBOX/pubvis"
mkdir -p "$PUBV"
cd "$PUBV" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
printf 'API = "ghp_abcdefghijklmnopqrstuvwxyz0123456789"\n' > conf.py
git -C "$PUBV" add conf.py >/dev/null; git -C "$PUBV" commit -qm "feat: conf" >/dev/null

# The same answer for a public and a private repository is wrong both ways: for a
# public one «stop» is the only correct answer, for a private one it becomes a wall out of
# nowhere — the human knows only they see the copy, and rewriting history protects
# them from nothing. So private gets ratification, public stays a stop.
OUT=$("$FRAIM" publish --provider github --public --yes 2>&1); RC=$?
check "public repository: stop stays a stop" "$RC" "2"
check "stop explains it is about visibility" \
      "$(printf '%s' "$OUT" | grep -c 'Репозиторий публичный')" "1"
check "public is not offered «accept the risk»" \
      "$(printf '%s' "$OUT" | grep -c 'нет варианта')" "1"

# Under a pipe without a privacy assertion — also a stop, but with a way out, not a wall.
OUT=$("$FRAIM" publish --url "$SANDBOX/pub-remote3.git" --yes 2>&1); RC=$?
check "unknown visibility: do not assume for the human" "$RC" "2"
check "refusal names how to unblock" \
      "$(printf '%s' "$OUT" | grep -c 'publish --private')" "1"

# Private copy: the findings leave, but are named one by one and accepted explicitly.
git init -q --bare "$SANDBOX/pub-priv.git"
OUT=$("$FRAIM" publish --url "$SANDBOX/pub-priv.git" --private --yes 2>&1); RC=$?
OUTPRIV=$OUT
check "private copy: work does not stall" "$RC" "0"
check "risk acceptance is said out loud" "$(printf '%s' "$OUT" | grep -c 'принято')" "1"
check "says how privacy is known" \
      "$(printf '%s' "$OUT" | grep -c 'с твоих слов')" "1"
# The product has no right to promise «nothing to fear in a private repo»: a private repository
# is switched to public with one button, and the history goes along with it.
check "acceptance does not promise what it cannot guarantee" \
      "$(printf '%s' "$OUT" | grep -c 'станет публичным')" "1"
check "findings really were pushed" \
      "$(git -C "$SANDBOX/pub-priv.git" rev-parse HEAD)" "$(git -C "$PUBV" rev-parse HEAD)"

# The cleanup task is not tied to a refusal: having accepted the risk once, cleanup is ordered later.
OUT=$("$FRAIM" publish --brief 2>&1); RC=$?
check "--brief prints the task on demand" "$RC" "0"
check "--brief gives the same self-contained block" \
      "$(printf '%s' "$OUT" | grep -c 'Отдай это агенту')" "1"
OUT=$(cd "$PUB" && "$FRAIM" publish --brief 2>&1)
check "--brief on a clean project does not invent work" \
      "$(printf '%s' "$OUT" | grep -c 'нечего вычищать')" "1"

# «No» to the findings question means «I want it, but clean», not «changed my mind about publishing».
# Previously the human got a single word «cancelled» and was left exactly where they started.
# The question is asked only on a terminal, so the rail calls the refusal branch itself, and
# a separate check guards that the dispatcher still enters it.
CANC=$(cd "$PUBV" && sh -c "$PUBLIB_CANCEL"'
    publish_scan "$(pwd -P)"
    publish_cancel_findings "$(pwd -P)"' 2>&1)
check "declining the risk hands a task to the agent" \
      "$(printf '%s' "$CANC" | grep -c 'Отдай это агенту')" "1"
check "task names the findings one by one" \
      "$(printf '%s' "$CANC" | grep -c 'conf.py')" "1"
check "refusal does not end with the word «cancelled»" \
      "$(printf '%s' "$CANC" | grep -c 'публикуем после чистки')" "1"
check "says how to check the cleanup result" \
      "$(printf '%s' "$CANC" | grep -c 'проверь сам: fraim publish --check')" "1"
check "and that publishing will continue afterwards" \
      "$(printf '%s' "$CANC" | grep -c 'без находок')" "1"
# The task's limits are the same as for a system refusal: the agent cleans, but does not publish.
check "task still forbids publishing" \
      "$(printf '%s' "$CANC" | grep -c 'publish nothing and push nothing')" "1"

# The class, not the case: if the refusal branch is ever simplified back to say «отменено»,
# the task will vanish silently — on a terminal, where tests do not go.
CANCWIRED=$(awk '/read -r _ans \|\| _ans=/,/^        else$/' "$REPO/installer/bin/fraim" |
            grep -c 'publish_cancel_findings' || true)
check "dispatcher calls this branch, does not print «cancelled»" "$CANCWIRED" "1"

# And the question itself names what «no» means: the decision is read where it is made.
check "risk acceptance names «no» as a way out" \
      "$(printf '%s' "$OUTPRIV" | grep -c 'ответь «нет»')" "1"


# The key's value must not reach the output: it would go to the scrollback, the agent's session log
# and someone else's chat. The scanner prints the file and line, and stops there.
PUBT="$SANDBOX/pubtok"
mkdir -p "$PUBT"
cd "$PUBT" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
printf 'TOKEN = "ghp_abcdefghijklmnopqrstuvwxyz0123456789"\n' > conf.py
head -c 6000000 /dev/urandom > big.bin 2>/dev/null
mkdir -p node_modules/pkg; printf '1\n' > node_modules/pkg/index.js
git -C "$PUBT" add -A -f >/dev/null; git -C "$PUBT" commit -qm "feat: conf" >/dev/null
OUT=$("$FRAIM" publish --check 2>&1)
check "token in a file found by its shape" "$(printf '%s' "$OUT" | grep -c 'conf.py:1')" "1"
check "the key value itself is not printed" \
      "$(printf '%s' "$OUT" | grep -c 'ghp_abcdefghijklmnopqrstuvwxyz')" "0"
check "heavy file — a warning, not a refusal" "$(printf '%s' "$OUT" | grep -c 'МБ в истории')" "1"
check "dependencies in history collapsed into one directory" \
      "$(printf '%s' "$OUT" | grep -c 'node_modules/ ')" "1"

# --- desync with the host -----------------------------------------------------
# Local bookkeeping («pushed / not pushed») is THIS machine's memory of past
# pushes. It lies exactly where a mistake costs the most: the repository is created and empty,
# the branch on the host was deleted, history was put there from somewhere else. So publish
# asks the host, not its own refs — the three cases below check each of these forms.
PUBH="$SANDBOX/pubhost"
mkdir -p "$PUBH"
cd "$PUBH" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
printf 'print(1)\n' > app.py
git -C "$PUBH" add app.py >/dev/null; git -C "$PUBH" commit -qm "feat: app" >/dev/null

# 1. Created but empty: the address was set by hand, history never got there. From outside the copy
#    looks existing — this is the worst of the states, and staying silent about it is not allowed.
git init -q --bare "$SANDBOX/pub-host.git"
git -C "$PUBH" remote add origin "$SANDBOX/pub-host.git"
"$FRAIM" status "$PUBH" 2>/dev/null | grep -q 'ни разу ничего не уезжало'
check "watchman sees unfinished setup without network" "$?" "0"

OUT=$("$FRAIM" publish 2>&1)
check "publish names the empty repository on the host" \
      "$(printf '%s' "$OUT" | grep -c 'ПУСТ')" "1"
# The host state lives in the plan as one line and nowhere else: the same thing a second time
# on top is noise, and people learn to scroll past noise.
check "host state stated exactly once" \
      "$(printf '%s' "$OUT" | grep -c 'история туда не доехала')" "1"
"$FRAIM" publish --yes >/dev/null 2>&1
check "the same command finishes the job" \
      "$(git -C "$SANDBOX/pub-host.git" rev-parse HEAD)" "$(git -C "$PUBH" rev-parse HEAD)"

# 2. The branch on the host was deleted, but refs/remotes remain here. By this machine's records «everything
#    was pushed» — and that is exactly the lie the reconciliation exists for.
BR=$(git -C "$PUBH" rev-parse --abbrev-ref HEAD)
git -C "$SANDBOX/pub-host.git" update-ref -d "refs/heads/$BR"
check "local records still say «pushed»" \
      "$(git -C "$PUBH" rev-list --count HEAD --not --remotes)" "0"
OUT=$("$FRAIM" publish 2>&1)
check "publish does not trust its records over the host" \
      "$(printf '%s' "$OUT" | grep -c 'совпадает с этой машиной')" "0"
"$FRAIM" publish --yes >/dev/null 2>&1
check "copy restored" \
      "$(git -C "$SANDBOX/pub-host.git" rev-parse HEAD)" "$(git -C "$PUBH" rev-parse HEAD)"

# 3. Work appeared on the host that is not here. The only way to «reconcile with one
#    button» is to overwrite someone else's work, so the command must stop and hand over a task.
OTHER="$SANDBOX/pubother"
git clone -q "$SANDBOX/pub-host.git" "$OTHER"
git -C "$OTHER" config user.email t@t; git -C "$OTHER" config user.name t
printf 'from another machine\n' > "$OTHER/other.py"
git -C "$OTHER" add other.py >/dev/null; git -C "$OTHER" commit -qm "feat: other" >/dev/null
git -C "$OTHER" push -q origin HEAD >/dev/null 2>&1
printf 'print(2)\n' >> "$PUBH/app.py"
git -C "$PUBH" commit -qam "fix: local" >/dev/null

OUT=$("$FRAIM" publish --yes 2>&1); RC=$?
check "divergence stops the push" "$RC" "2"
check "nothing overwritten on the host" \
      "$(git -C "$SANDBOX/pub-host.git" log --oneline | grep -c 'feat: other')" "1"
check "divergence explained, not called an error" \
      "$(printf '%s' "$OUT" | grep -c 'работа, которой нет здесь')" "1"
check "divergence hands a task to the agent" \
      "$(printf '%s' "$OUT" | grep -c 'reconcile the divergence')" "1"
check "task forbids force-push" "$(printf '%s' "$OUT" | grep -c 'Never suggest a force-push')" "1"

# A provider that is absent answers with instructions and the floor — not with «can't». The project here
# is clean on purpose: otherwise it would never reach the provider, the safety gate would stop it.
PUBP="$SANDBOX/pubprov"
mkdir -p "$PUBP"
cd "$PUBP" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
OUT=$("$FRAIM" publish --provider github --yes 2>&1); RC=$?
if command -v gh >/dev/null 2>&1; then
    check "github without gh: skipped (gh installed)" "skip" "skip"
else
    check "github without gh refuses without pushing" "$(git -C "$PUBP" remote | wc -l | tr -d ' ')" "0"
    check "refusal shows how to install gh" \
          "$(printf '%s' "$OUT" | grep -cE 'cli.github.com|install gh')" "1"
    check "refusal shows the floor: create by hand and give the URL" \
          "$(printf '%s' "$OUT" | grep -c 'publish --url')" "1"
fi
OUT=$("$FRAIM" publish --provider нетакого 2>&1); RC=$?
check "unknown provider rejected" "$RC" "2"

cd "$SANDBOX" || exit 1

# ------------------------------------------------- transport: key versus login
# A finding from real use. The address was ssh, there was no ssh key on the machine, gh was authorized
# over https. Pushing failed with `Permission denied (publickey)`, the hint suggested
# `gh auth login` — a command that with the https protocol installs a credential helper and does NOT
# install an ssh key. The human ran it, nothing changed, the loop closed.
printf '\nfraim publish (transport)\n'

# The environment around the tests may itself rewrite GitHub ssh addresses into https with its own
# url.insteadOf — a proxy in a cloud session does this, for example. The rails below check
# OUR decision, not someone else's substitution, so for the duration of the block the external git config
# is turned off: otherwise `git remote add git@github.com:…` silently becomes an https address and
# there is nothing left to check.
GITCFG_SAVED=${GIT_CONFIG_COUNT:-}
GIT_CONFIG_COUNT=0; export GIT_CONFIG_COUNT

PUBLIB='. "'"$REPO"'/installer/lib/core.sh"; . "'"$REPO"'/installer/lib/config.sh"
        . "'"$REPO"'/installer/lib/registry.sh"; . "'"$REPO"'/installer/lib/context.sh"
        . "'"$REPO"'/installer/lib/scaffold.sh"; . "'"$REPO"'/installer/lib/lang.sh"; . "'"$REPO"'/installer/lib/verbs.sh"; . "'"$REPO"'/installer/lib/tasks.sh"; . "'"$REPO"'/installer/lib/foundation.sh"; . "'"$REPO"'/installer/lib/verbtable.sh"
        . "'"$REPO"'/installer/lib/ade.sh"; . "'"$REPO"'/installer/lib/watchman.sh"; . "'"$REPO"'/installer/lib/update.sh"; . "'"$REPO"'/installer/lib/publish.sh"'

CONV=$(sh -c "$PUBLIB"'
    for u in git@github.com:me/proj.git ssh://git@gitlab.com/g/p.git https://github.com/a/b.git; do
        printf "%s " "$(publish_ssh_to_https "$u" || printf -- -)"
    done')
check "ssh address converts to https without losing the host" "$CONV" \
      "https://github.com/me/proj.git https://gitlab.com/g/p.git - "

# A key refusal is the host's answer, not network silence: they are fixed by different hands, and
# only one of the two is fixed by us. The fake ssh gives exactly the same line as the real one.
FAKESSH="$SANDBOX/fake-ssh"
printf '#!/bin/sh\nprintf "git@github.com: Permission denied (publickey).\\n" >&2\nexit 255\n' > "$FAKESSH"
chmod +x "$FAKESSH"
PUBT="$SANDBOX/pubtrans"
mkdir -p "$PUBT"
cd "$PUBT" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
git -C "$PUBT" remote add origin git@github.com:modehustle/crypto_trade.git

HOSTST=$(GIT_SSH_COMMAND="$FAKESSH" sh -c "$PUBLIB"'
    publish_host_state "'"$PUBT"'" master; printf "%s\n" "$PUB_HOST"')
check "key refusal is denied, not unreachable" "$HOSTST" "denied"

# Without gh the transport is not switched and the remote is not touched: replacing someone's address where
# there is nowhere to get a login anyway means trading one dead end for another.
mkdir -p "$SANDBOX/nobin"
NOGH=$(PATH="$SANDBOX/nobin:/usr/bin:/bin" sh -c "$PUBLIB"'
    publish_transport_https "'"$PUBT"'" >/dev/null 2>&1 && printf yes || printf no')
check "without gh the transport is not swapped" "$NOGH" "no"
check "and the address stayed what the human gave" \
      "$(git -C "$PUBT" remote get-url origin)" "git@github.com:modehustle/crypto_trade.git"

# With an authorized gh and a login configured for https the address switches — same
# repository, different transport.
STUB="$SANDBOX/stubbin"
mkdir -p "$STUB"
cat > "$STUB/gh" <<'GHSTUB'
#!/bin/sh
case "$1 $2" in
    "auth status") exit 0 ;;
    "config get")  printf 'https
'; exit 0 ;;
    "auth setup-git") exit 0 ;;
esac
exit 1
GHSTUB
chmod +x "$STUB/gh"
git config --global credential."https://github.com".helper "!gh auth git-credential"
SWITCHED=$(PATH="$STUB:$PATH" sh -c "$PUBLIB"'
    publish_transport_https "'"$PUBT"'" >/dev/null 2>&1 && printf yes || printf no')
check "with gh and an https login the transport switches" "$SWITCHED" "yes"
check "address became https of the same repository" \
      "$(git -C "$PUBT" remote get-url origin)" "https://github.com/modehustle/crypto_trade.git"

# The hint must name an action that works. `gh auth login` does not install an ssh
# key — that line is no longer here and must not be.
HINT=$(sh -c "$PUBLIB"'
    publish_push_hint "git@github.com: Permission denied (publickey)." \
        "git@github.com:me/proj.git" 2>&1')
check "hint gives a ready https address" \
      "$(printf '%s' "$HINT" | grep -c 'publish --url https://github.com/me/proj.git')" "1"
check "hint gives a second way out too — a key on the host" \
      "$(printf '%s' "$HINT" | grep -c 'ssh-keygen')" "1"
# The string is searched for among CODE, not comments: in the comment next to the fix
# the old text is quoted on purpose — otherwise in half a year nobody will remember why the rail
# is here.
BADHINT=$(grep -vE '^[[:space:]]*#' "$REPO/installer/lib/publish.sh" | grep -cF 'это чинит' || true)
check "hint no longer treats ssh with gh auth login" "$BADHINT" "0"

# And the whole path end to end, exactly as the owner had it: ssh address, no key, gh authorized over
# https. The fake ssh refuses just like the real one; the «host» is a local bare
# repository substituted for the https address via url.insteadOf. The push must
# get through by itself, without a second attempt by the human.
PUBE="$SANDBOX/pube2e"
mkdir -p "$PUBE"
git init -q --bare "$SANDBOX/pube2e-host.git"
git config --global url."$SANDBOX/pube2e-host.git".insteadOf "https://github.com/me/e2e.git"
cd "$PUBE" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
git -C "$PUBE" remote add origin git@github.com:me/e2e.git
OUT=$(PATH="$STUB:$PATH" GIT_SSH_COMMAND="$FAKESSH" "$FRAIM" publish --yes 2>&1); RC=$?
check "key refusal does not stop publishing" "$RC" "0"
check "switch is announced, not done silently" \
      "$(printf '%s' "$OUT" | grep -c 'адрес переключён на https')" "1"
check "history reached the host" \
      "$(git -C "$SANDBOX/pube2e-host.git" log --oneline 2>/dev/null | wc -l | tr -d ' ')" "1"
check "and reconciliation with the host matched" \
      "$(printf '%s' "$OUT" | grep -c 'на хосте лежит ровно то, что здесь')" "1"
git config --global --unset url."$SANDBOX/pube2e-host.git".insteadOf

if [ -n "$GITCFG_SAVED" ]; then GIT_CONFIG_COUNT=$GITCFG_SAVED; else unset GIT_CONFIG_COUNT; fi
cd "$SANDBOX" || exit 1

# Rail: publish sends what is already saved, and saves nothing itself. Should
# `git add` appear in this module — the verb would start deciding what to take into history,
# which is exactly what no verb in the system does (B6).
ADDS=$(grep -vE '^[[:space:]]*#' "$REPO/installer/lib/publish.sh" |
       grep -cE 'git (-C [^ ]+ )?(add|commit)' || true)
check "publish commits nothing itself" "$ADDS" "0"

# The watchman names the command, not bare git: the user was promised that no procedure
# will ask them to run a git command.
check "watchman calls fraim publish, not git push" \
      "$(grep -c 'wm_add remote .*git push' "$REPO/installer/lib/watchman.sh" || true)" "0"

# ---------------------------------------------------------------- install.sh
printf '\ninstall.sh (update and branch switch)\n'

# The clone is made with --depth 1 --branch, which implies --single-branch: the refspec
# mentions only main. So the documented way to try an unmerged branch —
# FRAIM_BRANCH=… sh install.sh — fetched commits into FETCH_HEAD and failed on checkout
# «pathspec did not match» on every machine where fraim was already installed. The rail holds exactly
# this path: it is documented in README, so it must work.
IREPO="$SANDBOX/origin.git"
IWORK="$SANDBOX/iwork"
git init -q --bare "$IREPO"
git init -q "$IWORK"; git -C "$IWORK" config user.email t@t; git -C "$IWORK" config user.name t
mkdir -p "$IWORK/installer/bin"; printf '#!/bin/sh\necho main\n' > "$IWORK/installer/bin/fraim"
git -C "$IWORK" add -A >/dev/null; git -C "$IWORK" commit -qm base
git -C "$IWORK" branch -M main; git -C "$IWORK" push -q "$IREPO" main
git -C "$IWORK" checkout -q -b try/unmerged
printf '#!/bin/sh\necho unmerged\n' > "$IWORK/installer/bin/fraim"
git -C "$IWORK" commit -qam feature; git -C "$IWORK" push -q "$IREPO" try/unmerged

IHOME="$SANDBOX/ihome"
mkdir -p "$IHOME"
FRAIM_HOME="$IHOME" FRAIM_REPO="file://$IREPO" FRAIM_BRANCH=main FRAIM_BIN_DIR="$IHOME/bin" \
    sh "$REPO/installer/install.sh" >/dev/null 2>&1
check "install: first clone landed on main" "$(sh "$IHOME/src/installer/bin/fraim")" "main"

FRAIM_HOME="$IHOME" FRAIM_REPO="file://$IREPO" FRAIM_BRANCH=try/unmerged FRAIM_BIN_DIR="$IHOME/bin" \
    sh "$REPO/installer/install.sh" >/dev/null 2>&1
check "install: switch to an unmerged branch" "$(sh "$IHOME/src/installer/bin/fraim")" "unmerged"

FRAIM_HOME="$IHOME" FRAIM_REPO="file://$IREPO" FRAIM_BRANCH=main FRAIM_BIN_DIR="$IHOME/bin" \
    sh "$REPO/installer/install.sh" >/dev/null 2>&1
check "install: back to main" "$(sh "$IHOME/src/installer/bin/fraim")" "main"

cd "$PROJ2" || exit 1

# ---------------------------------------------------------------- registry
printf '\nfraim projects (registry)\n'

"$FRAIM" projects add "$PROJ" >/dev/null 2>&1
"$FRAIM" projects add "$PROJ" >/dev/null 2>&1
check "add is idempotent" "$("$FRAIM" projects 2>/dev/null | grep -cx "  $PROJ")" "1"
"$FRAIM" projects rm "$PROJ" >/dev/null 2>&1
check "rm removes the entry" "$("$FRAIM" projects 2>/dev/null | grep -cx "  $PROJ")" "0"

# ---------------------------------------------------------------- init
printf '\nfraim init\n'

mkdir -p "$HOME/.codex" "$HOME/.claude"     # pretend two harnesses are installed
# OpenCode is detected by ~/.config/opencode, never by the bare ~/.config every machine has.
mkdir -p "$HOME/.config"
# Antigravity is detected by ~/.gemini/config, not by ~/.gemini: the bare directory
# belongs to Gemini CLI, which is a different product sharing the same home.
mkdir -p "$HOME/.gemini"
# PATH is trimmed to system dirs: agy/orca-ide/pi/devin from the developer's machine must not
# affect which harnesses are detected in the sandbox — detection here is by directories.
SANDBOX_PATH="/usr/bin:/bin"
cd "$PROJ" || exit 1
env PATH="$SANDBOX_PATH" "$FRAIM" init >/dev/null 2>&1
check "bare ~/.gemini is not Antigravity" \
    "$([ -d "$HOME/.gemini/config/skills" ] && echo yes || echo no)" "no"
check "bare ~/.config is not OpenCode" \
    "$([ -d "$HOME/.config/opencode" ] && echo yes || echo no)" "no"
mkdir -p "$HOME/.gemini/config" "$HOME/.config/opencode"
env PATH="$SANDBOX_PATH" "$FRAIM" init >/dev/null 2>&1
check "init succeeded" "$?" "0"
check "Codex: 12 skills" "$(find "$HOME/.codex/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')" "12"
check "Claude Code: 12 skills" "$(find "$HOME/.claude/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')" "12"
check "Antigravity: 12 skills" "$(find "$HOME/.gemini/config/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')" "12"
check "OpenCode: 12 skills in skills/ (plural)" "$(find "$HOME/.config/opencode/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')" "12"
check "context block in ~/.config/opencode/AGENTS.md" "$(grep -c 'fraim:begin' "$HOME/.config/opencode/AGENTS.md" 2>/dev/null)" "1"
# OpenCode wants each skill's name to match its folder — a mismatch is a skill it skips.
_mis=0
for _sk in "$HOME/.config/opencode/skills"/*/SKILL.md; do
    [ "$(sed -n 's/^name: //p' "$_sk" | head -1)" = "$(basename "$(dirname "$_sk")")" ] || _mis=$((_mis + 1))
done
check "OpenCode: every skill name matches its folder" "$_mis" "0"
check "context block in ~/.codex/AGENTS.md" "$(grep -c 'fraim:begin' "$HOME/.codex/AGENTS.md" 2>/dev/null)" "1"
check "context block in ~/.gemini/AGENTS.md" "$(grep -c 'fraim:begin' "$HOME/.gemini/AGENTS.md" 2>/dev/null)" "1"
check "GEMINI.md is not ours — we do not write to it" \
    "$([ -f "$HOME/.gemini/GEMINI.md" ] && echo yes || echo no)" "no"
check "project registered" "$("$FRAIM" projects 2>/dev/null | grep -cx "  $PROJ")" "1"
check "Bash(fraim:*) permission configured" "$(grep -c 'Bash(fraim' "$HOME/.claude/settings.json" 2>/dev/null)" "1"

# Idempotence is the whole update story: init is also update.
H1=$(find "$HOME/.codex/skills" -type f | sort | xargs md5sum | md5sum)
A1=$(md5sum < "$HOME/.codex/AGENTS.md")
"$FRAIM" init >/dev/null 2>&1
H2=$(find "$HOME/.codex/skills" -type f | sort | xargs md5sum | md5sum)
A2=$(md5sum < "$HOME/.codex/AGENTS.md")
check "repeated init does not change skills" "$H1" "$H2"
check "repeated init does not duplicate the block" "$A1" "$A2"

# A skill we own that vanished upstream must be swept; the user's own must not.
mkdir -p "$HOME/.codex/skills/obsolete" "$HOME/.codex/skills/mine"
printf -- '---\nname: obsolete\ndescription: "x"\nmetadata:\n  source: fraim\n---\n' > "$HOME/.codex/skills/obsolete/SKILL.md"
printf -- '---\nname: mine\ndescription: "x"\n---\n' > "$HOME/.codex/skills/mine/SKILL.md"
"$FRAIM" init >/dev/null 2>&1
check "our obsolete skill removed" "$([ -d "$HOME/.codex/skills/obsolete" ] && echo yes || echo no)" "no"
check "foreign skill untouched" "$([ -d "$HOME/.codex/skills/mine" ] && echo yes || echo no)" "yes"

"$FRAIM" doctor >/dev/null 2>&1
check "doctor succeeded" "$?" "0"
"$FRAIM" show orient 2>/dev/null | head -1 | grep -q -- '---'
check "show prints a procedure" "$?" "0"

# ---------------------------------------------------------------- update
printf '\nfraim update (update)\n'

# A local bare repository serves as the «host»: there is no network here and there must not be.
UPHOST="$SANDBOX/uphost.git"
UPSRC="$SANDBOX/upsrc"
git init -q --bare "$UPHOST"
git init -q "$SANDBOX/upseed"
git -C "$SANDBOX/upseed" config user.email t@t; git -C "$SANDBOX/upseed" config user.name t
mkdir -p "$SANDBOX/upseed/procedures" "$SANDBOX/upseed/installer"
printf 'x\n' > "$SANDBOX/upseed/procedures/orient.md"
printf '9.9.9\n' > "$SANDBOX/upseed/installer/VERSION"
git -C "$SANDBOX/upseed" add -A >/dev/null 2>&1
git -C "$SANDBOX/upseed" commit -qm init >/dev/null 2>&1
git -C "$SANDBOX/upseed" branch -M main >/dev/null 2>&1
git -C "$SANDBOX/upseed" push -q "$UPHOST" main >/dev/null 2>&1
# `git init --bare` sets HEAD to master; without this the clone arrives without a working copy
# and without HEAD — and then we would be testing something other than what we think.
git -C "$UPHOST" symbolic-ref HEAD refs/heads/main
git clone -q "$UPHOST" "$UPSRC" >/dev/null 2>&1

UPLIB='. "'"$REPO"'/installer/lib/core.sh"; . "'"$REPO"'/installer/lib/config.sh"
    . "'"$REPO"'/installer/lib/update.sh"; . "'"$REPO"'/installer/lib/ade.sh"; . "'"$REPO"'/installer/lib/watchman.sh"'

# The check goes to the network and writes the verdict to the cache.
sh -c "FRAIM_ROOT='$UPSRC' $UPLIB"'; update_probe' >/dev/null 2>&1
check "check succeeded → state in the cache" "$(awk '{print $4}' "$FRAIM_HOME/update-check")" "current"

printf 'more\n' >> "$SANDBOX/upseed/procedures/orient.md"
git -C "$SANDBOX/upseed" commit -aqm second >/dev/null 2>&1
git -C "$SANDBOX/upseed" push -q "$UPHOST" main >/dev/null 2>&1
sh -c "FRAIM_ROOT='$UPSRC' $UPLIB"'; update_probe' >/dev/null 2>&1
check "host moved ahead → behind" "$(awk '{print $4}' "$FRAIM_HOME/update-check")" "behind"
sh -c "FRAIM_ROOT='$UPSRC' $UPLIB"'; update_line' | grep -q 'fraim update'
check "the line names the command that fixes it" "$?" "0"

# A copy ahead of the host is not lag. For someone who edits the system locally the sha
# constantly differs from the host's, and telling them to update would be lying.
git -C "$UPSRC" config user.email t@t; git -C "$UPSRC" config user.name t
git -C "$UPSRC" pull -q origin main >/dev/null 2>&1
printf 'mine\n' >> "$UPSRC/procedures/orient.md"
git -C "$UPSRC" commit -aqm "своя правка" >/dev/null 2>&1
sh -c "FRAIM_ROOT='$UPSRC' $UPLIB"'; update_probe' >/dev/null 2>&1
check "local copy ahead → ahead, not behind" "$(awk '{print $4}' "$FRAIM_HOME/update-check")" "ahead"
UPF=$(sh -c "$UPLIB"'; WM_FINDINGS=; wm_check_update; printf "%s" "$WM_FINDINGS"')
check "and the watchman is silent about it" "${UPF:-empty}" "empty"
git -C "$UPSRC" reset -q --hard origin/main >/dev/null 2>&1

# Update edits `~/.fraim/src`, and only that. Running from a dev copy must say
# so out loud, not silently update someone else's directory.
sh -c "FRAIM_ROOT='$UPSRC' $UPLIB"'; update_apply' >/dev/null 2>&1
check "running not from ~/.fraim/src refuses to update" "$?" "1"
sh -c "FRAIM_ROOT='$UPSRC' $UPLIB"'; update_apply' 2>&1 | grep -q "$FRAIM_HOME/src"
check "and names the directory being updated" "$?" "0"

# An unreachable host is «unknown», not «all good»: network silence must not
# look like health (D1).
git -C "$UPSRC" remote set-url origin "$SANDBOX/нет-такого.git"
sh -c "FRAIM_ROOT='$UPSRC' $UPLIB"'; update_probe' >/dev/null 2>&1
check "host did not answer → unknown, not current" "$(awk '{print $4}' "$FRAIM_HOME/update-check")" "unknown"
git -C "$UPSRC" remote set-url origin "$UPHOST"

# The watchman reads the CACHE and does not go to the network: that is its contract (SCHEDULING.md, layer 1).
NETCALL=$(sed -n '/^wm_check_update() {/,/^}/p' "$REPO/installer/lib/watchman.sh" | grep -c 'git \|curl\|ls-remote' || true)
check "watchman does not go to the network for updates" "$NETCALL" "0"

printf '%s %s %s behind\n' "$(date +%s)" aaaaaaa bbbbbbb > "$FRAIM_HOME/update-check"
UPF=$(sh -c "$UPLIB"'; WM_FINDINGS=; wm_check_update; printf "%s" "$WM_FINDINGS"')
printf '%s' "$UPF" | grep -q '^system-update	info'
check "outdated version is a finding, and it is info" "$?" "0"
printf '%s %s %s current\n' "$(date +%s)" aaaaaaa aaaaaaa > "$FRAIM_HOME/update-check"
UPF=$(sh -c "$UPLIB"'; WM_FINDINGS=; wm_check_update; printf "%s" "$WM_FINDINGS"')
check "fresh version — silence" "${UPF:-empty}" "empty"

# The finding is a machine one, not a project one: it cannot spoil the project verdict.
printf '%s %s %s behind\n' "$(date +%s)" aaaaaaa bbbbbbb > "$FRAIM_HOME/update-check"
"$FRAIM" status "$SANDBOX/proj" >/dev/null 2>&1
UPRC=$?
"$FRAIM" status "$SANDBOX/proj" --json 2>/dev/null | grep -q '"id": "system-update"'
check "update visible in the project verdict" "$?" "0"
check "and does not raise its severity" "$UPRC" "$(printf '%s %s %s current\n' "$(date +%s)" a a > "$FRAIM_HOME/update-check"; "$FRAIM" status "$SANDBOX/proj" >/dev/null 2>&1; echo $?)"

# Can be turned off, like any watchman check.
printf '%s %s %s behind\n' "$(date +%s)" aaaaaaa bbbbbbb > "$FRAIM_HOME/update-check"
"$FRAIM" config set --machine updates off >/dev/null 2>&1
"$FRAIM" status "$SANDBOX/proj" --json 2>/dev/null | grep -q '"id": "system-update"'
check "updates off — no finding" "$?" "1"
"$FRAIM" config unset --machine updates >/dev/null 2>&1

# The cache goes stale by a setting, not by taste.
printf '%s %s %s current\n' "$(( $(date +%s) - 100 ))" a a > "$FRAIM_HOME/update-check"
sh -c "$UPLIB"'; update_cache_stale'
check "fresh cache not stale" "$?" "1"
printf '%s %s %s current\n' "$(( $(date +%s) - 200000 ))" a a > "$FRAIM_HOME/update-check"
sh -c "$UPLIB"'; update_cache_stale'
check "cache older than update_check_days is stale" "$?" "0"

# A copy laid out by hand is not subject to update — and says so rather than staying silent.
mkdir -p "$SANDBOX/handmade/procedures"
sh -c "FRAIM_ROOT='$SANDBOX/handmade' $UPLIB"'; update_src_is_clone'
check "a non-git clone is not an update source" "$?" "1"

rm -f "$FRAIM_HOME/update-check"

# ---------------------------------------------------------------- fleet
printf '\nfleet: checkouts and execution environment\n'

# A project with two checkouts: one card on the board in the main one, two in the sibling. Before this
# module the watchman did not see the second checkout at all.
FLEET="$SANDBOX/fleetproj"
mkdir -p "$FLEET/ai/tasks"
git -C "$FLEET" init -q
git -C "$FLEET" config user.email t@t; git -C "$FLEET" config user.name t
printf -- '---\nkind: task\ncreated: 2026-01-01\n---\n# A\n' > "$FLEET/ai/tasks/add-auth.md"
printf '# arch\n' > "$FLEET/ARCHITECTURE.md"
git -C "$FLEET" add -A >/dev/null 2>&1; git -C "$FLEET" commit -qm init >/dev/null 2>&1
git -C "$FLEET" worktree add -q "$SANDBOX/wt-rate-limit" -b rate-limit >/dev/null 2>&1
printf -- '---\nkind: task\ncreated: 2026-01-01\n---\n# R\n' > "$SANDBOX/wt-rate-limit/ai/tasks/rate-limit.md"

FJ=$("$FRAIM" status "$FLEET" --json 2>/dev/null || true)
printf '%s' "$FJ" | grep -q '"id": "worktree"'
check "parallel checkout visible in the verdict" "$?" "0"

# The checkout registry is kept by git, not by the environment: the answer is the same when there is no environment on the machine at all.
# PATH is trimmed to system dirs: the developer's machine may have a real orca-ide,
# and an inherited PATH would slip it into the «no environment» check.
FLJ=$(env PATH="/usr/bin:/bin" "$FRAIM" fleet "$FLEET" --json 2>/dev/null || true)
check "fleet lists both checkouts" "$(printf '%s' "$FLJ" | grep -c '"path"')" "2"
printf '%s' "$FLJ" | grep -q '"path": ".*wt-rate-limit", "current": false, "open_tasks": 2'
check "and counts each one's board" "$?" "0"
check "without an environment its section is empty" "$(printf '%s' "$FLJ" | grep -c '"key": "orca"')" "0"

# --- execution environment ---------------------------------------------------
# A stub instead of Orca: we do not have it and CI never will, and we depend not on the installed
# program but on the SHAPE of its answer. If the contract breaks, the test fails, not the user.
ADEBIN="$SANDBOX/adebin"; mkdir -p "$ADEBIN"
cat > "$ADEBIN/orca-ide" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "status --json")     [ -n "${STUB_DEAD:-}" ] && exit 1; printf '{"running":true}\n' ;;
  "automations list")  printf '[{"name":"n","prompt":"%s","repo":"%s"}]\n' "${STUB_PROMPT:-разбери очередь}" "$STUB_REPO" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$ADEBIN/orca-ide"

ADEENV="PATH=$ADEBIN:$PATH STUB_REPO=$FLEET"
AJ=$(env PATH="$ADEBIN:$PATH" STUB_REPO="$FLEET" "$FRAIM" status "$FLEET" --json 2>/dev/null || true)
printf '%s' "$AJ" | grep -q '"id": "ade-automation"'
check "free-form scheduled prompt is a finding" "$?" "0"
printf '%s' "$AJ" | grep -q '"id": "ade-automation", "severity": "info"'
check "and it is info: a foreign environment, we do not forbid it" "$?" "0"

# A scheduled watchman is layer 2 of SCHEDULING.md, not a finding.
AJ2=$(env PATH="$ADEBIN:$PATH" STUB_REPO="$FLEET" STUB_PROMPT="fraim status" \
        "$FRAIM" status "$FLEET" --json 2>/dev/null || true)
check "scheduled watchman does not become a finding" "$(printf '%s' "$AJ2" | grep -c 'ade-automation')" "0"

# The runtime does not answer — silence: whether it is running or not is the human's call (C1).
AJ3=$(env PATH="$ADEBIN:$PATH" STUB_REPO="$FLEET" STUB_DEAD=1 \
        "$FRAIM" status "$FLEET" --json 2>/dev/null || true)
check "closed runtime produces no findings" "$(printf '%s' "$AJ3" | grep -c 'ade-automation')" "0"
FLJ2=$(env PATH="$ADEBIN:$PATH" STUB_REPO="$FLEET" STUB_DEAD=1 "$FRAIM" fleet "$FLEET" --json 2>/dev/null || true)
printf '%s' "$FLJ2" | grep -q '"alive": false'
check "but fleet honestly says it does not answer" "$?" "0"

# Name trap: on Linux a bare `orca` is the GNOME screen reader, and
# launching it turns on speech synthesis on the human's machine. We check not «we picked another name»,
# but «we did not call it»: a decoy orca leaves a trace that must not be there.
cat > "$ADEBIN/orca" <<STUB
#!/bin/sh
printf 'spoke\n' > "$SANDBOX/screen-reader-ran"
STUB
chmod +x "$ADEBIN/orca"
rm -f "$SANDBOX/screen-reader-ran"
env PATH="$ADEBIN:$PATH" STUB_REPO="$FLEET" "$FRAIM" fleet "$FLEET" >/dev/null 2>&1 || true
check "bare orca on Linux is not launched" "$([ -f "$SANDBOX/screen-reader-ran" ] && echo ran || echo silent)" "silent"

# And the liveness check picks the safe name, not the first one that comes along.
rm -f "$ADEBIN/orca-ide"
# PATH is trimmed the same as above: a real orca-ide from the developer's machine does not count.
env PATH="$ADEBIN:/usr/bin:/bin" "$FRAIM" fleet "$FLEET" --json 2>/dev/null | grep -q '"key": "orca"'
check "without orca-ide the environment on Linux is not considered found" "$?" "1"
check "and the decoy orca is still silent" "$([ -f "$SANDBOX/screen-reader-ran" ] && echo ran || echo silent)" "silent"
rm -f "$ADEBIN/orca"

# Both checks can be turned off, like any watchman check.
"$FRAIM" config set --machine check_parallel off >/dev/null 2>&1
"$FRAIM" status "$FLEET" --json 2>/dev/null | grep -q '"id": "worktree'
check "check_parallel off — no checkout findings" "$?" "1"
env PATH="$ADEBIN:$PATH" STUB_REPO="$FLEET" "$FRAIM" status "$FLEET" --json 2>/dev/null | grep -q 'ade-automation'
check "check_parallel off — no environment findings" "$?" "1"
"$FRAIM" config unset --machine check_parallel >/dev/null 2>&1

# The watchman's contract: no network, no model. We ask the local runtime and read git.
NETADE=$(grep -c 'curl\|wget\|https\?://' "$REPO/installer/lib/ade.sh" || true)
check "environment module does not go to the network" "$NETADE" "0"

# Rail: a library put in lib/ and not sourced in bin/fraim breaks not right away
# and not there. That already happened with ade.sh — the menu test failed, not the one that added it.
UNWIRED=""
for _l in "$REPO"/installer/lib/*.sh; do
    _n=$(basename "$_l")
    grep -q "_libdir/$_n" "$REPO/installer/bin/fraim" || UNWIRED="$UNWIRED $_n"
done
check "every library is sourced in the dispatcher" "${UNWIRED:-clean}" "clean"

# ------------------------------------------------- fleet worker launch
printf '\nfleet: launch lifecycle with confirmed readiness\n'

# An Orca stub with a call log: each test reads the call LOG, not human
# output — the shape of the contract is checked (which subcommands, with which flags), not the text.
# Behaviour is switched with STUB_* variables: that way one section covers the happy
# path, the readiness timeout, and a failure at every stage.
FLHOME="$SANDBOX/fraim-home"; mkdir -p "$FLHOME"; export FLHOME
FLPROJ="$SANDBOX/flproj"; mkdir -p "$FLPROJ"; export FLPROJ
git -C "$FLPROJ" init -q; git -C "$FLPROJ" config user.email t@t; git -C "$FLPROJ" config user.name t
printf '# arch\n' > "$FLPROJ/ARCHITECTURE.md"
git -C "$FLPROJ" add -A >/dev/null 2>&1; git -C "$FLPROJ" commit -qm init >/dev/null 2>&1

cat > "$ADEBIN/orca-ide" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "${STUB_LOG:?}"
case "$1 $2" in
  "worktree rm")
       printf '{"ok":true}\n' ;;
  "status --json")
       printf '{"running":true}\n' ;;
  "worktree"*)
       [ -n "${STUB_WC_FAIL:-}" ] && { printf '{"ok":false}\n'; exit 1; }
       printf '{"ok":true,"worktree":{"path":"%s","createdAt":%s}}\n' \
           "${STUB_WT:-/tmp/stub-wt}" "${STUB_WT_CREATED_AT:-$(($(date +%s) * 1000))}" ;;
  "terminal create")
       [ -n "${STUB_TC_FAIL:-}" ] && { printf '{"ok":false}\n'; exit 1; }
       printf '{"ok":true,"terminal":{"handle":"term_aabf0418-1234abcd"}}\n' ;;
  "terminal wait")
       [ -n "${STUB_WAIT_FAIL:-}" ] && exit 1
       printf '{"ok":true,"state":"tui-idle"}\n' ;;
  "terminal read")
       printf '{"ok":true,"result":{"terminal":{"handle":"term_x","tail":["%s"]}}}\n' \
           "${STUB_TAIL:-Devin CLI v3000.5.20 · Pro}" ;;
  "terminal list")
       printf '{"ok":true,"result":{"terminals":[{"handle":"%s"}]}}\n' "${STUB_LIST_TERM:-term_aabf0418-1234abcd}" ;;
  "orchestration worker-start")
       [ -n "${STUB_WS_FAIL:-}" ] && { printf '{"ok":false,"stage":"dispatch_input"}\n'; exit 1; }
       printf '{"ok":true,"dispatchId":"ctx_1234abcd5678"}\n' ;;
  "orchestration dispatch-show")
       printf '{"ok":true,"dispatchId":"ctx_1234abcd5678"}\n' ;;
  "orchestration worker-release"|"terminal stop"|"worktree rm")
       printf '{"ok":true}\n' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$ADEBIN/orca-ide"

FLLIB='. "'"$REPO"'/installer/lib/core.sh"; . "'"$REPO"'/installer/lib/config.sh"
    . "'"$REPO"'/installer/lib/ade.sh"; . "'"$REPO"'/installer/lib/fleet.sh"'

# 1. Launch command: the built-in devin template substitutes the model; an unknown agent
# has no command — we do not invent one; launchcmd_<agent> from config decides everything.
DLC=$(FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" sh -c "$FLLIB"'; fleet_launch_command devin glm-5-2')
check "devin: built-in launch command with model" "$DLC" "devin --permission-mode bypass --model glm-5-2"
DLC=$(FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" sh -c "$FLLIB"'; fleet_launch_command no-such glm-5-2; printf rc=%s "$?"' 2>/dev/null)
check "we do not invent a command for an unknown agent" "$DLC" "rc=1"
DLC=$(FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" sh -c "$FLLIB"'; fleet_launch_command opencode zai/glm-5.3-flash')
check "opencode: built-in launch command with provider/model" "$DLC" "opencode --model zai/glm-5.3-flash"
DLC=$(FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" sh -c "$FLLIB"'; fleet_launch_command opencode ""')
check "opencode: no model — the bare agent" "$DLC" "opencode"
printf 'launchcmd_grok = grok --model %%s --yolo\n' > "$FLPROJ/ai/fraim.conf" 2>/dev/null || {
    mkdir -p "$FLPROJ/ai"; printf 'launchcmd_grok = grok --model %%s --yolo\n' > "$FLPROJ/ai/fraim.conf"; }
DLC=$(FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" sh -c "$FLLIB"'; fleet_launch_command grok glm-9 "$FLPROJ"')
check "launchcmd_<agent> from config substitutes the model" "$DLC" "grok --model glm-9 --yolo"
: > "$FLPROJ/ai/fraim.conf"

# 2. Full devin lifecycle with a model: worktree → terminal with the model in argv →
# tui-idle → worker-start --terminal, and not a single --model in orchestration.
STUB_LOG="$SANDBOX/fleet-calls.log"; STUB_WT="$SANDBOX/stub-wt"; : > "$STUB_LOG"
FLD=$(STUB_LOG="$STUB_LOG" STUB_WT="$STUB_WT" FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" \
      sh -c "$FLLIB"'; fleet_worker_start task_1a05eb1321c1 devin glm-5-2 high b1-t1 "$FLPROJ" main' 2>/dev/null)
check "devin: worker up, ctx_… id returned" "$FLD" "ctx_1234abcd5678"
grep -q 'worktree create' "$STUB_LOG" && grep -q 'terminal create' "$STUB_LOG" && \
  grep -q 'terminal wait' "$STUB_LOG" && grep -q 'worker-start' "$STUB_LOG"
check "devin: sequence create → terminal → wait → worker-start" "$?" "0"
grep -q -- '--model glm-5-2' "$STUB_LOG" && grep -q 'devin --permission-mode bypass --model glm-5-2' "$STUB_LOG"
check "devin: model went into the terminal launch command" "$?" "0"
grep 'worker-start' "$STUB_LOG" | grep -q -- '--model'
check "devin: orchestration worker-start without --model" "$?" "1"
grep 'worker-start' "$STUB_LOG" | grep -q -- '--terminal term_aabf0418'
check "devin: dispatch bound to the ready terminal" "$?" "0"

# 3. An agent that accepts the model natively takes the old path — and without extra steps.
: > "$STUB_LOG"
FLD=$(STUB_LOG="$STUB_LOG" STUB_WT="$STUB_WT" FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" \
      sh -c "$FLLIB"'; fleet_worker_start task_1a05eb1321c1 claude opus high b1-t2 "$PWD" main' 2>/dev/null)
check "claude: worker up natively" "$FLD" "ctx_1234abcd5678"
grep -q 'worktree create\|terminal create\|terminal wait' "$STUB_LOG"
check "claude: no explicit lifecycle — Orca creates the checkout itself" "$?" "1"
grep 'worker-start' "$STUB_LOG" | grep -q -- '--model opus --effort high'
check "claude: model and effort passed to Orca" "$?" "0"

# 4. Readiness timeout: no task, no Dispatch, resources cleaned up, the culprit named.
: > "$STUB_LOG"
STUB_WAIT_FAIL=1 STUB_LOG="$STUB_LOG" STUB_WT="$STUB_WT" FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" \
    sh -c "$FLLIB"'; fleet_worker_start task_1a05eb1321c1 devin glm-5-2 high b1-t3 "$PWD" main' >/dev/null 2>"$SANDBOX/wait-err"
check "tui-idle timeout fails the launch" "$?" "1"
grep -q 'tui-idle' "$SANDBOX/wait-err"
check "error names the readiness state" "$?" "0"
grep -c 'worker-start' "$STUB_LOG" | grep -q '^0$'
check "no Dispatch created after the timeout" "$?" "0"
grep -q 'terminal stop' "$STUB_LOG" && grep -q 'worktree rm' "$STUB_LOG"
check "and partial resources cleaned up" "$?" "0"

# 5. Failure before Dispatch is created: there is nothing to call worker-release on.
: > "$STUB_LOG"
STUB_TC_FAIL=1 STUB_LOG="$STUB_LOG" STUB_WT="$STUB_WT" FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" \
    sh -c "$FLLIB"'; fleet_worker_start task_x devin glm-5-2 high b1-t4 "$PWD" main' >/dev/null 2>&1
check "terminal create failure fails the launch" "$?" "1"
grep -q 'worker-release' "$STUB_LOG"
check "without Dispatch worker-release is not called" "$?" "1"
grep -q 'terminal stop' "$STUB_LOG" && grep -q 'worktree rm' "$STUB_LOG"
check "terminal and worktree cleaned up" "$?" "0"

# 6. Failure after Dispatch is created: release first, then the terminal, then the worktree.
: > "$STUB_LOG"
STUB_WS_FAIL=1 STUB_LOG="$STUB_LOG" STUB_WT="$STUB_WT" FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" \
    sh -c "$FLLIB"'; fleet_worker_start task_x devin glm-5-2 high b1-t5 "$PWD" main' >/dev/null 2>&1
check "Dispatch binding failure fails the launch" "$?" "1"
grep -q 'worker-release' "$STUB_LOG"
check "created Dispatch released" "$?" "0"
grep -q 'terminal stop' "$STUB_LOG" && grep -q 'worktree rm' "$STUB_LOG"
check "terminal and worktree cleaned up" "$?" "0"

# 7. Retry: each attempt creates a fresh checkout and does not reuse
# a dead terminal — no duplicate active workers appear.
: > "$STUB_LOG"
FLD1=$(STUB_LOG="$STUB_LOG" STUB_WT="$STUB_WT" FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" \
       sh -c "$FLLIB"'; fleet_worker_start task_r devin glm-5-2 high b1-t5 "$PWD" main' 2>/dev/null)
FLD2=$(STUB_LOG="$STUB_LOG" STUB_WT="$STUB_WT" FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" \
       sh -c "$FLLIB"'; fleet_worker_start task_r devin glm-5-2 high b1-t5 "$PWD" main' 2>/dev/null)
check "launch retry returns a worker again" "$(printf '%s' "$FLD2" | grep -c ctx_)" "1"
check "and creates exactly one new checkout per attempt" \
      "$(grep -c 'worktree create' "$STUB_LOG")" "2"

# 8. The readiness timeout is read from config, not hardcoded.
FLRT=$(FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" sh -c "$FLLIB"'; fleet_ready_timeout_ms')
check "readiness timeout defaults to 120000" "$FLRT" "120000"
printf 'fleet_ready_timeout_ms = 5000\n' >> "$FLPROJ/ai/fraim.conf"
FLRT=$(FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" sh -c "$FLLIB"'; fleet_ready_timeout_ms "$FLPROJ"')
check "and is overridden from the project" "$FLRT" "5000"
printf 'fleet_ready_timeout = 7\n' >> "$FLPROJ/ai/fraim.conf"
FLRT=$(FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" sh -c "$FLLIB"'; fleet_ready_timeout_ms "$FLPROJ"')
check "the new key in seconds wins over the retired one in ms" "$FLRT" "7000"
rm -f "$FLPROJ/ai/fraim.conf"

# 9. Capabilities cache and report: no-launch-model no longer means «model lost».
FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" sh -c "$FLLIB"'; fleet_caps_note devin no-launch-model' >/dev/null 2>&1
: > "$STUB_LOG"
STUB_LOG="$STUB_LOG" STUB_WT="$STUB_WT" FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" \
    sh -c "$FLLIB"'; fleet_worker_start task_c devin glm-5-2 high b1-t6 "$PWD" main' >/dev/null 2>&1
grep -q -- '--model glm-5-2' "$STUB_LOG"
check "known refusal does not lose the model: it is in the launch command" "$?" "0"

# 10. Under set -eu — as in the real dispatcher: an uninitialized variable in
# the launch path kills the build run, not one worker.
: > "$STUB_LOG"
FLD=$(STUB_LOG="$STUB_LOG" STUB_WT="$STUB_WT" FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" \
      sh -eu -c "$FLLIB"'; fleet_worker_start task_e devin glm-5-2 high b1-t7 "$PWD" main' 2>/dev/null)
check "launch survives set -eu (no unset variables)" "$FLD" "ctx_1234abcd5678"

# 11. A reused checkout (left over from a previous attempt) is not deleted by cleanup.
: > "$STUB_LOG"
STUB_WT_CREATED_AT=$(( $(date +%s) * 1000 - 3600000 )) STUB_WS_FAIL=1 \
    STUB_LOG="$STUB_LOG" STUB_WT="$STUB_WT" FRAIM_HOME="$FLHOME" PATH="$ADEBIN:/usr:/bin" \
    sh -c "$FLLIB"'; fleet_worker_start task_x devin glm-5-2 high b1-t8 "$PWD" main' >/dev/null 2>&1
grep -q 'worktree rm' "$STUB_LOG"
check "foreign (reused) worktree not deleted" "$?" "1"
grep -q 'terminal stop' "$STUB_LOG"
check "but its terminal is stopped" "$?" "0"
rm -f "$ADEBIN/orca-ide"

# ------------------------------------------------- model discovery for roles
printf '\nroles: model discovery\n'

# Parsers are checked against saved fixtures — real output of the sources —
# without installed agents (the parser is separate from the call and takes text on stdin).
# Each call is its own sh -c, so sections do not depend on order or a neighbour's failure.
roles_parse_out() {
    sh -c '
        . "'"$REPO"'/installer/lib/roles.sh"
        "$@" <<EOF2
'"$2"'
EOF2
' sh "$1" 2>&1
}

check "devin parser: ids only, no headers or aliases" \
      "$(roles_parse_out roles_parse_devin_models 'Claude Opus 5 (claude-opus-5)
  aliases: opus
  claude-opus-5-medium                   Claude Opus 5 Medium  [1M context, $5]
  claude-opus-5-high                     Claude Opus 5 High  [1M context, $5]')" \
      "claude-opus-5-high
claude-opus-5-medium"

check "cursor-agent parser: id up to the dash, no header" \
      "$(roles_parse_out roles_parse_cursor_models 'Available models

auto - Auto (current, default)
gpt-5.3-codex-low - Codex 5.3 Low
gpt-5.3-codex-high - Codex 5.3 High')" \
      "auto
gpt-5.3-codex-high
gpt-5.3-codex-low"

check "pi parser: model field, no header or tilde" \
      "$(roles_parse_out roles_parse_pi_models 'provider    model                          context  thinking
openrouter  ~anthropic/claude-haiku-latest 200K     yes
openai      gpt-5                          1M       yes')" \
      "anthropic/claude-haiku-latest
gpt-5"

check "codex parser: slug from the JSON cache (pretty and single-line)" \
      "$(roles_parse_out roles_parse_codex_models '{
  "models": [ { "slug": "gpt-5.6-sol" }, { "slug": "gpt-5.4-mini" } ]
}
{"models":[{"slug":"codex-auto-review"}]}')" \
      "codex-auto-review
gpt-5.4-mini
gpt-5.6-sol"

check "claude parser: id from the binary's embedded catalogue" \
      "$(roles_parse_out roles_parse_claude_models 'noise {id:"claude-opus-5",family:"opus",display_name:"Opus 5"} noise
{ id: "claude-haiku-4-5", family: "haiku" } tail')" \
      "claude-haiku-4-5
claude-opus-5"

check "opencode parser: provider/model lines, nested slashes and colons kept, noise dropped" \
      "$(roles_parse_out roles_parse_opencode_models 'INFO  loading providers
anthropic/claude-sonnet-5-5
openrouter/z-ai/glm-5.3-flash:free
zai/glm-5.3-flash

Warning: cache is stale')" \
      "anthropic/claude-sonnet-5-5
openrouter/z-ai/glm-5.3-flash:free
zai/glm-5.3-flash"

# Empty and broken input is a legal empty answer with exit code 0: an agent update
# that broke the parser degrades into «enter your own», not into an error.
for _p in roles_parse_devin_models roles_parse_cursor_models roles_parse_pi_models roles_parse_codex_models roles_parse_claude_models roles_parse_opencode_models; do
    _out=$(roles_parse_out "$_p" '' 2>/dev/null; roles_parse_out "$_p" 'garbage !! ##' 2>/dev/null)
    check "parser $_p: empty/broken input — empty, exit code 0" "$_out|" "|"
done

# roles_models_of: unknown agent — empty, exit code 0 (the source is not queried).
UNK=$(sh -c '. "'"$REPO"'/installer/lib/roles.sh"; roles_models_of no-such-agent; printf rc=%s "$?"' 2>&1)
check "roles_models_of for an unknown agent is empty and error-free" "$UNK" "rc=0"

# roles_agents_available: the agent list comes from harness_detect, not from Orca.
# Check that the output is harness keys (one per line), without orca providers
# (kimi, grok, minimax) and without "(недоступен: …)" labels.
_AGENTS=$(sh -c '. "'"$REPO"'/installer/lib/harness.sh"; . "'"$REPO"'/installer/lib/roles.sh"; roles_agents_available' 2>/dev/null)
check "roles_agents_available: has output (harnesses detected)" "$_AGENTS" "$_AGENTS"
[ -n "$_AGENTS" ] && check "roles_agents_available: no orca providers (kimi/grok/minimax)" \
    "$(printf '%s\n' "$_AGENTS" | grep -E 'kimi|grok|minimax' || true)" ""
[ -n "$_AGENTS" ] && check "roles_agents_available: no unavailability labels" \
    "$(printf '%s\n' "$_AGENTS" | grep 'недоступен' || true)" ""

# ---------------------------------------------------- build plan: waves and arithmetic
printf '\ndispatcher: build waves and arithmetic\n'

DLIB='. "'"$REPO"'/installer/lib/core.sh"; . "'"$REPO"'/installer/lib/config.sh"
    . "'"$REPO"'/installer/lib/harness.sh"; . "'"$REPO"'/installer/lib/ade.sh"
    . "'"$REPO"'/installer/lib/fleet.sh"; . "'"$REPO"'/installer/lib/roles.sh"
    . "'"$REPO"'/installer/lib/dispatch.sh"'
PLANS="$SANDBOX/plans"; mkdir -p "$PLANS"; export PLANS

# A plan without order is one wave; the behaviour of old plans does not change by a single byte.
cat > "$PLANS/flat.md" <<'PLAN'
## Subtask: a
**Role**: run-task
**Summary**: раз

### `a1.py`
- почему

### `a2.py`
- почему

## Subtask: b
**Role**: run-task
**Summary**: два

### `b1.py`
- почему

### `b2.py`
- почему
PLAN
check "plan without After — one wave" \
      "$(sh -c "$DLIB"'; dispatch_wave_count "$PLANS/flat.md"')" "1"

# A plan with order: contract → backend + frontend, and wave 2 shares a file with wave 1.
cat > "$PLANS/waves.md" <<'PLAN'
## Subtask: contract
**Role**: run-task
**Summary**: контракт

### `docs/events.md`
- формат

### `docs/schema.json`
- схема

## Subtask: backend
**Role**: run-task
**After**: contract
**Summary**: бэкенд

### `src/api.py`
- отправка

### `docs/events.md`
- пример

## Subtask: frontend
**Role**: run-task
**After**: contract
**Summary**: фронт

### `web/app.js`
- приём

### `web/style.css`
- вид
PLAN
check "waves derived from After" \
      "$(sh -c "$DLIB"'; dispatch_waves "$PLANS/waves.md"' | tr '\t' ':' | tr '\n' ' ')" \
      "contract:1 backend:2 frontend:2 "
check "wave 2 subtasks" \
      "$(sh -c "$DLIB"'; dispatch_wave_ids "$PLANS/waves.md" 2' | tr '\n' ' ')" "backend frontend "

# After pointing nowhere and a cycle — refusal, not silent levelling: either one costs
# N launches if discovered after handing out.
cat > "$PLANS/ghost.md" <<'PLAN'
## Subtask: a
**Role**: run-task
**After**: nosuch
**Summary**: раз

### `a1.py`
- почему
PLAN
sh -c "$DLIB"'; dispatch_waves "$PLANS/ghost.md"' >/dev/null 2>&1
check "After pointing to a nonexistent subtask — refused" "$?" "1"
check "refusal names the subtask" \
      "$(sh -c "$DLIB"'; dispatch_waves "$PLANS/ghost.md"' 2>&1 >/dev/null | grep -c 'nosuch')" "1"

cat > "$PLANS/cycle.md" <<'PLAN'
## Subtask: a
**Role**: run-task
**After**: b
**Summary**: раз

### `a1.py`
- почему

## Subtask: b
**Role**: run-task
**After**: a
**Summary**: два

### `b1.py`
- почему
PLAN
sh -c "$DLIB"'; dispatch_waves "$PLANS/cycle.md"' >/dev/null 2>&1
check "dependency cycle — refused" "$?" "1"
check "refusal names the cycle" \
      "$(sh -c "$DLIB"'; dispatch_waves "$PLANS/cycle.md"' 2>&1 >/dev/null | grep -c 'цикл')" "1"

# Arithmetic: warnings are printed but NEVER change the exit code — otherwise
# a metric that does not measure work would start failing plans.
cat > "$PLANS/big.md" <<'PLAN'
## Subtask: a
**Role**: run-task
**Summary**: раз

### `a1.py`
- x

## Subtask: b
**Role**: run-task
**Summary**: два

### `b1.py`
- x

## Subtask: c
**Role**: run-task
**Summary**: три

### `c1.py`
- x

## Subtask: d
**Role**: run-task
**Summary**: четыре

### `d1.py`
- x

## Subtask: e
**Role**: run-task
**Summary**: пять

### `e1.py`
- x

## Subtask: f
**Role**: run-task
**Summary**: шесть

### `f1.py`
- x

## Subtask: g
**Role**: run-task
**Summary**: семь

### `g1.py`
- x
PLAN
check "7 subtasks — acceptance ceiling warning" \
      "$(sh -c "$DLIB"'; dispatch_size_notes "$PLANS/big.md"' 2>&1 >/dev/null | grep -c 'потолок 6')" "1"
check "wide wave — warning" \
      "$(sh -c "$DLIB"'; dispatch_size_notes "$PLANS/big.md"' 2>&1 >/dev/null | grep -c 'одновременно')" "1"
# There are no lower thresholds: one subtask with one path for one cheap worker is a legitimate
# build (DECISIONS 2026-09-15). The ceilings remain.
check "subtask with one path — not a warning" \
      "$(sh -c "$DLIB"'; dispatch_size_notes "$PLANS/big.md"' 2>&1 >/dev/null | grep -c 'мельче цены раздачи')" "0"
check "small flat build warns about nothing" \
      "$(sh -c "$DLIB"'; dispatch_size_notes "$PLANS/flat.md"' 2>&1 >/dev/null)" ""
sh -c "$DLIB"'; dispatch_size_notes "$PLANS/big.md"' >/dev/null 2>&1
check "warnings do not change the exit code" "$?" "0"
check "clean plan warns about nothing" \
      "$(sh -c "$DLIB"'; dispatch_size_notes "$PLANS/waves.md"' 2>&1 >/dev/null)" ""

# The composition line: what this build costs, before a single launch.
check "composition line counts subtasks, waves and width" \
      "$(sh -c "$DLIB"'; dispatch_cost_line "$PLANS/waves.md"')" \
      "состав: 3 подзадачи, 2 волны, 2 воркера одновременно"
check "composition line on a flat plan" \
      "$(sh -c "$DLIB"'; dispatch_cost_line "$PLANS/flat.md"')" \
      "состав: 2 подзадачи, 1 волна, 2 воркера одновременно"

# ---------------------------------------------------- per-wave plan check
printf '\ndispatcher: per-wave plan check\n'

# One file shared by two subtasks of the SAME wave — refusal, as before.
cat > "$PLANS/clash.md" <<'PLAN'
## Subtask: a
**Role**: run-task
**Summary**: раз

### `shared.py`
- почему

### `a1.py`
- почему

## Subtask: b
**Role**: run-task
**Summary**: два

### `shared.py`
- почему

### `b1.py`
- почему
PLAN
sh -c "$DLIB"'; dispatch_check "$PLANS/clash.md"' >/dev/null 2>&1
check "overlap within a wave — refused" "$?" "1"
CLASH=$(sh -c "$DLIB"'; dispatch_check "$PLANS/clash.md"' 2>&1 >/dev/null)
check "refusal names the wave" "$(printf '%s' "$CLASH" | grep -c 'волна 1')" "1"
check "refusal shows the ladder of ways out" "$(printf '%s' "$CLASH" | grep -c 'After')" "1"

# The same file, but the subtasks are split across waves — passes. That is exit #3.
sh -c "$DLIB"'; dispatch_check "$PLANS/waves.md"' >/dev/null 2>&1
check "overlap across waves — passes" "$?" "0"

# An order that cannot be parsed fails the whole check.
sh -c "$DLIB"'; dispatch_check "$PLANS/cycle.md"' >/dev/null 2>&1
check "cycle fails dispatch-check" "$?" "1"
sh -c "$DLIB"'; dispatch_check "$PLANS/ghost.md"' >/dev/null 2>&1
check "After pointing nowhere fails dispatch-check" "$?" "1"

# The report shows each subtask's wave — before handing out, not after.
check "report names the subtask's wave" \
      "$(sh -c "$DLIB"'; dispatch_report "$PLANS/waves.md"' | awk 'NR>1 { printf "%s%s", $1, $2 }' | tr -d ' ')" \
      "1contract2backend2frontend"

# ---------------------------------------------------- collecting a wave into the build branch
# Real worktrees and real commits, no environment stub: the checkout registry is kept by git, and
# collecting must work the same no matter who created the checkout — Orca or a human.
printf '\ndispatcher: wave collection\n'

CB="$SANDBOX/collect"; mkdir -p "$CB"; export CB
git -C "$CB" init -q; git -C "$CB" config user.email t@t; git -C "$CB" config user.name t
mkdir -p "$CB/ai/builds"
printf 'base\n' > "$CB/one.py"; printf 'base\n' > "$CB/two.py"; printf 'base\n' > "$CB/three.py"
git -C "$CB" add -A >/dev/null; git -C "$CB" commit -qm init >/dev/null

cat > "$CB/plan.md" <<'PLAN'
## Subtask: one
**Role**: run-task
**Summary**: первая

### `one.py`
- почему

## Subtask: two
**Role**: run-task
**Summary**: вторая

### `two.py`
- почему
PLAN

BID=build-test; export BID
BDIR="$CB/ai/builds/$BID"
sh -c "$DLIB"'; build_seal "$CB" "$BID" "$CB/plan.md"' >/dev/null 2>&1
check "build created branch fraim/build-test" \
      "$(git -C "$CB" rev-parse --verify --quiet refs/heads/fraim/build-test >/dev/null 2>&1 && echo yes || echo no)" "yes"

# Two workers: their own checkouts off the build branch, their own commits in their own paths. The checkout name is
# «build-subtask», as dispatch_launch builds it: dispatch_worker_tree looks it up by that name.
git -C "$CB" worktree add -q -b w-one "$SANDBOX/$BID-one" fraim/build-test
git -C "$CB" worktree add -q -b w-two "$SANDBOX/$BID-two" fraim/build-test
printf 'one\n' >> "$SANDBOX/$BID-one/one.py"
git -C "$SANDBOX/$BID-one" commit -qam "one" >/dev/null
printf 'two\n' >> "$SANDBOX/$BID-two/two.py"
git -C "$SANDBOX/$BID-two" commit -qam "two" >/dev/null

OUT=$(sh -c "$DLIB"'; dispatch_collect "$CB" "'"$BID"'"' 2>&1)
check "collection passed" "$?" "0"
check "both subtasks merged" "$(printf '%s' "$OUT" | grep -c 'слита')" "2"
check "combined wave diff is printed" "$(printf '%s' "$OUT" | grep -c 'изменила целиком')" "1"
check "build branch carries both edits" \
      "$(git -C "$CB" show fraim/build-test:one.py | tail -1)$(git -C "$CB" show fraim/build-test:two.py | tail -1)" \
      "onetwo"
check "conductor's working tree untouched" \
      "$(git -C "$CB" rev-parse --abbrev-ref HEAD)" "master"
check "no temporary checkouts left" \
      "$(git -C "$CB" worktree list --porcelain | grep -c 'fraim-collect')" "0"
check "journal got a collection entry" "$(grep -c 'Wave 1 collected' "$BDIR/journal.md")" "1"
check "collected.tsv remembers what came back" "$(grep -c "	one	" "$BDIR/collected.tsv")" "1"

# Repeat: what is collected is not collected twice.
OUT=$(sh -c "$DLIB"'; dispatch_collect "$CB" "'"$BID"'" 1' 2>&1)
check "repeated collection merges nothing" "$(printf '%s' "$OUT" | grep -c 'уже собрана')" "2"

# Refusal 1: uncommitted work. Only a commit can be merged.
cat > "$CB/plan2.md" <<'PLAN'
## Subtask: three
**Role**: run-task
**Summary**: третья

### `three.py`
- почему
PLAN
BID2=build-dirty; export BID2
sh -c "$DLIB"'; build_seal "$CB" "'"$BID2"'" "$CB/plan2.md"' >/dev/null 2>&1
git -C "$CB" worktree add -q -b w-three "$SANDBOX/$BID2-three" fraim/build-dirty 2>/dev/null
printf 'three\n' >> "$SANDBOX/$BID2-three/three.py"
OUT=$(sh -c "$DLIB"'; dispatch_collect "$CB" "'"$BID2"'"' 2>&1)
check "uncommitted work — refused" "$?" "1"
check "refusal names the uncommitted work" "$(printf '%s' "$OUT" | grep -c 'незакоммиченное')" "1"
check "build branch did not move on refusal" \
      "$(git -C "$CB" show fraim/build-dirty:three.py | tail -1)" "base"

# Refusal 2: an edit outside the declared paths. The reconciliation with the tree exists precisely for this line.
git -C "$SANDBOX/$BID2-three" commit -qam "three" >/dev/null
printf 'stray\n' >> "$SANDBOX/$BID2-three/one.py"
git -C "$SANDBOX/$BID2-three" commit -qam "stray" >/dev/null
OUT=$(sh -c "$DLIB"'; dispatch_collect "$CB" "'"$BID2"'"' 2>&1)
check "edit outside its paths — refused" "$?" "1"
check "refusal names the foreign file" "$(printf '%s' "$OUT" | grep -c 'one.py')" "1"
check "build branch did not accept the foreign edit" \
      "$(git -C "$CB" show fraim/build-dirty:three.py | tail -1)" "base"

# ------------------------------------------------- barrier: which wave goes up
# Until a wave is collected, the next one does not go up — that is the barrier, and it rests not
# on an environment signal but on the collection record in git.
printf '\ndispatcher: barrier between waves\n'

WB="$SANDBOX/waves-build"; mkdir -p "$WB/ai/builds"; export WB
git -C "$WB" init -q 2>/dev/null; git -C "$WB" config user.email t@t; git -C "$WB" config user.name t
printf 'x\n' > "$WB/f.py"; git -C "$WB" add -A >/dev/null; git -C "$WB" commit -qm init >/dev/null
cp "$PLANS/waves.md" "$WB/plan.md"
WBID=build-waves; export WBID
sh -c "$DLIB"'; build_seal "$WB" "$WBID" "$WB/plan.md"' >/dev/null 2>&1

check "first uncollected wave — the first one" \
      "$(sh -c "$DLIB"'; build_next_wave "$WB" "$WBID"')" "1"
printf '1\tcontract\tabc123\t2026-09-09T00:00:00Z\n' > "$WB/ai/builds/$WBID/collected.tsv"
check "wave 1 collected — next is the second" \
      "$(sh -c "$DLIB"'; build_next_wave "$WB" "$WBID"')" "2"
printf '2\tbackend\tdef456\t2026-09-09T00:00:00Z\n' >> "$WB/ai/builds/$WBID/collected.tsv"
check "half-collected wave stays the next one" \
      "$(sh -c "$DLIB"'; build_next_wave "$WB" "$WBID"')" "2"
printf '2\tfrontend\tghi789\t2026-09-09T00:00:00Z\n' >> "$WB/ai/builds/$WBID/collected.tsv"
sh -c "$DLIB"'; build_next_wave "$WB" "$WBID"' >/dev/null 2>&1
check "all waves collected — nothing to raise" "$?" "1"

# ------------------------------------------------------- conductor acceptance end to end
# Acceptance is the conductor's whole job: verify after the workers, run the master check, tidy up,
# take it into the trunk and print the report to the output. The human types no commands, so what is checked
# is how this output and this merge could lie: an incomplete collection, a red check, a dirty
# working tree, a checkout with uncommitted work — and reversibility of the trunk write.
printf '\ndispatcher: conductor acceptance\n'

DLIBV="$DLIB"'
    . "'"$REPO"'/installer/lib/lang.sh"; . "'"$REPO"'/installer/lib/verbs.sh"; . "'"$REPO"'/installer/lib/tasks.sh"; . "'"$REPO"'/installer/lib/foundation.sh"; . "'"$REPO"'/installer/lib/verbtable.sh"'

AB="$SANDBOX/accept"; mkdir -p "$AB/ai/builds"; export AB
git -C "$AB" init -q; git -C "$AB" config user.email t@t; git -C "$AB" config user.name t
git -C "$AB" symbolic-ref HEAD refs/heads/main
printf 'base\n' > "$AB/one.py"; printf 'base\n' > "$AB/two.py"; printf '# d\n' > "$AB/DECISIONS.md"
git -C "$AB" add -A >/dev/null; git -C "$AB" commit -qm init >/dev/null

cat > "$AB/plan.md" <<'PLAN'
## Subtask: one
**Role**: run-task
**Summary**: первая

### `one.py`
- почему

## Subtask: two
**Role**: run-task
**Summary**: вторая
**After**: one

### `two.py`
- почему
PLAN

ABID=build-accept; export ABID
ABDIR="$AB/ai/builds/$ABID"
sh -c "$DLIB"'; build_seal "$AB" "$ABID" "$AB/plan.md"' >/dev/null 2>&1

# Refusal before collection: a report on a half-collected build would describe work other than what exists.
OUT=$(sh -c "$DLIB"'; build_accept "$AB" "$ABID"' 2>&1); RC=$?
check "uncollected build is not accepted" "$RC" "2"
check "refusal names the uncollected subtasks" "$(printf '%s' "$OUT" | grep -c 'two')" "1"
check "trunk untouched" "$(git -C "$AB" log --oneline | wc -l | tr -d ' ')" "1"

git -C "$AB" worktree add -q -b aw-one "$SANDBOX/$ABID-one" "fraim/$ABID"
printf 'one\n' >> "$SANDBOX/$ABID-one/one.py"
git -C "$SANDBOX/$ABID-one" commit -qam one >/dev/null
sh -c "$DLIB"'; dispatch_collect "$AB" "$ABID" 1' >/dev/null 2>&1
git -C "$AB" worktree add -q -b aw-two "$SANDBOX/$ABID-two" "fraim/$ABID"
printf 'two\n' >> "$SANDBOX/$ABID-two/two.py"
git -C "$SANDBOX/$ABID-two" commit -qam two >/dev/null
sh -c "$DLIB"'; dispatch_collect "$AB" "$ABID" 2' >/dev/null 2>&1

# The second subtask's worker kept working after collection — its checkout must not be touched.
printf 'черновик\n' >> "$SANDBOX/$ABID-two/two.py"
# The build's foundation is written by the conductor into the build branch; no subtask declared it.
git -C "$AB" worktree add -q "$SANDBOX/$ABID-fnd" "fraim/$ABID"
printf -- '- решение\n' >> "$SANDBOX/$ABID-fnd/DECISIONS.md"
git -C "$SANDBOX/$ABID-fnd" commit -qam foundation >/dev/null
git -C "$AB" worktree remove --force "$SANDBOX/$ABID-fnd"

# A red master check: what was collected does not go to the trunk. This is not a judgement but a fact,
# and so a machine decides it, not a human.
printf 'build_check = sh -c "exit 3"\n' > "$AB/ai/fraim.conf"
OUT=$(sh -c "$DLIB"'; build_accept "$AB" "$ABID"' 2>&1); RC=$?
check "red check blocks the trunk" "$RC" "1"
check "output names the check's exit code" \
      "$(printf '%s' "$OUT" | grep -c 'проектная проверка вернула код 3')" "1"
check "trunk untouched on a red check" \
      "$(git -C "$AB" log --oneline | wc -l | tr -d ' ')" "1"
check "build not marked accepted" "$([ -f "$ABDIR/accepted" ] && echo yes || echo no)" "no"
check "report lives in the output, not in a file" \
      "$([ -f "$ABDIR/report.md" ] && echo yes || echo no)" "no"

# Green check, but a dirty working tree: the merge would drag in someone else's unsaved work.
printf 'build_check = true\n' > "$AB/ai/fraim.conf"
printf 'чужое\n' >> "$AB/one.py"
OUT=$(sh -c "$DLIB"'; build_accept "$AB" "$ABID"' 2>&1); RC=$?
check "dirty tree blocks the trunk" "$RC" "1"
check "output names the unsaved work" "$(printf '%s' "$OUT" | grep -c 'несохранённое')" "1"
git -C "$AB" checkout -q -- one.py

# Everything matched: verification, check, cleanup, trunk — in one command and without a single command for the human.
OUT=$(sh -c "$DLIB"'; build_accept "$AB" "$ABID"' 2>&1); RC=$?
check "acceptance passed" "$RC" "0"
check "both subtasks in the output" \
      "$(printf '%s' "$OUT" | grep -cE '^    (one|two) +волна')" "2"
check "file nobody declared is named" \
      "$(printf '%s' "$OUT" | grep -c 'не объявлял никто: DECISIONS.md')" "1"
check "output names the merge into the trunk" "$(printf '%s' "$OUT" | grep -c 'в ствол: main')" "1"
check "output names the undo command" "$(printf '%s' "$OUT" | grep -c 'fraim undo')" "1"
check "collected work really is in the trunk" \
      "$(git -C "$AB" show main:two.py | tail -1)" "two"
check "merge marked as ours" \
      "$(git -C "$AB" log -1 --format=%B main | grep -c '^fraim: ')" "1"
check "build marked accepted" "$(grep -c '^Accepted by: conductor' "$ABDIR/accepted")" "1"
check "journal knows about the trunk" "$(grep -c 'merged into the trunk by the conductor' "$ABDIR/journal.md")" "1"
check "list knows the build is in the trunk" \
      "$(sh -c "$DLIB"'; build_list "$AB"' | grep -c 'в стволе')" "1"

# Cleanup: only what is provably redundant is removed. A checkout with uncommitted work is what
# the mode exists for, and it stays untouched whatever the acceptance outcome.
check "cleanup removed the collected subtask's checkout" \
      "$(git -C "$AB" worktree list --porcelain | grep -c "$ABID-one")" "0"
check "checkout with uncommitted work kept" \
      "$(git -C "$AB" worktree list --porcelain | grep -c "$ABID-two")" "1"
check "worker's work intact" "$(tail -1 "$SANDBOX/$ABID-two/two.py")" "черновик"
check "output warned about the kept checkout" \
      "$(printf '%s' "$OUT" | grep -c 'оставлен: есть незакоммиченное')" "1"

# The same thing is not taken into the trunk twice.
sh -c "$DLIB"'; build_accept "$AB" "$ABID"' >/dev/null 2>&1
check "accepted build is not accepted a second time" "$?" "2"

# The human's feedback is in words, and there is one lever for it: undoing the merge with one command.
# Without -m 1 revert fails on a merge, and that is exactly why writing to the trunk is acceptable at all.
AMERGE=$(git -C "$AB" rev-parse --short main)
sh -c "$DLIBV"'; verb_undo "$AB" "'"$AMERGE"'"' >/dev/null 2>&1
check "trunk write is undone with one command" "$?" "0"
check "after undo the trunk is back to before" \
      "$(git -C "$AB" show main:two.py | tail -1)" "base"
check "build branch intact after undo too" \
      "$(git -C "$AB" show "fraim/$ABID:two.py" | tail -1)" "two"


printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
