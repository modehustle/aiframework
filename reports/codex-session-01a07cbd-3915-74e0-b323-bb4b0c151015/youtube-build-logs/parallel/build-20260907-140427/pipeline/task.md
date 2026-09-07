# Подзадача pipeline

## Summary
implement the orchestration stubs against the already-fixed contracts: `classify.py` (SYSTEM_S1 prompt exists; `classify_batch` builds numbered-comment prompt, calls `llm.chat`, `llm.parse_json`, aligns to indices; `stage1_classify` uses ThreadPoolExecutor over batches + parallel repair pass for failed batches, persists `10_classified.json`), `synthesize.py` (`stage2_report` aggregates frequencies + top verbatim quotes → single `llm.chat` call with hard-timeout watchdog `config.SYNTH_HARD_TIMEOUT`, then `verify_quotes` and `render_markdown`; persist report JSON), `report.py` (`md_to_html`: minimal stdlib markdown→HTML or add nothing — implement a small converter without new dependencies), `regen.py` (load `10_classified.json` + `02_comments_raw.json` → `stage2_report` → render), `pipeline.py` (`run_pipeline`: wire search → comments → stage1 → stage2 → report, persist `01_videos.json` / `02_comments_raw.json`, Timeline stage events). Unit tests for `verify_quotes` and aggregation helpers in `tests/test_pipeline.py` (LLM mocked). Do not modify `llm.py`, `search.py`, `comments.py`, `config.py` — their contracts are fixed; if a contract blocks you, stop and report in the task file.

## Files to Change
- `src/youtube_niche/classify.py`
- `src/youtube_niche/synthesize.py`
- `src/youtube_niche/report.py`
- `src/youtube_niche/regen.py`
- `src/youtube_niche/pipeline.py`
- `tests/test_pipeline.py`

## Executor Rules
- Роль этой подзадачи: run-task
- Меняй только файлы из Files to Change. Всё остальное дерево принадлежит
  другим воркерам этой сборки: правка вне списка сольётся молча и без конфликта.
- Нужен файл вне списка — не трогай его, а останови работу и скажи об этом.
  Дирижёр перепланирует сборку; это дешевле молчаливого пересечения.
- Сборка build-20260907-140427. Приёмка одна на всю сборку, отдельной приёмки этой подзадачи нет.
