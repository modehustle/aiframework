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
