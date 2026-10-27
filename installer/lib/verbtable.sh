#!/bin/sh
# verbtable.sh — the one list of what the CLI does for an agent.
#
# The list used to be written by hand twice — in `fraim help` and in the master skill —
# and the two had already drifted apart. An agent learns the verbs from `fraim brief`,
# which prints this table, so the list it reads is always the list of the CLI it runs.
#
# group ;; situation ;; command ;; short (Russian, for `fraim help`) ;; detail (for the agent)
#
# Ordered by the moment of a session, not by command: an agent mid-work asks «I just
# changed behaviour — what now?», and the answer has to be one glance down the left column.
# The agent-facing columns are English, like every other instruction to the agent; the
# short column is Russian because `fraim help` is read by the human.
#   group: start · work · end · human · rare

vt_table() {
    cat <<'VT'
start ;; reading the foundation whole ;; fraim brief ;; весь фундамент, доска и список глаголов одним выводом ;; the map, house rules, living decisions, STACK.md and the board, uncut; once per session
start ;; looking something up ;; fraim find KEY… ;; найти запись целиком в фундаменте, задачах, бэклоге ;; 2–4 keys, both languages, word stems (cache кэш); returns whole entries with their heading
work ;; finished a coherent piece ;; fraim commit KIND "WHAT" PATH… ;; точка сохранения по перечисленным путям ;; a save point over exactly the paths you changed — never "everything"
work ;; changed what the program does ;; fraim decide "TITLE" [--supersedes "OLD"] ;; запись в DECISIONS.md (тело потоком) ;; body on stdin; goes on top; --supersedes moves the replaced entry to the archive
work ;; changed structure, components or data flow ;; fraim arch "SECTION" [--new] [--in FILE] ;; переписать раздел карты (тело потоком) ;; rewrites one section of ARCHITECTURE.md (or CONVENTIONS.md / STACK.md); body on stdin
work ;; something bit you that would trap the next change ;; fraim pitfall "LINE"… ;; грабли в CONVENTIONS.md ;; propose the line first; write it only on the human's yes
work ;; need to undo your own uncommitted edit ;; fraim restore PATH… ;; вернуть пути к последней точке ;; back to the last save point; a created file is removed
end ;; open questions remain, important but not for now ;; fraim backlog-new SLUG [--from WHERE] ;; записать вопрос в бэклог (потоком) ;; list them, ask; only approved ones; body on stdin: # title, ## В чём вопрос, ## Почему важно
end ;; finished a task taken from the board ;; fraim task-seal SLUG "RESULT" [--dropped] ;; закрыть задачу строкой итога ;; closes the card into the archive with one line of outcome; a master task only on the human's word
human ;; wants to know where things stand ;; fraim status ;; вердикт сторожа по проекту ;; the watchman's verdict; report it, do not act on it
human ;; wants to know what is planned ;; fraim tasks ;; доска задач и проектов ;; open tasks, projects with progress, age of each card
human ;; wants work set aside, or a project opened ;; fraim task-new SLUG [--master | --parent M | --from Q] ;; поставить задачу (карточка потоком) ;; via /make-task; body on stdin: # title, ## Что и зачем, ## Готово, когда, ## Ссылки
human ;; says a task is really a project ;; fraim task-master SLUG ;; сделать задачу проектом ;; turns an open task into a master task
human ;; wants to review open questions ;; fraim backlog ;; открытые вопросы ;; the backlog; a question that stops mattering → fraim backlog-drop
human ;; drops an open question ;; fraim backlog-drop SLUG "WHY" ;; снять вопрос из бэклога ;; closes it into the archive with the reason
rare ;; a save point must be taken back ;; fraim undo [HASH] ;; показать точки / отменить одну ;; lists the save points; undoes one with a counter-commit, never rewrites history
rare ;; starting / closing an investigation ;; fraim investigate-new SLUG ;; папка расследования + findings.md ;; inside /investigate
rare ;; closing an investigation with an outcome ;; fraim investigate-seal SLUG ;; проверить исход и уборку, заархивировать ;; inside /investigate; refuses without an outcome and a cleanup report
rare ;; a stack was boxed ;; fraim stack-passport ;; создать STACK.md из шаблона ;; inside /docker-deploy
rare ;; a prune is finished ;; fraim prune-mark ;; сбросить счётчик дрейфа маркером ;; inside /prune
VT
}

# The block `fraim brief` opens with: the rules that make the calls matter, then the
# verbs by situation. Short on purpose — the procedures carry the rest.
vt_brief() {
    printf 'The foundation is written only through these verbs: the text is yours; place, format\n'
    printf 'and line wrapping are theirs. Tasks and the backlog are filled by the human only — the\n'
    printf 'work in front of you is done here and now. No fraim on the machine: do the same with git.\n'
    vt_table | awk -F' ;; ' '
        BEGIN {
            title["start"] = "Start of a session"; title["work"] = "While working"
            title["end"] = "At the end of a piece of work"; title["human"] = "When the human wants it"
            title["rare"] = "Rare"
        }
        $1 != g { g = $1; printf "\n%s\n", title[g] }
        { printf "- %s → `%s` — %s\n", $2, $3, $5 }
    ' | fnd_wrap read
}

# The agent half of `fraim help`.
vt_help() {
    # Padding by characters, not bytes: printf %-24s would count every Cyrillic letter twice.
    vt_table | LC_ALL=C awk -F' ;; ' '
        function clen(x,  t) { t = x; gsub(/[\200-\277]/, "", t); return length(t) }
        {
            c = $3; sub(/^fraim /, "", c)
            n = clen(c)
            if (n <= 24) { pad = ""; for (i = n; i < 25; i++) pad = pad " "; printf "  fraim %s%s%s\n", c, pad, $4 }
            else printf "  fraim %s\n                                 %s\n", c, $4
        }'
}

# The verb table of the master skill, as markdown rows.
vt_skill() {
    printf '| Situation | Command | Notes |\n|---|---|---|\n'
    vt_table | awk -F' ;; ' '{ c = $3; gsub(/\|/, "\\|", c); printf "| %s | `%s` | %s |\n", $2, c, $5 }'
}

# What the human wants, and what that means here. Intents, not phrases: the human writes
# in any language and in their own words, and a list of sample sentences fails on the first
# wording it does not contain. The agent judges the intent; when it cannot tell «now» from
# «later», now is the default — the work in front of it is done here.
vt_intents() {
    cat <<'IN'
| The human's intent | What it means |
|---|---|
| set work aside to do later, not now | `/make-task` — an ordinary task |
| start something large that will take several tasks (a project) | `/make-task` — a master task |
| know what is pending, planned or in progress | `fraim tasks` — report it |
| work on a specific task from the board | `/run-task` |
| keep an open question without acting on it | `fraim backlog-new` after the human confirms / `fraim backlog` to review |
| have work done by cheaper models, or split into parallel directions | `/conductor` |
| get back into the project after a break | `/orient` |
| understand a behaviour nobody can explain, or check that something is feasible | `/investigate` |
| bring the documents back in line with the code | `/prune` |
IN
    printf '\n%s\n' 'Judge the intent, in whatever language and wording it comes. Anything else the human asks for is work to do now, in this session. Unsure whether they mean now or later — do it now, or ask one question.'
}
