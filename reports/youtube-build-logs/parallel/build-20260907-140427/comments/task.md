# Подзадача comments

## Summary
implement `src/youtube_niche/comments.py`: `normalize_votes` (int, '1.2K', 'тыс.', emoji-only → 0) and `download_comments_async` — wrap the sync `youtube_comment_downloader` generator in `asyncio.to_thread`, `asyncio.Semaphore(config.COMMENT_CONCURRENCY)`, attach video metadata (video_id/title/channel/views) to each comment, limit per video, ~1s spacing between videos. Unit tests for `normalize_votes` in `tests/test_comments.py`. Do not modify `config.py`.

## Files to Change
- `src/youtube_niche/comments.py`
- `tests/test_comments.py`

## Executor Rules
- Роль этой подзадачи: run-task
- Меняй только файлы из Files to Change. Всё остальное дерево принадлежит
  другим воркерам этой сборки: правка вне списка сольётся молча и без конфликта.
- Нужен файл вне списка — не трогай его, а останови работу и скажи об этом.
  Дирижёр перепланирует сборку; это дешевле молчаливого пересечения.
- Сборка build-20260907-140427. Приёмка одна на всю сборку, отдельной приёмки этой подзадачи нет.
