#!/bin/sh
# verbtable.sh — the one list of what the CLI does for an agent.
#
# The list used to be written by hand twice — in `fraim help` and in the master skill —
# and the two had already drifted apart. An agent learns the verbs from `fraim brief`,
# which prints this table, so the list it reads is always the list of the CLI it runs.
#
# group ;; command ;; short (for `fraim help`) ;; when to call it (for brief and the skill)
#   group: read · board · foundation · save · other

vt_table() {
    cat <<'VT'
read ;; fraim brief ;; весь фундамент, доска и этот список одним выводом ;; в начале сессии: весь фундамент, доска и этот список одним выводом — читать файлы отдельно не нужно
read ;; fraim find КЛЮЧ… ;; найти запись целиком в фундаменте, задачах, бэклоге ;; найти в фундаменте, задачах и бэклоге; 2–4 ключа, на обоих языках, основой слова (задач task); возвращает запись целиком
read ;; fraim status ;; вердикт сторожа по проекту ;; вердикт сторожа по проекту (--json для машины)
board ;; fraim tasks ;; доска задач и проектов ;; доска: открытые задачи, проекты с прогрессом, возраст карточек
board ;; fraim task-new СЛАГ [--master | --parent М | --from ВОПРОС] ;; поставить задачу (карточка потоком) ;; поставить задачу — только по слову человека; карточка потоком: «# Заголовок», «## Что и зачем», «## Готово, когда», «## Ссылки»
board ;; fraim task-master СЛАГ ;; сделать задачу проектом ;; сделать задачу проектом — только по слову человека
board ;; fraim task-seal СЛАГ "ИТОГ" [--dropped] ;; закрыть задачу строкой итога ;; закрыть задачу строкой итога (или отменить)
board ;; fraim backlog ;; открытые вопросы ;; открытые вопросы, отложенные человеком
board ;; fraim backlog-new СЛАГ [--from ОТКУДА] ;; записать вопрос в бэклог (потоком) ;; записать открытый вопрос — только то, что человек одобрил; потоком: «# Вопрос», «## В чём вопрос», «## Почему важно»
board ;; fraim backlog-drop СЛАГ "ПОЧЕМУ" ;; снять вопрос из бэклога ;; снять вопрос из бэклога
foundation ;; fraim decide "ЗАГОЛОВОК" [--supersedes "ЧТО"] ;; запись в DECISIONS.md (тело потоком) ;; поведение изменилось → запись в DECISIONS.md наверх (тело потоком); заменённая запись сама уходит в архив
foundation ;; fraim pitfall "СТРОКА"… ;; грабли в CONVENTIONS.md ;; грабли, одобренные человеком → в Known Pitfalls / Lessons
foundation ;; fraim arch "РАЗДЕЛ" [--new] [--in ФАЙЛ] ;; переписать раздел карты (тело потоком) ;; переписать раздел ARCHITECTURE.md (или CONVENTIONS.md / STACK.md) целиком; тело потоком
save ;; fraim commit ВИД "ЧТО" ПУТЬ… ;; точка сохранения по перечисленным путям ;; точка сохранения ровно по перечисленным путям — после каждого законченного куска
save ;; fraim restore ПУТЬ… ;; вернуть пути к последней точке ;; вернуть пути к последней точке сохранения
save ;; fraim undo [ХЕШ] ;; показать точки / отменить одну ;; показать точки / отменить одну встречным коммитом
other ;; fraim investigate-new СЛАГ ;; папка расследования + findings.md ;; начать расследование (/investigate)
other ;; fraim investigate-seal СЛАГ ;; проверить исход и уборку, заархивировать ;; закрыть расследование с исходом
other ;; fraim stack-passport ;; создать STACK.md из шаблона ;; завести STACK.md по схеме
other ;; fraim prune-mark ;; сбросить счётчик дрейфа маркером ;; отметить завершённый /prune
VT
}

# The block `fraim brief` opens with: what to call, and the three rules that make the
# calls matter. Short on purpose — the procedures carry the rest.
vt_brief() {
    printf 'Фундамент пишется только глаголами: текст твой, место, формат и перенос строк — их.\n'
    printf 'Задачи и бэклог пополняет только человек; ты делаешь работу здесь и сейчас.\n'
    printf 'Нет fraim на машине — делай то же обычным git, правила те же.\n\n'
    vt_table | awk -F' ;; ' '{ printf "- `%s` — %s\n", $2, $4 }' | fnd_wrap
}

# The agent half of `fraim help`.
vt_help() {
    # Padding by characters, not bytes: printf %-24s would count every Cyrillic letter twice.
    vt_table | LC_ALL=C awk -F' ;; ' '
        function clen(x,  t) { t = x; gsub(/[\200-\277]/, "", t); return length(t) }
        {
            c = $2; sub(/^fraim /, "", c)
            n = clen(c)
            if (n <= 24) { pad = ""; for (i = n; i < 25; i++) pad = pad " "; printf "  fraim %s%s%s\n", c, pad, $3 }
            else printf "  fraim %s\n                                 %s\n", c, $3
        }'
}

# The verb table of the master skill, as markdown rows.
vt_skill() {
    printf '| Command | When |\n|---|---|\n'
    vt_table | awk -F' ;; ' '{ c = $2; gsub(/\|/, "\\|", c); printf "| `%s` | %s |\n", c, $4 }'
}

# What the human says, and what that means here. The human does not type commands; the
# agent has to recognise the request in words. One table, read by the AGENTS.md block,
# the machine context block and the master skill.
vt_phrases() {
    cat <<'PH'
| человек говорит | это значит |
|---|---|
| «запиши задачу», «на потом», «поставь в задачи» | `/make-task` — обычная задача |
| «заведи проект», «мастер-задача», «это большая штука из многих задач» | `/make-task` — мастер-задача |
| «что у меня в задачах», «что на доске» | `fraim tasks` — пересказать |
| «возьми задачу X», «давай X из задач» | `/run-task` |
| «запиши вопрос», «в бэклог», «что в бэклоге» | `fraim backlog-new` (после его «да») / `fraim backlog` |
| «отдай дешёвому», «раздай», «через флот» | `/conductor` |
| «где мы», «что дальше» после паузы | `/orient` |
| «разберись, почему…», «реально ли X» | `/investigate` |
| «сверь документы с кодом» | `/prune` |
PH
}
