# Ревизия: флот на новых харнесах — кто воркер, кто дирижёр

> **Решение владельца (2026-10-31).** Из четырёх вилок §3 взята одна — **субагенты самого
> харнеса** (С); безголовый запуск других харнесов (Б), ACP через `acpx` (A) и генерация
> определений субагентов (Ф2 в §6) отложены: выбор «свои субагенты или чужой харнес» — хрупкая
> дорожка. Orca и таблица ролей удалены, сборка — один круг задач с доски, приёмка закрывает
> задачи круга тем же слиянием ([DECISIONS.md](DECISIONS.md), 2026-10-31). Разбор ниже остаётся
> картой на случай, если к другим харнесам вернёмся.

> Дата: 2026-10-31 · Предмет: 28 строк `harness_table` против контракта флота
> ([MODES.md §9](MODES.md#9-контракт-ade--шесть-операций)) и рекомендации
> [AUDIT-FLEET.md](AUDIT-FLEET.md) §6.1 «исполнитель — подключаемый, по умолчанию — субагенты харнеса».
> Повод: ревизия флота писалась, когда в таблице было 9 харнесов (коммит `600c281`); через
> двадцать минут их стало 28. Её §6.1 оставил открытым «у Codex, pi, Hermes и Antigravity
> наличие и форму субагентов нужно проверить». Здесь проверено всё: кто из 28 может быть
> воркером без TUI, кто — дирижёром со своими субагентами, и как это ложится на флот.
>
> Пятая ревизия в ряду [AUDIT.md](AUDIT.md), [AUDIT-VERBS.md](AUDIT-VERBS.md),
> [AUDIT-PLAN-COST.md](AUDIT-PLAN-COST.md), [AUDIT-FLEET.md](AUDIT-FLEET.md). Где прочитано
> в самом пакете, а где — в документации или выдаче поиска, — в [§9](#9-что-прочитано-а-что-суждение).

## 0. Итог одним экраном

1. **За год харнесы сами стали средой исполнения.** Из 28 строк нашей таблицы у 25 есть
   безголовый запуск «один промпт до конца» (у 23 — с моделью в argv), у 13 — свои субагенты с
   файлами определений и моделью на агента, 23 говорят по ACP (трое — через адаптеры), и 17 из
   них уже есть в реестре готового безголового ACP-клиента `acpx`. Без локального безголового
   режима остались только Zed, Warp и ZCode.
2. **Значит, Orca для запуска воркера больше не нужна.** Годятся три тонкие вилки: субагенты
   самого дирижёра (**С**), безголовый процесс на воркера (**Б**), ACP через `acpx` (**A**). Вместе
   они закрывают W1, W3, W4, W5 и W7 аудита; Orca остаётся четвёртой и замораживается, как аудит
   и предлагал.
3. **Чего нет ни у одного харнеса — дисциплины приёмки.** Улика прямо из этого репозитория:
   31 октября шесть субагентов-переводчиков Claude Code в своих worktree правили общий
   `installer/locale/languages`, и конфликт разрешали руками при слиянии. `dispatch check`
   отказал бы на таком плане до раздачи. Запуск стал товаром (Copilot `/fleet`, Droid
   `--mission`), проверка — нет: это и есть ниша флота.
4. **Предложение** (§6): `fraim dispatch prepare` — чекауты волны, брифы и карточки запуска,
   только git → вилка С (процедура и сгенерированные определения воркера) → вилка Б (`run --exec
   headless`, блокирующий `wait`, `redo` через возобновление сессии, расход в `collected.tsv`) →
   вилка A. Какая вилка — решает таблица ролей, а не вкус дирижёра.
5. **Шесть развилок для владельца** (§8); главная — считать ли безголовый запуск «своей ADE»
   ([MODES.md §10](MODES.md#10-границы-чего-мы-не-строим)). Флаги в этой ревизии **прочитаны**
   в пакетах и документации, ни один харнес не запускался: каждая строка запуска до встраивания
   проходит живой прогон.

---

## 1. Мерка: что флот спрашивает у харнеса

Контракт [MODES.md §9](MODES.md#9-контракт-ade--шесть-операций) — шесть операций среды
исполнения. Год назад их давала только Orca. Теперь почти каждый харнес отвечает на них сам,
одним из трёх способов, и для каждого харнеса достаточно семи вопросов:

| | вопрос | что закрывает |
|---|---|---|
| **Б** | безголовый запуск: один промпт до конца без TUI, модель в argv, без вопросов человеку | §9.2–9.3; находка W4 (вставка в TUI) |
| **Ж** | машинный итог: JSON с исходом, расходом и фактической моделью | §9.5; W5 (нет учёта стоимости) |
| **В** | возобновить сессию воркера по id | W3 (нет переделки как глагола) |
| **С** | свои субагенты: файлы определений на уровне пользователя, модель на агента | §9.2–9.5 силами дирижёра; §6.1 аудита |
| **М** | модель субагента можно задать в момент вызова, без файла | нужен ли генератор определений |
| **A** | ACP-сервер (Agent Client Protocol) | один запускатель на всех |
| **Ф** | свой флот или фоновые агенты | среда исполнения или конкурент дирижёра |

Флаги вида `--worktree` есть у многих (Claude Code, Gemini, Qwen, Cline, Vibe, Hermes, Codex),
но в мерку не входят: чекаут воркера обязан ответвляться от `fraim/<build>` и называться
`<build>-<sub>` — именно так его находит `collect` (`dispatch_worker_tree`). Чужой worktree
ответвляется от текущей ветки и называется по-своему, поэтому чекаут готовит сам fraim.

---

## 2. Матрица

Версии — пакеты, опубликованные к 31 октября 2026. Знаки источника: **п** — прочитано в самом
пакете или бинарнике (флаги, справка, схема), **д** — официальная документация, **в** — только
выдача поиска, **?** — не нашлось.

### 2.1 Воркер: безголовый запуск

| харнес | безголовый запуск | модель · усилие | без вопросов | итог и расход | возобновить | ACP | ист. |
|---|---|---|---|---|---|---|---|
| Claude Code 2.1.316 | `claude -p` (stdin) | `--model` · `--effort` | `--permission-mode auto\|acceptEdits\|bypassPermissions` | `--output-format json`: `total_cost_usd`, `usage`, `modelUsage`, `session_id` | `--resume <id>` | адаптер `claude-agent-acp` | п |
| Codex 0.166 | `codex exec` (stdin `-`) | `-m` · `-c model_reasoning_effort=…` | `--sandbox workspace-write`; `--dangerously-bypass-approvals-and-sandbox` (`--full-auto` больше нет) | `--json`: `turn.completed` → `input/cached/output/reasoning_tokens`; `-o` последнее сообщение | `codex exec resume <id>` | адаптер `codex-acp` | п |
| Gemini CLI 0.66 | `gemini -p` (+ stdin) | `-m` · — | `--approval-mode yolo` | `--output-format json`: `response`, `stats`, `session_id` | `--resume` | `--acp` | п |
| Qwen Code 0.26.4 | `qwen -p` (+ stdin) | `-m` · — | `--approval-mode yolo` | `-o json`; `--max-wall-time`, `--json-file` | `-r <id>` | `--acp` | п |
| OpenCode 1.19.5 | `opencode run` | `-m prov/model` · `--variant` | `--auto` | `--format json`: `step_finish` → `tokens`, `cost` | `-s <id>` | `opencode acp` | п |
| Kilo Code 7.8.18 | `kilo run` | как OpenCode | `--auto` | как OpenCode; `kilo stats` | `-s <id>` | `kilo acp` | п |
| Cline 3.0.74 | `cline "<prompt>"` (TUI только с `-i`) | `-P`, `-m` · `--thinking` | `-y` (ограниченный набор) | `--json` | `--id <id>` | `--acp` | п |
| Factory Droid 1.1.0 | `droid exec -f <файл>` | `-m` · `-r` | `--auto low\|medium\|high` | `-o json\|stream-json` | `-s <id>` | `-o acp` | п |
| Augment 0.36 | `auggie -p -if <файл>` | `-m` · — | ? | `--output-format json`, `--show-cost` | `-r <id>` | `--acp` | п |
| Continue cn 1.5.47 | `cn -p` | только через `--config` / hub · — | `--auto` | `--format json` | `--resume` (последняя) | — | п |
| Kimi Code 2.4.1 | `kimi -p` | `-m <алиас>` · — | `--auto` | `--output-format stream-json` | `-S <id>` | `kimi acp` | п |
| Mistral Vibe 3.0.4 | `vibe -p` | `--model <алиас>` · — | `--auto-approve` | `--output json`; `--max-price` | `--resume <id>` | `vibe-acp` | п |
| Hermes 0.19 | `hermes -z` | `-m prov/model` · — | `--yolo` | `--usage-file`: цена, токены, модель — пишется и при сбое | `-r <id>` | `hermes-acp` | п |
| pi 1.4.0 | `pi -p` (+ stdin) | `--model prov/id` · `--thinking` | не нужно: вопросов нет вовсе | `--mode json`: `usage` с `cost` | `--session <id>` | адаптер `pi-acp` | п |
| omp 18.14 | `omp -p` | `--model` · `--smol`/`--slow` | `--yolo` | `--mode json` | `--continue`, `--fork` | `--mode acp` | п |
| OpenClaw 2026.10 | `openclaw agent exec --message-file <файл> --cwd <dir>` | `--model` + цепочка запасных | конфиг | `--json`; код 0/1 | `--state-dir` | `openclaw acp` | п |
| Copilot CLI 1.0.105 | `copilot -p` | `--model` · — | `--allow-all-tools` | печатает использованную модель (без `-s`); JSON — ? | ? | `--acp --stdio` | д |
| Crush 0.99 | `crush run` (+ stdin) | `-m` · — | `-y` | только текст | `-s <id>` | — | д |
| Junie 1468 | `junie "<prompt>"` | `--model` · — | allowlist `~/.junie/allowlist.json` | `--output-format json` | ? | `--acp=true` | в |
| Cursor | `cursor-agent -p` | `--model <slug>` · в slug | `--force` / `--yolo` | `--output-format json\|stream-json` (json — один объект в конце) | ? | `cursor-agent acp` | д, в |
| Kiro | `kiro-cli chat --no-interactive` | флага нет: `model` в конфиге агента или `chat.defaultModel` | `--trust-all-tools` | только текст | ? | `kiro-cli-chat acp` | д |
| Antigravity | `agy -p` | `--model` (по адаптерам) · — | ? | `--output-format json\|stream-json` | ? | `agy_acp_server.par` | в |
| Devin CLI | `devin -p` | `--model` · — | `--permission-mode bypass` | ? | ? | `devin acp` | д, в |
| Goose 1.53 | `goose run -t "<prompt>"` | `--provider`, `--model` · — | только переменная `GOOSE_MODE=auto` | `--output-format json\|stream-json` | `--no-session` / сессии | `goose acp` | д, в |
| Grok Build | `grok -p` | `-m` · — | `--always-approve` | `--output-format json\|streaming-json` | `-r`, `-s`, `-c` | `grok agent stdio` | д |
| Zed | **нет**: встроенный агент без редактора не запускается | — | — | — | — | только клиент ACP | д |
| Warp | **нет** локально (`warp` — интерактив); облако — Oz CLI | у облачных агентов | ? | ? | ? | — | д, в |
| ZCode | **нет**: только `zcode app-server --stdio` и мост `zcode-acp` от сообщества | — | — | — | — | мост сообщества | в |

### 2.2 Дирижёр: субагенты и свой флот

| харнес | определения субагентов | модель на агента | модель при вызове | свой флот / фон | ист. |
|---|---|---|---|---|---|
| Claude Code | `~/.claude/agents/*.md`; ключи: `model`, `effort`, `permissionMode`, `maxTurns`, `isolation: worktree`, `background`, `omitClaudeMd` | да | да, но только алиасы (`haiku`, `sonnet`) | `--bg` + `claude agents --json`, `logs`, `stop`, `rm`; `--cloud` | п |
| Codex | `~/.codex/agents/*.toml`: `name`, `description`, `developer_instructions` + переопределения конфига; `[agents] max_threads`, `default_subagent_model` | да | да (`spawn_agent`, поле `model`) | `codex cloud exec / status / diff / apply` | п |
| Gemini CLI | `~/.gemini/agents/*.md`, строгая схема: `model`, `tools`, `max_turns`, `timeout_mins` | да | нет | — | п |
| Qwen Code | `~/.qwen/agents/*.md`: `model`, `approvalMode`, `background`, **`executor: {kind: acp\|codex}`** — субагента исполняет другой харнес | да; или другой харнес | да | «арена»: одна задача на нескольких моделях | п |
| OpenCode | `~/.config/opencode/agents/*.md`, `mode: subagent` | да, любой провайдер | нет | `opencode serve` | п |
| Kilo Code | `~/.config/kilo/agents/*.md`; `kilo agent create` | да, любой провайдер | нет | `kilo worktree`, `kilo cloud start/status/result`, демон | п |
| Factory Droid | `~/.factory/droids/*.md` («custom droids») | вероятно (`model`) | нет | **`droid exec --mission --worker-model … --validator-model …`** | п (ключ модели — ?) |
| Augment | `~/.augment/agents/*.md`: `model`, `tools`, `disabled_tools` | да | нет | демон, облачные агенты | п |
| Copilot CLI | `~/.copilot/agents/*.md`, `.github/agents/`: `model`, `tools` | да | нет | **`/fleet`** (апрель 2026), `/delegate` | д |
| omp | `~/.omp/agent/agents/*.md` | да | да (пин модели в задаче, изоляция, пакеты) | — | п |
| Mistral Vibe | `~/.vibe/agents/*.toml`, `agent_type = "subagent"` | ? | нет | — | п |
| Kimi Code | `.kimi-code/agents`, `--agent-file <md>` | ? | ? | фоновые субагенты | п |
| Cline | файлов нет: инструмент spawn и «команды агентов» | ? | ? | `--zen` (фоновый хаб), **`--kanban`** | п |
| Continue | бета: модели с ролью `subagent` в конфиге | да | — | `cn serve` | п |
| Hermes | файлов нет: `delegate_task` | ? | ? | шлюз, cron | п |
| OpenClaw | файлов нет: `sessions_spawn`, `runtime: "acp"` → внешние харнесы | в конфиге (`agents.defaults.subagents.model`) | нет | шлюз | п |
| pi | **нет по замыслу** («skips sub-agents») | — | — | — | п |
| Crush | не найдено | — | — | `crush server` | д |
| Junie | не найдено | — | — | — | в |
| Cursor | `~/.cursor/agents/*.md` (читает и `.claude/`, `.codex/`): `model`, `readonly`, `is_background` | да (на форуме — баг: иногда наследует модель родителя) | нет | Cloud Agents | д, в |
| Kiro | `~/.kiro/agents/*.json`: `model`, `tools`, `toolsSettings`; дирижёру нужен инструмент `subagent` | да (наследует ли субагент — ?) | нет | ? | д |
| Antigravity | ? | ? | ? | Agent Manager в IDE — без CLI | в |
| Devin CLI | `~/.config/devin/agents/<имя>/AGENT.md` (экспериментально; импортирует агентов из `.claude/`) | да | ? | облачные сессии Devin | д |
| Goose | файлов нет: динамические субагенты, под-рецепты `--sub-recipe` | нет | нет | — | д |
| Grok Build | файлов нет: фоновые субагенты (`--background-wait-timeout`) | ? | ? | — | д |
| Zed | — | — | — | параллельные агенты в редакторе (Zed 1.0) | д, в |
| Warp | профили агентов | ? | — | облачные агенты Oz | д, в |
| ZCode | ? | — | — | — | — |

---

## 3. Четыре способа поднять воркера

Из матрицы следуют четыре вилки. Сравнение по контракту §9:

| операция §9 | С: субагенты дирижёра | Б: безголовый процесс | A: ACP через `acpx` | Orca (сейчас) |
|---|---|---|---|---|
| 1. чекаут | fraim: `git worktree add` | fraim | fraim | `worktree create` |
| 2. агент на модели | определение `model:` или параметр вызова | argv: `--model` | `acpx --model` (если агент объявил модели) | `worker-start --model` / launchcmd / `/model` в TUI |
| 3. задание | промпт вызова | stdin, `-f`/`--message-file` или argv | `--file` | `task-create` + вставка в TUI |
| 4. жив ли | вызов ещё не вернулся | процесс жив | сессия `acpx … status` | `worker-show`, опрос |
| 5. исход | **вызов возвращает отчёт** | код выхода + JSON | `stopReason` в NDJSON | `worker_done` (если воркер позвал) |
| 6. уборка | харнес; worktree — `build_accept` | worktree — `build_accept` | `sessions close` | `worker-release` |
| другой вендор | нет (кроме мульти-провайдерных, см. ниже) | **да** | да | да |
| переживает сессию дирижёра | нет | **да** | да (сессии `acpx`) | да |
| учёт расхода (W5) | плохо: харнес отдаёт сводку, не всегда | **да**, где есть JSON | частично | нет |

### 3.1 Субагенты дирижёра

Дирижёр зовёт воркеров своим инструментом (Task / Agent / `spawn_agent`), вызов возвращается с
отчётом. Это ровно то, что аудит назвал §6.1, и это «не свой оркестратор»: оркестратор — сам
харнес. fraim готовит чекауты и брифы, дальше работают `collect` и `accept` без изменений.

Новое по сравнению с аудитом:

- **субагенты есть у большинства** — список в §2.2; у Codex они есть (`~/.codex/agents/*.toml`,
  инструмент `spawn_agent` с полем `model`), у pi нет и не будет («skips sub-agents» — его
  принцип), у Hermes есть `delegate_task`, но без файлов определений;
- **модель при вызове** задают только Claude Code (параметр `model`, но только алиасы — `haiku`,
  `sonnet`, а таблица ролей хранит полные id), Codex, omp и Qwen. У OpenCode, Kilo, Gemini,
  Droid, Copilot, Augment модель живёт только в файле определения — значит, fraim должен этот
  файл сгенерировать, как генерирует скиллы;
- **«другой вендор» больше не абсолютный запрет**: субагент OpenCode, Kilo, Cline, Augment
  берёт модель любого провайдера, а субагент Qwen Code может исполняться **другим харнесом** —
  `executor: {kind: acp | codex}`; встроены делегаты `claude-code` (через `claude-agent-acp`)
  и `codex`. OpenClaw умеет то же через `sessions_spawn({ runtime: "acp" })`;
- **W6 закрывается настройкой**: у определения Claude Code есть ключ `omitClaudeMd` — воркер не
  получает `CLAUDE.md` с правилом «обнови фундамент».

Пределы: субагент умирает вместе с сессией дирижёра; расход по воркерам видно не везде; свой
`isolation: worktree` у Claude Code ответвляется от текущей ветки в `.claude/worktrees/` — для
флота не годится (см. §1), поэтому чекаут по-прежнему делает fraim.

### 3.2 Безголовый процесс на воркера

fraim запускает в каждом чекауте `<харнес> <флаги> --model M`, ждёт выхода и читает JSON. Это
есть почти у всех (§2.1), и это закрывает сразу четыре находки аудита: нет вставки в TUI (W4),
итог и расход в JSON (W5), переделка — возобновление той же сессии в том же чекауте (W3), и нет
опроса: `fraim dispatch wait` блокируется до выхода и печатает по строке на воркера (W7).

Таблица ролей уже говорит `агент:модель:усилие` — безголовый запуск берёт её как есть, включая
`devin:glm-5.2` из первого живого прогона. Механизм шаблона тоже уже есть: `fleet_launch_command`
с `%s` под модель и переопределением `launchcmd_<agent>` из конфига. Меняется только то, что
шаблон — безголовая строка, а не команда для терминала Orca.

Цена: fraim начинает запускать процессы (pid, код выхода, файл вывода, таймаут) — это
развилка с MODES §10, см. §8; и таблица флагов — беговая дорожка: в Codex 0.166 уже нет
`--full-auto`, Vibe с 2.11.1 перестал подтверждать всё в `-p`, Gemini объявил
`--experimental-acp` устаревшим в пользу `--acp`, Crush заменил `-p` на `run`.

### 3.3 ACP через `acpx`

`acpx` (npm, 0.21.1, авторы OpenClaw) — «headless CLI client for the Agent Client Protocol».
Одна форма вызова для всех: `acpx --cwd <чекаут> --model M --approve-all --format json <агент>
exec --file <бриф>`; итог — NDJSON-события ACP со `stopReason`, есть `--timeout`, именованные
сессии для переделок и `compare` (один промпт нескольким агентам). Главное — **его реестр уже
знает команду ACP-запуска для 17 харнесов из нашей таблицы**: `gemini --acp`, `qwen --acp`,
`kimi acp`, `opencode acp`, `kilo acp`, `cursor-agent acp`, `copilot --acp --stdio`, `devin acp`,
`droid exec --output-format acp`, `grok agent stdio`, `junie --acp=true`, `kiro-cli-chat acp`,
`openclaw acp`, `agy_acp_server.par` (Antigravity), адаптеры `claude-agent-acp`, `codex-acp`,
`pi-acp`. Беговую дорожку флагов `acpx` берёт на себя.

Цена: зависимость от Node ≥ 22.13 и пре-1.0 интерфейса; модель задаётся, только если агент
объявил её через ACP; расход в событиях не гарантирован. Поэтому — необязательная вилка, когда
`acpx` есть в `PATH`, а не основа.

### 3.4 Встроенные флоты харнесов — не исполнители

Трое уже везут собственного дирижёра, который сам делит работу: Factory Droid (`droid exec
--mission --worker-model … --validator-model …`), Copilot (`/fleet`, апрель 2026), Cline
(«команды агентов», `--kanban`). По логике [ADE_TARGETS.md](installer/ADE_TARGETS.md)
инструмент, который сам решает, что кому делать, — не среда, а конкурирующий дирижёр:
интегрироваться с ним нельзя, можно только выбрать одного из двух. Отдать ему сборку — значит
обойти проверку плана. «Арена» Qwen Code — другое: одна задача на нескольких моделях, то есть
сравнение, а не раздача.

Отдельно стоят **фоновые менеджеры без планирования**: `claude --bg` + `claude agents --json` +
`claude rm` (удаляет и свой worktree), `codex cloud exec / status / diff / apply`, `kilo cloud
start / status / result`, облачные агенты Cursor, Warp (Oz) и Devin. Это настоящие среды по §9,
включая долгий фон, ради которого аудит оставлял Orca. Кандидаты на потом, после вилок С и Б.

---

## 4. Что это меняет в находках аудита

| находка AUDIT-FLEET | было | стало |
|---|---|---|
| **W1** исполнитель — только Orca | субагенты «не рассматривались» | вилка Б есть у 25 харнесов из 28, вилка С — у 13; Orca — четвёртая |
| **W3** нет переделки как глагола | дирижёр уходил в сырой CLI Orca | возобновление сессии воркера есть почти у всех: `claude --resume`, `codex exec resume`, `opencode run -s`, `droid exec -s`, `gemini --resume`, `qwen -r`, `kimi -S`, `pi --session`, `cline --id`, `vibe --resume`, `auggie -r`, `crush -s`, `grok -r`, `hermes -r` → глагол `fraim dispatch redo` |
| **W4** управление чужим TUI | регэкспы, `tui-idle`, баннер, `/model` в терминал | в вилках С и Б TUI нет вовсе; эта часть `fleet.sh` остаётся только для Orca |
| **W5** нет учёта стоимости | ответить на вопрос аудита можно было только археологией трейсов | JSON-итог с расходом: Claude Code (`total_cost_usd`, `modelUsage`), Codex (`turn.completed` → токены), OpenCode и Kilo (`step_finish` → `tokens`, `cost`), pi и omp (`usage.cost`), Gemini и Qwen (`stats`), Hermes (`--usage-file` — пишется даже при сбое), Augment (`--show-cost`) |
| **W6** воркер слушается блока AGENTS.md | `DECISIONS.md` тронут в 2 из 4 подзадач | строка в блоке (аудит §6.5) остаётся главным средством; где можно — выключить подгрузку: `omitClaudeMd` в определении Claude Code, `--no-context-files` у omp |
| **W7** опрос — 9% контекста дирижёра | `watch`, `check --wait` | субагент возвращается сам; для безголовых — блокирующий `dispatch wait` с одной строкой на воркера |
| §6.1, открытый вопрос | «у Codex, pi, Hermes, Antigravity — проверить» | Codex — да; pi — нет по принципу; Hermes — `delegate_task` без файлов определений; Antigravity — не нашлось (§2.2) |
| §6.4 субагенты для чтения | `investigate` живёт только во флоте | читающий субагент на дешёвой модели доступен почти везде; у Codex (`explorer`) и Vibe (`explore`) он встроен |

Оценка, не измерение: в сборке 2.2 справки Orca, учёт диспетчей и опрос заняли 19% + 12% + 9% =
**40%** вывода инструментов в контексте дирижёра. Вилки С и Б заменяют это одной командой
подготовки и одной строкой на воркера. Ревью, слияние и проверки (46%) остаются — это и есть
цена сверки, и снижает её только `build_check` (аудит §6.3), а не смена исполнителя.

## 5. Почему дисциплина флота нужна и при «бесплатном» запуске

Запуск стал товаром: Copilot `/fleet`, Droid `--mission`, субагенты в worktree у Claude Code.
Приёмка — нет. Две улики:

- **в этом репозитории** 31 октября локализацию собирали девять субагентов Claude Code в своих
  worktree (ветки `worktree-agent-*`). Шесть переводчиков, кроме своего
  `installer/locale/<lang>/`, правили общий `installer/locale/languages`; слияние `4b9221e`
  записало `# Conflicts: installer/locale/languages`, конфликт разрешали руками. `dispatch
  check` отказал бы на таком плане **до раздачи** (пересечение путей внутри волны), а лестница
  выхода из коллизии предложила бы очевидное: шесть строк в `languages` дописывает дирижёр;
- **блог GitHub про `/fleet`** предупреждает о том же своими словами: два агента пишут один файл
  — побеждает последний; «давайте агентам разные файлы».

Значит, позиционирование флота сужается и проясняется: fraim не запускает лучше харнеса — он
**проверяет**: объявленные пути, волны из `After`, сверка с деревом, `collect` с отказом на
чужом пути, одна приёмка с `build_check`, откат одной командой. Исполнитель — заменяемая
деталь, и чем тоньше вилка к нему, тем лучше.

---

## 6. Предложение реализации

Порядок — от дешёвого к дорогому; каждая фаза полезна сама по себе.

**Ф0. Из аудита, как было** (§6.5 и §6.2 AUDIT-FLEET): W8, W9, строка W6 в блоке AGENTS.md,
секция `## Contract` в плане. Ни одна из них не зависит от исполнителя.

**Ф1. `fraim dispatch prepare BUILD` — операция §9.1 без ADE.** Только git. Для первой
несобранной волны (барьер тот же, что у `run`): на каждую подзадачу
`git worktree add <каталог>/<build>-<sub> -b fraim/<build>-<sub> fraim/<build>` (повторный
вызов ничего не ломает), бриф — как сейчас, роль → `агент:модель:усилие` через `roles_resolve`.
Печатает по карточке на подзадачу: чекаут · бриф · агент, модель, усилие · строка запуска или
«субагент». В `fleet.tsv` — вид исполнителя и чекаут. Это и есть «ручной путь», который
`/conductor` уже описывает словами («открой task.md и выполни в своём чекауте»), только теперь
чекаут создан, назван и ответвлён правильно. `collect` и `accept` не меняются.

**Ф2. Вилка С — субагенты дирижёра.** Шаг 4 `/conductor`: «если роль подзадачи — твой же харнес
и у него есть субагенты, подними по субагенту на карточку, параллельно; промпт — бриф и путь к
чекауту; дождись всех; дальше `collect`». Где модель нельзя передать при вызове (OpenCode, Kilo,
Gemini, Droid, Copilot, Augment, Vibe) или можно только алиасом (Claude Code), `fraim init` и
`fraim roles set` генерируют определение `fraim-<роль>` в каталог агентов харнеса — рядом со
скиллами, с той же меткой `source: fraim` и тем же правом забрать своё. Внутри: правила воркера
W1–W5, модель и усилие из таблицы ролей, выключатели W6 (`omitClaudeMd: true` у Claude Code).
Форматов два: markdown с YAML (у каждого свой список ключей; Gemini отвергает лишние) и TOML
(Codex: `name`, `description`, `developer_instructions`, `model`, `model_reasoning_effort`;
Vibe: `agent_type = "subagent"`). Каталоги — новая колонка таблицы харнесов.

**Ф3. Вилка Б — безголовый процесс.**
- `fraim dispatch run BUILD --exec headless`: Ф1, затем в каждом чекауте отвязанный процесс
  `строка > ai/builds/<id>/<sub>.out`, код выхода — в `<sub>.exit`, pid — в `fleet.tsv`;
- `fraim dispatch wait BUILD [--timeout S]`: блокируется до выхода всех (или до таймаута —
  инструмент оболочки у харнеса дирижёра сам ограничен минутами) и печатает по строке:
  `<sub>  код  время  модель  токены вход/выход  цена`; что формат не отдал — «—» и путь к сырому
  файлу. Расход идёт в `collected.tsv` — это и есть учёт W5;
- `fraim dispatch redo BUILD SUB "возражение"`: возобновить сессию того же воркера в том же
  чекауте (id сессии — из его JSON) и записать возражение в журнал — это W3;
- таблица строк запуска рядом с `fleet_launch_command`: агент → шаблон с `{model}`, `{effort}`,
  `{brief}`, `{checkout}`. Встроенной строка становится только после живого прогона (решение
  2026-10-31: «no new built-in fleet launch command — none was run live»); остальное —
  `launchcmd_<agent>`, который уже есть: человек учит fraim новому харнесу одной строкой.

Строки-кандидаты — прочитаны в пакетах или документации, ни одна не запускалась:

| агент | строка |
|---|---|
| claude | `claude -p --model {model} --effort {effort} --permission-mode auto --output-format json < {brief}` |
| codex | `codex exec -m {model} -c model_reasoning_effort={effort} --sandbox workspace-write --add-dir {gitdir} --json - < {brief}` |
| opencode, kilo | `opencode run -m {model} --variant {effort} --auto --format json "$(cat {brief})"` (то же — `kilo run`) |
| gemini | `gemini -m {model} --approval-mode yolo --output-format json -p "Execute the brief above." < {brief}` |
| qwen | `qwen -m {model} --approval-mode yolo -o json --max-wall-time 45m -p "Execute the brief above." < {brief}` |
| droid | `droid exec -f {brief} -m {model} -r {effort} --auto medium -o json --cwd {checkout}` |
| augment | `auggie -p -if {brief} -m {model} --output-format json -w {checkout}` |
| pi | `pi -p --model {model} --thinking {effort} --mode json "Execute the brief above." < {brief}` |
| hermes | `hermes -z "$(cat {brief})" -m {model} --yolo --usage-file {out}.usage.json` |
| kimi | `kimi -p "$(cat {brief})" -m {model} --auto --output-format stream-json` |
| vibe | `vibe -p "$(cat {brief})" --model {model} --auto-approve --output json --workdir {checkout}` |
| devin | `devin -p --model {model} --permission-mode bypass "$(cat {brief})"` (по документации) |
| cursor | `cursor-agent -p --force --model {model} --output-format json "$(cat {brief})"` (по документации) |
| grok | `grok -p -m {model} --always-approve --output-format json --cwd {checkout} "$(cat {brief})"` (по документации) |
| goose | `GOOSE_MODE=auto goose run -t "$(cat {brief})" --model {model} --output-format json --no-session` (по документации) |

`{gitdir}` — общий каталог git проекта (`git rev-parse --git-common-dir`), см. §7.2; `{out}` —
файл вывода воркера в `ai/builds/<id>/`.

**Ф4. Вилка A — `acpx`, если он есть в `PATH`.** Та же Ф3, строка одна на всех:
`acpx --cwd {checkout} --model {model} --approve-all --format json --timeout {s} <агент> exec --file {brief}`;
имя агента — из реестра `acpx`, для остальных — `--agent '<команда ACP>'`.

**Ф5. Orca — заморозка** (аудит §7): без новых функций, только починка; пересмотр после
нескольких сборок по данным учёта из Ф3.

Как выбирается вилка — детерминированно, из таблицы ролей, а не вкусом дирижёра: агент роли =
харнес дирижёра и у харнеса есть субагенты → С; иначе есть строка запуска (встроенная или
`launchcmd_<agent>`) → Б; иначе есть `acpx` и агент в его реестре → A; иначе есть Orca → Orca;
иначе — карточки из Ф1 и ручной путь.

## 7. Риски и ловушки

1. **«Без вопросов» — это права пользователя ОС.** `--yolo`, `bypassPermissions`,
   `--skip-permissions-unsafe` разрешают воркеру всё, что может сам человек; у pi системы
   разрешений нет вовсе. Сверка с деревом сторожит репозиторий, а не машину. Брать самый узкий
   режим, в котором воркер правит, гоняет тесты и коммитит: песочница Codex
   (`--sandbox workspace-write`), `--permission-mode auto` у Claude Code, `-y` у Cline
   («ограниченный набор»), `--auto medium` у Droid; полный обход — только по слову человека.
2. **Песочница, ограниченная чекаутом, не даст закоммитить.** В связанном worktree `.git` — это
   файл со ссылкой на `<корень>/.git/worktrees/<имя>`, объекты лежат в `<корень>/.git/objects`,
   то есть вне чекаута. Codex нужен `--add-dir` на общий каталог git; проверить вживую для каждой
   строки с песочницей.
3. **Бриф лежит вне чекаута** (`ai/parallel/…` в корне). Харнес, запертый в чекауте, может его не
   прочитать — поэтому в строках выше бриф идёт через stdin, `-f`, `-if`, `--message-file`, а не
   путём.
4. **Беговая дорожка флагов** (§3.2). Защита — строка встраивается только после живого прогона;
   метод уже есть: проверка харнесов 2026-10-31 подставляла локальный сервер, притворяющийся
   моделью, и читала первый запрос — здесь тот же стенд заодно покажет, что argv принят и какой
   формат у JSON. И правило, которое `fleet.sh` уже записал: неверный argv — это задача, которая
   молча не стартовала; значит, незапустившийся воркер обязан падать громко (код выхода и файл
   вывода), а не числиться запущенным.
5. **Изоляция только по файлам** (Known Pitfalls) никуда не делась, и к ней добавляется лимит
   провайдера: пять воркеров на одной подписке упираются в один и тот же предел (поэтому у Codex
   есть `max_threads`, у omp — ограничение параллельности по провайдеру).
6. **Отчёт субагента входит в контекст дирижёра.** Бриф должен просить отчёт в несколько строк —
   иначе дирижёр снова платит за то, что флот сэкономил.

## 8. Развилки, требующие слова владельца

1. **Безголовый запуск — это «своя ADE» по MODES §10?** Моя позиция: нет. §10 запрещает
   рантайм — PTY, менеджер worktree, десктоп, аккаунты, планировщик. Запустить документированный
   CLI в каталоге и дождаться кода выхода — это `make -j`, а worktree и сейчас делает git. Но
   текст границы в §10 меняется, поэтому нужно слово владельца, а потом запись в DECISIONS.
2. **С какой вилки начать.** Моя позиция: Ф1 → Ф2 → Ф3 → Ф4. Довод за обратный порядок Ф2/Ф3:
   безголовая вилка межвендорная и считает деньги, а первый живой прогон владельца был именно
   межвендорным (`devin:glm-5.2`).
3. **`acpx`** — только необязательная вилка (моя позиция) или не опираться вовсе.
4. **Где живут чекауты воркеров.** Внутри проекта в игнорируемом каталоге (как
   `.claude/worktrees/`, `.qwen/worktrees/`) — тогда до них дотягиваются песочницы харнесов,
   запертые в проекте; или рядом с проектом, как делает Orca. Моя позиция: внутри, каталог
   добавляют в `.gitignore` `scaffold` и `upgrade`.
5. **Встроенные флоты харнесов.** Моя позиция: одна строка в `/conductor` — «не отдавай сборку
   собственному флоту харнеса (`/fleet`, `--mission`): он обходит проверку плана».
6. **Коммитит ли `wait` брошенную воркером работу.** Первый живой прогон: воркер не
   закоммитил, коммитил дирижёр руками. Моя позиция: да — после кода выхода 0, одним коммитом с
   именем подзадачи в чекауте воркера; `collect` по-прежнему проверяет пути.

---

## 9. Что прочитано, а что суждение

| утверждение | как получено |
|---|---|
| флаги Codex, Gemini CLI, Qwen Code, OpenCode, Kilo, Cline, Droid, Augment, Continue, Kimi, pi, omp, OpenClaw, Mistral Vibe, Hermes | прочитаны статически в опубликованных пакетах npm и PyPI: JS-бандлы, строки платформенных бинарников (`strings`; у Kilo — UTF-16), справка и скиллы, лежащие в самом пакете. Ничего не установлено и не запущено: установка с install-скриптами в этой среде запрещена, а чтение пакета как данных безопаснее |
| Claude Code | `--help` установленного 2.1.316 и строки его бинарника: список ключей определения агента, поля JSON-итога |
| реестр `acpx` (команды ACP-запуска 17 наших харнесов) | прочитан в пакете `acpx` 0.21.1, `dist/agent-registry-*.js` |
| Copilot CLI, Crush, Junie | официальная документация через выдачу поиска: JS Copilot в бинарнике сжат, Crush и Junie скачивают бинарник с GitHub, закрытого из этой среды |
| Cursor, Kiro, Antigravity, Devin CLI, Goose, Grok Build, Zed, Warp, ZCode | официальная документация через выдачу поиска; сами сайты отсюда недоступны, страницы целиком не прочитаны — ячейки с «в» особенно требуют сверки |
| сборка локализации этого репозитория | `git diff --name-only` по каждому слиянию `worktree-agent-*` и сообщение слияния `4b9221e` |
| «смена исполнителя снимает ~40% накладных дирижёра» | оценка по долям AUDIT-FLEET §2.2, не измерение |
| «флаг работает» | **не проверено ни для одного харнеса**: прочитано ≠ запущено |

Источники документации: [Copilot CLI programmatic reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-programmatic-reference) ·
[Copilot `/fleet`](https://github.blog/2026/04/01/run-multiple-agents-at-once-with-fleet-in-copilot-cli/) ·
[Crush `run`](https://next-docs.charm.land/crush/cli/run.html) ·
[Junie headless](https://junie.jetbrains.com/docs/junie-headless.html) ·
[Cursor headless](https://cursor.com/docs/cli/headless) · [Cursor subagents](https://cursor.com/docs/subagents) ·
[Kiro headless](https://kiro.dev/docs/cli/headless/) · [Kiro subagents](https://kiro.dev/docs/cli/chat/subagents) ·
[Devin essential commands](https://docs.devin.ai/cli/essential-commands) · [Devin subagents](https://docs.devin.ai/cli/subagents) ·
[Goose CLI commands](https://goose-docs.ai/docs/guides/goose-cli-commands) · [Goose subagents](https://goose-docs.ai/docs/guides/subagents) ·
[Grok Build headless](https://docs.x.ai/build/cli/headless-scripting) ·
[Zed external agents](https://zed.dev/docs/ai/external-agents) · [Zed #59146](https://github.com/zed-industries/zed/discussions/59146) ·
[Warp Agent CLI](https://docs.warp.dev/agents/cli/) · [zcode-acp](https://github.com/william0wang/zcode-acp) ·
[acpx](https://www.npmjs.com/package/acpx).
