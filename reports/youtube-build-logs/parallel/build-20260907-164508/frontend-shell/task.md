# Подзадача frontend-shell

## Summary
create a polished responsive dashboard shell and visual system in plain HTML/CSS. Use the fixed DOM IDs exactly. The UI language is Russian; report content remains in its source language. Aim for an editorial analytics dashboard rather than a generic admin template: strong typography, calm warm-neutral palette, clear status chips, report cards, metric tiles, opportunity cards, responsive detail layout, accessible focus/hover states, reduced-motion support, dialog and toast styling. No JavaScript, external fonts, images, libraries, inline handlers, or external network assets in this subtask.

## Files to Change
- `src/youtube_niche/web_static/index.html`
- `src/youtube_niche/web_static/styles.css`

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
