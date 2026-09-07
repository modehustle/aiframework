# Conductor: Quick Start

**За 5 минут от нулевой до параллельной сборки.**

---

## Setup (первый раз)

```bash
# 1. Установи fraim из ветки
git clone -b claude/modes-open-questions-ofdv1r \
    https://github.com/modehustle/aiframework.git
cd aiframework
./installer/install.sh

# 2. Проверь что установилось
fraim version
fraim help | grep dispatch
```

---

## Тестовый проект (3 минуты)

```bash
# Создай тестовую папку
mkdir ~/conductor-test && cd ~/conductor-test

# Инициализируй как проект
fraim scaffold

# Скопируй пример плана
cp /path/to/aiframework/example-build-plan.md build-plan.md
```

---

## Цикл: Dispatch → Execute → Collect → Accept

### 1. Conductor запускает dispatch (30 сек)

```bash
fraim dispatch build-plan.md
```

**Вывод:**
```
Разбор плана...
Раздача подзадач...
Worker A → /path/to/project/ai/parallel/A/task.md
Worker B → /path/to/project/ai/parallel/B/task.md
Worker C → /path/to/project/ai/parallel/C/task.md
Сборка запечатана: build-20260907-123456
Флот готов к запуску. Следующий шаг: запустить воркеров в ADE
```

**Проверь что создалось:**
```bash
ls -la ai/parallel/*/task.md  # три задачи для воркеров
ls -la ai/builds/build-20260907-123456/  # журнал сборки
```

---

### 2. Workers начинают работу (в параллель, 30 минут)

**Для каждого воркера (A, B, C):**

```bash
# На машине воркера (или в отдельной Orca сессии):
cd /path/to/project

# Создать worker branch
git checkout -b worker/build-20260907-123456-A origin/main

# Прочитать задачу
cat ai/parallel/A/task.md

# Сделать работу (30 мин)
# ...реализуй изменения...

# Коммитить через fraim (это пишет в фундамент + git)
fraim commit task "A: standardize errors in core.sh" \
    src/core.sh src/config.sh

# Залить в свой worker branch
git push -u origin worker/build-20260907-123456-A

# Написать result.md для conductor'а
cat > ai/parallel/A/result.md <<'EOF'
# Subtask A Result

## Summary
Standardized all error messages in core.sh and config.sh.
Replaced 42 die() calls with "die <function>: <error>" format.

## Files Modified
- src/core.sh (23 lines changed)
- src/config.sh (19 lines changed)

## Tests
All tests pass.
EOF
```

**Параллельно:** Worker B и C делают то же для своих подзадач.

---

### 3. Conductor проверяет статус (30 сек)

```bash
fraim dispatch:status build-20260907-123456
```

**Вывод:**
```
Build: build-20260907-123456
Status: DISPATCHED
Worker status:
  A: DONE
  B: DONE
  C: IN PROGRESS
```

**Когда все DONE:**

```bash
# Вернись на main
git checkout main

# Фетч всех worker branches
git fetch origin "worker/build-20260907-123456-*"
```

---

### 4. Conductor собирает результаты (1 минута)

```bash
fraim dispatch:collect build-20260907-123456
```

**Что происходит:**
1. ✅ Мержит worker/A → main
2. ✅ Мержит worker/B → main
3. ✅ Мержит worker/C → main
4. ✅ Объединяет результаты в `ai/builds/build-id/result.md`
5. ✅ Проверяет: нет ли конфликтов

**Вывод:**
```
Собираю результаты...
Результаты собраны в ai/builds/build-20260907-123456/result.md
```

**Проверь результаты:**
```bash
cat ai/builds/build-20260907-123456/result.md

# Просмотри мерж коммиты
git log --oneline -5
# merge worker/build-20260907-123456-A
# merge worker/build-20260907-123456-B
# merge worker/build-20260907-123456-C
```

---

### 5. Conductor принимает сборку (30 сек)

```bash
fraim dispatch:accept build-20260907-123456
```

**Что происходит:**
1. ✅ Создаёт build.accepted маркер
2. ✅ Пишет в DECISIONS.md:
   ```
   ## Build build-20260907-123456 accepted
   
   - **Date**: 2026-09-07 12:34:56 UTC
   - **Type**: parallel (conductor mode)
   - **Workers**: 3
   - **Result**: All subtasks completed successfully
   ```
3. ✅ Создаёт build journal с заглушкой для lessons

**Вывод:**
```
Принимаю сборку...
Build build-20260907-123456 accepted. DECISIONS.md updated.
```

**Проверь фундамент:**
```bash
git log DECISIONS.md | head -20  # видна новая запись
cat DECISIONS.md | grep -A3 "build-20260907-123456"
```

---

## ✅ Готово!

**Один цикл завершён:**
- ✅ 3 воркера работали параллельно
- ✅ Conductor собрал их работу в один merge
- ✅ Фундамент обновлен (DECISIONS.md)
- ✅ Main содержит все изменения

**Уложено в один разговор с conductor'ом, вместо N разговоров "принять задачу 1, 2, 3".**

---

## Команды за шпаргалкой

```bash
# Dispatch новой сборки
fraim dispatch build-plan.md
fraim dispatch:status build-ID           # проверить статус

# После того как воркеры готовы
git fetch origin "worker/build-ID-*"
fraim dispatch:collect build-ID          # собрать результаты
fraim dispatch:accept build-ID           # одна приёмка

# Если что-то пошло не так
fraim dispatch:status build-ID           # посмотреть какой воркер упал
# ... разреши проблему в ai/parallel/WORKER/ ...
fraim dispatch:collect build-ID --retry  # попробуй снова
```

---

## Когда это не нужно

❌ **Используй [/make-task](procedures/make-task.md) → [/run-task](procedures/run-task.md) если:**
- Одна задача, один агент (нет параллелизма)
- Воркеры зависят друг от друга
- Нужна интерактивная отладка

---

## Когда это идеально подходит

✅ **Используй conductor если:**
- 3-5 **полностью независимых** подзадач
- Каждая > 30 минут (окупает overhead)
- Разные файлы (нет конфликтов merge)
- Хочешь одну приёмку вместо N

**Пример:** рефакторинг трёх модулей, добавление языка интернационализации, миграция трёх микросервисов.

---

## Что дальше

→ [procedures/conductor.md](procedures/conductor.md) — полная процедура  
→ [PARALLEL-V1.md](PARALLEL-V1.md) — архитектура v1  
→ [INTEGRATION-PARALLEL.md](INTEGRATION-PARALLEL.md) — git flow  
→ [MODES.md](MODES.md) — режимы работы по конструкции

---

## Потом (v2)

- Orca integration: spawn workers автоматически
- Semantic markers: "A модифицирует X, B модифицирует Y" → automerge
- Streaming: collect results по мере готовности (не ждать всех)
- Rollback: `fraim dispatch:cancel` откатывает всё
