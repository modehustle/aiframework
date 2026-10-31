# Целевые харнесы и точки интеграции

> Вход в проектирование инсталлера. По каждому харнесу: какие вообще есть способы
> в него встроиться, и в какой из них имеет смысл целиться нам.
> Срез популярности — рейтинг приложений OpenRouter по расходу токенов (август 2026),
> плюс Devin CLI и Devin Desktop, которых в топ-10 нет, но которые важны как класс.
>
> **Октябрь 2026: список расширен до 28 харнесов, пути сверены по первоисточникам.** Раздел
> [Срез октябрь 2026](#срез-октябрь-2026) действует поверх всего, что ниже: часть путей
> августовского среза оказалась неверной (pi, omp, Devin, Hermes, Antigravity CLI).

## Оглавление

- [Срез октябрь 2026](#срез-октябрь-2026)
- [Главный вывод](#главный-вывод)
- [Что мы вообще встраиваем](#что-мы-вообще-встраиваем)
- [Сводная таблица](#сводная-таблица)
- [Разбор по харнесам](#разбор-по-харнесам)
- [Рекомендация по инсталлеру](#рекомендация-по-инсталлеру)
- [Что это меняет в репозитории](#что-это-меняет-в-репозитории)
- [Открытые вопросы](#открытые-вопросы)

---

## Срез октябрь 2026

### Зачем

Августовский список был почти целиком терминальным: из восьми харнесов только Antigravity —
IDE. Тем временем Agent Skills приняли редакторы и расширения (Cursor, Copilot, Cline, Kilo
Code, Zed, Kiro, Junie, Augment, Continue), терминал Warp и персональный агент OpenClaw, а у
открытого стандарта появился общий пользовательский каталог `~/.agents/skills`.

### Популярность

openrouter.ai из этой среды недоступен, поэтому срез собран по выдаче поиска на неделю
с 19 октября 2026 — неполный и с разными датами снимков:

- все приложения: Codex (~2.62T токенов), Claude Code (~2.13T), Hermes Agent (~731B), pi
  (~582B); Kilo Code — №3 в категориях Coding Agents и CLI Agents;
- в верхних ~25 видны ещё OpenClaw (~714B), Cline (~139B, №9 CLI Agents), Qwen Code
  (~81B), Goose (~13.5B), Crush (~2.9B);
- Cursor, Copilot, Zed, Kiro, Junie, Augment, Warp ходят к моделям не через OpenRouter и в
  его рейтинге не видны — но это и есть та не-терминальная половина рынка, ради которой
  список расширяется.

### Главное правило: одна копия в `~/.agents/skills`

Его читают Codex, pi, omp, OpenCode, Devin, Gemini CLI, Qwen Code, Kimi Code, Mistral Vibe,
Goose, Crush, OpenClaw, Copilot (CLI и VS Code), Cursor, Cline, Kilo Code, Zed, Warp и
Augment. Вторую копию того же имени часть харнесов не прощает: Gemini CLI показывает
«Skill conflict detected» на экране, pi, omp и Hermes пишут предупреждение, Crush и OpenCode
молча берут одну из двух (живая проверка уточнила: pi предупреждает на стартовом экране,
omp молча отдаёт предпочтение своей копии, Codex показывает модели обе). Поэтому каждый, кто читает общий каталог, получает скиллы только
туда. Свой каталог — у тех, кто общий не читает: Claude Code, Hermes, Antigravity, Grok
Build, Kiro, Continue, ZCode.

Так же общий `~/.agents/AGENTS.md`: его читают Cline, Warp, Goose и Kimi Code.

### Таблица

| Харнес | Класс | Скиллы | Глобальные правила | Опознаётся по | Модели |
|---|---|---|---|---|---|
| Hermes Agent | CLI-агент | `~/.hermes/skills` | нет (только `SOUL.md`) | `hermes`, `~/.hermes` | — |
| Claude Code | CLI + IDE + десктоп | `~/.claude/skills` | `~/.claude/CLAUDE.md` | `claude`, `~/.claude` | каталог в бинарнике |
| Codex | CLI + IDE + десктоп | `~/.agents/skills` | `~/.codex/AGENTS.md` | `codex`, `~/.codex` | `~/.codex/models_cache.json` |
| omp | CLI | `~/.agents/skills` | `~/.omp/agent/AGENTS.md` | `omp`, `~/.omp/agent` | — |
| pi | CLI | `~/.agents/skills` | `~/.pi/agent/AGENTS.md` | `pi`, `~/.pi/agent` | `pi --list-models` |
| Devin CLI / Desktop | CLI + десктоп | `~/.agents/skills` | `~/.config/devin/AGENTS.md` | `devin`, `~/.config/devin` | `devin models list` |
| Antigravity | IDE + CLI | `~/.gemini/config/skills` + `~/.gemini/antigravity-cli/skills` | `~/.gemini/AGENTS.md` | `agy`, `~/.gemini/config` | — |
| OpenCode | CLI (TUI) | `~/.agents/skills` | `~/.config/opencode/AGENTS.md` | `opencode`, `~/.config/opencode` | `opencode models` |
| Gemini CLI | CLI | `~/.agents/skills` | `~/.gemini/GEMINI.md` | `gemini`, `~/.gemini/settings.json` | — |
| Qwen Code | CLI | `~/.agents/skills` | `~/.qwen/AGENTS.md` | `qwen`, `~/.qwen` | — |
| Kimi Code | CLI | `~/.agents/skills` | `~/.agents/AGENTS.md` | `kimi`, `~/.kimi-code` | — |
| Mistral Vibe | CLI | `~/.agents/skills` | `~/.vibe/AGENTS.md` | `vibe`, `~/.vibe` | — |
| Goose | CLI + десктоп | `~/.agents/skills` | `~/.agents/AGENTS.md` | `goose`, `~/.config/goose` | — |
| Crush | CLI (TUI) | `~/.agents/skills` | `~/.config/crush/CRUSH.md` | `crush`, `~/.config/crush` | `crush models` |
| Factory Droid | CLI | `~/.agents/skills` | `~/.factory/AGENTS.md` | `droid`, `~/.factory` | — |
| Grok Build | CLI | `~/.grok/skills` | `~/.grok/AGENTS.md` | `grok`, `~/.grok` | `grok models` |
| OpenClaw | персональный агент | `~/.agents/skills` | нет (workspace `AGENTS.md` — его) | `openclaw`, `~/.openclaw` | — |
| GitHub Copilot | VS Code + CLI | `~/.agents/skills` | `~/.copilot/copilot-instructions.md` | `copilot`, `~/.copilot` | — |
| Cursor | IDE + CLI | `~/.agents/skills` | нет (только в настройках) | `cursor-agent`, `cursor`, `~/.cursor` | `cursor-agent models` |
| Cline | VS Code + CLI | `~/.agents/skills` | `~/.agents/AGENTS.md` | `cline`, `~/.cline` | — |
| Kilo Code | VS Code + CLI | `~/.agents/skills` | `~/.config/kilo/AGENTS.md` | `kilo`, `~/.config/kilo`, `~/.kilo`, `~/.kilocode` | `kilo models` |
| Zed | редактор | `~/.agents/skills` | `~/.config/zed/AGENTS.md` | `zed`, `~/.config/zed` | — |
| Warp | терминал | `~/.agents/skills` | `~/.agents/AGENTS.md` | `warp`, `~/.warp`, `~/.config/warp-terminal` | — |
| Augment | IDE + `auggie` | `~/.agents/skills` | `~/.augment/rules/fraim.md` | `auggie`, `~/.augment` | — |
| Kiro | IDE + CLI | `~/.kiro/skills` | `~/.kiro/steering/fraim.md` | `kiro-cli`, `~/.kiro` | — |
| Junie | плагин JetBrains + CLI | `~/.agents/skills` | нет (проверено вживую) | `junie`, `~/.junie` | — |
| Continue | IDE + `cn` | `~/.continue/skills` | `~/.continue/rules/fraim.md` | `cn`, `~/.continue` | — |
| ZCode (Z.ai, GLM) | десктоп | `~/.zcode/skills` | `~/.zcode/AGENTS.md` | `~/.zcode`, `/Applications/ZCode.app` | — |

«Модели» — откуда выбор ролей (`fraim roles`) берёт список; прочерк значит «введи сам».
Запуск воркера флота с моделью в argv по-прежнему встроен только для Devin и OpenCode:
для остальных `--model` в интерактивном режиме либо не существует (Crush, Vibe, Goose),
либо не проверен вживую, а неверный argv — это задача, которая молча не стартовала.

### Живая проверка (31 октября 2026)

Документация врёт и устаревает, поэтому 19 харнесов, которые ставятся из npm и PyPI,
проверены настоящей установкой: пакет — в отдельный префикс, чистый `HOME`, настоящий
`fraim init`, а потом вопрос самому агенту. Где агент без ключа не показывает список
скиллов, подставлялся локальный сервер, притворяющийся моделью, и читался первый запрос,
который агент отправил: в нём настоящий системный промпт со скиллами и правилами.
Контрольные прогоны убирали по одному каталогу, чтобы убедиться, откуда именно читается.

| Харнес (версия) | Как спросили | Скиллы | Блок |
|---|---|---|---|
| Claude Code 2.1.316 | запрос к подставному серверу | ✓ `~/.claude/skills` | ✓ `~/.claude/CLAUDE.md` |
| Codex 0.166.0 | `codex debug prompt-input` | ✓ `~/.agents/skills` | ✓ `~/.codex/AGENTS.md` |
| pi 1.4.0 | RPC `get_commands`, стартовый экран | ✓ `~/.agents/skills` | ✓ `~/.pi/agent/AGENTS.md` |
| omp 18.14.1 | `omp skill list -g --json`, RPC | ✓ `~/.agents/skills` | ✓ `~/.omp/agent/AGENTS.md` |
| OpenCode 1.19.5 | `opencode debug skill`, подставной провайдер | ✓ `~/.agents/skills` | ✓ `~/.config/opencode/AGENTS.md` |
| Kilo Code 7.8.18 | `kilo debug skill`, подставной провайдер | ✓ `~/.agents/skills` | ✓ `~/.config/kilo/AGENTS.md` |
| Gemini CLI 0.66.0 | `gemini skills list`, `/memory show` | ✓ `~/.agents/skills` | ✓ `~/.gemini/GEMINI.md` |
| Qwen Code 0.26.4 | `-o stream-json`, подставной сервер | ✓ `~/.agents/skills` | ✓ `~/.qwen/AGENTS.md` |
| Kimi Code 2.4.1 | подставной сервер | ✓ `~/.agents/skills` | ✓ `~/.agents/AGENTS.md` |
| Mistral Vibe 3.0.4 | подставной сервер | ✓ `~/.agents/skills` | ✓ `~/.vibe/AGENTS.md` |
| Hermes 0.19.0 | `hermes skills list`, подставной сервер | ✓ `~/.hermes/skills` | — не пишем |
| OpenClaw 2026.9.2 | `openclaw skills info orient` | ✓ `~/.agents/skills` | — не пишем |
| Copilot CLI 1.0.105 | `copilot skill list`, `copilot instruction list` | ✓ `~/.agents/skills` | ✓ `~/.copilot/copilot-instructions.md` |
| Cline 3.0.74 | `cline config --json`, подставной сервер | ✓ `~/.agents/skills` | ✓ `~/.agents/AGENTS.md` |
| Crush 0.99.0 | подставной провайдер | ✓ (и `~/.claude/skills`) | ✓ `~/.config/crush/CRUSH.md` |
| Augment 0.36.0 | подставной сервер | ✓ (и `~/.claude/skills`) | ✓ `~/.augment/rules/fraim.md`, всегда |
| Continue cn 1.5.47 | подставной сервер | ✓ `~/.continue/skills` | ✓ `~/.continue/rules/fraim.md`, всегда |
| Factory Droid 1.1.0 | `droid exec`, подставная модель | ✓ `~/.agents/skills` | ✓ `~/.factory/AGENTS.md` |
| Junie 1468.30 | TUI, подставная модель | ✓ | ✗ `~/.junie/AGENTS.md` не грузится |

Что проверка изменила: Junie не читает пользовательский `AGENTS.md` вообще (проектный —
читает), блок ему больше не пишем; Junie и Factory Droid читают общий `~/.agents/skills`,
поэтому получают скиллы туда. Остальные 17 строк подтвердились как есть.

Что всплыло попутно:
- **Hermes обрезает описание скилла до 57 знаков** в списке, который видит модель
  (`make-task: Only when the human wants work set aside for later or a p...`). Слова,
  по которым скилл должен срабатывать, после 57-го знака до модели не доходят.
- **OpenClaw с профилем** (`--profile`, `--dev`, свой `OPENCLAW_STATE_DIR`) общий каталог не
  читает — скиллы видны только в состоянии по умолчанию.
- **Gemini CLI** заводит `~/.gemini/settings.json` только когда человек выбрал способ входа;
  до этого его опознаёт лишь бинарник `gemini` в `PATH`.
- **OpenCode и Kilo** при стоящем рядом Claude Code видят каждый скилл дважды и пишут в лог
  12 предупреждений «duplicate skill name» на старте — текст одинаковый, работе не мешает.
- **omp** из npm не запускается без `bun` в `PATH`, хотя опознаётся и ставится нормально.

Не проверить из облачной среды — закрытые сайты загрузки: Cursor, Zed, Warp, Kiro, Devin,
Antigravity, ZCode, Goose, Grok Build. Для них строки по-прежнему держатся на документации.

### Что было неверно в августовском срезе

- **pi** читает `~/.pi/agent/skills`, `~/.agents/skills` и `~/.pi/agent/AGENTS.md`, а не
  `~/.pi/…` (`~/.claude/skills` и `~/.codex/skills` он перестал читать в 0.50, январь 2026).
  Подтверждено на живой машине: `/skill:orient` pi не нашёл. **omp** — то же самое, `~/.omp/agent/`.
- **Devin CLI** живёт в `~/.config/devin/`, а не в `~/.devin/` (тот — у Devin Local). Наши
  скиллы он при этом видел — через копию Claude Code: Devin CLI по умолчанию читает
  `~/.claude/skills` и `~/.claude/CLAUDE.md`. Без Claude Code на машине не видел бы.
- **Hermes**: `~/.hermes/AGENTS.md` грузится, только когда рабочий каталог — `~/.hermes`.
  Всегда грузится лишь `SOUL.md` — «личность», которую Hermes заводит сам.
- **Antigravity**: `~/.gemini/config/skills` читают IDE и Antigravity 2.0, а CLI `agy` —
  `~/.gemini/antigravity-cli/skills`. Ставим в оба, как и гугловский `agents-cli`.
- **Codex**: `~/.codex/skills` помечен в исходниках устаревшим; основной — `~/.agents/skills`.

`fraim init` забирает наши копии с этих мест сам (только `source: fraim` и блок между
маркерами).

### Не вошли

- **Roo Code** — закрыт 15 мая 2026, репозиторий в архиве; пользователей отправили в Cline.
- **Windsurf** — Cascade закрыт 1 июля 2026; преемник Devin Desktop делит `~/.config/devin`
  со строкой Devin CLI, отдельная строка не нужна.
- **Amp, Trae** — пути нашлись только во вторичных источниках; добавить, когда подтвердятся.

**ZCode** (агент Z.ai под модели GLM, в августовском срезе — «пропустить»: точки входа не
нашлось) теперь добавлен: `~/.zcode/AGENTS.md` читается в каждой сессии (пересказ его
документации в [ripr-swarm#3038](https://github.com/EffortlessMetrics/ripr-swarm/issues/3038)),
скиллы — `~/.zcode/skills` (два вторичных источника). Сайт zcode.z.ai отсюда недоступен,
строку надо сверить на машине с ZCode. Сами модели GLM и так работают в Claude Code,
OpenCode, Kilo Code, Cline и других через GLM Coding Plan — ZCode нужен тем, кто сидит в
родном приложении Z.ai.
- **Gemini CLI** в строю, но с 18 июня 2026 он только для Code Assist Standard/Enterprise;
  частных пользователей Google перевёл на Antigravity CLI.

### Источники (октябрь 2026)

Прочитаны в исходниках или официальной документации на GitHub:
[codex `host_roots.rs`](https://github.com/openai/codex/blob/main/codex-rs/ext/skills/src/host_roots.rs) ·
[pi skills.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/skills.md) ·
[oh-my-pi `discovery/builtin.ts`](https://github.com/can1357/oh-my-pi/blob/main/packages/coding-agent/src/discovery/builtin.ts) ·
[hermes `prompt_builder.py`](https://github.com/NousResearch/hermes-agent/blob/main/agent/prompt_builder.py) ·
[google/agents-cli `_antigravity.py`](https://github.com/google/agents-cli/blob/main/src/google/agents/cli/setup/_antigravity.py) ·
[gemini-cli skills.md](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/skills.md) ·
[qwen-code skills.md](https://github.com/QwenLM/qwen-code/blob/main/docs/users/features/skills.md) ·
[kimi-code skills.md](https://github.com/MoonshotAI/kimi-code/blob/main/docs/en/customization/skills.md) ·
[mistral-vibe README](https://github.com/mistralai/mistral-vibe) ·
[goose `skills/mod.rs`](https://github.com/block/goose/blob/main/crates/goose/src/skills/mod.rs) ·
[crush README](https://github.com/charmbracelet/crush) ·
[Factory docs](https://github.com/Factory-AI/factory) ·
[grok-build user guide](https://github.com/xai-org/grok-build) ·
[openclaw skills.md](https://github.com/openclaw/openclaw/blob/main/docs/tools/skills.md) ·
[Copilot CLI reference (github/docs)](https://github.com/github/docs) ·
[VS Code `chat.agentSkillsLocations`](https://github.com/microsoft/vscode-docs) ·
[cline `skill-directories.ts`](https://github.com/cline/cline/blob/main/apps/vscode/src/core/storage/skill-directories.ts) ·
[kilocode `instruction.ts`](https://github.com/Kilo-Org/kilocode) ·
[zed skills.md](https://github.com/zed-industries/zed/blob/main/docs/src/ai/skills.md) ·
[warp docs](https://github.com/warpdotdev/docs) ·
[continue `loadMarkdownSkills.ts`](https://github.com/continuedev/continue) ·
[Roo-Code (архив)](https://github.com/RooCodeInc/Roo-Code).
Только по выдаче поиска с официальных страниц (сверить на живой машине): Cursor, Devin,
Kiro, Junie, Augment, ZCode. Отправная точка для поиска — реестр
[vercel-labs/skills](https://github.com/vercel-labs/skills/blob/main/docs/agents.md); сам он
источником не служил и в нескольких строках расходится с первоисточниками.

---

## Главный вывод

Пока мы обсуждали «под каждый агент свой формат», рынок успел сойтись на одном.

**Agent Skills** — открытый стандарт: каталог с `SKILL.md` (markdown + YAML-фронтматтер)
и опциональными `scripts/`, `references/`, `assets/`. Опубликован Anthropic
18 декабря 2025 как открытая спецификация, дальше вышел из-под Anthropic и живёт
на `agentskills.io`. Заявленная совместимость — 20+ платформ: Codex, Gemini CLI,
GitHub Copilot, Cursor, VS Code и другие.

Для нас это значит, что **основной формат доставки не надо изобретать** — надо в него
попасть. Из топ-10 OpenRouter формат `SKILL.md` напрямую поддерживают шесть харнесов
(Hermes, Claude Code, omp, pi, Codex, плюс Devin CLI вне топа), и это **~69% токенов
всего топ-10** (4.39T из 6.39T).

Второй, более слабый, но ещё более широкий слой — **`AGENTS.md`**: обычный markdown
в корне репозитория, читается 30+ агентами, с конца 2025 под Linux Foundation
(Agentic AI Foundation). Это слой контекста, не команд.

---

## Что мы вообще встраиваем

У продукта два слоя, и у них разные механизмы доставки. Это разделение проходит
через весь дальнейший разбор:

| Слой | Что это у нас | Как агент это получает |
|---|---|---|
| **Процедуры** | 12 файлов в `procedures/` — вызываются явно (`/make-task`) | skills / slash-команды / плагины |
| **Контекст** | правило «фундамент читается первым, обновляется последним» | `AGENTS.md`, `CLAUDE.md`, rules-файлы |

Контекстный слой нужен ещё и как **подсказка**: он говорит агенту, что процедуры
вообще существуют и когда их звать. Без него skills у большинства харнесов
придётся звать руками.

---

## Сводная таблица

| # | Харнес | Токены | Класс | Точка интеграции для нас | Приоритет |
|---|---|---|---|---|---|
| 1 | **Hermes Agent** | 2.47T | CLI, open source (Nous Research) | `hermes skills install <URL>` | **P0** |
| 2 | **Claude Code** | 1T | CLI, проприетарный (Anthropic) | плагин + marketplace, внутри — skills | **P0** |
| 3 | **Kilo Code** | 513B | CLI + IDE-расширение, open source | `~/.kilocode/workflows/` | P1 |
| 4 | **DeepSeek Harness** | 511B | CLI + Web, MIT, dev preview | своя плагин-система | отложить |
| 5 | **Zazen** (форк Freebuff) | 435B | CLI, на базе Codebuff | не установлено | исследовать |
| 6 | **omp** | 403B | CLI, open source (форк pi) | `skills/*/SKILL.md` | **P0** |
| 7 | **Cline** | 343B | IDE-расширение + CLI, open source | workflows + `.clinerules/` | P1 |
| 8 | **pi** | 329B | CLI, open source | `pi install <git-пакет>` | **P0** |
| 9 | **ZCode** | 199B | приложение, проприетарное | не найдено | пропустить |
| 10 | **Codex** | 191B | CLI + IDE-расширение (OpenAI) | skills | **P0** |
| — | **Devin CLI** | вне рейтинга | CLI, проприетарный (Cognition) | skills | P1 |
| — | **Antigravity** | вне рейтинга | IDE + CLI, проприетарный (Google) | `~/.gemini/config/skills/` | **P0** |
| — | **OpenCode** | вне рейтинга | CLI (TUI), open source | `~/.config/opencode/skills/` | **P0** |
| — | **Devin Desktop** | вне рейтинга | десктоп-оболочка (Cognition) | наследует от вложенного агента | — |

P0 закрывается **одним** артефактом — каталогом со `SKILL.md`. Это и есть ядро инсталлера.

---

## Разбор по харнесам

### 1. Hermes Agent — 2.47T

Открытый агент Nous Research, лидер рейтинга с отрывом в 2.5 раза. В первом
приближении именно он, а не Claude Code, определяет, что значит «интегрироваться
в популярный харнес».

**Опции:**

- **A. Skills.** Каталог `~/.hermes/skills/` — единый источник правды: туда кладутся
  и встроенные, и установленные из хаба, и созданные самим агентом. Формат — открытый
  стандарт agentskills.io. Ставится командой `hermes skills install <источник>`,
  где источником может быть registry, git или **прямой http(s)-URL на `SKILL.md`**.
- **B. Автоинъекция контекста.** Hermes сам подхватывает `AGENTS.md`, `SOUL.md`,
  `MEMORY.md`, `USER.md` и даже `.cursorrules` в системный промпт.
- **C. `config.yaml`.** Скилл может объявить свои настройки во фронтматтере `SKILL.md`,
  они складываются в namespace `skills.config`; `hermes config migrate` находит
  ненастроенное.
- **D. MCP-сервер.**

**Рекомендация: A.** Установка с URL — это ровно то «как установка программы», которое
мы искали: одна команда, без клонирования репозитория и без ручного копирования.
Плюс C даёт бесплатный способ хранить настройки (например, дефолтный тир модели для
`run-task`). B добавляем как подсказку.

> Известная шероховатость: при установке с URL Hermes тянет только сам `SKILL.md`
> и может пропустить `references/`, `templates/`, `scripts/`
> ([issue #35125](https://github.com/NousResearch/hermes-agent/issues/35125)).
> Для нас это прямое проектное ограничение: **каждая процедура должна быть
> самодостаточным одним файлом**, а не `SKILL.md` + приложения. К счастью, наши
> процедуры сейчас именно такие.

### 2. Claude Code — 1T

**Опции:**

- **A. Skills** — `~/.claude/skills/`, тот же стандарт.
- **B. Slash-команды** — `~/.claude/commands/*.md`, вызов строго явный.
- **C. Плагин + marketplace** — git-репозиторий с `.claude-plugin/marketplace.json`.
  Плагин бандлит skills, команды, хуки и MCP-конфиг разом. Установка:
  `/plugin marketplace add <repo>` → `/plugin install <name>`. Даёт версионирование,
  `/plugin update` и удаление чужими руками.
- **D. `CLAUDE.md` / `AGENTS.md`** — контекстный слой.
- **E. MCP.**

**Рекомендация: C, внутри которого лежит A.** Это единственная опция во всём списке,
которая даёт **готовый канал обновлений**, — не надо писать ни проверку версий, ни
апдейтер. А начинкой плагина остаются те же самые каталоги `SKILL.md`, что и у всех
остальных, так что дублирования не возникает.

### 3. Kilo Code — 513B

**Опции:**

- **A. `kilo.jsonc`** — единый конфиг, общий для VS Code-расширения, CLI и Cloud Agents.
  Появился в v7 (переезд с Roo-производной v5 на кодовую базу OpenCode).
- **B. Workflows** — markdown-файлы, они же slash-команды. Глобальные —
  `~/.kilocode/workflows/`, доступны во всех проектах; проектные — `.kilocode/workflows/`.
- **C. `.kilocode/rules/`** — legacy, но обратная совместимость сохранена.
- **D. MCP.**

**Рекомендация: B.** Глобальные workflows ложатся на наши команды один в один и
не требуют сборки — просто markdown в каталог. A выглядит правильнее стратегически,
но v7 сейчас движущаяся мишень (старые rules и mode-файлы уже выпилены), поэтому
садиться на неё рано.

### 4. DeepSeek Harness — 511B

Открытый (MIT) харнес DeepSeek на Node.js, архитектура «всё есть плагин»: моделью,
реестром инструментов, песочницей и даже самим циклом агента являются плагины.
Взлетел мгновенно — 165k звёзд за неделю.

**Опции:** собственная плагин-система (на Cordis); вероятно MCP, но не проверено.

**Рекомендация: отложить.** Официально это developer preview с прямым предупреждением
о ломающих изменениях. Своя плагин-система означает адаптер, который придётся
переписывать, и при этом ноль переиспользования с остальными. Вернуться, когда
стабилизируется — трафик того стоит.

### 5. Zazen (форк Freebuff) — 435B

Форк Freebuff (`CodebuffAI/freebuff`), который сам построен на открытом мульти-агентном
фреймворке Codebuff. Работает через OpenAI-совместимый шлюз.

**Опции:** предположительно агентные определения Codebuff; наличие skills или
slash-команд подтвердить не удалось.

**Рекомендация: исследовать отдельно.** Достоверной информации о механизме расширения
нет — это единственная позиция в списке, где я не смог установить точку интеграции.
Ставить сюда работу до разведки нельзя.

### 6. omp — 403B

Форк pi, переписанный на TypeScript, с сессиями, субагентами и расширениями.

**Опции:**

- **A. Skills** — обнаруживаются на один уровень под `skills/` по маске `*/SKILL.md`
  (нерекурсивно). При `skills.enableSkillCommands: true` каждый найденный скилл
  автоматически получает свою slash-команду.
- **B. Плагины** — бандлят код расширений, skills, slash-команды, хуки, инструменты,
  агентов, правила, промпты и конфиги MCP/LSP/DAP.
- **C. Markdown-файлы как slash-команды** — отдельная ступень в резолвере команд.

**Рекомендация: A.** Тот же артефакт, что и везде, и бесплатным бонусом — автоматические
slash-команды, то есть та же эргономика `/make-task`, что у Claude Code, без отдельного
адаптера.

### 7. Cline — 343B

**Опции:**

- **A. `.clinerules/`** — все `.md` и `.txt` внутри собираются в единый свод правил.
  Есть интерактивный `/newrule`.
- **B. Workflows** — через `/workflow`, автоматизация повторяющихся задач.
- **C. MCP.**

**Рекомендация: B для процедур + A для контекстного слоя.** Оговорка: у Cline центр
тяжести смещён в сторону проекта, а не машины, поэтому «поставил один раз — работает
везде» здесь получается хуже, чем у CLI-харнесов. Это делает его кандидатом на
per-project установку, а не глобальную.

### 8. pi — 329B

Минималистичный терминальный харнес Марио Цехнера («адаптируется под твой воркфлоу,
а не наоборот»), родитель omp.

**Опции:**

- **A. Skills** — стандарт agentskills, подгрузка по требованию, без сброса кэша промпта.
  Официальный репозиторий `badlogic/pi-skills` прямо заявлен как совместимый
  с Claude Code и Codex CLI.
- **B. Пакетный менеджер** — `pi install <npm- или git-пакет>`. Пакет бандлит
  расширения, skills, промпты и темы.
- **C. `AGENTS.md`** — поддерживается.

**Рекомендация: B.** У pi настоящий пакетный менеджер, то есть снова полноценная
«установка программы» одной командой, и версионирование приезжает от npm/git.
Содержимым пакета остаются всё те же skills.

### 9. ZCode — 199B

Проприетарное приложение, работает с GLM, OpenRouter, Anthropic API, Moonshot, DeepSeek
и любым OpenAI/Anthropic-совместимым сервисом.

**Опции:** документированного механизма расширения найти не удалось.

**Рекомендация: пропустить.** Самая низкая позиция в топ-10 при отсутствии подтверждённой
точки входа — соотношение усилий к отдаче худшее в списке.

### 10. Codex — 191B

**Опции:**

- **A. Skills** — санкционированный путь, вызываются и явно, и неявно.
- **B. `~/.codex/prompts/*.md`** — slash-команды вида `/prompts:<имя>`, фронтматтер
  с `description` и `argument-hint`. **Официально помечены как deprecated** — документация
  прямо отсылает на skills. Плюс в 0.117.0 они отвалились вместе с локальными skills
  ([#15939](https://github.com/openai/codex/issues/15939),
  [#15941](https://github.com/openai/codex/issues/15941)).
- **C. `AGENTS.md`** — Codex его родитель, поддержка первого класса.
- **D. MCP.**

**Рекомендация: A, и осознанно НЕ B.** Соблазн взять `~/.codex/prompts/` велик — формат
почти дословно совпадает с фронтматтером Claude Code, — но строить доставку на
задепрекейченном и на данный момент сломанном механизме нельзя.

### Devin CLI

Локальный агент Cognition: читает файлы, выполняет команды, правит код, не отправляя
рабочую копию в облако. Модель на выбор, включая собственную SWE-1.6.

**Опции:**

- **A. Skills** — в документации по расширениям перечислены MCP-конфиг, skills, хуки,
  lifecycle-хуки, `AGENTS.md`, субагенты.
- **B. `AGENTS.md`.**
- **C. Playbooks + Knowledge** — только на облачной стороне Devin, не в локальном CLI.
- **D. MCP.**

**Рекомендация: A.** Отдельно стоит отметить C: **Playbooks — это концептуально самое
близкое к нашей системе, что есть на рынке** (воспроизводимые процедуры под повторяющуюся
сложную работу — миграции БД, интеграции). Это не точка интеграции, но полезный ориентир:
кто-то уже продаёт ровно эту идею, и на неё стоит смотреть при позиционировании.

### Antigravity (Google)

Агент-первая среда Google на Gemini: IDE (форк VS Code), CLI и сам агент. В рейтинг
OpenRouter не попадает — ходит не через него, — но это второй после Claude Code
проприетарный харнес, который люди ставят рядом с нашим.

**Опции:**

- **A. Skills** — тот же открытый стандарт, каталог со `SKILL.md`.
- **B. Правила** — `AGENTS.md` и `GEMINI.md` глобально, `.agents/rules/` в проекте.
- **C. MCP.**

**Рекомендация: A + B, но с двумя оговорками, которые стоили разведки.**

Каталог скиллов у Antigravity успел переехать, и в сети живы все прежние адреса:
`~/.gemini/skills`, `~/.gemini/antigravity/global_skills`, `~/.gemini/antigravity-cli/skills`.
Каждый из них читает **часть** обличий продукта. Единственный, который читают все три
(IDE, CLI и агент), — `~/.gemini/config/skills/`; проектный — `.agents/skills/`. Целимся
в глобальный.

Контекстный блок кладём в `~/.gemini/AGENTS.md`, а не в `~/.gemini/GEMINI.md`, хотя
Antigravity читает оба. `GEMINI.md` в этом же каталоге — глобальный контекст **Gemini CLI**,
другого продукта, который его себе и переписывает: наш блок там оказался бы в чужом файле
([gemini-cli #16058](https://github.com/google-gemini/gemini-cli/issues/16058) — конфликт
признан и закрыт как «не планируется»). `AGENTS.md` рядом читается тем же Antigravity и
никому не принадлежит.

Бинарник называется `agy`. Признак присутствия — каталог `~/.gemini/config`, а не
`~/.gemini`: голый `~/.gemini` заводит и Gemini CLI, который этим харнесом не является.

### OpenCode

Открытый терминальный агент (TUI) с любым провайдером моделей; на его кодовой базе стоит и
Kilo Code v7.

**Опции:**

- **A. Skills** — открытый стандарт: `~/.config/opencode/skills/<имя>/SKILL.md` глобально,
  `.opencode/skills/` в проекте. Имя в фронтматтере обязано совпадать с именем каталога.
- **B. Правила** — `~/.config/opencode/AGENTS.md` глобально, `AGENTS.md` в проекте.
- **C. MCP и плагины.**

**Рекомендация: A + B.** Две оговорки. Каталог — `skills/` во множественном числе; старый
`skill/` ещё гуляет по сторонним страницам. И OpenCode держит запасные пути от Claude Code:
читает `~/.claude/skills` (наши скиллы при стоящем рядом Claude Code видны дважды — тем же
текстом) и `~/.claude/CLAUDE.md`, но последний — только пока нет своего `AGENTS.md`, а его
заводит наш блок.

Модели — `opencode models`, по одной `провайдер/модель` в строке; ровно эту строку берёт
`--model` и в `opencode run`, и в TUI, поэтому воркер флота запускается
`opencode --model <провайдер/модель>`.

### Devin Desktop

Запущен 2 июня 2026 как следующее поколение Windsurf. На старте умеет запускать внутри
себя Codex, Claude Agent, OpenCode и произвольные **ACP**-агенты, давая им общий
Kanban-интерфейс и Spaces.

**Рекомендация: не интегрироваться напрямую.** Desktop — это оболочка над чужими агентами,
а не харнес со своим форматом расширений. Наш скилл, установленный в Claude Code или Codex,
приезжает в Devin Desktop сам. Следить стоит за **ACP** — если он станет общим протоколом
подключения агентов к оболочкам, это следующий кандидат в универсальные точки входа
после Agent Skills.

Отдельно: Devin Desktop — прямой наследник Windsurf, под который изначально писались
наши процедуры (`bootstrap.md` до сих пор ссылается на Cascade). То есть исходная
целевая среда системы никуда не делась, она переименовалась и стала мульти-агентной.

---

## Рекомендация по инсталлеру

**Целиться в Agent Skills, всё остальное — тонкие адаптеры вокруг.**

**Ядро (P0).** Инсталлер генерирует из `procedures/` набор каталогов формата
Agent Skills — по одному на процедуру. Этот **один** артефакт закрывает Hermes,
Claude Code, omp, pi, Codex и Devin CLI, то есть ~69% токенов топ-10, и попутно
Cursor, Copilot, Gemini CLI и остальные принявшие стандарт. Разница между харнесами
сводится к целевому каталогу и к способу установки:

| Харнес | Куда | Чем |
|---|---|---|
| Hermes | `~/.hermes/skills/` | `hermes skills install <URL>` |
| Claude Code | `~/.claude/skills/` | плагин из marketplace |
| pi | пакет | `pi install <git>` |
| omp | `skills/` | копирование |
| Codex | каталог skills | копирование |
| Devin CLI | каталог skills | копирование |
| Antigravity | `~/.gemini/config/skills/` | копирование |
| OpenCode | `~/.config/opencode/skills/` | копирование |

**Контекстный слой (P0).** Блок для `AGENTS.md`, объясняющий инвариант фундамента
и то, когда звать какую процедуру. Читается 30+ агентами и служит подсказкой для тех,
у кого skills не триггерятся сами.

**Адаптеры (P1).** Kilo Code (`~/.kilocode/workflows/`) и Cline (workflows +
`.clinerules/`) — те же процедуры, другая обёртка. Плюс Devin CLI, если у него
каталог skills окажется нестандартным.

**Отложено.** DeepSeek Harness — до выхода из dev preview. Zazen — до разведки.
ZCode — не трогаем.

**Порядок работ:** сначала генератор skills + `AGENTS.md`-блок (это Hermes, pi, omp,
Codex, Devin CLI сразу), затем плагин Claude Code поверх той же начинки (появляется
канал обновлений), затем адаптеры Kilo и Cline.

---

## Что это меняет в репозитории

Три следствия, которые стоит зафиксировать до написания кода:

1. **Нужен манифест.** ✅ Сделано, но источником правды стал **фронтматтер самой
   процедуры**, а не отдельный файл: имя, описание и тир модели живут в шапке
   `procedures/<имя>.md`. Всё, что перечисляет процедуры, идёт через одну функцию,
   читающую каталог, — список нигде не захардкожен. `procedures/manifest.json`
   генерируется из фронтматтера (`fraim build`) и остаётся объявленным артефактом
   обмена для не-shell генераторов и CI, но ничего в репозитории его не читает: два
   источника правды разошлись бы. Описание перестаёт быть косметикой — у skills именно
   оно решает, вызовется процедура или нет.

   Попутно вскрылось ограничение стандарта: имя скилла обязано быть kebab-case
   (`^[a-z0-9-]+$`), а описание — до 1024 символов и **без угловых скобок**. Поэтому
   команды переименованы: `/make-task`, `/run-task`, `/revise-task`, `/reconcile-task`,
   `/design-session`, `/docker-deploy`.
2. **Процедура обязана оставаться одним файлом.** ✅ Из-за поведения Hermes при установке
   с URL (см. выше) и из-за нерекурсивного обнаружения у omp. Теперь это не соглашение,
   а проверка: тест `в каждом скилле ровно один файл` падает, если процедуру растащат
   на `references/`.
3. **Версия продукта должна попадать в provenance-штамп.** ✅ В `## Plan provenance`
   рядом с «Based on» появилась строка `System: fraim <версия>`: `/make-task` её пишет,
   `/run-task` сверяет на шаге 4.6a и при расхождении объявляет дефект плана, а
   `fraim status` замечает это со стороны. Механизм детекта протухания распространён
   на сам продукт.

Плюс место для проверки обновлений искать не нужно: `orient` уже запускается при каждом
возвращении в проект и уже докладывает о здоровье фундамента в блоке «Foundation health».
✅ Теперь он начинается с `fraim status --json` и докладывает вердикт сторожа, а не
впечатление агента.

---

## Открытые вопросы

- **Zazen (435B)** — единственная позиция без установленной точки интеграции. Нужна разведка.
- **Kilo Code** — садиться на legacy `~/.kilocode/workflows/` или ждать стабилизации
  `kilo.jsonc`? Пока выбран первый вариант как дешёвый и обратимый.
- **ACP** — станет ли протокол Devin Desktop общим способом подключать агентов к оболочкам.
  Если да, это следующая универсальная точка входа после Agent Skills.
- **MCP** — присутствует почти у всех и остаётся единственным вариантом, где обновления
  централизованы по-настоящему (процедуры отдаются в момент вызова, на диске не лежат).
  Ценой того, что вызов идёт через tool, а не через `/команду`. Отдельное продуктовое
  решение, не деталь доставки.

---

## Источники

Срез популярности — рейтинг приложений OpenRouter, август 2026.

- [App & Agent Rankings — OpenRouter](https://openrouter.ai/apps)
- [Agent Skills — спецификация](https://github.com/agentskills/agentskills) ·
  [The Agent Skills Open Standard: Write One Skill, Run It Everywhere](https://qaskills.sh/blog/agent-skills-open-standard-portability)
- [AGENTS.md — гайд и статус стандарта](https://www.morphllm.com/agents-md-guide) ·
  [кросс-инструментальная переносимость](https://codex.danielvaughan.com/2026/05/27/agent-instruction-files-agents-md-claude-md-cross-tool-portability-codex-cli/)
- [Hermes Agent — конфигурация](https://hermes-agent.nousresearch.com/docs/user-guide/configuration) ·
  [skills](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills/) ·
  [issue #35125](https://github.com/NousResearch/hermes-agent/issues/35125)
- [Claude Code — marketplace плагинов](https://code.claude.com/docs/en/plugin-marketplaces) ·
  [официальный каталог](https://github.com/anthropics/claude-plugins-official)
- [Kilo Code — workflows](https://kilo.ai/docs/features/slash-commands/workflows) ·
  [CLI](https://kilo.ai/docs/code-with-ai/platforms/cli)
- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) ·
  [разбор архитектуры](https://thenewstack.io/deepseek-harness-open-source-plugins/)
- [Freebuff](https://github.com/CodebuffAI/freebuff) · [Zazen](https://geekhub.mx/en/apps/zazen)
- [omp — плагины](https://omp.sh/docs/plugins) · [slash-команды](https://omp.sh/docs/slash)
- [Cline — rules](https://docs.cline.bot/customization/cline-rules)
- [pi](https://pi.dev/) · [расширения](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md) ·
  [pi-skills](https://github.com/badlogic/pi-skills)
- [ZCode — обзор](https://www.bitdoze.com/zcode-ai-review/)
- [Codex — custom prompts (deprecated)](https://developers.openai.com/codex/custom-prompts) ·
  [#15939](https://github.com/openai/codex/issues/15939) · [#15941](https://github.com/openai/codex/issues/15941)
- [Devin CLI](https://cognition.com/blog/devin-for-terminal) ·
  [Devin Desktop](https://www.fixedlabs.ai/blog/devin-desktop-review)
- [Antigravity — Agent Skills](https://antigravity.google/docs/ide/skills/) ·
  [правила](https://antigravity.google/docs/rules-workflows/) ·
  [CLI (`agy`)](https://antigravity.google/docs/cli/getting-started/) ·
  [каталоги скиллов для Antigravity 2.0](https://github.com/google/agents-cli/issues/26) ·
  [конфликт GEMINI.md с Gemini CLI](https://github.com/google-gemini/gemini-cli/issues/16058)
- [OpenCode — skills](https://opencode.ai/docs/skills/) · [правила](https://opencode.ai/docs/rules/) ·
  [CLI](https://opencode.ai/docs/cli/)
