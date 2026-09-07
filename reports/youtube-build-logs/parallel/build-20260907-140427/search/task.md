# Подзадача search

## Summary
implement InnerTube search + two-factor scoring in `src/youtube_niche/search.py`. Implement `parse_view_count` (RU/EN/FI/DE/PL locales: "1.5K", "1 234 тыс.", "1,2 mln", "t."), `search_videos` via httpx POST to `youtubei/v1/search` (client config from `config.py`), walking videoRenderer entries; fetch likes for the top-12 pool only (second InnerTube call per video); fill `score_video` usage. Add unit tests for `parse_view_count` and `score_video` edge cases (0 views, missing likes) in `tests/test_search.py`. No browser automation, no Playwright.

## Files to Change
- `src/youtube_niche/search.py`
- `tests/test_search.py`

## Executor Rules
- Роль этой подзадачи: run-task
- Меняй только файлы из Files to Change. Всё остальное дерево принадлежит
  другим воркерам этой сборки: правка вне списка сольётся молча и без конфликта.
- Нужен файл вне списка — не трогай его, а останови работу и скажи об этом.
  Дирижёр перепланирует сборку; это дешевле молчаливого пересечения.
- Сборка build-20260907-140427. Приёмка одна на всю сборку, отдельной приёмки этой подзадачи нет.
