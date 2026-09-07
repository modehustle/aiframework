# Build plan: web-service — report dashboard and managed analysis runs

Build a complete local web service on top of the existing YouTube niche-analysis
pipeline. The service is single-user and has no authentication in this build. It must
discover legacy folders already present under `reports/`, visualize `report.json`, allow
starting a new run, poll its progress, download JSON/HTML artifacts, and delete inactive
runs. No external frontend libraries or CDNs.

Workers must change only their declared paths. Foundation files (`ARCHITECTURE.md`,
`CONVENTIONS.md`, `DECISIONS.md`, `README.md`) belong to the conductor and are updated once
after the merged build. If an undeclared file is required, stop and report it.

## Fixed HTTP contract

- `GET /health` → HTTP 200 `{ "status": "ok" }`.
- `GET /api/reports` → `{ "items": ReportSummary[] }`, newest first.
- `POST /api/reports` with `CreateReportRequest` → HTTP 202 `ReportSummary`. Reject invalid
  input with 422. Queue the work in-process; the request must not wait for the pipeline.
- `GET /api/reports/{id}` → `ReportDetail`, or 404.
- `DELETE /api/reports/{id}` → HTTP 204; return 409 for `queued`/`running`, 404 if absent.
- `GET /api/reports/{id}/download/{format}` where format is `json` or `html` → artifact
  download, 404 when absent. Never accept arbitrary filenames or paths.
- `GET /` serves the packaged dashboard; `/assets/*` serves packaged static assets.

`CreateReportRequest` fields: `query` required string 1..200; `top_n` integer 1..25 default
10; `comments_per_video` integer 1..1000 default 500; `model` optional string; `max_age`
optional enum `week|month|year`; `use_cache` boolean default true.

`ReportSummary` fields: `id`, `query`, `status` (`queued|running|completed|failed`),
`created_at` ISO-8601 string, `updated_at` ISO-8601 string, `stage` nullable string,
`error` nullable string, `has_json` boolean, `has_html` boolean.

`ReportDetail` contains all summary fields plus `report` (parsed report JSON or null).
Job metadata is persisted atomically as `reports/<id>/job.json`. Legacy folders without
`job.json` are read-only-compatible: infer timestamps from the folder suffix/mtime,
completed when `report.json` exists, otherwise failed, and derive a display query from the
folder slug. On server startup, stale persisted `queued`/`running` jobs become `failed`
with a restart/interruption error. Path traversal in report ids must be impossible.

## Fixed DOM contract

`index.html` owns this exact set of IDs used by `app.js`: `app`, `new-report-button`,
`create-dialog`, `create-form`, `query`, `top-n`, `comments-per-video`, `max-age`, `model`,
`use-cache`, `cancel-create`, `create-error`, `report-count`, `active-count`, `report-list`,
`empty-state`, `detail-panel`, `detail-content`, `close-detail`, `toast-region`.
The dialog form uses native controls and no inline event handlers. Templates may be built
by JavaScript, so no additional template IDs are required.

## Frontend behavior contract

The frontend calls only the fixed HTTP endpoints above. It refreshes the list on load and
polls every 3 seconds only while any report is queued/running. Clicking a report opens its
detail. Detail visualization renders `videos_summary`, every available `discourse` group,
and `opportunities`; unknown/missing fields degrade gracefully. Use DOM construction and
`textContent` for report/user strings (never inject API data through `innerHTML`). Actions:
create, close dialog, delete after native confirmation, download JSON, download HTML.
Surface request errors in the form/toast and preserve a usable empty/loading/error state.

## Subtask: backend
**Role**: run-task
**Summary**: implement the FastAPI service, filesystem-backed report/job catalog, background single-worker queue, pipeline run-directory injection, routes, packaged-static serving, and backend tests. Add `fastapi` and `uvicorn` runtime dependencies and a `youtube-niche-web` console script. Keep the existing CLI compatible. Metadata writes must be atomic (temporary sibling then replace); validate IDs as direct children of `config.REPORTS_DIR`; never follow user-supplied paths. Load `.env` for the web entry point using the same non-overwriting behavior as the CLI. Unit/API tests must use temporary report directories and mock pipeline execution; no network or real LLM calls.

### `src/youtube_niche/web.py`
- FastAPI app factory, Pydantic request/response models, routes, static dashboard serving,
  single-worker background execution and CLI entry point

### `src/youtube_niche/web_store.py`
- atomic `job.json` persistence, legacy report discovery, safe id resolution, status/stage
  derivation from metadata and timeline, delete guard, startup interruption recovery

### `src/youtube_niche/pipeline.py`
- backward-compatible optional explicit run directory so POST can return a stable id before
  the background pipeline begins

### `pyproject.toml`
- FastAPI/Uvicorn dependencies, web console script, packaged static-file inclusion if needed

### `tests/test_web.py`
- store and API contract coverage: legacy discovery, sorting, validation, create 202, detail,
  safe downloads, traversal rejection, active-delete conflict, completed delete, restart
  recovery; pipeline mocked

## Subtask: frontend-shell
**Role**: run-task
**Summary**: create a polished responsive dashboard shell and visual system in plain HTML/CSS. Use the fixed DOM IDs exactly. The UI language is Russian; report content remains in its source language. Aim for an editorial analytics dashboard rather than a generic admin template: strong typography, calm warm-neutral palette, clear status chips, report cards, metric tiles, opportunity cards, responsive detail layout, accessible focus/hover states, reduced-motion support, dialog and toast styling. No JavaScript, external fonts, images, libraries, inline handlers, or external network assets in this subtask.

### `src/youtube_niche/web_static/index.html`
- accessible semantic dashboard, create-report dialog/form, list/empty states, detail panel,
  toast live region, link to local stylesheet and deferred local script

### `src/youtube_niche/web_static/styles.css`
- complete responsive visual system and all states/classes needed by the frontend behavior

## Subtask: frontend-behavior
**Role**: run-task
**Summary**: implement the complete dependency-free browser client against the fixed HTTP and DOM contracts. Render report cards/status/stages, counters, creation workflow, conditional polling, detail visualization, opportunity cards and categorical discourse sections, downloads and guarded delete. All dynamic API/user content must be assigned with `textContent` or safe attribute setters; do not use `innerHTML` with dynamic data. Use only classes documented by readable naming in this file; tolerate missing optional DOM nodes and malformed/missing report fields without crashing.

### `src/youtube_niche/web_static/app.js`
- API client, state, safe render helpers, polling lifecycle, dialog form, detail/actions,
  loading/empty/error handling and toast feedback
