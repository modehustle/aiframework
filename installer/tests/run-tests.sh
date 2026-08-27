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

# ---------------------------------------------------------------- registry
printf '\nfraim projects (реестр)\n'

"$FRAIM" projects add "$PROJ" >/dev/null 2>&1
"$FRAIM" projects add "$PROJ" >/dev/null 2>&1
check "add идемпотентен" "$("$FRAIM" projects 2>/dev/null | grep -c "$PROJ")" "1"
"$FRAIM" projects rm "$PROJ" >/dev/null 2>&1
check "rm убирает запись" "$("$FRAIM" projects 2>/dev/null | grep -c "$PROJ")" "0"

# ---------------------------------------------------------------- init
printf '\nfraim init\n'

mkdir -p "$HOME/.codex" "$HOME/.claude"     # pretend two harnesses are installed
cd "$PROJ" || exit 1
"$FRAIM" init >/dev/null 2>&1
check "init завершился успешно" "$?" "0"
check "Codex: 13 скиллов" "$(find "$HOME/.codex/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')" "13"
check "Claude Code: 13 скиллов" "$(find "$HOME/.claude/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')" "13"
check "контекстный блок в ~/.codex/AGENTS.md" "$(grep -c 'fraim:begin' "$HOME/.codex/AGENTS.md" 2>/dev/null)" "1"
check "проект зарегистрирован" "$("$FRAIM" projects 2>/dev/null | grep -c "$PROJ")" "1"
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
