# Подзадача frontend-behavior

## Summary
implement the complete dependency-free browser client against the fixed HTTP and DOM contracts. Render report cards/status/stages, counters, creation workflow, conditional polling, detail visualization, opportunity cards and categorical discourse sections, downloads and guarded delete. All dynamic API/user content must be assigned with `textContent` or safe attribute setters; do not use `innerHTML` with dynamic data. Use only classes documented by readable naming in this file; tolerate missing optional DOM nodes and malformed/missing report fields without crashing.

## Files to Change
- `src/youtube_niche/web_static/app.js`

## Executor Rules
- Роль этой подзадачи: run-task
- Меняй только файлы из Files to Change. Всё остальное дерево принадлежит
  другим воркерам этой сборки: правка вне списка сольётся молча и без конфликта.
- Нужен файл вне списка — не трогай его, а останови работу и скажи об этом.
  Дирижёр перепланирует сборку; это дешевле молчаливого пересечения.

- **Фундамент проекта в этой подзадаче не твой.** `DECISIONS.md`,
  `ARCHITECTURE.md`, `CONVENTIONS.md` не трогай, даже если `AGENTS.md` проекта
  велит обновлять их после изменения. Здесь это правило отменено: под
  параллелизмом фундамент пишет сборка, один раз, после приёмки
  (MODES.md §2, инвариант 0.4). Два воркера, дописавшие DECISIONS.md
  каждый от себя, дают конфликт слияния на ровном месте.
- Что стоило бы записать в фундамент — напиши словами в свой отчёт. Дирижёр
  соберёт это со всей сборки и внесёт одной записью.

- **Закоммить свою работу.** Не оставляй сделанное незакоммиченным: сборку
  собирают слиянием веток, и то, что не в коммите, до неё не доедет.
- Сборка build-20260907-164508. Приёмка одна на всю сборку, отдельной приёмки этой подзадачи нет.
