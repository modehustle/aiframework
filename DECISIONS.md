# DECISIONS — aiframework  (append-only)

> Newest on top. One entry per decision. Never rewrite history — supersede with a new
> entry, or relocate stale entries to `ai/archive/decisions_log.md` via `/prune`.

## 2026-10-31 — ZCode is a supported harness; the pi and Devin finding confirmed and narrowed

Context: the owner pointed out that pi and Devin did read our skills, and asked for Z.ai's GLM
agent.
On the owner's machine pi did not find `/skill:orient`, which confirms pi never read `~/.pi/skills`
(its user skills are `~/.pi/agent/skills` and `~/.agents/skills`; it stopped reading
`~/.claude/skills` and `~/.codex/skills` in 0.50, January 2026). Devin CLI did see our skills, but
only through Claude Code's copy: it reads `~/.claude/skills` and `~/.claude/CLAUDE.md` by default,
never `~/.devin/skills`.
Decision: (1) A row for ZCode, Z.ai's desktop agent for GLM: skills in its own `~/.zcode/skills`,
the block in `~/.zcode/AGENTS.md` (read every session), recognised by `~/.zcode` or the macOS app
bundle — it ships no CLI binary we could name. Its own directory, not the shared one: only one
secondary source says it reads `~/.agents/skills`. (2) The documents say precisely what was wrong
for Devin: the directory, not the visibility.
Alternatives: leaving GLM to the harnesses that already run its models (Claude Code, OpenCode,
Kilo Code, Cline through the GLM Coding Plan) rejected — the owner asked for the native app too.
Consequences: the ZCode row rests on a quoted summary of its docs (zcode.z.ai is unreachable from
here) and is to be confirmed on a machine with ZCode installed.

## 2026-10-31 — harnesses: 27 rows, one shared ~/.agents/skills copy, paths checked against sources

Context: the owner asked to widen the list of supported harnesses beyond terminal agents. Checking
every row against the harnesses' own source code and docs (October 2026) found that four existing
rows wrote where the harness never reads: pi and omp keep their agent home in `~/.pi/agent` and
`~/.omp/agent`, Devin for Terminal in `~/.config/devin`, Hermes loads no global AGENTS.md; the
Antigravity CLI reads `~/.gemini/antigravity-cli/skills`, and Codex marks `~/.codex/skills`
deprecated in favour of `~/.agents/skills`. Most harnesses now also read the open standard's shared
`~/.agents/skills`, and several of them warn on a second copy of the same skill (Gemini CLI on
screen, pi, omp, Hermes).
Decision: (1) A harness that reads `~/.agents/skills` gets its skills there and nowhere else; only
a harness that does not read it (Claude Code, Hermes, Antigravity, Factory Droid, Grok Build, Kiro,
Junie, Continue) gets its own directory. (2) Nineteen rows are added: Gemini CLI, Qwen Code, Kimi
Code, Mistral Vibe, Goose, Crush, Factory Droid, Grok Build, OpenClaw, GitHub Copilot, Cursor,
Cline, Kilo Code, Zed, Warp, Augment, Kiro, Junie, Continue; pi, omp, Devin, Codex, OpenCode and
Antigravity are corrected. (3) The probe cell takes a comma-separated list of binaries and `$HOME`
paths; once a row names a path, the parent of its skills directory no longer counts (`~/.agents`
says nothing about which product is installed, `~/.gemini` is shared by Gemini CLI and
Antigravity — Gemini CLI is recognised by `gemini` or `~/.gemini/settings.json`). (4) The skills
cell may name several directories; Antigravity gets both of its own. (5) The instructions cell is
`-` where rules live only in a settings screen (Cursor) or the only always-loaded file is one the
harness seeds itself and owns (Hermes `SOUL.md`, OpenClaw's workspace `AGENTS.md`); where a harness
reads a rules directory (Kiro, Augment, Continue), the cell names our own `fraim.md` in it; Cline,
Warp, Goose and Kimi Code share `~/.agents/AGENTS.md`. (6) `harness_retired_table` lists the old
wrong locations; `fraim init` removes from them only skills marked `source: fraim` and the block
between our markers (`context_uninstall`; a file that held only the block is deleted), and never a
path some row still uses. (7) The roles picker lists models for Kilo (`kilo models`), Crush (`crush
models`), Grok (`grok models`) and Cursor; no new built-in fleet launch command — none was run
live. This replaces item (1) of «OpenCode is a supported harness» as to the skills directory.
Alternatives: installing into every directory a harness reads rejected — the duplicate warnings;
installing only into `~/.agents/skills` for all rejected — Claude Code, Hermes, Antigravity and
others do not read it; writing into Hermes `SOUL.md` or OpenClaw's workspace file rejected for now
— creating them first would stop the harness seeding its own; Roo Code (shut down 2026-05-15),
Windsurf (became Devin Desktop, which shares Devin's directory), Amp and Trae (no primary source
readable) left out.
Consequences: on a machine with Claude Code, harnesses that also read `~/.claude/skills` or
`~/.claude/CLAUDE.md` still see our text twice — the same text. Cursor, Devin, Kiro, Junie and
Augment rows rest on search excerpts of their official pages, not on pages read whole; they are to
be confirmed on a machine with each installed.

## 2026-10-28 — fraim upgrade is a machine command over the registry

Context: the owner noticed the asymmetry: `fraim update` brings a new release to the machine once,
while `fraim upgrade` had to be run inside every project, one by one, and nobody remembers which
projects exist.
Decision: `fraim upgrade` with no path upgrades every project in the registry
(`~/.fraim/projects`), plus the project in the current directory when it is under the system and
not registered yet (it is registered on the way, so the watchman's «→ fraim upgrade» still works
from inside an unregistered project). A missing directory or a folder not under the system is
skipped with a line, each project runs in its own subshell so a refusal in one does not end the
sweep, and a summary closes it; the exit is 1 when any project failed, 2 on an empty registry
outside a project. `fraim upgrade PATH` keeps the old behaviour for one project. `fraim init`
(and so `fraim update`) names the number of registered projects and points to `fraim upgrade`.
Alternatives: running the sweep inside `fraim update` rejected — upgrade commits into each project,
and an update runs from a schedule or an image (`--quiet`) where nobody is looking at those
repositories; a separate `fraim upgrade --all` rejected — the common case would need the flag.
Consequences: a bare `fraim upgrade` inside a project now also touches the other registered
projects; tests call `fraim upgrade .` where they mean one project.

## 2026-10-28 — OpenCode is a supported harness

Context: the owner asked for OpenCode to be supported like the other agents. It reads the open
Agent Skills format and a global AGENTS.md, lists its models itself and takes a model in argv, so
it fits every table we keep without new mechanics.
Decision: (1) A harness row: probe `opencode`, skills in `~/.config/opencode/skills` (plural),
the context block in `~/.config/opencode/AGENTS.md`; presence is that directory, never the bare
`~/.config`. (2) The roles picker discovers models with `opencode models`, one `provider/model`
per line; the parser keeps nested slashes and colons and drops anything with a space. (3) A
built-in fleet launch command `opencode --model %s` (bare `opencode` without a model), so a fleet
worker on OpenCode takes the custom launch path with the model in argv; no readiness banner,
`tui-idle` alone decides, and `launchcmd_opencode` / `readypattern_opencode` still override.
Alternatives: relying on OpenCode's fallback to `~/.claude/skills` rejected — it exists only when
Claude Code is installed and can be switched off by an environment variable; writing the block
into `~/.claude/CLAUDE.md` for it rejected — that file belongs to another harness.
Consequences: with Claude Code installed too, OpenCode sees our skills twice under the same names,
with the same text. The AGENTS.md our block creates ends OpenCode's fallback to
`~/.claude/CLAUDE.md`, so a human's own global rules for OpenCode belong in its AGENTS.md. The
facts come from OpenCode's documentation, not a live run: the launch command and the
`opencode models` format are to be confirmed on a machine with OpenCode.

## 2026-10-28 — a task's kind is required; a project is laid down with its subtasks; after orders the queue

Context: a live test in Devin CLI on a cheap model. The human asked for a project; the model went
through fraim, put down one ordinary card and wrote the project's breakdown into a folder of the
project of its own choosing. Three things allowed it: `task-new` defaulted to `kind: task`, so
missing the word `--master` cost nothing; the rules forbade making a master on one's own but said
nothing about the opposite mistake; and a project was laid down empty — its breakdown waited for
`/run-task`, so a model that had already split the work had no sanctioned place to put the split.
The board also had no queue: children were listed alphabetically with nothing saying what comes
first.
Decision: (1) `task-new` refuses without `--task`, `--master` or `--parent` (a child is always a
task); the refusal says how to choose and to ask the human one question when unsure. (2) A master
may bring its children in the same call: a `## Subtasks` section, one `### <slug> — <title>` block
per child with `What and why:`, `Done when:` and an optional `After:`. Every child is checked
(slug, both fields, no placeholder, not already on the board) before any card is written; the
section is removed from the master, since the cards are the breakdown; the project and its
children are one save point. /make-task proposes the breakdown for the human to approve and puts it
down in that call; /run-task still breaks down a master that came alone. (3) A child may carry
`after:` — siblings it waits for. In a `## Subtasks` block `After` may name only blocks above it,
and `--after` (with `--parent`) only existing children of that project, so a cycle cannot be
written through the verbs. A child waits while any card in its `after` is still open; `fraim tasks`
lists a project's children by dependency depth, marks a waiting one with what it waits for, and
names on the master line the ones nobody waits on; `task-seal` names them after closing a child,
and warns when a dropped card was waited on. `fraim tasks --json` carries `after`, `waiting_on`
and the master's `ready`.
Alternatives: a position number per child rejected — it needs a reorder verb and says nothing a
dependency does not; independent children are equal and the human picks. Inferring the kind from
the size of the request rejected — it is the agent deciding what N3 reserves for the human. Keeping
the breakdown as a list on the master rejected — a second copy of the board that goes stale with
the first closed child. A watchman finding for plan-like files outside `ai/` rejected for now —
heuristic, and the sanctioned place removes the reason to write them.
Consequences: every caller of `task-new` names the kind; existing cards are untouched (no `after`
means no wait). A cycle written by hand cannot hang the board: the depth passes are bounded.

## 2026-10-28 — fraim commit checks what it adds; the watchman checks the foundation's language

Context: the verbs check only the text they are handed. A foundation file edited by hand bypasses
them, and code comments are written by no verb at all — both still drifted into the operator's
language.
Decision: (1) `fraim commit` measures the lines the save point adds (changes against HEAD, new files
whole): the foundation files and `ai/**/*.md` as text, code files by their comments only — `#`,
`//`, `/* */`, `--`, `<!-- -->` by extension, found outside string literals. Strings are not
checked: the operator's messages live there in the operator's language. Other files (README, docs,
data) are not checked. A refusal names each file with its first offending line and commits nothing.
Old text is not re-checked, so a project with a non-English past can still commit. (2) The watchman
gets `check_language` (on by default): it measures the foundation, the open cards and the backlog
as they are now and reports every unit that is not English, by file, pointing to /prune — this
catches what was saved with plain git or not saved at all. The archive is history and is not read.
(3) /prune translates such text, meaning unchanged. (4) `lang_measure all` reports every failing
unit, not the first.
Alternatives: a git pre-commit hook rejected — it lives in one clone and the product is
harness- and machine-agnostic; checking whole files at commit time rejected — a project's old text
would block every save point; baselining old foundation text in the watchman rejected — it is what
the next session reads, so it is drift whatever its age; checking string literals rejected — they
hold the operator's locale by design.
Consequences: projects whose foundation is still partly in another language get an attention
finding until it is translated (this repository: the Russian entries of DECISIONS.md). Python
docstrings are string literals and are not seen.

## 2026-10-28 — the write verbs refuse text that is not English

Context: the rule «the project is English inside» (2026-10-27) lived only in instructions. Live
sessions showed that models talking to the human in Russian drift into Russian in the foundation
they write a minute later — decisions, pitfalls, cards — and nothing stopped them. The operator's
locale may be any language, so the rule cannot rely on one model's discipline.
Decision: (1) A new library `lang.sh` measures text deterministically, on bytes, with no locale:
a unit (paragraph, list item, table row, heading) is refused when more than a fifth of its letters
belong to a non-Latin script (Cyrillic, Greek, Hebrew, Arabic, Indic, CJK, Hangul…), or when it
carries three or more everyday function words of a Latin-script language (es, de, fr, it, pt, nl,
pl) or words with diacritics, and more of them than English function words. Quoted spans —
`code`, fenced blocks, «…», “…”, "…" — are not measured: that is where a name or the human's own
words in another language go. (2) Every verb that writes text into a project runs it before
writing: `decide` (title and body), `pitfall`, `arch` (body; the name with `--new`), `task-new`,
`task-seal` (result), `backlog-new`, `backlog-drop` (reason), `fraim commit` (message),
`investigate-seal` (findings.md). A refusal exits 2 and writes nothing. (3) The refusal is
addressed to the agent and is in English: what was refused, why, the offending line, and how to
fix it — a refusal in the operator's language would push the agent further into it. (4) The rule
is also stated up front: in the project AGENTS.md block, the machine context block and the opening
of `fraim brief`.
Alternatives: a config switch to turn the check off rejected — the owner's rule holds in every
project, and quoting is the way out of a false alarm; requiring a share of English function words
rejected — terse English (a template paragraph, a list of names) has none and was refused in
testing; checking whole texts rather than units rejected — a Russian paragraph inside the long
English findings template stayed under the threshold; language detection by a model or a library
rejected — non-deterministic and not POSIX shell.
Consequences: test fixtures that fed Russian text to the verbs were rewritten in English. Existing
Russian entries in old projects are untouched: only new text is checked, and `--supersedes` takes a
heading as a reference, unchecked. Mixed Latin-script languages beyond the seven listed pass the
word test; non-Latin scripts are caught whatever the language.

## 2026-10-27 — the product is English inside; Russian is only the operator's locale

Context: the owner's model — fraim is an English product, because agents work better in English; the
human talks to the agent in any language and uses fraim in the locale they set. An audit found
Russian far beyond the operator's messages: card headings checked by the verbs, text the CLI writes
into projects (migration card, backlog link, abandoned-investigation note, build journal, accepted
marker, worker brief, publish briefs, fraim.conf header), commit messages, ~565 lines of procedures
and ~300 lines of code comments. CONVENTIONS.md even required procedure text and commit messages in
Russian.
Decision: (1) Everything inside the product is English: code, comments, procedures, data formats,
everything written into a project or into git history, everything addressed to the agent. (2) Card
headings become `## What and why`, `## Done when`, `## Links`; backlog: `## Question`, `## Why it
matters`; `fraim upgrade` renames the old Russian headings in place (heading lines only). (3) Build
journals are written in English; `build_base_sha` still reads the old «- База:» line. (4) Russian
stays only as the operator's locale — messages, refusals, the watchman's verdict, `fraim help` — for
now hardcoded; it moves to a message catalog (`locale/ru`) together with the review of the
deterministic layer. (5) Project docs may stay Russian until a public release. This supersedes the
CONVENTIONS rule «procedure text, commit messages and user-facing CLI output in Russian». Procedures
and code comments are translated in the following commits.
Alternatives: translating the operator's messages now rejected — they move into a catalog first,
otherwise they are rewritten twice; keeping Russian card headings rejected — a data format in one
human language is part of the product, not a locale.

## 2026-10-27 — справочник глаголов — по ситуациям и по-английски для агента

Decision: таблица `vt_table` упорядочена по моменту сессии — начало, по ходу работы, в конце куска,
когда этого хочет человек, редкое — и у каждого глагола первой стоит ситуация («finished a coherent
piece → fraim commit»), а не команда. Агентские колонки и рамка `fraim brief` (заголовки, метка
конца) и таблица мастер-скилла — по-английски, как все инструкции агенту; краткая колонка для `fraim
help` и всё, что CLI говорит человеку, — по-русски.
Alternatives: словарь «команда → когда звать» отвергнут — агент в работе ищет от ситуации и
пролистывал весь список; русский текст для агента отвергнут — инструкции агенту везде на английском,
и мастер-скилл смешивал языки.

## 2026-10-27 — намерения вместо фраз; пустой открытый вход — отказ, а не зависание

Context: владелец заметил два изъяна вчерашней записи «агент узнаёт продукт…». Таблица «слова
человека» была списком русских реплик-образцов: она ломается на первой другой формулировке и на
любом другом языке. И глаголы, читающие текст со входа, вечно ждали конца потока, если вход открыт,
но пуст.
Decision: (1) `vt_phrases` заменена на `vt_intents` — таблицу намерений по-английски (отложить на
потом, завести проект, узнать, что запланировано, заняться задачей с доски, сохранить открытый
вопрос, отдать дешёвым моделям, вернуться после паузы, разобраться в непонятном, свести документы с
кодом) и правило: суди по намерению на любом языке; непонятно «сейчас» или «потом» — делай сейчас
или спроси. Процедуры /make-task, /run-task и /conductor переписаны так же. Пункт (2) записи «агент
узнаёт продукт…» в части фраз этим заменён, остальное в ней действует. (2) `verb_read_body` ждёт
только первый байт, до 3 с (FRAIM_BODY_WAIT, в десятых долях); пришедший текст дочитывается целиком;
нет текста — предупреждение и отказ с правильной формой вызова. Чтение идёт в фоне с явно переданным
дескриптором: асинхронная команда неинтерактивного shell иначе читает /dev/null.
Alternatives: оставить фразы и добавить английские отвергнуто — тот же хрупкий список, только
длиннее; флаг `--file` вместо входа отвергнут — не лечит зависание у того, кто всё равно зовёт без
флага.

## 2026-10-27 — агент узнаёт продукт из одной таблицы глаголов и из блока AGENTS.md

Context: владелец работает только словами — из CLI он набирал разве что `fraim upgrade`. Значит,
продукт должен знать агент. Мастер-скилл срабатывал только на вопросы «где проект стоит», и в
обычной сессии не загружался; список глаголов был написан руками дважды (`fraim help` и
мастер-скилл) и уже разошёлся — поэтому существующие `decide` и `pitfall` агенты забывали.
Decision: (1) единая таблица `vt_table` в `installer/lib/verbtable.sh` (группа, команда, кратко,
когда звать); из неё собираются список глаголов в начале `fraim brief`, агентская половина `fraim
help` и таблица глаголов мастер-скилла; рельс-тест требует, чтобы каждая команда таблицы была в
диспетчере. (2) `vt_phrases` — слова человека → процедура или глагол («запиши задачу», «заведи
проект», «возьми задачу X», «что в бэклоге», «отдай дешёвому»…); общая для блока AGENTS.md проекта и
мастер-скилла. (3) Блок AGENTS.md проекта (всегда загружен харнессом) говорит: начни с `fraim
brief`, ищи через `fraim find`, пиши фундамент глаголами, задачи и бэклог пополняет только человек,
в конце — открытые вопросы на его «да». (4) Мастер-скилл переписан: описание срабатывает на проект
под fraim, задачи, доску, бэклог, решения; внутри — слова человека, процедуры и сгенерированная
таблица глаголов. `fraim upgrade` обновляет блок в существующих проектах.
Alternatives: подсказка про дешёвого исполнителя в выводе `fraim tasks` отложена владельцем; хранить
таблицу фраз отдельно в каждом блоке отвергнуто — это та же двойная запись, что развела help и
скилл.

## 2026-10-27 — upgrade делит миграцию на механику и задачу миграции на доске

Decision: `fraim upgrade` (и шаг upgrade в `fraim clean`) сам делает всё вычислимое — заводит
`ai/backlog/`, переводит задачи старого формата в карточки, обновляет блок AGENTS.md — а то, что
требует суждения, ставит пунктами в одну карточку `fraim-migration` на доске: задачи без нужных
разделов и ARCHITECTURE.md без разделов «## » (без них `fraim arch` не работает). Пункты не
дублируются при повторном запуске. Как их доделать — раздел «Миграция формата» в /prune.
Alternatives: предупреждение в выводе upgrade отвергнуто — оно уезжает вверх экрана и забывается;
отдельная процедура миграции отвергнута — карточка на доске уже и есть способ, которым следующая
сессия узнаёт о работе.

## 2026-10-27 — фундамент читается целиком и пишется глаголами: brief, find, arch, перенос строк, автоперенос заменённых решений, бэклог

Context: обратная связь владельца. Агенты, даже сильные, читают фундамент первыми ~200 строками и
работают с третью карты, не зная об этом; grep возвращает строку без заголовка, а в DECISIONS абзацы
записаны строками по 900 знаков, которые инструменты чтения режут. Запись в фундамент велась руками
— запись не наверх, потерянный заголовок, решение без следа. Отдельно: открытые вопросы, которые
агент называет в конце сессии, пропадали вместе с чатом.
Decision: (1) `fraim brief` печатает весь фундамент одним выводом: сначала список глаголов (из
единой таблицы `verbtable.sh`), затем ARCHITECTURE, CONVENTIONS, решения в сжатом виде (заголовок,
Supersedes, абзац Decision), STACK, доску; строки переносятся на 100 знаков; в конце метка «показано
всё». (2) `fraim find КЛЮЧ…` ищет по фундаменту, архиву решений, задачам, бэклогу и расследованиям;
ключи через ИЛИ, без учёта регистра (в UTF-8 локали), по подстроке; морфологию не угадывает —
варианты на двух языках и основы слова подставляет агент; возвращает запись целиком с заголовком.
(3) `fraim arch "РАЗДЕЛ" [--new] [--in CONVENTIONS.md|STACK.md]` заменяет тело ровно одного раздела,
отказывает на неизвестное имя со списком существующих, на заголовки в теле и на DECISIONS.md;
работает с любыми `## `-разделами файла, поэтому миграции не требует. (4) Глаголы записи (decide,
pitfall, arch, task-new, backlog-new) переносят прозу на 100 знаков; таблицы, код и заголовки на
диске не трогаются; существующие файлы массово не переписываются — переносит вывод brief/find. (5)
`decide --supersedes`, совпавший ровно с одним заголовком, переносит ту запись целиком в
`ai/archive/decisions_log.md`; несколько совпадений — отказ до записи; ни одного — остаётся ссылкой.
(6) Бэклог `ai/backlog/<слаг>.md` — открытые вопросы, не задачи: `backlog-new`, `backlog-drop`,
`task-new --from`; пополняет только человек, агент в конце задачи перечисляет вопросы и спрашивает.
(7) Глаголы находят корень проекта вверх по каталогам. (8) Текст глаголов идёт через ENVIRON, а не
awk -v.
Alternatives: бюджет размера файлов фундамента отвергнут владельцем — универсально его не задать;
стемминг в CLI отвергнут — недетерминированно и зависит от языка; массовый перенос строк в
существующих файлах отвергнут — риск сломать таблицы и списки при нулевой пользе, раз агент читает
через brief; фиксированный список разделов для arch отвергнут — проекты после /onboard пишут карту
по-своему.
Consequences: процедуры читают фундамент через `fraim brief` и ищут через `fraim find`; /prune
больше не переносит заменённые решения руками, если замена записана через decide. Список глаголов в
`fraim help` и мастер-скилле пока пишется отдельно — сведение к `verbtable.sh` идёт следующим шагом.

## 2026-10-27 — задача — карточка с намерением, а не план; доска с мастер-задачами; revise/reconcile удалены
> Supersedes: 2026-09-09 «two modes» в части задачной церемонии (/make-task → /run-task → task-seal как передача плана)

Context: обратная связь владельца после месяцев живой работы. Работа идёт реактивно: агенту пишут задачу, он делает её в той же сессии и сохраняется глаголами. Задачная церемония несла фундаментальный изъян — в задачу закладывался контекст кода (пути, паттерны, reference scan, штамп провенанса), снимок начинал протухать в момент записи, и половина системы была машинерией вокруг протухания: stale-plan, plan-version, plan-retelling, blockers, /revise-task, /reconcile-task, plan-seal, гейты task-seal/reconcile-seal на result.md.
Decision: (1) задача — карточка `ai/tasks/<slug>.md`: frontmatter `kind` (task | master), `created`, необязательный `parent`; тело — заголовок, «Что и зачем», «Готово, когда», «Ссылки». Никакого контекста кода. (2) Статус — место файла: на доске открыта, в `ai/archive/tasks/` закрыта (глагол дописывает closed, outcome done|dropped, result, commit). (3) Мастер-задача — проект: тип задаётся явно словом человека (`--master`, `fraim task-master`), подзадачи ссылаются `parent`, вложенность в один уровень, «в работе» вычисляется по закрытым подзадачам, закрывает проект только человек. (4) Задачи ставит только человек; агент не предлагает превращать работу в задачу. (5) /run-task — обычная сессия на способной модели, контекст собирается свежим; дешёвый исполнитель — только воркер флота по брифу, который дирижёр пишет прямо перед раздачей (раздел «Воркер флота» в /run-task). (6) Удалены /revise-task, /reconcile-task, глаголы task-block, task-result, task-revise, plan-seal, reconcile-seal (отвечают одной фразой, куда делись), находки blocker, stale-plan, plan-version, plan-retelling, unsealed и их ключи конфига. (7) Новые глаголы: `fraim tasks [--json]`, `task-new СЛАГ [--master | --parent М]` с телом на stdin, `task-master`, `task-seal СЛАГ "ИТОГ" [--dropped]`. (8) `fraim upgrade` и чистка механически переводят задачи старого формата в карточки (Summary → заголовок, Goal+Why → «Что и зачем», Acceptance Criteria → «Готово, когда»; план — в `ai/archive/legacy-plans/`); что не разобралось — карточка `fraim-migration` для /prune.
Alternatives: статусы канбана (inbox / в работе / готово) отвергнуты — у обычной задачи «в работе» не бывает, она либо лежит, либо сделана; вычислять тип мастер-задачи по наличию детей отвергнуто — большая задача без детей выглядела бы обычной, а агент мог бы сам решить, что она «слишком большая»; вложенные папки вместо `parent` отвергнуты — ссылку можно перецепить, дерево остаётся плоским; подсказка про дешёвого исполнителя в выводе `fraim tasks` отложена владельцем.
Consequences: план «под пол» больше нигде не пишется, кроме брифа воркера. В проектах со старыми задачами сторож даёт находку shape (ai/tasks:старый-формат), и `fraim upgrade` / `fraim clean` переводят их. Инвариант 0.4 держит сторож по коммитам кода, а не гейт на result.md.

## 2026-09-15 — the fleet mode is retired: reactive work always, the conductor only on the human's request (supersedes 2026-09-09 «two modes»)

Context: feedback from real use. The project switch `mode = fleet` made every session in the project a conductor, and the conductor dispatched work that was cheaper to do in place — raising a worker for one task is pointless. At the same time the routing table («a feature was agreed → /make-task, then /run-task») kept pushing the agent into the task ceremony on its own. The owner named the two real reasons to conduct: (1) economy — a conductor on a strong model spends tokens on management while workers on a cheap model write the code, and it may still edit itself when that is cheaper than dispatching; (2) work that clearly splits into different directions. Both are the human's call.
Decision: (1) no project mode: the `mode` and `check_parallel_drift` config keys are removed, and with them the conductor section of AGENTS.md, the SessionStart hook, the watchman's «work going around the build» finding and the menu item. (2) `/conductor` and `/make-task` run only when the human asks; the agent neither starts nor suggests them. The machine routing table, the `fraim` skill, `/investigate`, `/orient`, `/onboard`, `/bootstrap` and the templates stop routing structural work to `/make-task`. (3) `fraim mode` stays only to remove the old mode's leftovers (the `mode` line, the conductor section, our hook — nothing else), and `fraim mode --hook` is a silent exit 0 so a leftover hook never breaks a session. (4) Waves, collect and the conductor's acceptance stay; the lower size floors (≥3 per wave, ≥2 paths) are removed — a single-subtask build on one cheap worker is legitimate. The ceilings (≤6 subtasks, ≤5 per wave, ≤3 waves, ≤10 paths) stay as warnings.
Alternatives: the agent suggesting a fleet in one line when it sees a fit rejected by the owner (initiative is the human's); letting the agent start economy delegation by itself rejected likewise; removing waves along with the mode rejected (already built and tested, and harmless when the human starts every build); dropping `fraim mode` outright rejected (every project switched before carries a hook that calls it at session start).
Consequences: MODES.md §2 becomes one mode plus two procedures; the conductor procedure is rewritten for the two cases and allows the conductor its own edits when they cost less than a dispatch, never inside paths already handed out. Existing projects keep working; running `fraim mode` in a formerly-fleet project cleans it up.

## 2026-09-09 — the whole acceptance is the conductor's, trunk write included (supersedes the entry below)

Context: the entry below split «приёмка» into the conductor's checking and the human's ratification, but left the human two things the owner did not want them to have — a command to type (`git merge --no-ff fraim/<build>`, plus `dispatch return`) and a `report.md` artefact to open. The owner's correction was direct: the human types no commands at all, the report belongs in the terminal output rather than a file, and the trunk write is the conductor's too — because a build nobody merged has not been checked against the tree it has to live in.
Decision: (1) `fraim dispatch accept СБОРКА` now also writes the trunk: one `--no-ff` merge of the build branch into the branch the project root is on, carrying the `fraim:` trailer. (2) The report is printed to stdout; `report.md` is gone. (3) `fraim dispatch return` is gone with it — the human's negative answer is words in the chat, and the conductor records it in the build journal's «Уроки дирижёра». (4) The trunk write is skipped, loudly and with exit 1, whenever the machine already knows something is wrong: a non-zero `build_check`, a build that changed nothing, unsaved work in the project's tree, a conflict, a detached HEAD or the root standing on the build branch itself. These are facts, not judgements, so no human is called for them. (5) `verb_undo` learns `-m 1` for merge commits, which is what makes `fraim undo <merge>` a working one-command rollback of a trunk write — and the conductor types that too. (6) MODES.md §4 flips from вариант A to вариант B for the fleet, and B5 gains the two mechanical conditions under which a judgement stop may stand AFTER an action: the undo costs one command typed by the agent, and the machine refuses to act on what it knows is wrong.
Alternatives: keeping the gate before the trunk write (вариант A) rejected — the argument for A was that a refusal costs unwinding N interleaved results, and `collect` had already made that false: the build enters the trunk as ONE merge commit; pushing after the merge rejected (a local merge is not publication — the copy off the machine stays a separate decision, BACKLOG §3); asking the human to confirm before the merge rejected (that is the command the owner explicitly does not want to type, and B4 — the harness already gates what it gates); keeping `report.md` as a machine-readable trail rejected (the journal already carries the trail, and the file was tokens spent on something read once).
Consequences: `build_list` has two states again (`не принята` / `принята, в стволе`). `dispatch accept` returns 0 in the trunk, 1 checked-but-not-merged, 2 refused. A fleet project should set `build_check`, because without it the acceptance merges having run nothing — the output says so, in as many words. The conductor must be on the trunk with a clean tree when it accepts, which is now part of the procedure.

## 2026-09-09 — приёмка дирижёра: acceptance is work and is delegated, ratification is judgement and is not

Context: one word, «приёмка», carried two different things, and the CLI stamped only the second — `build_accept` wrote a time and a HEAD, while everything that should have preceded it (verify every subtask against the tree, look at the build as a whole, run the project's own checks, tidy up the checkouts and workers the fleet created) was a list of commands somebody had to remember to run one at a time in a chat. What reached the human was N diffs plus the word «принято», which is the opposite of what MODES.md §5 promises. The owner's framing settled it: the conductor is the one who has seen what was handed out and what came back, so the checking is his; the human reads his report, and saying "this part is wrong" IS the human's acceptance.
Decision: (1) `fraim dispatch accept СБОРКА` becomes the CONDUCTOR's stage and does four things — refuses while any subtask is uncollected; verifies the assembled branch against the union of the plan's declared paths (naming files no subtask declared: the build's own foundation, or a leak); runs the project's own check via the new `build_check` config key in a throwaway checkout of the build branch; cleans up. (2) It writes `ai/builds/<id>/report.md` — the single artefact the human reads — with a machine-filled «Чем заняться» and a «Словами дирижёра» section the conductor fills before handing it over. Findings do not suppress the report (a red check is a result, not a reason to stay silent); they make the command exit non-zero. (3) Чистка removes only what the build itself created and only when provably redundant: a worker checkout goes when its commit is already an ancestor of the build branch, uncommitted work is a refusal rather than a `--force`, and the build's own workers are released through the environment's own per-worker verb. (4) `fraim dispatch return СБОРКА "причина"` records the human's negative answer in the build journal and clears the acceptance, so the conductor checks and reports again. (5) B5 is restated rather than weakened: acceptance is work and is delegated; ratification — «годится?» plus the trunk write — is judgement and stays with the human, and the gate still stands before the trunk write, which no verb performs.
Alternatives: leaving acceptance with the human as before rejected (it made the human do the conductor's checking, which is the cost the mode exists to remove); giving the conductor the trunk write too rejected (that is MODES.md §4 вариант B — the refusal then costs an unwind of N interleaved results, handed to the person least able to do it); a separate `review` verb next to a human `accept` rejected (two verbs for one stage, and the old `accept` would have stayed a stamp with nothing behind it); raising the six-subtask ceiling now that a conductor does the reading rejected and written down as a trap in MODES.md §5 — a report over interleaved results is a retelling (A5), and the ceiling is set by verifiability, not by who reads; a project check baked into the procedure text rejected (the test command is project configuration, C1 — hence `build_check`).
Consequences: `build_list` has three states (`не принята` / `принята дирижёром — отчёт ждёт человека` / `возвращена человеком`), and «принята» no longer means «готово». `dispatch accept` now exits 1 when the report has findings and 2 when it refuses, so callers must distinguish. A build with no `build_check` configured says so in the report instead of implying a green check. Worker branches are deliberately left alone: their commits are already in the build branch, and deleting a branch we did not create is exactly the "what not to touch" question B6 forbids passing to the user.

## 2026-09-09 — the fleet gets order: waves, a per-wave barrier, and a collect stage

Context: the fleet refused the most common shape of real work. `dispatch_check` rejected any plan where two subtasks claimed one path, and the conductor procedure told the agent to offer the ordinary route in that case — so "the pieces overlap, I cannot isolate them" was the procedure being followed literally, not a model being lazy. Separately, nothing merged the workers' results at all: `build_accept` recorded a time and a HEAD, and integration was manual. A survey of prior art (DESIGN-fleet-prior-art.md) placed our fan-out among six control models and supplied the reasons below.
Decision: (1) a subtask may declare `**After**: id[, id]`; waves are DERIVED from that, never hand-numbered. (2) The path-collision check becomes per-wave: refused inside a wave, allowed across waves. (3) A strict barrier between waves — chosen over dependency-gated claiming because that model unblocks work on the executor's self-report, which is exactly what MODES.md §3 refuses to trust, and because polling worker state would require a scheduler of our own (MODES.md §10). (4) `fraim dispatch collect` merges a wave into a new per-build branch `fraim/<build>`, refusing on a missing checkout, uncommitted work, a file outside the declared paths, or a merge conflict; it prints the wave's combined diff, which is the only place a semantic divergence the path check cannot see becomes visible. (5) Workers now branch from the build branch, and `dispatch run` launches one wave — the first uncollected one. (6) The conductor's ladder out of a collision is ordered: group → redraw boundaries → order into waves → only then say it does not split. (7) The time threshold ("a piece longer than half an hour") is removed: nobody can measure it, and it read as a rule while working as the cheapest excuse to refuse. It is replaced by a comparison the conductor states out loud (dispatching is worth it when executing costs more than dispatching) and by four countable numbers derived from the single-acceptance ceiling — ≤6 subtasks per build, 3–5 per wave, ≤3 waves, 2–10 paths per subtask — all of them warnings, never refusals.
Alternatives: `**Wave**: N` written by hand rejected (a global fact needing manual renumbering on every edit, and a stale number is invisible to any check); dependency-gated claiming without a barrier rejected (see above; Claude Code agent teams documents the exact failure — "task status can lag: teammates sometimes fail to mark tasks as completed, which blocks dependent tasks"); speculative parallel merging à la Zuul rejected (it pays off when re-running the check is cheap, and re-running a worker costs a model and an hour); merging an out-of-lane change with a warning rejected (it would make the tree verification decorative); `dispatch accept` merging into the trunk rejected (the gate stands before the trunk write, MODES.md §4 вариант A).
Consequences: plans without `After` behave exactly as before — one wave. Builds created before this change have no build branch and `collect` says so rather than guessing. `fleet.tsv` is appended per wave instead of truncated. A build's acceptance now covers up to three waves, so the six-subtask ceiling is what keeps "one acceptance" honest — MODES.md §5 carries that arithmetic. Worker isolation remains file-only: ports, databases and caches are shared and no check sees them (BACKLOG §6).

## 2026-09-09 — two modes, not three: reactive is the default, fleet is the switch

Context: `MODES.md` described three modes (reactive, task, parallel), but the task mode was never one: by the five-row test in MODES.md §1 it differs from reactive in nothing, and the `mode` config key never switched it on — `task` was literally "not parallel". The name promised authority the code did not implement, and the agent read it as licence to write a task for itself and then execute it in the same session.
Decision: `mode` takes `reactive` (default) and `fleet`. The task ceremony (`/make-task` → `/run-task` → `task-seal`) stays as a PROCEDURE inside the reactive mode — the way to hand work to someone who is not in this conversation — and writing a task for yourself to execute in the same session is now stated as forbidden in the AGENTS.md project block. The legacy values `task` and `parallel` are read as `reactive`/`fleet` (mode_canon in config.sh) but never written; `fraim mode task|parallel` still works and warns. Every "is the fleet on here" test goes through `mode_get`, so a legacy value cannot silently fall back to the default.
Alternatives: renaming without legacy aliases rejected (every installed project carries `mode = parallel` in ai/fraim.conf and would silently lose the mode); keeping `parallel` as the name rejected (the human switches on a fleet, not a property of the work, and `fraim fleet` already exists); dropping `/make-task` along with the mode rejected (the fleet worker IS a `/run-task`, and handing work to another session is a real need).
Consequences: MODES.md §2 is now two modes and keeps the old anchor `#2-три-режима` so existing links do not break; the conductor procedure says `fraim mode fleet`. The refusal class "chunks overlap, cannot split" is untouched by this and is the next piece of work (sequential waves + a collect verb).

## 2026-09-08 — role picker agent list comes from the harness table, not Orca

Context: `roles_agents_available` asked Orca (`orca account list --json`) for the list of agents in the role picker, coupling the picker to a specific execution environment. Devin (a harness fraim installs into) was invisible because Orca doesn't list it as a provider; Kimi (not installed, not in the harness table) appeared because Orca knows it as a provider. The product is environment-agnostic — Orca is one possible ADE, not a dependency.
Decision: `roles_agents_available` now reads from `harness_detect` (harness.sh) — the same table fraim uses to install skills, probed by binary on PATH or home directory. `roles_providers` and `roles_parse_providers` removed as dead code. The picker shows only agents fraim knows and can serve; Orca remains the execution environment for fleet launch (a separate concern).
Consequences: an agent not in the harness table cannot be picked even if Orca can launch it — add it to `harness_table` first. A harness present on the machine but not on PATH appears via its home directory probe.

## 2026-09-08 — fleet launch waits for confirmed tui-idle and applies the model via a per-agent launch command

Context: Orca 1.4.196 + Devin CLI inject the orchestration preamble before the TUI is ready (agent_prompt_stalled at dispatch_input, every worker of a build dies), and Orca's worker-start --model supports only Claude/Codex/Cursor, so role-table models for other agents were silently dropped. Diagnosis archived in the youtube investigation fleet-agent-prompt-stalled.
Decision: fleet_worker_start becomes a two-path lifecycle with one contract. Native path (default): worker-start --agent --model --effort as before. Custom path (when a launch command is known via config launchcmd_<agent> or the devin built-in "devin --permission-mode bypass --model %s", or the agent is known no-launch-model): worktree create -> terminal create --command (model in argv) -> terminal wait --for tui-idle (config fleet_ready_timeout_ms, default 120000) -> worker-start --task --terminal --worktree, which keeps full task/dispatch provenance and worker lifecycle. Failures clean up best-effort: worker-release (dispatch recovered from the receipt or dispatch-show), terminal stop, worktree rm. No sleep anywhere; readiness is the terminal's own state. In-session model switching stays only as explicitly configured modelcmd_<agent>.
Alternatives: increasing sleep rejected (masks the race, still racy); a Devin-only branch rejected (next agent hits the same wall); dispatch --inject rejected (unsupervised, loses worker_done/stop/release accounting); always using the custom path rejected (bypasses Orca's launch.effective reporting for Claude/Codex/Cursor); guessing in-session commands for unknown agents rejected (silently corrupts the first task line).
Consequences: an agent whose launch argv changes needs a launchcmd_<agent> config update; a tui-idle timeout now fails the worker honestly instead of delivering a prompt into an unready TUI; the stub orca-ide in tests must answer the new subcommands.

## 2026-09-08 — role picker models come from per-agent live discovery, not a catalogue

Context: the roles picker offered only hardcoded claude suggestions plus already-configured models; a wrong id surfaced only at fleet launch, where it degraded silently. Investigations (archived findings 2026-09-08) confirmed every installed agent carries its own fresh model data.
Decision: the roles picker discovers models live from the chosen agent itself (roles_models_of): native listing command first (devin, pi, cursor-agent), cache file (codex) or embedded binary catalogue (claude) as fallback, typed value when nothing answers. Effort levels come from the same source where provided. No cache, no provider HTTP APIs, one tolerant parser per source tested against fixtures.
Alternatives: direct provider API queries rejected (keys, network, a second support surface); a baked catalogue rejected (treadmill P0); a single global parser rejected (formats differ per agent and drift independently); a TTL cache rejected (measured source latency 0.06-1.6s makes staleness pointless).
Consequences: an agent update can break its parser — the failure mode is an empty list degrading to the typed value, and fixture tests catch it before production.

## 2026-09-08 — onboarded: foundation derived from existing code

Foundation (ARCHITECTURE.md, CONVENTIONS.md) derived from the existing code: POSIX-shell CLI in installer/, 13 procedures in procedures/, plugin packaging, session traces in reports/. Ratified by the human; root docs (README, MODES, PRINCIPLES, DESIGN, AUDIT*, BACKLOG) treated as design input that may drift.
