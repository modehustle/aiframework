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
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "ожидалось [$3], получено [$2]"; fi; }

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
export FRAIM_HOME="$HOME/.fraim"
mkdir -p "$HOME" "$FRAIM_HOME"

# Фикстуры ниже — намеренно минимальные каталоги: у них нет ни AGENTS.md, ни ai/fraim.conf,
# потому что каждая проверяет что-то одно. Проверка соответствия стандарту сработала бы на
# всех сразу и заглушила бы то, ради чего фикстура заведена. Выключаем её машинной настройкой
# и включаем обратно в проекте, который её и проверяет (проект бьёт машину).
printf 'check_shape = off\n' > "$FRAIM_HOME/config"

# ---------------------------------------------------------------- procedures
printf '\nprocedures/\n'

N=$(ls "$REPO"/procedures/*.md | grep -v manifest | wc -l | tr -d ' ')
check "12 процедур на диске" "$N" "12"

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
check "фронтматтер всех процедур корректен" "${BADFM:-clean}" "clean"

# --- рельсы -----------------------------------------------------------------
# `fraim commit` прожил в двух процедурах несколько релизов, потому что ничто не
# сверяло текст процедур с диспетчером. Эти три проверки ловят класс, а не случай.

DISPATCH=$(awk '/^case \$_cmd in/,/^esac$/' "$REPO/installer/bin/fraim" |
           sed -n 's/^[[:space:]]*\([a-z|_-]*\)).*/\1/p' | tr '|' '\n' |
           grep -E '^[a-z][a-z-]*$' | sort -u)
# Только команды в коде — с бэктиком или в начале строки блока. Иначе английская
# проза «a fraim project» читается как команда.
USED=$(grep -ohE '(^|`)fraim [a-z][a-z-]*' "$REPO"/procedures/*.md |
       sed 's/^`//; s/^fraim //' | sort -u)

UNKNOWN=""
for v in $USED; do
    printf '%s\n' "$DISPATCH" | grep -qx "$v" || UNKNOWN="$UNKNOWN $v"
done
check "каждая команда fraim из процедур есть в CLI" "${UNKNOWN:-none}" "none"

UNDOC=""
HELP=$("$REPO/installer/bin/fraim" help 2>/dev/null)
for v in $DISPATCH; do
    printf '%s\n' "$HELP" | grep -qw -- "$v" || UNDOC="$UNDOC $v"
done
check "каждая команда CLI описана в fraim help" "$(printf '%s' "${UNDOC:-none}" | tr -s ' ')" "none"

# Гейты парсят заголовки, которые печатает шаблон. Тест берёт литерал из кода гейта
# и ищет его в шаблонах — а не в собственной копии формата.
MISSING_HEAD=""
HEADS=$(grep -oE "verb_section_filled [^ ]+ '[^']+'" "$REPO/installer/lib/verbs.sh" |
        sed "s/.*'\(.*\)'/\1/" | sort -u)
OLDIFS=$IFS; IFS='
'
for h in $HEADS; do
    grep -rqF "$h" "$REPO/installer/templates" || MISSING_HEAD="$MISSING_HEAD [$h]"
done
IFS=$OLDIFS
check "заголовки, которые читают гейты, есть в шаблонах" "${MISSING_HEAD:-none}" "none"

# Ни одна процедура не меняет состояние git руками — ни одна, без исключений.
# Список был закрытым и сократился до пустого: репозиторий заводит scaffold, точку
# сохранения ставит commit, возврат делают undo и restore. Любое совпадение здесь —
# либо новый глагол, либо ошибка.
GITHAND=$(grep -lE 'git (commit|add|init|restore|checkout|reset|stash|clean|push)' \
          "$REPO"/procedures/*.md | while read -r f; do basename "$f"; done | sort | tr '\n' ' ')
check "процедуры не трогают git руками" "$GITHAND" ""

# ---------------------------------------------------------------- menu
printf '\nfraim menu (экран)\n'

# Самое дорогое свойство меню — не то, как оно выглядит, а то, что его нет там,
# где его быть не должно. Подавляющее большинство вызовов CLI делает агент через
# пайп; команда, ждущая нажатия, повесила бы сессию молча.
OUT=$(timeout 10 "$FRAIM" menu </dev/null 2>&1 | head -1)
check "menu без терминала печатает usage, а не ждёт клавишу" \
      "$(printf '%s' "$OUT" | cut -c1-6)" "fraim "

OUT=$(timeout 10 "$FRAIM" </dev/null 2>&1 | head -1)
check "голый fraim без терминала печатает usage" \
      "$(printf '%s' "$OUT" | cut -c1-6)" "fraim "

# Карточка меню рисуется ПОСЛЕ сторожа, а в POSIX sh нет локальных переменных: сторож
# пишет _w, _n, _msg, пока работает. Меню, считавшее ширину до wm_run, получало
# «Illegal number: точек сохранения» и рисовало одну пустую строку — ровно на проектах,
# где находок больше всего. Рельс проверяет отрисовку на проекте с ремоутом и
# неотправленными точками, то есть в той самой ситуации.
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
    . "'"$REPO"'/installer/lib/scaffold.sh"; . "'"$REPO"'/installer/lib/verbs.sh"
    . "'"$REPO"'/installer/lib/watchman.sh"; . "'"$REPO"'/installer/lib/menu.sh"
    cd "'"$CARD"'" && menu_card && printf "%s\n" "$MENU_CARD"' 2>&1)
check "карточка меню не падает на числах сторожа" "$(printf '%s' "$CARDOUT" | grep -c 'Illegal number')" "0"
check "карточка меню показывает текст находок" \
      "$(printf '%s' "$CARDOUT" | grep -c 'не уехали в удалённую копию')" "1"
# Длинную строку карточка режет по двоеточию, а не по колонке: посчитать колонку
# правильно можно только зная локаль, а под LC_ALL=C кириллица режется пополам.
check "длинная находка режется по смыслу" \
      "$(printf '%s' "$CARDOUT" | grep -c 'скелет развёрнут, но не заполнен: …')" "1"
cd "$SANDBOX" || exit 1

# Навигация после сторожа. В POSIX sh нет локальных переменных, а menu_card зовёт
# сторожа, который пишет собственный `_n` (счётчик очереди). Счётчик пунктов меню жил
# в такой же `_n`, и после первой же отрисовки карточки становился нулём: стрелка вниз
# честно двигала выбор и тут же возвращала его на первую строку, а цифры 1-8 не
# срабатывали вовсе. Рельс воспроизводит ровно эту последовательность.
NAV=$(sh -c '
    . "'"$REPO"'/installer/lib/core.sh"; . "'"$REPO"'/installer/lib/config.sh"
    . "'"$REPO"'/installer/lib/registry.sh"; . "'"$REPO"'/installer/lib/context.sh"
    . "'"$REPO"'/installer/lib/scaffold.sh"; . "'"$REPO"'/installer/lib/verbs.sh"
    . "'"$REPO"'/installer/lib/watchman.sh"; . "'"$REPO"'/installer/lib/menu.sh"
    cd "'"$CARD"'" || exit 1
    MENU_N=$(menu_count); MENU_SEL=1
    menu_card
    MENU_SEL=$((MENU_SEL + 1)); [ "$MENU_SEL" -gt "$MENU_N" ] && MENU_SEL=1
    printf "%s/%s\n" "$MENU_SEL" "$MENU_N"' 2>&1)
ITEMS_N=$(sh -c '. "'"$REPO"'/installer/lib/menu.sh"; menu_count')
check "стрелка вниз двигает выбор после сторожа" "$NAV" "2/$ITEMS_N"

# Меню обязано пережить код возврата каждого своего пункта. CLI работает под `set -e`,
# а `fraim status` выходит с 1, как только в проекте есть что показать человеку, — то
# есть в самом обычном случае. Без защиты выбор «Скан проекта» печатал вердикт и убивал
# процесс посреди экрана, оставляя терминал без эха и без курсора.
MBR=$(sed -n '/^menu_exec() {/,/^    esac$/p' "$REPO/installer/lib/menu.sh" |
      grep -cE '^        [0-9]+\)')
MGUARD=$(sed -n '/^menu_exec() {/,/^    esac$/p' "$REPO/installer/lib/menu.sh" |
      grep -c '|| true')
check "каждое действие меню переживает свой код возврата" "$MGUARD" "$MBR"

# Пункт меню и его действие живут в двух местах (menu_items и menu_exec). Рельс
# ловит класс: добавили строку — забыли ветку. Последний пункт («Выход») ветки
# не имеет по построению.
ITEMS=$(sed -n '/^menu_items() {/,/^}/p' "$REPO/installer/lib/menu.sh" |
        sed -n '/<<.ITEMS./,/^ITEMS$/p' | grep -c '	')
BRANCH=$(sed -n '/^menu_exec() {/,/^}/p' "$REPO/installer/lib/menu.sh" |
         grep -cE '^        [0-9]+\)')
check "у каждого пункта меню есть действие" "$BRANCH" "$((ITEMS - 1))"

# ---------------------------------------------------------------- build
printf '\nfraim build\n'

"$FRAIM" build >/dev/null 2>&1
check "build завершился успешно" "$?" "0"

PLUG="$REPO/installer/claude-plugin/skills"
check "плагин: 13 скиллов" "$(find "$PLUG" -name SKILL.md | wc -l | tr -d ' ')" "13"

# The single-file rule is a compatibility constraint, not tidiness:
# Hermes fetches only SKILL.md when installing from a URL, and omp discovers
# skills non-recursively. Anything beside SKILL.md would arrive missing.
EXTRA=$(find "$PLUG" -type f ! -name SKILL.md | wc -l | tr -d ' ')
check "в каждом скилле ровно один файл" "$EXTRA" "0"

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
check "тело скилла совпадает с исходником байт в байт" "$DIFFS" "0"

python3 -c "import json,sys;json.load(open('$REPO/procedures/manifest.json'))" 2>/dev/null
check "манифест — валидный JSON" "$?" "0"

# ---------------------------------------------------------------- watchman
printf '\nfraim status (сторож)\n'

PROJ="$SANDBOX/proj"
mkdir -p "$PROJ"
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "проект не под системой → exit 2" "$?" "2"

git -C "$PROJ" init -q
git -C "$PROJ" config user.email t@t; git -C "$PROJ" config user.name t
mkdir -p "$PROJ/ai/tasks"
printf '# Arch\n' > "$PROJ/ARCHITECTURE.md"
printf 'x\n' > "$PROJ/main.py"
git -C "$PROJ" add -A >/dev/null; git -C "$PROJ" commit -qm init
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "чистый проект → exit 0" "$?" "0"

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
check "2 коммита кода (ниже порога) → exit 0" "$?" "0"
printf 'line 3\n' >> "$PROJ/app.py"
git -C "$PROJ" add app.py >/dev/null 2>&1
git -C "$PROJ" commit -qm "fix: change 3" >/dev/null 2>&1
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "3 коммита кода (порог) → exit 1" "$?" "1"
"$FRAIM" status "$PROJ" 2>/dev/null | grep -q '/prune'
check "вердикт указывает на /prune" "$?" "0"

# The map moving is one anchor; a prune commit is the other, and the nearer one wins.
printf 'updated\n' >> "$PROJ/ARCHITECTURE.md"
git -C "$PROJ" add ARCHITECTURE.md >/dev/null 2>&1
git -C "$PROJ" commit -qm "prune: reconcile foundation" >/dev/null 2>&1
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "обновление карты сбрасывает счётчик → exit 0" "$?" "0"
rm -f "$PROJ/ai/fraim.conf"

# Blockers: the executor refused the plan and stopped.
mkdir -p "$PROJ/ai/tasks/add-auth"
printf '# Blocked\n' > "$PROJ/ai/tasks/add-auth/blockers.md"
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "blockers.md → exit 1" "$?" "1"
"$FRAIM" status "$PROJ" 2>/dev/null | grep -q '/revise-task'
check "вердикт указывает на /revise-task" "$?" "0"
rm -rf "$PROJ/ai/tasks/add-auth"

# Stale plan: HEAD moved after the plan was written against an older commit.
BASE=$(git -C "$PROJ" rev-parse HEAD)
mkdir -p "$PROJ/ai/tasks/feature-x"
printf '# Task Context\n\n## Plan provenance\n- Based on: HEAD %s\n' "$BASE" > "$PROJ/ai/tasks/feature-x/context.md"
printf '# Task\n' > "$PROJ/ai/tasks/feature-x/task.md"
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "план на актуальном HEAD → exit 0" "$?" "0"
printf 'y\n' >> "$PROJ/main.py"
git -C "$PROJ" commit -aqm second
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "HEAD ушёл вперёд → exit 1" "$?" "1"
"$FRAIM" status "$PROJ" 2>/dev/null | grep -q 'отстал'
check "вердикт называет протухший план" "$?" "0"

# Протухание меряется по ПОВЕРХНОСТИ плана, а не по счётчику коммитов. Три исхода —
# и первый из них тот, из-за которого проверка была бесполезна: очередь, запечатывая
# сама себя, двигала HEAD и объявляла протухшими все планы в себе.
STALE="$SANDBOX/stale"
mkdir -p "$STALE/ai/tasks" "$STALE/src"
git -C "$STALE" init -q
git -C "$STALE" config user.email t@t; git -C "$STALE" config user.name t
printf '# Arch\n' > "$STALE/ARCHITECTURE.md"
printf '# Conv\n' > "$STALE/CONVENTIONS.md"
printf 'app\n' > "$STALE/src/app.py"
printf 'other\n' > "$STALE/src/other.py"
git -C "$STALE" add -A >/dev/null 2>&1
git -C "$STALE" commit -qm init >/dev/null 2>&1

stale_plan() { # slug base surface-file
    mkdir -p "$STALE/ai/tasks/$1"
    printf '# Task Context\n\n## Plan provenance\n- Based on: HEAD %s\n\n## Codebase Context\n- `%s` — образец\n' \
        "$2" "$3" > "$STALE/ai/tasks/$1/context.md"
    printf '# Task\n\n## Files to Change\n\n### `%s`\n- **Action:** modify\n' "$3" > "$STALE/ai/tasks/$1/task.md"
}

BASE=$(git -C "$STALE" rev-parse --short HEAD)
stale_plan alpha "$BASE" src/app.py
stale_plan beta  "$BASE" src/app.py
git -C "$STALE" add -A >/dev/null 2>&1
git -C "$STALE" commit -qm "plan: alpha — план готов к исполнению" >/dev/null 2>&1
printf 'x\n' >> "$STALE/ai/tasks/beta/task.md"
git -C "$STALE" add -A >/dev/null 2>&1
git -C "$STALE" commit -qm "plan: beta — план готов к исполнению" >/dev/null 2>&1

"$FRAIM" status "$STALE" >/dev/null 2>&1
check "очередь запечатала себя (только ai/) → не протухание" "$?" "0"
check "ни одного stale-plan на бухгалтерии" \
    "$("$FRAIM" status "$STALE" --json 2>/dev/null | grep -c '"id": "stale-plan"')" "0"

# Код поехал мимо файлов плана: сказать стоит, блокировать — нет.
printf 'changed\n' >> "$STALE/src/other.py"
git -C "$STALE" commit -aqm "feat: other" >/dev/null 2>&1
"$FRAIM" status "$STALE" >/dev/null 2>&1
check "коммит мимо поверхности плана → exit 0" "$?" "0"
check "но он назван как info" \
    "$("$FRAIM" status "$STALE" --json 2>/dev/null | grep -c '"severity": "info", "message": "план «alpha»')" "1"

# Изменился файл, на котором план стоит, — вот это протухание, и оно с уликой.
printf 'changed\n' >> "$STALE/src/app.py"
git -C "$STALE" commit -aqm "feat: app" >/dev/null 2>&1
"$FRAIM" status "$STALE" >/dev/null 2>&1
check "изменился файл из плана → exit 1" "$?" "1"
"$FRAIM" status "$STALE" 2>/dev/null | grep -q 'план «alpha» отстал: изменился src/app.py'
check "находка называет файл, а не число коммитов" "$?" "0"

# Каталог в Codebase Context покрывает всё под собой.
BASE2=$(git -C "$STALE" rev-parse --short HEAD)
stale_plan gamma "$BASE2" src/
printf 'deep\n' > "$STALE/src/nested.py"
git -C "$STALE" add -A >/dev/null 2>&1
git -C "$STALE" commit -qm "feat: nested" >/dev/null 2>&1
"$FRAIM" status "$STALE" 2>/dev/null | grep -q 'план «gamma» отстал: изменился src/nested.py'
check "каталог в поверхности ловит файл под ним" "$?" "0"

# Фундамент, который исполнитель и так перечитывает на Шаге 1, поверхностью не считается:
# он стоит в КАЖДОМ плане по шаблону, и одна правка карты подняла бы всю очередь разом.
BASE4=$(git -C "$STALE" rev-parse --short HEAD)
stale_plan delta "$BASE4" src/app.py
printf 'map moved\n' >> "$STALE/ARCHITECTURE.md"
git -C "$STALE" add -A >/dev/null 2>&1
git -C "$STALE" commit -qm "prune: карта" >/dev/null 2>&1
check "правка ARCHITECTURE.md не поднимает очередь" \
    "$("$FRAIM" status "$STALE" --json 2>/dev/null | grep -c '"severity": "attention", "message": "план «delta»')" "0"

# План без перечисленных файлов сверить не с чем — там счётчик коммитов и остаётся.
BASE3=$(git -C "$STALE" rev-parse --short HEAD)
mkdir -p "$STALE/ai/tasks/blind"
printf '# Task Context\n\n## Plan provenance\n- Based on: HEAD %s\n' "$BASE3" > "$STALE/ai/tasks/blind/context.md"
printf 'more\n' >> "$STALE/src/other.py"
git -C "$STALE" commit -aqm "feat: other again" >/dev/null 2>&1
"$FRAIM" status "$STALE" 2>/dev/null | grep -q 'план «blind» отстал от HEAD на 1 коммит кода'
check "план без списка файлов падает обратно на счётчик" "$?" "0"

# Version drift of the system itself.
printf -- '- System: fraim 0.0.1-old\n' >> "$PROJ/ai/tasks/feature-x/context.md"
"$FRAIM" status "$PROJ" 2>/dev/null | grep -q 'написан fraim 0.0.1-old'
check "план от старой версии fraim замечен" "$?" "0"

python3 -c "import json,sys;json.load(sys.stdin)" < "$("$FRAIM" status "$PROJ" --json > "$SANDBOX/s.json" 2>/dev/null; echo "$SANDBOX/s.json")"
check "--json — валидный JSON" "$?" "0"

# The watchman is read-only. Anything else and it could not be put on a cron.
BEFORE=$(find "$PROJ" -newer "$PROJ/ARCHITECTURE.md" -type f | md5sum)
"$FRAIM" status "$PROJ" >/dev/null 2>&1
AFTER=$(find "$PROJ" -newer "$PROJ/ARCHITECTURE.md" -type f | md5sum)
check "сторож ничего не пишет" "$BEFORE" "$AFTER"


# ---------------------------------------------------------------- scaffold
printf '\nfraim scaffold\n'

PROJ2="$SANDBOX/proj2"
mkdir -p "$PROJ2"
git -C "$PROJ2" init -q
git -C "$PROJ2" config user.email t@t; git -C "$PROJ2" config user.name t
printf 'x\n' > "$PROJ2/main.py"
cd "$PROJ2" || exit 1

"$FRAIM" scaffold >/dev/null 2>&1
check "scaffold завершился успешно" "$?" "0"

MISSING=""
for f in README.md ARCHITECTURE.md CONVENTIONS.md DECISIONS.md .gitignore \
         ai/README.md ai/fraim.conf ai/archive/decisions_log.md AGENTS.md CLAUDE.md; do
    [ -f "$PROJ2/$f" ] || MISSING="$MISSING $f"
done
for d in ai/tasks ai/archive ai/investigations; do
    [ -d "$PROJ2/$d" ] || MISSING="$MISSING $d/"
done
check "все файлы и папки скелета созданы" "${MISSING:-none}" "none"

check "имя проекта подставлено" "$(grep -c 'ARCHITECTURE — proj2' "$PROJ2/ARCHITECTURE.md")" "1"

# The repository has to describe itself to an agent that has never heard of fraim —
# a cloud session, CI, a second machine. The pointer travels in git, not on the machine.
check "AGENTS.md несёт инвариант" "$(grep -c 'golden rule' "$PROJ2/AGENTS.md")" "1"
check "AGENTS.md работает без CLI" "$(grep -c 'If it is not installed' "$PROJ2/AGENTS.md")" "1"
check "CLAUDE.md указывает на AGENTS.md" "$(grep -c '@AGENTS.md' "$PROJ2/CLAUDE.md")" "1"
check "AGENTS.md закоммичен скелетом" \
    "$(git -C "$PROJ2" ls-files --error-unmatch AGENTS.md >/dev/null 2>&1 && echo yes || echo no)" "yes"


# A scaffold must never masquerade as a filled foundation: that is worse than no
# files at all, because the agent reads them, finds nothing, and goes back to guessing.
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "незаполненный скелет → exit 1" "$?" "1"
"$FRAIM" status "$PROJ2" 2>/dev/null | grep -q 'не заполнен'
check "сторож отличает скелет от фундамента" "$?" "0"

# Additive by construction: safe to run on a project that already has files.
printf 'MINE\n' > "$PROJ2/ARCHITECTURE.md"
"$FRAIM" scaffold >/dev/null 2>&1
check "scaffold не перезаписывает существующее" "$(cat "$PROJ2/ARCHITECTURE.md")" "MINE"

for f in README.md ARCHITECTURE.md CONVENTIONS.md DECISIONS.md; do
    printf '# %s\nfilled\n' "$f" > "$PROJ2/$f"
done
git -C "$PROJ2" add -A >/dev/null; git -C "$PROJ2" commit -qm "bootstrap: foundation"
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "заполненный фундамент → exit 0" "$?" "0"

# --- фундамент: считаем изменения, а не время ------------------------------
# Раньше мерилось время между последним коммитом кода и последним коммитом карты.
# В цикле задач это работало, а в реактивном режиме — самом частом — инвертировалось:
# сто коммитов за две недели молчали, один коммит через две недели поднимал тревогу.
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
check "9 коммитов кода — ниже порога" "$?" "0"

printf 'l10\n' >> "$PROJ5/main.py"; git -C "$PROJ5" commit -qam "fix 10" >/dev/null
"$FRAIM" status "$PROJ5" >/dev/null 2>&1
check "10 коммитов кода без карты → exit 1" "$?" "1"
"$FRAIM" status "$PROJ5" 2>/dev/null | grep -q 'с последнего обновления ARCHITECTURE.md'
check "вердикт называет отставание карты" "$?" "0"

# Все десять уместились в один день — по старой метрике это было бы «отставание 0 дней».
SPAN=$(git -C "$PROJ5" log -1 --format=%ct)
FIRST=$(git -C "$PROJ5" log --format=%ct -- ARCHITECTURE.md | tail -1)
check "и всё это в пределах одного дня" "$(( (SPAN - FIRST) / 86400 ))" "0"

printf 'updated\n' >> "$PROJ5/ARCHITECTURE.md"
git -C "$PROJ5" commit -qam "task: карта обновлена" >/dev/null
"$FRAIM" status "$PROJ5" >/dev/null 2>&1
check "обновление карты сбрасывает счётчик" "$?" "0"

# Прунинг, который честно ничего не изменил в карте, тоже обнуляет: иначе вердикт
# просил бы сделать прополку, которая только что прошла.
i=1; while [ $i -le 10 ]; do
    printf 'r%s\n' "$i" >> "$PROJ5/main.py"
    git -C "$PROJ5" commit -qam "fix r$i" >/dev/null
    i=$((i+1))
done
"$FRAIM" status "$PROJ5" >/dev/null 2>&1
check "снова накопилось → exit 1" "$?" "1"
git -C "$PROJ5" add -A >/dev/null
# --allow-empty: a prune that honestly changed nothing still has to leave the anchor,
# which is exactly what `fraim prune-mark` does.
git -C "$PROJ5" commit -q --allow-empty -m "prune: reconcile foundation" >/dev/null
"$FRAIM" status "$PROJ5" >/dev/null 2>&1
check "прошедший /prune сбрасывает счётчик" "$?" "0"

# --- git как данность -------------------------------------------------------
# Каждая точка сохранения здесь — коммит, поэтому проект без репозитория это проект,
# в котором ничего нельзя вернуть. Репозиторий — часть скелета, а не то, что пользователь
# обязан завести сам.
PROJ3="$SANDBOX/proj3"
mkdir -p "$PROJ3"
"$FRAIM" scaffold "$PROJ3" >/dev/null 2>&1
check "scaffold завёл репозиторий там, где его не было" \
    "$([ -d "$PROJ3/.git" ] && echo yes || echo no)" "yes"
check "подпись коммитов настроена" \
    "$(git -C "$PROJ3" config user.email)" "fraim@localhost"

# А внутри чужого репозитория — не заводит: вложенный репозиторий тихо отцепил бы
# файлы человека от его же истории.
mkdir -p "$PROJ3/sub"
"$FRAIM" scaffold "$PROJ3/sub" >/dev/null 2>&1
check "вложенный репозиторий не заводится" \
    "$([ -d "$PROJ3/sub/.git" ] && echo yes || echo no)" "no"

PROJ4="$SANDBOX/proj4"
mkdir -p "$PROJ4/ai/tasks"
printf '# Arch\n' > "$PROJ4/ARCHITECTURE.md"
"$FRAIM" status "$PROJ4" 2>/dev/null | grep -q 'нет репозитория'
check "сторож видит проект без репозитория" "$?" "0"

# ------------------------------------------------- существующий чужой репозиторий
# The shape every real onboarding has: history, a remote, its own README and .gitignore.
# Everything below used to be skipped silently on exactly this shape.
printf '\nчужой репозиторий (онбординг)\n'

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
check "scaffold отработал на чужом репозитории" "$?" "0"
check "чужой README не тронут" "$(cat "$LEGACY/README.md")" "# Legacy"
check "чужой .gitignore сохранён" "$(grep -c '^node_modules/$' "$LEGACY/.gitignore")" "1"
check "секреты дописаны в чужой .gitignore" "$(grep -c '^\.env$' "$LEGACY/.gitignore")" "1"
check ".env теперь игнорируется" \
    "$(git -C "$LEGACY" check-ignore -q .env && echo yes || echo no)" "yes"
check "data/ в чужой проект не навязан" "$(grep -c '^data/$' "$LEGACY/.gitignore")" "0"

# Idempotent: a second pass must not append the same lines again.
"$FRAIM" scaffold >/dev/null 2>&1
check "повторный scaffold не дублирует строки" "$(grep -c '^\.env$' "$LEGACY/.gitignore")" "1"

# A tracked .env is not fixed by ignoring it, and silence there would be the dangerous
# outcome — the user would push believing the secret is covered.
printf 'SECRET=yyy\n' > "$LEGACY/.env2"
git -C "$LEGACY" add -f .env >/dev/null 2>&1
git -C "$LEGACY" commit -qm "oops" >/dev/null 2>&1
"$FRAIM" scaffold 2>&1 | grep -q 'уже в истории git'
check "отслеживаемый .env вызывает предупреждение" "$?" "0"
rm -f "$LEGACY/.env2"

# Save points that never left this machine: detection only, never a reach for the network.
#
# Две разные величины, и мерить их одной было бы враньём (D5). Здесь адрес прописан, а
# отправляли по нему ни разу — это незакрытая настройка, а не отставание копии, и на хосте
# в этот момент обычно лежит пустой репозиторий, который снаружи выглядит существующим.
"$FRAIM" status "$LEGACY" 2>/dev/null | grep -q 'ни разу ничего не уезжало'
check "сторож видит незаконченную настройку копии" "$?" "0"

# А вот это уже отставание: копия наполнена, и после неё легли новые точки.
git -C "$LEGACY" push -q origin HEAD >/dev/null 2>&1
printf 'y\n' >> "$LEGACY/src/index.js"
git -C "$LEGACY" commit -qam "fix: y" >/dev/null 2>&1
printf 'z\n' >> "$LEGACY/src/index.js"
git -C "$LEGACY" commit -qam "fix: z" >/dev/null 2>&1
"$FRAIM" status "$LEGACY" 2>/dev/null | grep -q 'не уехали в удалённую копию'
check "сторож видит неуехавшие точки сохранения" "$?" "0"
"$FRAIM" config set unpushed_threshold 1 >/dev/null 2>&1
"$FRAIM" status "$LEGACY" >/dev/null 2>&1
check "выше порога — это тревога" "$?" "1"
"$FRAIM" config set unpushed_threshold 99 >/dev/null 2>&1

NOREMOTE="$SANDBOX/noremote"
mkdir -p "$NOREMOTE"; cd "$NOREMOTE" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
"$FRAIM" status "$NOREMOTE" 2>/dev/null | grep -q 'нет удалённой копии'
check "проект без remote назван честно" "$?" "0"
"$FRAIM" config set check_remote off >/dev/null 2>&1
"$FRAIM" status "$NOREMOTE" 2>/dev/null | grep -c 'удалённой копии' | grep -q '^0$'
check "выключенная проверка remote молчит" "$?" "0"
"$FRAIM" config set check_remote on >/dev/null 2>&1

# The blind spot that mattered once reactive work became the main mode: a foundation
# file that never entered history at all is invisible to --untracked-files=no.
rm -f "$NOREMOTE/AGENTS.md"
git -C "$NOREMOTE" rm -q --cached AGENTS.md >/dev/null 2>&1
git -C "$NOREMOTE" commit -qm "drop" >/dev/null 2>&1
printf 'brand new\n' > "$NOREMOTE/AGENTS.md"
"$FRAIM" status "$NOREMOTE" 2>/dev/null | grep -q 'после последней точки сохранения'
check "неотслеживаемый файл фундамента замечен" "$?" "0"

cd "$PROJ2" || exit 1

# ---------------------------------------------------------------- config
printf '\nfraim config\n'

check "значение по умолчанию" "$("$FRAIM" config 2>/dev/null | grep foundation_lag_commits | awk '{print $2}')" "10"
"$FRAIM" config set foundation_lag_commits 3 >/dev/null 2>&1
check "проектная настройка записана" "$(grep -c 'foundation_lag_commits = 3' "$PROJ2/ai/fraim.conf")" "1"
check "источник значения показан" "$("$FRAIM" config 2>/dev/null | grep foundation_lag_commits | grep -c 'ai/fraim.conf')" "1"
"$FRAIM" config set --machine stale_plan_commits 4 >/dev/null 2>&1
check "машинная настройка записана" "$(grep -c 'stale_plan_commits = 4' "$FRAIM_HOME/config")" "1"
"$FRAIM" config set nonsense_key 1 >/dev/null 2>&1
check "неизвестный ключ отвергнут" "$?" "2"

# A check turned off must actually stop firing.
for i in 1 2 3; do
    printf 'drift %s\n' "$i" >> "$PROJ2/app.py"
    git -C "$PROJ2" add app.py >/dev/null 2>&1
    git -C "$PROJ2" commit -qm "fix: drift $i" >/dev/null 2>&1
done
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "дрейф выше порога → exit 1" "$?" "1"
"$FRAIM" config set check_foundation off >/dev/null 2>&1
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "выключенная проверка не срабатывает" "$?" "0"
"$FRAIM" config set check_foundation on >/dev/null 2>&1
"$FRAIM" config set foundation_lag_commits 10 >/dev/null 2>&1

# ---------------------------------------------------------------- verbs
printf '\nдетерминированные глаголы\n'

"$FRAIM" task-new add-auth >/dev/null 2>&1
check "task-new создал задачу" "$([ -f "$PROJ2/ai/tasks/add-auth/context.md" ] && echo yes || echo no)" "yes"
check "провенанс: дата проставлена" "$(grep -c '^- Planned: 20' "$PROJ2/ai/tasks/add-auth/context.md")" "1"
check "провенанс: git-ref проставлен" "$(grep -c '^- Based on: HEAD ' "$PROJ2/ai/tasks/add-auth/context.md")" "1"
check "провенанс: версия системы проставлена" "$(grep -c '^- System: fraim ' "$PROJ2/ai/tasks/add-auth/context.md")" "1"
"$FRAIM" task-new add-auth >/dev/null 2>&1
check "task-new не затирает существующую задачу" "$?" "2"
"$FRAIM" task-new "Not Kebab" >/dev/null 2>&1
check "task-new требует kebab-case" "$?" "2"

# The gate: each precondition must actually block.
"$FRAIM" task-seal add-auth >/dev/null 2>&1
check "гейт: без result.md не архивирует" "$?" "2"

printf '## Status\n✅ complete\n' > "$PROJ2/ai/tasks/add-auth/result.md"
"$FRAIM" task-seal add-auth >/dev/null 2>&1
check "гейт: без раздела Foundation не архивирует" "$?" "2"

printf '\n## Foundation updated\n- `ARCHITECTURE.md`: <what changed>\n' >> "$PROJ2/ai/tasks/add-auth/result.md"
"$FRAIM" task-seal add-auth >/dev/null 2>&1
check "гейт: незаполненные плейсхолдеры не проходят" "$?" "2"

python3 - "$PROJ2/ai/tasks/add-auth/result.md" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace("- `ARCHITECTURE.md`: <what changed>",
                                   "- `ARCHITECTURE.md`: no structural change"))
PY
printf '# blocked\n' > "$PROJ2/ai/tasks/add-auth/blockers.md"
"$FRAIM" task-seal add-auth >/dev/null 2>&1
check "гейт: заблокированная задача не архивируется" "$?" "2"
rm -f "$PROJ2/ai/tasks/add-auth/blockers.md"

"$FRAIM" task-seal add-auth >/dev/null 2>&1
check "гейт: честный отчёт пропускается" "$?" "0"
check "задача убрана из очереди" "$([ -d "$PROJ2/ai/tasks/add-auth" ] && echo yes || echo no)" "no"
check "задача лежит в архиве" "$(find "$PROJ2/ai/archive" -maxdepth 1 -name '*_add-auth' | wc -l | tr -d ' ')" "1"
check "архивация закоммичена" "$(git -C "$PROJ2" log --oneline -1 --format=%s)" "archive: add-auth"

# The reactive save point is the record of unplanned work: an ordinary commit verb.
mkdir -p "$PROJ2/src"; printf 'reactive\n' >> "$PROJ2/src/a.py"
"$FRAIM" commit fix "off-by-one" src/a.py >/dev/null 2>&1
check "реактивная точка сохранения закоммичена" "$(git -C "$PROJ2" log --oneline -1 --format=%s)" "fix: off-by-one"
check "точка сохранения помечена трейлером" "$(git -C "$PROJ2" log -1 --format=%b | grep -c '^fraim: ')" "1"

"$FRAIM" stack-passport >/dev/null 2>&1
check "stack-passport создал STACK.md" "$([ -f "$PROJ2/STACK.md" ] && echo yes || echo no)" "yes"
check "имя проекта подставлено в паспорт" "$(grep -c 'STACK PASSPORT — proj2' "$PROJ2/STACK.md")" "1"
check "паспорт помечен как незаполненный" "$(grep -c 'fraim:stub' "$PROJ2/STACK.md")" "1"
"$FRAIM" stack-passport >/dev/null 2>&1
check "stack-passport не перезаписывает" "$?" "2"

"$FRAIM" prune-mark >/dev/null 2>&1
check "prune-mark оставил якорь-коммит" "$(git -C "$PROJ2" log --oneline -1 --format=%s | grep -c '^prune: reconcile foundation')" "1"
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "маркер сбросил счётчик дрейфа" "$?" "0"

# --- task-block / task-revise ----------------------------------------------
"$FRAIM" task-new fix-cache >/dev/null 2>&1
"$FRAIM" task-block fix-cache >/dev/null 2>&1
check "task-block завёл blockers.md" "$(grep -c 'fraim:stub' "$PROJ2/ai/tasks/fix-cache/blockers.md")" "1"
"$FRAIM" task-seal fix-cache >/dev/null 2>&1
check "гейт: заблокированную задачу не запечатать" "$?" "2"

"$FRAIM" task-revise fix-cache "wrong path in step 3" "path realigned with the code" >/dev/null 2>&1
check "task-revise отработал" "$?" "0"
check "task-revise снял блокер" "$([ -f "$PROJ2/ai/tasks/fix-cache/blockers.md" ] && echo yes || echo no)" "no"
check "task-revise записал ревизию" "$(grep -c '^## Revision 1 — 20' "$PROJ2/ai/tasks/fix-cache/task.md")" "1"
check "task-revise записал дефект" "$(grep -c 'Defect: wrong path in step 3' "$PROJ2/ai/tasks/fix-cache/task.md")" "1"
check "провенанс не задвоился" "$(grep -c '^- Planned: ' "$PROJ2/ai/tasks/fix-cache/context.md")" "1"
check "task-revise закоммитил" "$(git -C "$PROJ2" log --oneline -1 --format=%s)" "revise: fix-cache — wrong path in step 3"
"$FRAIM" task-revise fix-cache "again" "again" >/dev/null 2>&1
check "task-revise без блокера отказывает" "$?" "2"

# --- task-result ------------------------------------------------------------
"$FRAIM" task-result fix-cache >/dev/null 2>&1
check "task-result завёл отчёт" "$(grep -c '^## Foundation updated$' "$PROJ2/ai/tasks/fix-cache/result.md")" "1"
"$FRAIM" task-seal fix-cache >/dev/null 2>&1
check "гейт: незаполненную заготовку не архивирует" "$?" "2"

fill_result() {
    python3 - "$1" <<'PY2'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
t = "\n".join(l for l in t.splitlines() if "fraim:stub" not in l) + "\n"
t = re.sub(r"(## Foundation updated\n)(?:- .*\n)+",
           "\\1- `ARCHITECTURE.md`: no structural change\n", t)
t = re.sub(r"(## Divergence from plan\n)<[^>]*>\n(?:- .*\n)+",
           "\\1- Plan assumed a sync call; it is async.\n", t)
t = re.sub(r"^(- \(one-off\)|- \(pitfall\)|- \(bug\)|- \[x/|- `path/to|<verbatim|<If any|✅ complete).*$",
           "none", t, flags=re.M)
p.write_text(t)
PY2
}
fill_result "$PROJ2/ai/tasks/fix-cache/result.md"
"$FRAIM" task-seal fix-cache >/dev/null 2>&1
check "гейт: заполненный отчёт пропускается" "$?" "0"

"$FRAIM" task-new stale-plan >/dev/null 2>&1
"$FRAIM" task-result stale-plan >/dev/null 2>&1
"$FRAIM" task-result stale-plan --reset >/dev/null 2>&1
check "task-result --reset снял отчёт" "$([ -f "$PROJ2/ai/tasks/stale-plan/result.md" ] && echo yes || echo no)" "no"

# --- reconcile-seal (вторая дверь) ------------------------------------------
"$FRAIM" task-result stale-plan --reconcile >/dev/null 2>&1
check "task-result --reconcile завёл раздел расхождений" \
    "$(grep -c '^## Divergence from plan$' "$PROJ2/ai/tasks/stale-plan/result.md")" "1"
"$FRAIM" reconcile-seal stale-plan >/dev/null 2>&1
check "гейт: незаполненную заготовку не сводит" "$?" "2"
fill_result "$PROJ2/ai/tasks/stale-plan/result.md"
python3 - "$PROJ2/ai/tasks/stale-plan/result.md" <<'PY2'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
t = p.read_text().replace("- Plan assumed a sync call; it is async.\n", "")
p.write_text(t)
PY2
"$FRAIM" reconcile-seal stale-plan >/dev/null 2>&1
check "гейт: пустой раздел расхождений не проходит" "$?" "2"
printf -- '- Plan assumed a sync call; it is async.\n' >> "$PROJ2/ai/tasks/stale-plan/result.md"
"$FRAIM" reconcile-seal stale-plan >/dev/null 2>&1
check "reconcile-seal сводит и архивирует" "$?" "0"
check "дрейфнувшая сессия в архиве" "$(find "$PROJ2/ai/archive" -maxdepth 1 -name '*_stale-plan' | wc -l | tr -d ' ')" "1"
check "reconcile-seal закоммитил своим видом" \
    "$(git -C "$PROJ2" log --oneline -1 --format=%s)" "reconcile: stale-plan — sealed drifted session"

# --- investigate-new / investigate-seal -------------------------------------
"$FRAIM" investigate-new selector-flicker >/dev/null 2>&1
check "investigate-new завёл расследование" \
    "$([ -f "$PROJ2/ai/investigations/selector-flicker/findings.md" ] && echo yes || echo no)" "yes"
check "провенанс расследования проставлен" \
    "$(grep -c '^- Based on: HEAD ' "$PROJ2/ai/investigations/selector-flicker/findings.md")" "1"
check "слаг подставлен" \
    "$(grep -c 'INVESTIGATION — selector-flicker' "$PROJ2/ai/investigations/selector-flicker/findings.md")" "1"
"$FRAIM" investigate-seal selector-flicker >/dev/null 2>&1
check "гейт: заготовку расследования не архивирует" "$?" "2"

FIND="$PROJ2/ai/investigations/selector-flicker/findings.md"
python3 - "$FIND" <<'PY2'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
t = "\n".join(l for l in p.read_text().splitlines() if "fraim:stub" not in l)
p.write_text(t + "\n")
PY2
"$FRAIM" investigate-seal selector-flicker >/dev/null 2>&1
check "гейт: без исхода не архивирует" "$?" "2"

python3 - "$FIND" <<'PY2'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
t = t.replace("<root cause, plainly. Route: reactive fix (surgical) | /make-task (structural) | /revise-task | /prune.>",
              "The selector is rebuilt on every render; the observer attaches to the old node.")
p.write_text(t)
PY2
"$FRAIM" investigate-seal selector-flicker >/dev/null 2>&1
check "гейт: без отчёта об уборке не архивирует" "$?" "2"

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
"$FRAIM" investigate-seal selector-flicker >/dev/null 2>&1
check "investigate-seal архивирует расследование с исходом" "$?" "0"
check "расследование в архиве" \
    "$(find "$PROJ2/ai/archive" -maxdepth 1 -name '*_investigate_selector-flicker' | wc -l | tr -d ' ')" "1"
check "архивация расследования закоммичена" \
    "$(git -C "$PROJ2" log --oneline -1 --format=%s)" "archive: investigate selector-flicker"

# --- сторож видит незапечатанное -------------------------------------------
"$FRAIM" task-new unsealed-one >/dev/null 2>&1
"$FRAIM" task-result unsealed-one >/dev/null 2>&1
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "сторож замечает незапечатанную задачу" "$?" "1"
check "вердикт зовёт task-seal" "$("$FRAIM" status "$PROJ2" 2>/dev/null | grep -c 'не запечатана')" "1"
rm -rf "$PROJ2/ai/tasks/unsealed-one"

"$FRAIM" investigate-new open-one >/dev/null 2>&1
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "расследование в работе не поднимает тревогу" "$?" "0"
rm -rf "$PROJ2/ai/investigations/open-one"

# --- fraim commit -----------------------------------------------------------
"$FRAIM" commit test "нет путей" >/dev/null 2>&1
check "commit без путей отказывает" "$?" "2"
"$FRAIM" commit BAD "вид не тот" README.md >/dev/null 2>&1
check "commit проверяет вид" "$?" "2"
printf 'x\n' >> "$PROJ2/README.md"
"$FRAIM" commit task "точка сохранения" README.md >/dev/null 2>&1
check "commit ставит точку сохранения" "$(git -C "$PROJ2" log --oneline -1 --format=%s)" "task: точка сохранения"

# --- undo / restore ---------------------------------------------------------
# Обещание «работай смело, точка сохранения есть» пустое, если вернуться к ней можно
# только через git reset. Отмена — встречный коммит: историю не переписываем.
printf 'undo-me\n' >> "$PROJ2/README.md"
"$FRAIM" commit task "правка, которую отменим" README.md >/dev/null 2>&1
UNDO_REF=$(git -C "$PROJ2" rev-parse --short HEAD)
"$FRAIM" undo >/dev/null 2>&1
check "undo без аргумента показывает, а не делает" \
    "$(git -C "$PROJ2" rev-parse --short HEAD)" "$UNDO_REF"
check "undo перечисляет наши точки" "$("$FRAIM" undo 2>/dev/null | grep -c "$UNDO_REF")" "1"

"$FRAIM" undo "$UNDO_REF" >/dev/null 2>&1
check "undo отменил правку" "$(grep -c 'undo-me' "$PROJ2/README.md")" "0"
check "история не переписана — добавлен встречный коммит" \
    "$(git -C "$PROJ2" cat-file -e "$UNDO_REF^{commit}" 2>/dev/null; echo $?)" "0"

# Чужой коммит не отменяем никогда — в чужом репозитории это разница между
# инструментом и происшествием.
printf 'theirs\n' >> "$PROJ2/main.py"
git -C "$PROJ2" commit -qam "их собственный коммит" >/dev/null 2>&1
"$FRAIM" undo "$(git -C "$PROJ2" rev-parse --short HEAD)" >/dev/null 2>&1
check "чужой коммит не отменяется" "$?" "2"

# Отказ, когда файлы самой точки сейчас правятся: отмену не с чем свести.
printf 'again\n' >> "$PROJ2/README.md"
"$FRAIM" commit task "вторая правка" README.md >/dev/null 2>&1
UNDO_REF2=$(git -C "$PROJ2" rev-parse --short HEAD)
printf 'dirty\n' >> "$PROJ2/README.md"
"$FRAIM" undo "$UNDO_REF2" >/dev/null 2>&1
check "undo отказывается, если файлы точки сейчас изменены" "$?" "2"
git -C "$PROJ2" checkout -- README.md >/dev/null 2>&1
"$FRAIM" undo "$UNDO_REF2" >/dev/null 2>&1
check "после сохранения правок отмена проходит" "$?" "0"

# restore — рабочее дерево, по именованным путям. `git restore .` унёс бы вместе с
# нашим мусором незаконченную работу человека; именно поэтому /investigate раньше
# требовал чистого дерева и перекладывал git-задачу на пользователя.
printf 'mine, unsaved\n' >> "$PROJ2/main.py"
printf 'scratch\n' > "$PROJ2/scratch-probe.py"
printf 'CHANGED\n' >> "$PROJ2/README.md"
"$FRAIM" restore README.md scratch-probe.py >/dev/null 2>&1
check "restore вернул отслеживаемый файл" "$(grep -c 'CHANGED' "$PROJ2/README.md")" "0"
check "restore удалил созданное" "$([ -e "$PROJ2/scratch-probe.py" ] && echo yes || echo no)" "no"
check "restore не тронул чужую незаконченную работу" "$(grep -c 'mine, unsaved' "$PROJ2/main.py")" "1"
git -C "$PROJ2" checkout -- main.py >/dev/null 2>&1

"$FRAIM" restore >/dev/null 2>&1
check "restore без путей отказывает" "$?" "2"
"$FRAIM" restore . >/dev/null 2>&1
check "restore «всё» отказывает" "$?" "2"
"$FRAIM" restore ../outside >/dev/null 2>&1
check "restore за пределы проекта отказывает" "$?" "2"

# Сторож видит несохранённое — но только то, что глаголы сохраняют сами.
printf 'edited by hand\n' >> "$PROJ2/ARCHITECTURE.md"
"$FRAIM" status "$PROJ2" 2>/dev/null | grep -q 'после последней точки сохранения'
check "сторож видит несохранённый фундамент" "$?" "0"
git -C "$PROJ2" checkout -- ARCHITECTURE.md >/dev/null 2>&1
printf 'work in progress\n' >> "$PROJ2/main.py"
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "незакоммиченный код человека тревогу не поднимает" "$?" "0"
git -C "$PROJ2" checkout -- main.py >/dev/null 2>&1

# commit_verbs = off must actually stop the commits.
"$FRAIM" config set commit_verbs off >/dev/null 2>&1
BEFORE_N=$(git -C "$PROJ2" rev-list --count HEAD)
printf 'more\n' >> "$PROJ2/src/a.py"; "$FRAIM" commit fix "another" src/a.py >/dev/null 2>&1
check "commit_verbs = off отключает коммит" "$(git -C "$PROJ2" rev-list --count HEAD)" "$BEFORE_N"
"$FRAIM" config set commit_verbs on >/dev/null 2>&1

cd "$REPO" || exit 1

# --- decide / pitfall: запись в фундамент ------------------------------------
cd "$PROJ2" || exit 1

printf 'Decision: sqlite in WAL mode.\n' | "$FRAIM" decide "storage engine" >/dev/null 2>&1
check "decide дописал запись" "$(grep -c '^## 20.* — storage engine$' "$PROJ2/DECISIONS.md")" "1"
check "decide снял маркер заглушки" "$(grep -c 'fraim:stub' "$PROJ2/DECISIONS.md")" "0"

printf 'Decision: retry with jitter.\n' | "$FRAIM" decide "retries" >/dev/null 2>&1
check "новое решение легло сверху" \
      "$(grep -m1 '^## 20' "$PROJ2/DECISIONS.md" | sed 's/.*— //')" "retries"
check "старое решение осталось" "$(grep -c '— storage engine$' "$PROJ2/DECISIONS.md")" "1"

printf 'Decision: postgres after all.\n' |
    "$FRAIM" decide "storage engine, take two" --supersedes "storage engine" >/dev/null 2>&1
check "supersede записан, старое не удалено" \
      "$(grep -c '^> Supersedes: storage engine$' "$PROJ2/DECISIONS.md")$(grep -c '— storage engine$' "$PROJ2/DECISIONS.md")" "11"

"$FRAIM" decide "empty" </dev/null >/dev/null 2>&1
check "decide отвергает пустое тело" "$?" "2"
check "decide не коммитит сам" \
      "$(git -C "$PROJ2" log --oneline -1 --format=%s | grep -c '^decide')" "0"

# Ранние тесты затёрли фундамент болванкой без разделов — сначала проверим, что
# глагол на такой файл честно отказывается, а не дописывает в пустоту.
"$FRAIM" pitfall "nowhere to put this" >/dev/null 2>&1
check "pitfall отказывается без раздела Known Pitfalls" "$?" "2"
cp "$REPO/installer/templates/foundation/CONVENTIONS.md" "$PROJ2/CONVENTIONS.md"

"$FRAIM" pitfall "S3 client truncates keys over 1024 bytes." >/dev/null 2>&1
check "pitfall дописал строку в свой раздел" \
      "$(sed -n '/^## Known Pitfalls/,$p' "$PROJ2/CONVENTIONS.md" | grep -c 'S3 client truncates')" "1"
check "заглушка «None yet» убрана" "$(grep -c '^- None yet\.$' "$PROJ2/CONVENTIONS.md")" "0"
"$FRAIM" pitfall "Tests fail unless TZ=UTC." >/dev/null 2>&1
check "вторая строка легла следом" \
      "$(sed -n '/^## Known Pitfalls/,$p' "$PROJ2/CONVENTIONS.md" | grep -c '^- ')" "2"

# --- plan-seal: четвёртая дверь ---------------------------------------------
"$FRAIM" task-new add-cache >/dev/null 2>&1
"$FRAIM" plan-seal add-cache >/dev/null 2>&1
check "гейт плана: заготовку не выпускает" "$?" "2"

python3 - "$PROJ2/ai/tasks/add-cache" <<'PYFILL'
import pathlib, sys
d = pathlib.Path(sys.argv[1])
ctx = {'Goal': 'Cache price lookups for 60 seconds.',
       'Why': 'The upstream is slow and rate limited.',
       'Codebase Context': '- `app.py` — entry point, holds the price call',
       'Constraints': '- Do NOT modify: `DECISIONS.md`',
       'Decisions and Rationale': 'In-process TTL cache, not Redis: a service for 60 seconds does not pay.',
       'Known Pitfalls': 'None known.',
       'Out of Scope': 'Event-based invalidation.'}
task = {'Summary': 'TTL cache around get_price().',
        'Files to Change': '### `app.py`\n- **Action:** modify\n- **Must be true after:** get_price() serves from cache while the entry is under 60s old\n- **Pattern reference:** n/a',
        'Step-by-step Implementation': '1. Add the cache dict next to get_price() in `app.py`.',
        'Acceptance Criteria': '- [ ] Two calls in a row make one network request',
        'Verification Commands': '```bash\npython3 -c "import sys"\n```',
        'Foundation updates': "- `ARCHITECTURE.md`: no structural change",
        'Executor Rules': '- Follow the plan literally.'}
for name, fill in (('context.md', ctx), ('task.md', task)):
    p = d / name
    out = []
    for line in p.read_text().splitlines():
        if 'fraim:stub' in line:
            continue
        out.append(line)
        head = line[3:].strip() if line.startswith('## ') else None
        if head:
            for k, v in fill.items():
                if head.startswith(k):
                    out.append(v)
                    break
    p.write_text('\n'.join(out) + '\n')
PYFILL

"$FRAIM" plan-seal add-cache >/dev/null 2>&1
check "гейт плана: заполненный план проходит" "$?" "0"
check "план сохранён точкой" "$(git -C "$PROJ2" log --oneline -1 --format=%s)" "plan: add-cache — план готов к исполнению"

printf 'Как мы обсуждали, TTL держим на 60.\n' >> "$PROJ2/ai/tasks/add-cache/context.md"
"$FRAIM" plan-seal add-cache >/dev/null 2>&1
check "гейт плана: отсылку к разговору не пропускает" "$?" "2"
python3 - "$PROJ2/ai/tasks/add-cache/context.md" <<'PYCUT'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_text("".join(l for l in p.read_text().splitlines(True) if "обсуждали" not in l))
PYCUT

python3 - "$PROJ2/ai/tasks/add-cache/context.md" <<'PYBAD'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace('`app.py` — entry point', '`src/pricing.py` — entry point'))
PYBAD
"$FRAIM" plan-seal add-cache >/dev/null 2>&1
check "гейт плана: несуществующий путь не пропускает" "$?" "2"
python3 - "$PROJ2/ai/tasks/add-cache/context.md" <<'PYFIX'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace('`src/pricing.py` — entry point', '`app.py` — entry point'))
PYFIX

python3 - "$PROJ2/ai/tasks/add-cache/task.md" <<'PYEMPTY'
import pathlib, sys, re
p = pathlib.Path(sys.argv[1])
t = p.read_text()
t = re.sub(r'## Verification Commands\n.*?\n## ', '## Verification Commands\n\n## ', t, flags=re.S)
p.write_text(t)
PYEMPTY
"$FRAIM" plan-seal add-cache >/dev/null 2>&1
check "гейт плана: пустую проверку не пропускает" "$?" "2"

rm -rf "$PROJ2/ai/tasks/add-cache"

# ---------------------------------------------------------------- version
printf '\nfraim version (что именно стоит)\n'

# Номер версии не отвечает на вопрос «приехало ли обновление»: между релизами ветка
# уезжает на десяток коммитов, а номер стоит на месте. Поэтому команда обязана называть
# ещё и источник — иначе после git pull остаётся только гадать.
VOUT=$("$FRAIM" version 2>&1)
check "version печатает номер первой строкой" \
      "$(printf '%s' "$VOUT" | head -1)" "$(cat "$REPO/installer/VERSION")"
check "version называет ветку и коммит" "$(printf '%s' "$VOUT" | grep -c 'коммит')" "1"
# fraim_version при этом остаётся однострочной: её вывод уезжает в штампы провенанса и
# во фронтматтер скиллов, и лишняя строка там сломала бы обе проверки протухания.
STAMP=$(sh -c '. "'"$REPO"'/installer/lib/core.sh"; fraim_version' 2>/dev/null)
check "fraim_version осталась одной строкой" "$(printf '%s' "$STAMP" | wc -l | tr -d ' ')" "0"

# ---------------------------------------------------------------- clean
printf '\nfraim clean (чистка)\n'

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

# исполненная задача с честным отчётом — гейт её пропустит
"$FRAIM" task-new done-task >/dev/null 2>&1
printf '# Result\n\n## Status\ncomplete\n\n## Foundation updated\n- ARCHITECTURE.md: no structural change\n' \
    > "$CL/ai/tasks/done-task/result.md"
# исполненная задача без отчёта о фундаменте — гейт обязан отказать и в чистке
"$FRAIM" task-new bad-task >/dev/null 2>&1
printf '# Result\n\n## Status\ncomplete\n' > "$CL/ai/tasks/bad-task/result.md"
# протухший план — чистка НЕ должна его трогать
"$FRAIM" task-new stale-plan >/dev/null 2>&1
for i in 1 2 3; do
    printf 'c%s\n' "$i" >> "$CL/app.py"
    git -C "$CL" add app.py >/dev/null; git -C "$CL" commit -qm "fix: c$i" >/dev/null
done
# брошенное расследование и доведённое до исхода
"$FRAIM" investigate-new abandoned-one >/dev/null 2>&1
touch -d '40 days ago' "$CL/ai/investigations/abandoned-one/findings.md" 2>/dev/null ||
    touch -t "$(date -v-40d +%Y%m%d0000 2>/dev/null || echo 202001010000)" \
        "$CL/ai/investigations/abandoned-one/findings.md"
# папка расследования без findings.md — ни исхода, ни отчёта; была невидима обоим
mkdir -p "$CL/ai/investigations/no-report"
printf 'заметки на коленке\n' > "$CL/ai/investigations/no-report/notes.md"
touch -d '40 days ago' "$CL/ai/investigations/no-report/notes.md" "$CL/ai/investigations/no-report" 2>/dev/null ||
    touch -t "$(date -v-40d +%Y%m%d0000 2>/dev/null || echo 202001010000)" \
        "$CL/ai/investigations/no-report/notes.md" "$CL/ai/investigations/no-report"
# и такая же папка, но свежая: её трогать нельзя — это работа, которая идёт
mkdir -p "$CL/ai/investigations/fresh-no-report"
printf 'начали сегодня\n' > "$CL/ai/investigations/fresh-no-report/notes.md"
"$FRAIM" investigate-new solved-one >/dev/null 2>&1
python3 - "$CL/ai/investigations/solved-one/findings.md" <<'PYSOLVE'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
t = t.replace('<the ONE unclear thing, as a question that can be answered>', 'why the counter lies')
t = t.replace('<root cause, plainly. Route: reactive fix (surgical) | /make-task (structural) | /revise-task | /prune.>',
              'it counted folders, not runnable tasks')
t = t.replace('<what was ruled out, where exactly you got stuck, what the human must decide or provide.>', '')
t = t.replace('<repo: what `git status` shows — and world: what was undone, counted against the baseline above>',
              'repo: clean; world: untouched')
t = '\n'.join(l for l in t.splitlines() if 'fraim:stub' not in l)
p.write_text(t + '\n')
PYSOLVE

# Под пайпом без --yes чистка обязана только показать план: «сама всё сделает» не значит
# «без спроса», а ратификация не исчезает оттого, что действий стало много (B5).
PLAN=$("$FRAIM" clean </dev/null 2>&1)
check "clean без --yes ничего не делает" "$([ -d "$CL/ai/investigations/abandoned-one" ] && echo yes || echo no)" "yes"
check "clean показывает план" "$(printf '%s' "$PLAN" | grep -c 'Чистка сделает')" "1"
check "план включает фундамент" "$(printf '%s' "$PLAN" | grep -c 'до стандарта')" "1"
check "план включает брошенное расследование" "$(printf '%s' "$PLAN" | grep -c 'abandoned-one')" "1"
check "план включает доведённое расследование" "$(printf '%s' "$PLAN" | grep -c 'solved-one')" "1"
# Папка без findings.md переживала любое число чисток молча: обход шёл по файлу, а не
# по папке. Теперь её видит и сторож, и чистка — но только когда она действительно
# перестала двигаться, иначе чистка уносила бы в архив работу, которая идёт.
check "план включает папку без findings.md" "$(printf '%s' "$PLAN" | grep -c 'no-report')" "1"
check "план НЕ трогает свежую папку без findings.md" \
      "$(printf '%s' "$PLAN" | grep -c 'fresh-no-report')" "0"
check "сторож называет папку без findings.md" \
      "$("$FRAIM" status "$CL" 2>/dev/null | grep -c 'без findings.md')" "2"
check "план включает незапечатанную задачу" "$(printf '%s' "$PLAN" | grep -c 'done-task')" "1"
check "план НЕ трогает протухший план" "$(printf '%s' "$PLAN" | grep -c 'stale-plan')" "0"

OUT=$("$FRAIM" clean --yes </dev/null 2>&1)
check "clean --yes отработал" "$(printf '%s' "$OUT" | grep -c 'сделано:')" "1"
check "фундамент доведён до стандарта" "$(grep -c '^## Known Pitfalls / Lessons$' "$CL/CONVENTIONS.md")" "1"
check "доведённое расследование заархивировано" \
      "$(find "$CL/ai/archive" -maxdepth 1 -name '*investigate_solved-one' | wc -l | tr -d ' ')" "1"
check "брошенное расследование заархивировано" \
      "$(find "$CL/ai/archive" -maxdepth 1 -name '*investigate_abandoned-one' | wc -l | tr -d ' ')" "1"
# Архив обязан говорить правду: не «сделано», а «брошено, исхода нет, уборка не проверялась».
check "в архиве записано, что расследование брошено" \
      "$(cat "$CL"/ai/archive/*investigate_abandoned-one/findings.md | grep -c '^## Abandoned$')" "1"
check "и что уборка не проверялась" \
      "$(cat "$CL"/ai/archive/*investigate_abandoned-one/findings.md | grep -c 'Уборка не проверялась')" "1"
check "исполненная задача запечатана" "$([ -d "$CL/ai/tasks/done-task" ] && echo yes || echo no)" "no"
# Гейт остаётся гейтом внутри чистки: задача без отчёта о фундаменте не уезжает в архив.
check "задача без отчёта о фундаменте осталась" "$([ -d "$CL/ai/tasks/bad-task" ] && echo yes || echo no)" "yes"
check "папка без findings.md заархивирована" \
      "$(find "$CL/ai/archive" -maxdepth 1 -name '*investigate_no-report' | wc -l | tr -d ' ')" "1"
check "и получила отчёт, а не уехала в архив молча" \
      "$(cat "$CL"/ai/archive/*investigate_no-report/findings.md 2>/dev/null | grep -c '^## Abandoned$')" "1"
check "свежая папка без findings.md не тронута" \
      "$([ -d "$CL/ai/investigations/fresh-no-report" ] && echo yes || echo no)" "yes"
# Хвост чистки называет, ЧТО осталось и ПОЧЕМУ. Раньше в конце стояло одно число, а
# причина отказа уезжала вверх экрана посреди списка — человек видел папки на месте и
# ни одного слова о том, что от него требуется.
check "чистка честно сказала, что осталось" "$(printf '%s' "$OUT" | grep -c 'Осталось требующего тебя')" "1"
check "хвост называет оставшееся по имени" "$(printf '%s' "$OUT" | tail -6 | grep -c 'bad-task')" "1"
check "хвост называет причину отказа" "$(printf '%s' "$OUT" | tail -6 | grep -c 'Foundation updated')" "1"
check "протухший план не тронут" "$([ -d "$CL/ai/tasks/stale-plan" ] && echo yes || echo no)" "yes"

# Повторный заход не должен находить работу там, где её уже нет.
PLAN2=$("$FRAIM" clean </dev/null 2>&1)
check "повторная чистка не предлагает сделанное" "$(printf '%s' "$PLAN2" | grep -c 'solved-one')" "0"
cd "$SANDBOX" || exit 1

# ------------------------------------------------- стандарт фундамента и upgrade
printf '\nсоответствие стандарту (shape) и fraim upgrade\n'

# Проект «старой версии»: фундамент есть, но заведён до AGENTS.md/CLAUDE.md, до
# ai/fraim.conf и до раздела Known Pitfalls. Ни одна прежняя проверка на нём не
# срабатывала — сторож говорил «всё чисто», а fraim pitfall при этом отказывался.
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
check "сторож видит отставание от стандарта" "$(printf '%s' "$OUT" | grep -c 'отстал от стандарта')" "1"
check "названы AGENTS.md и CLAUDE.md" \
      "$(printf '%s' "$OUT" | grep -c 'AGENTS.md')$(printf '%s' "$OUT" | grep -c 'CLAUDE.md')" "11"
check "назван недостающий раздел" "$(printf '%s' "$OUT" | grep -c 'Known-Pitfalls')" "1"

cd "$OLD" || exit 1
"$FRAIM" pitfall "verb has nowhere to write" >/dev/null 2>&1
check "до upgrade глагол pitfall отказывает" "$?" "2"

"$FRAIM" upgrade >/dev/null 2>&1
check "upgrade завершился успешно" "$?" "0"
check "upgrade завёл AGENTS.md с блоком" "$(grep -c 'fraim:begin' "$OLD/AGENTS.md")" "1"
check "upgrade завёл CLAUDE.md с указателем" "$(grep -c 'AGENTS.md' "$OLD/CLAUDE.md")" "2"
check "upgrade дописал раздел Known Pitfalls" "$(grep -c '^## Known Pitfalls / Lessons$' "$OLD/CONVENTIONS.md")" "1"
check "содержимое старого файла не тронуто" "$(grep -c '^rules$' "$OLD/CONVENTIONS.md")" "1"
"$FRAIM" pitfall "now it lands" >/dev/null 2>&1
check "после upgrade глагол pitfall работает" "$?" "0"
"$FRAIM" status "$OLD" >/dev/null 2>&1
check "после upgrade проверка стандарта молчит" "$("$FRAIM" status "$OLD" 2>/dev/null | grep -c 'отстал от стандарта')" "0"
"$FRAIM" upgrade >/dev/null 2>&1
check "upgrade идемпотентен" "$("$FRAIM" status "$OLD" 2>/dev/null | grep -c 'отстал от стандарта')" "0"

# --- очередь и фундамент как данные -----------------------------------------
QP="$SANDBOX/queueproj"
mkdir -p "$QP"
git -C "$QP" init -q; git -C "$QP" config user.email t@t; git -C "$QP" config user.name t
cd "$QP" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
"$FRAIM" task-new blocked-one >/dev/null 2>&1; "$FRAIM" task-block blocked-one >/dev/null 2>&1
"$FRAIM" task-new done-one    >/dev/null 2>&1; "$FRAIM" task-result done-one >/dev/null 2>&1
"$FRAIM" task-new ready-one   >/dev/null 2>&1
J=$("$FRAIM" status --json 2>/dev/null)

check "json: состояние каждой задачи" \
      "$(printf '%s' "$J" | grep -c '"slug": "blocked-one", "state": "blocked"')$(printf '%s' "$J" | grep -c '"slug": "done-one", "state": "done"')$(printf '%s' "$J" | grep -c '"slug": "ready-one", "state": "runnable"')" "111"
# Раньше счётчик считал папки: три задачи, из которых исполнима одна, читались как
# «3 задачи в очереди → /run-task». Это была неправда в самом читаемом месте вывода.
check "счётчик считает исполнимые, а не папки" \
      "$(printf '%s' "$J" | grep -c '1 задача готова к исполнению')" "1"
check "json: заглушка отличима от заполненного" \
      "$(printf '%s' "$J" | grep -c '"ARCHITECTURE.md": "stub"')" "1"
check "json: отсутствующий файл виден как missing" \
      "$(printf '%s' "$J" | grep -c '"STACK.md": "missing"')" "1"

# Пустое состояние не должно ронять сторожа: grep -c на нуле совпадений возвращает 1,
# и под set -e это тихо убивало весь прогон.
EMPTY="$SANDBOX/emptyq"
mkdir -p "$EMPTY"; cd "$EMPTY" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
check "сторож не умирает на пустой очереди" "$("$FRAIM" status "$EMPTY" 2>/dev/null | grep -c 'скелет развёрнут')" "1"

cd "$PROJ2" || exit 1

# ---------------------------------------------------------------- publish
printf '\nfraim publish (копия вне машины)\n'

# Всё здесь работает без сети и без gh: «хостом» служит локальный bare-репозиторий.
# Это не упрощение ради теста — это тот же путь, которым идёт --url, то есть пол,
# на который падает любой провайдер, когда его CLI нет или он повёл себя не так.
PUB="$SANDBOX/pub"
mkdir -p "$PUB"
cd "$PUB" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
printf 'print(1)\n' > app.py
git -C "$PUB" add app.py >/dev/null; git -C "$PUB" commit -qm "feat: app" >/dev/null

OUT=$("$FRAIM" publish --check 2>&1); RC=$?
check "check на чистом проекте проходит" "$RC" "0"
check "check говорит, что копии нет" "$(printf '%s' "$OUT" | grep -c 'Копии вне этой машины нет')" "1"
check "check перечисляет, чем можно опубликовать" \
      "$(printf '%s' "$OUT" | grep -c 'Чем можно опубликовать')" "1"
check "отсутствующий CLI объясняется, а не просто отмечается" \
      "$(printf '%s' "$OUT" | grep -c 'gh auth login')" "1"

# Ратификация. Под пайпом без --yes команда обязана напечатать план и НЕ ТРОНУТЬ ничего:
# это тот же контракт, что у `fraim clean`, и проверяется он по состоянию, а не по тексту.
git init -q --bare "$SANDBOX/pub-remote.git"
OUT=$("$FRAIM" publish --url "$SANDBOX/pub-remote.git" 2>&1)
check "план без --yes ничего не отправляет" "$(git -C "$PUB" remote | wc -l | tr -d ' ')" "0"
check "план называет, что уедет" "$(printf '%s' "$OUT" | grep -c 'что едет')" "1"

OUT=$("$FRAIM" publish --url "$SANDBOX/pub-remote.git" --yes 2>&1); RC=$?
check "публикация с --yes проходит" "$RC" "0"
check "ремоут прописан" "$(git -C "$PUB" remote get-url origin)" "$SANDBOX/pub-remote.git"
check "сверка с хостом сошлась" "$(printf '%s' "$OUT" | grep -c 'на хосте лежит ровно то')" "1"
check "на хосте та же точка" \
      "$(git -C "$SANDBOX/pub-remote.git" rev-parse HEAD)" "$(git -C "$PUB" rev-parse HEAD)"

OUT=$("$FRAIM" publish 2>&1)
check "повторный запуск ничего не делает" \
      "$(printf '%s' "$OUT" | grep -c 'совпадает с этой машиной')" "1"

printf 'print(2)\n' >> app.py
git -C "$PUB" commit -qam "fix: more" >/dev/null
"$FRAIM" publish --yes >/dev/null 2>&1
check "следующая точка уезжает той же командой" \
      "$(git -C "$SANDBOX/pub-remote.git" rev-parse HEAD)" "$(git -C "$PUB" rev-parse HEAD)"

# --- проверка безопасности --------------------------------------------------
# Главное свойство: она смотрит на то, что УЕДЕТ, а не на то, что лежит в папке.
# Файл, удалённый из дерева, остаётся в паке и уезжает с первым же push.
PUBS="$SANDBOX/pubsec"
mkdir -p "$PUBS"
cd "$PUBS" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
printf 'DB_PASSWORD=hunter2\n' > .env
git -C "$PUBS" add -f .env >/dev/null; git -C "$PUBS" commit -qm "oops" >/dev/null
git -C "$PUBS" rm -q --cached .env >/dev/null; git -C "$PUBS" commit -qm "убрал" >/dev/null

OUT=$("$FRAIM" publish --check 2>&1); RC=$?
check "секрет, стёртый из дерева, но живой в истории — найден" \
      "$(printf '%s' "$OUT" | grep -c '\.env')" "1"
check "находка в истории роняет код возврата" "$RC" "1"

OUT=$("$FRAIM" publish --url "$SANDBOX/pub-remote2.git" --yes 2>&1); RC=$?
check "гейт останавливает публикацию" "$RC" "2"
check "ремоут при отказе не прописан" "$(git -C "$PUBS" remote | wc -l | tr -d ' ')" "0"
check "отказ называет обход" "$(printf '%s' "$OUT" | grep -c 'находка ложная')" "1"
# Отказ отдаёт готовое задание, а не совет: «убери файл из истории» — это просьба об
# экспертизе, которой у пользователя может не быть.
check "отказ печатает задание агенту" \
      "$(printf '%s' "$OUT" | grep -c 'Отдай это агенту')" "1"
check "задание самодостаточно: в нём путь проекта" \
      "$(printf '%s' "$OUT" | grep -c "Проект: $PUBS")" "1"
check "задание называет найденное поимённо" "$(printf '%s' "$OUT" | grep -c '  - \.env')" "1"
check "задание ставит границы агенту" "$(printf '%s' "$OUT" | grep -c 'Границы:')" "1"
check "задание не советует переписывать историю молча" \
      "$(printf '%s' "$OUT" | grep -c 'Не запускай без моего')" "1"

git init -q --bare "$SANDBOX/pub-remote2.git"
OUT=$("$FRAIM" publish --url "$SANDBOX/pub-remote2.git" --yes --force 2>&1); RC=$?
check "--force проходит и говорит, что делает" "$RC" "0"
check "--force называет необратимость" "$(printf '%s' "$OUT" | grep -c 'необратимо')" "1"

# Значение ключа не должно попасть в вывод: он уедет в скроллбек, в лог сессии агента
# и в чужой чат. Сканер печатает файл и строку, и на этом останавливается.
PUBT="$SANDBOX/pubtok"
mkdir -p "$PUBT"
cd "$PUBT" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
printf 'TOKEN = "ghp_abcdefghijklmnopqrstuvwxyz0123456789"\n' > conf.py
head -c 6000000 /dev/urandom > big.bin 2>/dev/null
mkdir -p node_modules/pkg; printf '1\n' > node_modules/pkg/index.js
git -C "$PUBT" add -A -f >/dev/null; git -C "$PUBT" commit -qm "feat: conf" >/dev/null
OUT=$("$FRAIM" publish --check 2>&1)
check "токен в файле найден по форме" "$(printf '%s' "$OUT" | grep -c 'conf.py:1')" "1"
check "само значение ключа не печатается" \
      "$(printf '%s' "$OUT" | grep -c 'ghp_abcdefghijklmnopqrstuvwxyz')" "0"
check "тяжёлый файл — предупреждение, а не отказ" "$(printf '%s' "$OUT" | grep -c 'МБ в истории')" "1"
check "зависимости в истории свёрнуты в один каталог" \
      "$(printf '%s' "$OUT" | grep -c 'node_modules/ ')" "1"

# --- рассинхрон с хостом ----------------------------------------------------
# Локальная бухгалтерия («уехало / не уехало») — это память ЭТОЙ машины о прошлых
# отправках. Она врёт ровно там, где ошибка дороже всего: репозиторий создан и пуст,
# ветку на хосте снесли, историю туда положили из другого места. Поэтому publish
# спрашивает хост, а не свои refs — три случая ниже проверяют каждую из этих форм.
PUBH="$SANDBOX/pubhost"
mkdir -p "$PUBH"
cd "$PUBH" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
printf 'print(1)\n' > app.py
git -C "$PUBH" add app.py >/dev/null; git -C "$PUBH" commit -qm "feat: app" >/dev/null

# 1. Создан, но пуст: адрес прописан руками, история туда не доехала. Снаружи копия
#    выглядит существующей — это худшее из состояний, и молчать о нём нельзя.
git init -q --bare "$SANDBOX/pub-host.git"
git -C "$PUBH" remote add origin "$SANDBOX/pub-host.git"
"$FRAIM" status "$PUBH" 2>/dev/null | grep -q 'ни разу ничего не уезжало'
check "сторож видит недоведённую настройку без сети" "$?" "0"

OUT=$("$FRAIM" publish 2>&1)
check "publish называет пустой репозиторий на хосте" \
      "$(printf '%s' "$OUT" | grep -c 'ПУСТ')" "1"
# Состояние хоста живёт в плане одной строкой и больше нигде: второй раз то же самое
# сверху — шум, а шум учат пролистывать.
check "состояние хоста сказано ровно один раз" \
      "$(printf '%s' "$OUT" | grep -c 'история туда не доехала')" "1"
"$FRAIM" publish --yes >/dev/null 2>&1
check "та же команда доводит работу до конца" \
      "$(git -C "$SANDBOX/pub-host.git" rev-parse HEAD)" "$(git -C "$PUBH" rev-parse HEAD)"

# 2. Ветку на хосте снесли, а refs/remotes здесь остались. По записям этой машины «всё
#    уехало» — и это ровно то враньё, ради которого сверка и существует.
BR=$(git -C "$PUBH" rev-parse --abbrev-ref HEAD)
git -C "$SANDBOX/pub-host.git" update-ref -d "refs/heads/$BR"
check "локальные записи всё ещё говорят «уехало»" \
      "$(git -C "$PUBH" rev-list --count HEAD --not --remotes)" "0"
OUT=$("$FRAIM" publish 2>&1)
check "publish не верит своим записям против хоста" \
      "$(printf '%s' "$OUT" | grep -c 'совпадает с этой машиной')" "0"
"$FRAIM" publish --yes >/dev/null 2>&1
check "копия восстановлена" \
      "$(git -C "$SANDBOX/pub-host.git" rev-parse HEAD)" "$(git -C "$PUBH" rev-parse HEAD)"

# 3. На хосте появилась работа, которой здесь нет. Единственный способ «свести одной
#    кнопкой» — затереть чужое, поэтому команда обязана остановиться и отдать задание.
OTHER="$SANDBOX/pubother"
git clone -q "$SANDBOX/pub-host.git" "$OTHER"
git -C "$OTHER" config user.email t@t; git -C "$OTHER" config user.name t
printf 'from another machine\n' > "$OTHER/other.py"
git -C "$OTHER" add other.py >/dev/null; git -C "$OTHER" commit -qm "feat: other" >/dev/null
git -C "$OTHER" push -q origin HEAD >/dev/null 2>&1
printf 'print(2)\n' >> "$PUBH/app.py"
git -C "$PUBH" commit -qam "fix: local" >/dev/null

OUT=$("$FRAIM" publish --yes 2>&1); RC=$?
check "расхождение останавливает отправку" "$RC" "2"
check "на хосте ничего не затёрто" \
      "$(git -C "$SANDBOX/pub-host.git" log --oneline | grep -c 'feat: other')" "1"
check "расхождение объяснено, а не названо ошибкой" \
      "$(printf '%s' "$OUT" | grep -c 'работа, которой нет здесь')" "1"
check "расхождение отдаёт задание агенту" \
      "$(printf '%s' "$OUT" | grep -c 'свести расхождение')" "1"
check "задание запрещает force-push" "$(printf '%s' "$OUT" | grep -c 'force-push не предлагать')" "1"

# Провайдер, которого нет, отвечает инструкцией и полом — а не «нельзя». Проект здесь
# чистый нарочно: иначе до провайдера дело не дойдёт, его остановит гейт безопасности.
PUBP="$SANDBOX/pubprov"
mkdir -p "$PUBP"
cd "$PUBP" || exit 1
"$FRAIM" scaffold >/dev/null 2>&1
OUT=$("$FRAIM" publish --provider github --yes 2>&1); RC=$?
if command -v gh >/dev/null 2>&1; then
    check "github без gh: пропущено (gh установлен)" "skip" "skip"
else
    check "github без gh отказывает, не отправляя" "$(git -C "$PUBP" remote | wc -l | tr -d ' ')" "0"
    check "отказ показывает, как поставить gh" \
          "$(printf '%s' "$OUT" | grep -cE 'cli.github.com|install gh')" "1"
    check "отказ показывает пол: создать руками и дать ссылку" \
          "$(printf '%s' "$OUT" | grep -c 'publish --url')" "1"
fi
OUT=$("$FRAIM" publish --provider нетакого 2>&1); RC=$?
check "неизвестный провайдер отвергается" "$RC" "2"

cd "$SANDBOX" || exit 1

# Рельс: publish отправляет то, что уже сохранено, и ничего не сохраняет сам. Стоит
# появиться `git add` в этом модуле — и глагол начнёт решать, что забрать в историю,
# то есть ровно то, чего в системе не делает ни один глагол (B6).
ADDS=$(grep -vE '^[[:space:]]*#' "$REPO/installer/lib/publish.sh" |
       grep -cE 'git (-C [^ ]+ )?(add|commit)' || true)
check "publish ничего не коммитит сам" "$ADDS" "0"

# Сторож называет команду, а не голый git: пользователю обещано, что ни одна процедура
# не попросит его выполнить git-команду.
check "сторож зовёт fraim publish, а не git push" \
      "$(grep -c 'wm_add remote .*git push' "$REPO/installer/lib/watchman.sh" || true)" "0"

# ---------------------------------------------------------------- install.sh
printf '\ninstall.sh (обновление и смена ветки)\n'

# Клон делается с --depth 1 --branch, а это подразумевает --single-branch: refspec
# упоминает только main. Поэтому документированный способ проверить неслитую ветку —
# FRAIM_BRANCH=… sh install.sh — фетчил коммиты в FETCH_HEAD и падал на checkout
# «pathspec did not match» на каждой машине, где fraim уже стоял. Рельс держит именно
# этот путь: он документирован в README, значит он обязан работать.
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
check "install: первый клон встал на main" "$(sh "$IHOME/src/installer/bin/fraim")" "main"

FRAIM_HOME="$IHOME" FRAIM_REPO="file://$IREPO" FRAIM_BRANCH=try/unmerged FRAIM_BIN_DIR="$IHOME/bin" \
    sh "$REPO/installer/install.sh" >/dev/null 2>&1
check "install: переход на неслитую ветку" "$(sh "$IHOME/src/installer/bin/fraim")" "unmerged"

FRAIM_HOME="$IHOME" FRAIM_REPO="file://$IREPO" FRAIM_BRANCH=main FRAIM_BIN_DIR="$IHOME/bin" \
    sh "$REPO/installer/install.sh" >/dev/null 2>&1
check "install: возврат на main" "$(sh "$IHOME/src/installer/bin/fraim")" "main"

cd "$PROJ2" || exit 1

# ---------------------------------------------------------------- registry
printf '\nfraim projects (реестр)\n'

"$FRAIM" projects add "$PROJ" >/dev/null 2>&1
"$FRAIM" projects add "$PROJ" >/dev/null 2>&1
check "add идемпотентен" "$("$FRAIM" projects 2>/dev/null | grep -cx "  $PROJ")" "1"
"$FRAIM" projects rm "$PROJ" >/dev/null 2>&1
check "rm убирает запись" "$("$FRAIM" projects 2>/dev/null | grep -cx "  $PROJ")" "0"

# ---------------------------------------------------------------- init
printf '\nfraim init\n'

mkdir -p "$HOME/.codex" "$HOME/.claude"     # pretend two harnesses are installed
cd "$PROJ" || exit 1
"$FRAIM" init >/dev/null 2>&1
check "init завершился успешно" "$?" "0"
check "Codex: 13 скиллов" "$(find "$HOME/.codex/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')" "13"
check "Claude Code: 13 скиллов" "$(find "$HOME/.claude/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')" "13"
check "контекстный блок в ~/.codex/AGENTS.md" "$(grep -c 'fraim:begin' "$HOME/.codex/AGENTS.md" 2>/dev/null)" "1"
check "проект зарегистрирован" "$("$FRAIM" projects 2>/dev/null | grep -cx "  $PROJ")" "1"
check "разрешение Bash(fraim:*) прописано" "$(grep -c 'Bash(fraim' "$HOME/.claude/settings.json" 2>/dev/null)" "1"

# Idempotence is the whole update story: init is also update.
H1=$(find "$HOME/.codex/skills" -type f | sort | xargs md5sum | md5sum)
A1=$(md5sum < "$HOME/.codex/AGENTS.md")
"$FRAIM" init >/dev/null 2>&1
H2=$(find "$HOME/.codex/skills" -type f | sort | xargs md5sum | md5sum)
A2=$(md5sum < "$HOME/.codex/AGENTS.md")
check "повторный init не меняет скиллы" "$H1" "$H2"
check "повторный init не дублирует блок" "$A1" "$A2"

# A skill we own that vanished upstream must be swept; the user's own must not.
mkdir -p "$HOME/.codex/skills/obsolete" "$HOME/.codex/skills/mine"
printf -- '---\nname: obsolete\ndescription: "x"\nmetadata:\n  source: fraim\n---\n' > "$HOME/.codex/skills/obsolete/SKILL.md"
printf -- '---\nname: mine\ndescription: "x"\n---\n' > "$HOME/.codex/skills/mine/SKILL.md"
"$FRAIM" init >/dev/null 2>&1
check "устаревший наш скилл удалён" "$([ -d "$HOME/.codex/skills/obsolete" ] && echo yes || echo no)" "no"
check "чужой скилл не тронут" "$([ -d "$HOME/.codex/skills/mine" ] && echo yes || echo no)" "yes"

"$FRAIM" doctor >/dev/null 2>&1
check "doctor завершился успешно" "$?" "0"
"$FRAIM" show orient 2>/dev/null | head -1 | grep -q -- '---'
check "show печатает процедуру" "$?" "0"

printf '\n%s пройдено, %s провалено\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
