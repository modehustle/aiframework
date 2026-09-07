# Подзадача backend

## Summary
implement the FastAPI service, filesystem-backed report/job catalog, background single-worker queue, pipeline run-directory injection, routes, packaged-static serving, and backend tests. Add `fastapi` and `uvicorn` runtime dependencies and a `youtube-niche-web` console script. Keep the existing CLI compatible. Metadata writes must be atomic (temporary sibling then replace); validate IDs as direct children of `config.REPORTS_DIR`; never follow user-supplied paths. Load `.env` for the web entry point using the same non-overwriting behavior as the CLI. Unit/API tests must use temporary report directories and mock pipeline execution; no network or real LLM calls.

## Files to Change
- `src/youtube_niche/web.py`
- `src/youtube_niche/web_store.py`
- `src/youtube_niche/pipeline.py`
- `pyproject.toml`
- `tests/test_web.py`

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
