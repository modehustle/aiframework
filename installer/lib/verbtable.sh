#!/bin/sh
# verbtable.sh — the one list of what the CLI does for an agent.
#
# The list used to be written by hand twice — in `fraim help` and in the master skill —
# and the two had already drifted apart. An agent learns the verbs from `fraim brief`,
# which prints this table, so the list it reads is always the list of the CLI it runs.
#
# group ;; command ;; when to call it
#   group: read · board · foundation · save · other

vt_table() {
    cat <<'VT'
read ;; fraim brief ;; в начале сессии: весь фундамент, доска и этот список одним выводом — читать файлы отдельно не нужно
read ;; fraim find КЛЮЧ… ;; найти в фундаменте, задачах и бэклоге; 2–4 ключа, на обоих языках, основой слова (задач task); возвращает запись целиком
read ;; fraim status ;; вердикт сторожа по проекту (--json для машины)
board ;; fraim tasks ;; доска: открытые задачи, проекты с прогрессом, возраст карточек
board ;; fraim task-new СЛАГ [--master | --parent М | --from ВОПРОС] ;; поставить задачу — только по слову человека; карточка потоком: «# Заголовок», «## Что и зачем», «## Готово, когда», «## Ссылки»
board ;; fraim task-master СЛАГ ;; сделать задачу проектом — только по слову человека
board ;; fraim task-seal СЛАГ "ИТОГ" [--dropped] ;; закрыть задачу строкой итога (или отменить)
board ;; fraim backlog ;; открытые вопросы, отложенные человеком
board ;; fraim backlog-new СЛАГ [--from ОТКУДА] ;; записать открытый вопрос — только то, что человек одобрил; потоком: «# Вопрос», «## В чём вопрос», «## Почему важно»
board ;; fraim backlog-drop СЛАГ "ПОЧЕМУ" ;; снять вопрос из бэклога
foundation ;; fraim decide "ЗАГОЛОВОК" [--supersedes "ЧТО"] ;; поведение изменилось → запись в DECISIONS.md наверх (тело потоком); заменённая запись сама уходит в архив
foundation ;; fraim pitfall "СТРОКА"… ;; грабли, одобренные человеком → в Known Pitfalls / Lessons
foundation ;; fraim arch "РАЗДЕЛ" [--new] [--in ФАЙЛ] ;; переписать раздел ARCHITECTURE.md (или CONVENTIONS.md / STACK.md) целиком; тело потоком
save ;; fraim commit ВИД "ЧТО" ПУТЬ… ;; точка сохранения ровно по перечисленным путям — после каждого законченного куска
save ;; fraim restore ПУТЬ… ;; вернуть пути к последней точке сохранения
save ;; fraim undo [ХЕШ] ;; показать точки / отменить одну встречным коммитом
other ;; fraim investigate-new СЛАГ ;; начать расследование (/investigate)
other ;; fraim investigate-seal СЛАГ ;; закрыть расследование с исходом
other ;; fraim stack-passport ;; завести STACK.md по схеме
other ;; fraim prune-mark ;; отметить завершённый /prune
VT
}

# The block `fraim brief` opens with: what to call, and the three rules that make the
# calls matter. Short on purpose — the procedures carry the rest.
vt_brief() {
    printf 'Фундамент пишется только глаголами: текст твой, место, формат и перенос строк — их.\n'
    printf 'Задачи и бэклог пополняет только человек; ты делаешь работу здесь и сейчас.\n'
    printf 'Нет fraim на машине — делай то же обычным git, правила те же.\n\n'
    vt_table | awk -F' ;; ' '{ printf "- `%s` — %s\n", $2, $3 }' | fnd_wrap
}
