# Conductor: Parallel Execution

> **Зачем эта процедура.** В параллельном режиме работу ведёт мастер-сессия (conductor), которая разбивает задачу на подзадачи, раздаёт флоту воркеров в ADE, собирает результаты и принимает одной приёмкой всю сборку. Это не `/run-task` — это MODES.md §2 и §5.
>
> **Соседние документы:** [MODES.md](../MODES.md) §2 и §5 — режим по конструкции; [PARALLEL-V1.md](../PARALLEL-V1.md) — как это реализовано; [make-task.md](make-task.md) — если нужна одна последовательная задача; [run-task.md](run-task.md) — если нужно исполнить готовый план.

## Что это даёт

| Параметр | Задачный режим | Параллельный (conductor) |
|----------|---|---|
| Инициатор | Человек | Человек (conductor) |
| Исполнители | Одна сессия, один агент | N воркеров в ADE, независимо |
| Время | T (последовательно) | T/N (параллельно) + overhead |
| Приёмка | По каждой задаче | Один раз на сборку (§5) |
| Внимание | N разговоров | Один разговор + review |
| Фундамент пишет | Исполнитель | Conductor (сборка, один раз) |

---

## Шаг 1. Разработать план сборки

**Вход:** большая задача, которая распадается на N независимых подзадач.

**Вход:** build-plan.md в корне проекта.

```markdown
# Build Plan: <название>

## Subtask: A
**Summary**: <что делает A>

### `path/to/file1.ts`
- Brief why this file changes

### `path/to/file2.md`
- Brief why this file changes

---

## Subtask: B
**Summary**: <что делает B>

### `path/to/file3.rs`
...

---

## Subtask: C
...
```

**Ограничение:** каждый файл в `Files to Change` должен появиться ровно один раз.
Иначе `dispatch-check` отклонит план.

**Если столкновение:** отредактируй план так, чтобы один воркер читал, другой писал.
Или объедини две подзадачи в одну.

---

## Шаг 2. Запустить dispatch

```bash
fraim dispatch build-plan.md
```

**Что происходит:**
1. `dispatch-check` проверяет пути — не пересекаются ли файлы
2. Создаёт директории `ai/parallel/A/`, `ai/parallel/B/`, `ai/parallel/C/`
3. В каждой — `task.md` для воркера + наследованный `context.md`
4. Печатает: `build-20260907-123456 готов` (build ID)

**Выход:** `ai/parallel/<worker-id>/task.md` для каждого воркера.

---

## Шаг 3. Раздать флоту

**В Orca или на машине с N сессиями Claude:**

```bash
# Для каждого worker-а A, B, C:
fraim task-new parallel/A
fraim run-task parallel/A

# Или в Orca:
orca session create --task ai/parallel/A/task.md --agent claude-haiku
```

**Что делает воркер:**
- Читает `task.md`
- Читает `context.md`
- Реализует изменения в `Files to Change`
- Пишет `result.md` с кратким резюме
- Коммитит через `fraim commit`

**Каждый воркер работает независимо. Conductor ждёт.**

---

## Шаг 4. Собрать результаты

**Когда все воркеры готовы:**

```bash
fraim dispatch:collect build-20260907-123456
```

**Что происходит:**
1. Читает все `ai/parallel/<worker>/result.md`
2. Мержит в `ai/builds/<build-id>/result.md`
3. Проверяет: нет ли конфликтов merge (если есть — выход с ошибкой)
4. Создаёт `build.sealed.md` с журналом

**Выход:** `ai/builds/<build-id>/` с объединённым результатом.

---

## Шаг 5. Ревью и принять сборку

```bash
cat ai/builds/build-20260907-123456/result.md

# Прочитай резюме от каждого воркера.
# Если всё ОК:
fraim dispatch:accept build-20260907-123456
```

**Что происходит при accept:**
1. Проверяет: все ли `Files to Change` модифицированы (или явно пропущены)
2. Проверяет: нет ли конфликтов git между веткой conductor'а и воркеров
3. Сливает все изменения в текущий branch (или main, если conductor был на main)
4. Пишет в DECISIONS.md: `## Build <id> accepted by <conductor>`
5. Отмечает сборку как завершённую

**Выход:** основной branch содержит все изменения всех воркеров + запись в фундамент.

---

## Шаг 6. Lessons (опционально)

После приёмки conductor может добавить в build journal lessons:

```bash
cat ai/builds/build-20260907-123456/build.sealed.md

# Отредактировать раздел ## Lessons:
# - Воркер A и B оба пытались модифицировать config.sh — хорошо разделили read vs write
# - Воркер C долго ждал ответ от API — следующий раз лучше mock
```

Эти lessons станут фундаментом для MODES.md §11.4 и будущих сборок.

---

## Когда это работает хорошо

✅ Задача распадается на 3-5 **полностью независимых** подзадач  
✅ Каждый воркер трогает **разные файлы**  
✅ **Нет** перекрёстных зависимостей между воркерами  
✅ Время одной подзадачи > 30 минут (параллелизм окупается)  
✅ Тестирование **не требует** координации (каждый тестирует свою часть)

---

## Когда это **не** работает

❌ Одна подзадача < 10 минут (overhead раздачи дороже выигрыша)  
❌ Воркеры зависят друг от друга (нужна синхронизация)  
❌ Все трогают `package.json` или `DECISIONS.md` (конфликт гарантирован)  
❌ Тестирование требует всей системы (одна тестовая сессия на флот)

**В этих случаях используй [make-task](make-task.md) → [run-task](run-task.md).**

---

## Возможные ошибки

### `dispatch-check` отклонил план
```
dispatch-check: semantic collision — same file in different subtasks:
  src/payment/service.ts (in: A, B)
```

**Решение:** редактируй план так, чтобы файл появился один раз:
- Может быть, A только **пишет**, B только **читает** → переформулируй summary
- Может быть, надо объединить A+B в одну подзадачу
- Может быть, переделать на более мелкие области (одна подзадача — один модуль)

### Воркер застрял
```
fraim dispatch:collect build-20260907-123456
Error: worker B не завершена (result.md не найдена)
```

**Решение:** проверь статус воркера B:
```bash
cd ai/parallel/B
fraim status  # что произошло
```

Если дошёл до конца, но result.md не создал:
```bash
fraim task-result parallel/B --reset
# Воркер заново напишет result.md
```

### Конфликт при collect
```
fraim dispatch:collect build-20260907-123456
Error: merge conflict in src/config.ts (workers A and C)
```

**Решение:** это значит `dispatch-check` пропустил столкновение (или вы вручную добавили файл).

Разреши конфликт вручную в `ai/parallel/merge-conflict/src/config.ts`, потом:
```bash
fraim dispatch:collect build-20260907-123456 --resolve-conflicts
```

---

## Команды conductor'а (полный список)

```bash
fraim dispatch ПЛАН              # проверить и раздать флоту
fraim dispatch:status BUILD-ID   # статус сборки (какие воркеры готовы)
fraim dispatch:collect BUILD-ID  # собрать результаты
fraim dispatch:accept BUILD-ID   # одна приёмка + слияние + фундамент
fraim dispatch:cancel BUILD-ID   # отменить сборку (оставить как есть)
fraim dispatch:lessons BUILD-ID  # открыть build.sealed.md для редактирования lessons
```

---

## Примеры

### Пример 1: Рефакторинг трёх модулей (независимо)

```markdown
# Build Plan: Auth Refactor

## Subtask: A
**Summary**: Convert `src/auth/jwt.ts` to typed handlers

### `src/auth/jwt.ts`

---

## Subtask: B
**Summary**: Rewrite `src/auth/session.ts` validation

### `src/auth/session.ts`

---

## Subtask: C
**Summary**: Update `src/auth/index.ts` exports for new API

### `src/auth/index.ts`
```

**dispatch-check:** ✅ разные файлы → go  
**Работа:** A, B, C параллельно  
**Риск:** C зависит от A и B по API → воркер C может заблокироваться  
**Решение:** C читает новые типы из A+B, не пишет; работает

---

### Пример 2: Добавление языка в систему (потенциально конфликтный)

```markdown
# Build Plan: Add Russian i18n

## Subtask: A
**Summary**: Add `ru.json` localization files

### `src/locales/ru.json`
### `src/locales/ru-RU.json`

---

## Subtask: B
**Summary**: Register Russian locale in `src/i18n/index.ts`

### `src/i18n/index.ts`
```

**dispatch-check:** ✅  
**Риск:** если B слишком быстро, может попробовать импортировать ru.json до того как A создал  
**Решение:** B читает, A пишет → B ждёт (или добавьте явную зависимость в plan)

---

## Transitions

→ [MODES.md](../MODES.md): чтение про режимы и архитектуру  
→ [make-task](make-task.md): если нужна одна последовательная задача  
→ [run-task](run-task.md): если уже есть готовая задача и нужна её исполнить  
→ [reconcile-task](reconcile-task.md): если сборка дрейфнула (воркер ушёл в отладку)
