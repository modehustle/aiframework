# Подзадача llm

## Summary
implement `src/youtube_niche/llm.py`: `parse_json` (tolerant: ``` fences, thinking text before/after JSON, bare arrays, control chars, trailing commas), `chat` (httpx POST to OpenRouter per `config.py`, cache read/write via `cache_path`, backoff retry per `config.BACKOFF_BATCH`/`BACKOFF_SYNTH` chosen by caller, `reasoning: {enabled: false}` when `reasoning_off(model)`, timeline events llm_ok/llm_empty_content/cache_hit/llm_error). Unit tests for `parse_json` variants and cache key determinism in `tests/test_llm.py`. Mock HTTP in tests (no network).

## Files to Change
- `src/youtube_niche/llm.py`
- `tests/test_llm.py`

## Executor Rules
- Роль этой подзадачи: run-task
- Меняй только файлы из Files to Change. Всё остальное дерево принадлежит
  другим воркерам этой сборки: правка вне списка сольётся молча и без конфликта.
- Нужен файл вне списка — не трогай его, а останови работу и скажи об этом.
  Дирижёр перепланирует сборку; это дешевле молчаливого пересечения.
- Сборка build-20260907-140427. Приёмка одна на всю сборку, отдельной приёмки этой подзадачи нет.
