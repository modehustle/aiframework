# Parallel Mode: Git Integration

**Как результаты от флота попадают в основной branch.**

---

## Архитектура

```
Conductor (мастер-сессия, на main)
    ↓
    fraim dispatch build-plan.md
    ↓ [создаёт ai/parallel/A/, ai/parallel/B/, ai/parallel/C/]
    ↓
    Раздача флоту (в Orca или на машине)
    ↓
Fleet Workers (N сессий, каждая на своём branch)
    A: git checkout -b worker/A
    B: git checkout -b worker/B
    C: git checkout -b worker/C
    ↓ [каждый работает независимо]
    ↓
    Коммиты в worker branches:
    A: "task A: standardize errors" → worker/A
    B: "task B: add logging" → worker/B
    C: "task C: extract utils" → worker/C
    ↓
    result.md для conductor → ai/parallel/X/result.md
    ↓
Conductor: collect results
    fraim dispatch:collect build-20260907-123456
    ↓ [мержит worker/A, worker/B, worker/C в main]
    ↓
Main contains all changes
    + new entry in DECISIONS.md (Build <id> accepted)
    + build journal with lessons
```

---

## Шаг 1: Создание worker branches

**Когда conductor запускает dispatch:**

```bash
cd /project
git checkout main
fraim dispatch build-plan.md
```

**Результат:** worker task folders созданы в `ai/parallel/`.
**Git state:** conductor всё ещё на main, рабочие папки готовы.

---

## Шаг 2: Worker начинает работу

**На машине флота (или в Orca сессии для worker A):**

```bash
cd /project
git fetch origin main

# Worker A создаёт свой branch
git checkout -b worker/build-20260907-123456-A origin/main
```

**Или через fraim:**

```bash
cd ai/parallel/A
fraim task-new parallel/A
fraim run-task parallel/A  # работает в изолированной сессии
```

---

## Шаг 3: Worker коммитит результаты

**Worker пишет задачу, потом:**

```bash
cd /project

# 1. Коммит изменений через fraim (atomicity + фундамент)
fraim commit task "A: standardize error messages" \
    src/core.sh src/config.sh

# 2. Пихает в свой worker branch
git push -u origin worker/build-20260907-123456-A

# 3. Пишет result.md для conductor
cat > ai/parallel/A/result.md <<'EOF'
# Subtask A Result

## Changes Made
- Replaced 42 die() calls in core.sh with `die "<func>: <msg>"`
- Updated 18 die() calls in config.sh
- All error messages now follow consistent format

## Files Modified
- src/core.sh: 23 lines changed
- src/config.sh: 19 lines changed

## Tests Passed
- test/unit/core.test.sh: ✓
- test/unit/config.test.sh: ✓

## No Blockers
EOF
```

---

## Шаг 4: Conductor собирает результаты

**Когда все воркеры готовы:**

```bash
git checkout main

# Фетч всех worker branches
git fetch origin "worker/build-20260907-123456-*"

# Conductor смержит все в main
fraim dispatch:collect build-20260907-123456
```

**Что происходит в collect:**

```bash
# Под капотом:
git merge -m "Merge worker/build-20260907-123456-A" \
    worker/build-20260907-123456-A

git merge -m "Merge worker/build-20260907-123456-B" \
    worker/build-20260907-123456-B

git merge -m "Merge worker/build-20260907-123456-C" \
    worker/build-20260907-123456-C
```

**Если конфликтов нет:** результаты объединены в main.  
**Если конфликты есть:** conductor разрешает их перед accept.

---

## Шаг 5: Conductor принимает

```bash
fraim dispatch:accept build-20260907-123456
```

**Что происходит:**

1. ✅ Проверка: все Files to Change модифицированы или явно пропущены
2. ✅ Проверка: нет конфликтов merge
3. ✅ Запись в DECISIONS.md:
   ```
   ## Build build-20260907-123456 accepted
   
   - **Date**: 2026-09-07 12:34:56 UTC
   - **Type**: parallel (conductor mode)
   - **Workers**: 3
   - **Result**: All subtasks completed successfully
   ```
4. ✅ Создание build journal с lessons (пока пусто)
5. ✅ Отметка build как завершённого

**Выход:** main содержит все изменения + фундамент обновлён.

---

## Шаг 6 (опционально): Lessons

**Conductor может записать lessons для следующей сборки:**

```bash
cat ai/builds/build-20260907-123456/build.sealed.md

# Открыть в редакторе:
# vi ai/builds/build-20260907-123456/build.sealed.md
```

**Заполнить раздел `## Lessons`:**

```markdown
## Lessons

- **Collision in config.sh**: Worker A и B оба читали config.sh, но строки не пересекались. 
  Решение сработало: read-only для B, write для A.

- **Worker C задержка**: Ждала коммитов A и B. В следующий раз раньше запустить или 
  добавить явный fork-join синхронизм.

- **Merge скорость**: 3 worker ветки мержили 30 сек. Приемлемо для 3x speedup.
```

Эти lessons автоматически попадают в build journal и становятся фундаментом 
для MODES.md §11.4 и PARALLEL-V2.

---

## Git Flow: Полная диаграмма

```
main                    ┃ dispatch        collect        accept
                        ┃                 ↓              ↓
 ━━━━━━━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╋━━━━━━━━━━━
     conductor creates  ┃ dispatch:       merge all      mark
     build-plan.md      ┃ split & check   workers into   accepted +
                        ┃                 main (+ fundi) write lesson
                        ┃
worker/A ──────────────┬────────────┬─────────────────────────→
  task A commits       │ worker A   │ push to origin
  in isolation         │ works      │ create result.md
                       │            │
worker/B ──────────────┬────────────┬─────────────────────────→
  task B commits       │ worker B   │ push to origin
  in isolation         │ works      │ create result.md
                       │            │
worker/C ──────────────┬────────────┬─────────────────────────→
  task C commits       │ worker C   │ push to origin
  in isolation         │ works      │ create result.md
```

---

## Сценарии: Что может пойти не так

### 1. Конфликт merge при collect

```bash
fraim dispatch:collect build-20260907-123456
Error: merge conflict in src/config.ts (workers A and C)
```

**Причина:** dispatch-check пропустила пересечение, или вы после dispatch добавили файл.

**Решение:**

```bash
# Conductor разрешает конфликт вручную
cd /project
git status  # показывает CONFLICT in src/config.ts

# Отредактируй файл, разреши конфликт
vim src/config.ts

# Коммит разрешения
git add src/config.ts
git commit -m "resolve merge conflict between worker A and C"

# Повтори collect
fraim dispatch:collect build-20260907-123456 --skip-merge
```

### 2. Worker застрял или потерпел неудачу

```bash
fraim dispatch:status build-20260907-123456
Worker status:
  A: DONE
  B: IN PROGRESS (3 hours, timeout?)
  C: DONE
```

**Решение:**

```bash
# Проверь воркер B напрямую
cd /path/to/worker/B/project
git log --oneline  # что там произошло?
git status  # застрял ли на конфликте?

# Вариант 1: Разреши конфликт, заполни result.md
git add .
git commit -m "resolved conflict"

# Вариант 2: Отменить воркер B, пересчитать без него
fraim dispatch:collect build-20260907-123456 --skip-worker B
```

### 3. Conductor забыл про сборку

```bash
# Через неделю:
git status
On branch main
Your branch is behind 'origin/main' by 1 commit
```

**Решение:**

```bash
# Найти недовершённые сборки
fraim dispatch:status  # список всех builds

# Продолжить сборку
fraim dispatch:collect build-20260907-123456
fraim dispatch:accept build-20260907-123456
```

---

## Автоматизация: CI/CD Integration

**Для Orca/ADE с несколькими воркерами:**

```bash
# В Orca orchestration:
orca fleet create --size 3 --image claude-haiku

# Для каждого worker slot:
orca run \
  --task ai/parallel/A/task.md \
  --output-dir ai/parallel/A/

# Conductor собирает после того как все returned:
fraim dispatch:collect build-20260907-123456 --await-all-workers

# Если всё ОК:
fraim dispatch:accept build-20260907-123456
git push origin main
```

---

## Atomicity Guarantee

**Conductor никогда не пишет в основной branch сам.**

- Только после все воркеры коммитили (в их worker branches)
- Только после collect объединил все (локально у conductor)
- Только если `fraim dispatch:accept` прошёл проверки

**Инвариант:** main всегда перестраиваемый, всегда имеет запись в DECISIONS.md.

---

## Следующая версия (v2)

- [ ] Orca integration: spawn worker sessions автоматически
- [ ] Streaming result collection: pull results по мере готовности (не ждать всех)
- [ ] Automatic conflict resolution: semantic markers ("A: write, B: read" → automerge)
- [ ] Build timeout: если worker > 24h без прогресса → escalate
- [ ] Rollback: `fraim dispatch:cancel` откатывает all worker branches + main к pre-dispatch
