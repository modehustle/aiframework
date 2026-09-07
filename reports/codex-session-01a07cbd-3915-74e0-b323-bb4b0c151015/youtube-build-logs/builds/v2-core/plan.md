# Build plan: v2-core — implement the YouTube Niche Analyzer v2 modules

Foundation is bootstrapped (commit 0598a13): skeleton with typed stubs in
`src/youtube_niche/`, contracts (signatures, artifact names, config constants)
are already fixed. Workers implement the stubs; nobody touches `config.py`,
`__init__.py`, `pyproject.toml`, or foundation files. If a change outside the
declared paths seems needed — stop and report instead of editing.

## Subtask: search
**Role**: run-task
**Summary**: implement InnerTube search + two-factor scoring in `src/youtube_niche/search.py`. Implement `parse_view_count` (RU/EN/FI/DE/PL locales: "1.5K", "1 234 тыс.", "1,2 mln", "t."), `search_videos` via httpx POST to `youtubei/v1/search` (client config from `config.py`), walking videoRenderer entries; fetch likes for the top-12 pool only (second InnerTube call per video); fill `score_video` usage. Add unit tests for `parse_view_count` and `score_video` edge cases (0 views, missing likes) in `tests/test_search.py`. No browser automation, no Playwright.

### `src/youtube_niche/search.py`
- the module itself: all stubs live here

### `tests/test_search.py`
- unit tests for pure functions (locale parsing, scoring)

## Subtask: comments
**Role**: run-task
**Summary**: implement `src/youtube_niche/comments.py`: `normalize_votes` (int, '1.2K', 'тыс.', emoji-only → 0) and `download_comments_async` — wrap the sync `youtube_comment_downloader` generator in `asyncio.to_thread`, `asyncio.Semaphore(config.COMMENT_CONCURRENCY)`, attach video metadata (video_id/title/channel/views) to each comment, limit per video, ~1s spacing between videos. Unit tests for `normalize_votes` in `tests/test_comments.py`. Do not modify `config.py`.

### `src/youtube_niche/comments.py`
- the module itself

### `tests/test_comments.py`
- unit tests for vote normalization

## Subtask: llm
**Role**: run-task
**Summary**: implement `src/youtube_niche/llm.py`: `parse_json` (tolerant: ``` fences, thinking text before/after JSON, bare arrays, control chars, trailing commas), `chat` (httpx POST to OpenRouter per `config.py`, cache read/write via `cache_path`, backoff retry per `config.BACKOFF_BATCH`/`BACKOFF_SYNTH` chosen by caller, `reasoning: {enabled: false}` when `reasoning_off(model)`, timeline events llm_ok/llm_empty_content/cache_hit/llm_error). Unit tests for `parse_json` variants and cache key determinism in `tests/test_llm.py`. Mock HTTP in tests (no network).

### `src/youtube_niche/llm.py`
- the module itself

### `tests/test_llm.py`
- parser + cache tests, HTTP mocked

## Subtask: pipeline
**Role**: run-task
**Summary**: implement the orchestration stubs against the already-fixed contracts: `classify.py` (SYSTEM_S1 prompt exists; `classify_batch` builds numbered-comment prompt, calls `llm.chat`, `llm.parse_json`, aligns to indices; `stage1_classify` uses ThreadPoolExecutor over batches + parallel repair pass for failed batches, persists `10_classified.json`), `synthesize.py` (`stage2_report` aggregates frequencies + top verbatim quotes → single `llm.chat` call with hard-timeout watchdog `config.SYNTH_HARD_TIMEOUT`, then `verify_quotes` and `render_markdown`; persist report JSON), `report.py` (`md_to_html`: minimal stdlib markdown→HTML or add nothing — implement a small converter without new dependencies), `regen.py` (load `10_classified.json` + `02_comments_raw.json` → `stage2_report` → render), `pipeline.py` (`run_pipeline`: wire search → comments → stage1 → stage2 → report, persist `01_videos.json` / `02_comments_raw.json`, Timeline stage events). Unit tests for `verify_quotes` and aggregation helpers in `tests/test_pipeline.py` (LLM mocked). Do not modify `llm.py`, `search.py`, `comments.py`, `config.py` — their contracts are fixed; if a contract blocks you, stop and report in the task file.

### `src/youtube_niche/classify.py`
- stage 1 implementation

### `src/youtube_niche/synthesize.py`
- stage 2 implementation

### `src/youtube_niche/report.py`
- md→html converter

### `src/youtube_niche/regen.py`
- stage-2 rebuild

### `src/youtube_niche/pipeline.py`
- orchestration + artifact persistence

### `tests/test_pipeline.py`
- verify_quotes + aggregation tests, LLM mocked
