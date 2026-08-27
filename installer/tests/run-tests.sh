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
mkdir -p "$HOME"

# ---------------------------------------------------------------- procedures
printf '\nprocedures/\n'

N=$(ls "$REPO"/procedures/*.md | grep -v manifest | wc -l | tr -d ' ')
check "13 процедур на диске" "$N" "13"

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

# ---------------------------------------------------------------- build
printf '\nfraim build\n'

"$FRAIM" build >/dev/null 2>&1
check "build завершился успешно" "$?" "0"

PLUG="$REPO/installer/claude-plugin/skills"
check "плагин: 14 скиллов" "$(find "$PLUG" -name SKILL.md | wc -l | tr -d ' ')" "14"

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

# Drift: 5 hotfixes since the last prune marker is the default threshold.
printf -- '--- pruned 2026-01-01 ---\n' > "$PROJ/ai/hotfix_log.md"
i=1; while [ $i -le 4 ]; do printf -- '- 2026-08-01 10:00 — `a.py` — fix — behavior: no\n' >> "$PROJ/ai/hotfix_log.md"; i=$((i+1)); done
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "4 хотфикса (ниже порога) → exit 0" "$?" "0"
printf -- '- 2026-08-01 11:00 — `a.py` — fix — behavior: no\n' >> "$PROJ/ai/hotfix_log.md"
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "5 хотфиксов (порог) → exit 1" "$?" "1"
"$FRAIM" status "$PROJ" 2>/dev/null | grep -q '/prune'
check "вердикт указывает на /prune" "$?" "0"

# Entries logged BEFORE the marker are already reconciled and must not count.
printf -- '--- pruned 2026-08-02 ---\n' >> "$PROJ/ai/hotfix_log.md"
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "маркер прунинга сбрасывает счётчик → exit 0" "$?" "0"

# Per-project threshold override.
printf 'hotfix_threshold = 2\n' > "$PROJ/ai/fraim.conf"
printf -- '- 2026-08-03 10:00 — `a.py` — fix — behavior: no\n' >> "$PROJ/ai/hotfix_log.md"
printf -- '- 2026-08-03 11:00 — `a.py` — fix — behavior: no\n' >> "$PROJ/ai/hotfix_log.md"
"$FRAIM" status "$PROJ" >/dev/null 2>&1
check "порог из ai/fraim.conf соблюдается → exit 1" "$?" "1"
rm -f "$PROJ/ai/fraim.conf" "$PROJ/ai/hotfix_log.md"

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
         ai/README.md ai/hotfix_log.md ai/fraim.conf ai/archive/decisions_log.md; do
    [ -f "$PROJ2/$f" ] || MISSING="$MISSING $f"
done
for d in ai/tasks ai/archive ai/investigations; do
    [ -d "$PROJ2/$d" ] || MISSING="$MISSING $d/"
done
check "все файлы и папки скелета созданы" "${MISSING:-none}" "none"

check "имя проекта подставлено" "$(grep -c 'ARCHITECTURE — proj2' "$PROJ2/ARCHITECTURE.md")" "1"

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

# ---------------------------------------------------------------- config
printf '\nfraim config\n'

check "значение по умолчанию" "$("$FRAIM" config 2>/dev/null | grep hotfix_threshold | awk '{print $2}')" "5"
"$FRAIM" config set hotfix_threshold 3 >/dev/null 2>&1
check "проектная настройка записана" "$(grep -c 'hotfix_threshold = 3' "$PROJ2/ai/fraim.conf")" "1"
check "источник значения показан" "$("$FRAIM" config 2>/dev/null | grep hotfix_threshold | grep -c 'ai/fraim.conf')" "1"
"$FRAIM" config set --machine stale_plan_commits 4 >/dev/null 2>&1
check "машинная настройка записана" "$(grep -c 'stale_plan_commits = 4' "$FRAIM_HOME/config")" "1"
"$FRAIM" config set nonsense_key 1 >/dev/null 2>&1
check "неизвестный ключ отвергнут" "$?" "2"

# A check turned off must actually stop firing.
printf -- '--- pruned 2026-01-01 ---\n' > "$PROJ2/ai/hotfix_log.md"
for i in 1 2 3 4 5; do printf -- '- e — `a` — f — behavior: no\n' >> "$PROJ2/ai/hotfix_log.md"; done
git -C "$PROJ2" commit -qam "test: hotfix log" >/dev/null 2>&1
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "дрейф выше порога → exit 1" "$?" "1"
"$FRAIM" config set check_drift off >/dev/null 2>&1
"$FRAIM" status "$PROJ2" >/dev/null 2>&1
check "выключенная проверка не срабатывает" "$?" "0"
"$FRAIM" config set check_drift on >/dev/null 2>&1
rm -f "$PROJ2/ai/hotfix_log.md"

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

# hotfix-log owns the format the drift counter reads.
"$FRAIM" hotfix-log src/a.py "fix off-by-one" no >/dev/null 2>&1
check "hotfix-log записал строку в точном формате" \
    "$(grep -cE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} — `src/a\.py` — fix off-by-one — behavior: no$' "$PROJ2/ai/hotfix_log.md")" "1"
check "hotfix-log закоммитил" "$(git -C "$PROJ2" log --oneline -1 --format=%s)" "hotfix: fix off-by-one"
"$FRAIM" hotfix-log src/a.py "bad" maybe >/dev/null 2>&1
check "hotfix-log отвергает неверный behavior" "$?" "2"

"$FRAIM" stack-passport >/dev/null 2>&1
check "stack-passport создал STACK.md" "$([ -f "$PROJ2/STACK.md" ] && echo yes || echo no)" "yes"
check "имя проекта подставлено в паспорт" "$(grep -c 'STACK PASSPORT — proj2' "$PROJ2/STACK.md")" "1"
check "паспорт помечен как незаполненный" "$(grep -c 'fraim:stub' "$PROJ2/STACK.md")" "1"
"$FRAIM" stack-passport >/dev/null 2>&1
check "stack-passport не перезаписывает" "$?" "2"

"$FRAIM" prune-mark >/dev/null 2>&1
check "prune-mark поставил маркер" "$(grep -c '^--- pruned 20' "$PROJ2/ai/hotfix_log.md")" "1"
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
t = t.replace("<root cause, plainly. Route: /hotfix (surgical) | /make-task (structural) | /revise-task | /prune.>",
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
"$FRAIM" hotfix-log src/b.py "another" no >/dev/null 2>&1
check "commit_verbs = off отключает коммит" "$(git -C "$PROJ2" rev-list --count HEAD)" "$BEFORE_N"
"$FRAIM" config set commit_verbs on >/dev/null 2>&1

cd "$REPO" || exit 1

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
check "Codex: 14 скиллов" "$(find "$HOME/.codex/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')" "14"
check "Claude Code: 14 скиллов" "$(find "$HOME/.claude/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')" "14"
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
